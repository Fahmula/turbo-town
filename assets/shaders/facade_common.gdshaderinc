// Helpers for facade.gdshader (realism branch). Pure functions, no samplers.
// Wall frame used throughout: T = cross(up, n) is "right" seen from outside,
// up is world up, and depth runs INTO the wall (along -n).

#include "res://assets/shaders/world_common.gdshaderinc"

// Soft rectangle mask in metres; fw = pixel footprint in metres.
float rect_mask(vec2 p, vec2 lo, vec2 hi, vec2 fw) {
	vec2 a = smoothstep(lo - fw, lo + fw, p);
	vec2 b = 1.0 - smoothstep(hi - fw, hi + fw, p);
	return a.x * a.y * b.x * b.y;
}

// Distance (m) from p to the nearest edge of the rectangle; positive inside.
float rect_dist(vec2 p, vec2 lo, vec2 hi) {
	vec2 d = min(p - lo, hi - p);
	return min(d.x, d.y);
}

// 1 where x < edge and 0 where x > edge, soft over +-w.
float soft_lt(float x, float edge, float w) {
	return 1.0 - smoothstep(edge - w, edge + w, x);
}

float soft_gt(float x, float edge, float w) {
	return smoothstep(edge - w, edge + w, x);
}

// 1 where |x| < half_w (a bar centred on 0).
float soft_bar(float x, float half_w, float w) {
	return soft_lt(abs(x), half_w, max(w, 1e-4));
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Interior mapping: intersects a ray with the room box [-1, 1]^3 (x right,
// y up, z into the building) starting at p inside it. Returns the face
// (0 back, 1 left, 2 right, 3 floor, 4 ceiling), the face's (u, v) in
// [-1, 1] (the image conventions of tools/blender/make_building_interiors.py:
// back u = x; left u = z; right u = -z; floor u = x, v = z; ceiling u = x, v = -z)
// and the ray length t in box units.
void room_hit(vec3 p, vec3 d, out int face, out vec2 uv, out float t) {
	vec3 sg = vec3(d.x >= 0.0 ? 1.0 : -1.0, d.y >= 0.0 ? 1.0 : -1.0, 1.0);
	vec3 inv = 1.0 / (d + vec3(step(abs(d.x), 1e-5) * 1e-5, step(abs(d.y), 1e-5) * 1e-5, 0.0));
	vec3 tt = (sg - p) * inv;
	t = min(tt.x, min(tt.y, tt.z));
	vec3 h = p + d * t;
	if (t == tt.z) {
		face = 0;
		uv = vec2(h.x, h.y);
	} else if (tt.x < tt.y) {
		face = sg.x < 0.0 ? 1 : 2;
		uv = vec2(sg.x < 0.0 ? h.z : -h.z, h.y);
	} else {
		face = sg.y < 0.0 ? 3 : 4;
		uv = vec2(h.x, sg.y < 0.0 ? h.z : -h.z);
	}
}

// Brick/stone/stucco scans are stored as ratio * 0.2 (see tools/textures/fetch_building.py).
const float RATIO_SCALE = 5.0;

// Tints a scan ratio with a wall colour. k = 1: per-channel (keeps the
// scan's hue variation), k = 0: luminance only (for big hue changes).
vec3 tint_scan(vec3 ratio, vec3 wall, float k) {
	return wall * mix(vec3(luma(ratio)), ratio, k);
}

// Narrow vertical sine folds for curtains (0 deep, 1 crest).
float cloth_folds(float x, float phase) {
	return 0.5 + 0.5 * sin(x * 38.0 + phase + 1.2 * sin(x * 9.0));
}
