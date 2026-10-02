// Shared helpers for the vehicle shaders (ART_BIBLE.md §7, §13, §14).
// Noise is hashed from object-space positions (stable: they don't wobble
// per pixel), so a pattern sticks to the panel and dents carry it along.

float vh_hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vh_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Trilinear value noise, 0..1.
float vh_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(vh_hash3(i), vh_hash3(i + vec3(1, 0, 0)), f.x),
			mix(vh_hash3(i + vec3(0, 1, 0)), vh_hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(vh_hash3(i + vec3(0, 0, 1)), vh_hash3(i + vec3(1, 0, 1)), f.x),
			mix(vh_hash3(i + vec3(0, 1, 1)), vh_hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// A smoothstep step at `edge` whose width follows the screen-space rate of
// change of `x` (no aliasing, no shimmer at 1280x800).
float vh_step(float edge, float x, float min_width) {
	float w = max(fwidth(x), min_width);
	return smoothstep(edge - w, edge + w, x);
}

// Decodes body_kit's UV tags: kind, and (s, t) metres from the patch centre.
// Untagged faces are kind 0. The glTF export flips V (v' = 1 - v).
void vh_kind(vec2 uv, out float kind, out vec2 st) {
	kind = floor(uv.x / 10.0 + 0.0005);
	st = kind > 0.5 ? vec2(uv.x - kind * 10.0 - 5.0, 1.0 - uv.y) : vec2(0.0);
}
