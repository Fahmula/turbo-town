// Shared helpers for the world shaders (ART_BIBLE.md §7).
//
// Global shader uniforms (Project Settings > Shader Globals):
//   night     0 = day, 1 = night (set by DayNight)
//   quality   0 = Low, 1 = Medium, 2 = High (set by GraphicsQuality.apply)
//   wet       0 = dry, 1 = soaked (set by Weather; lags behind the rain)
//   rain      0 = none, 1 = a downpour, falling now (set by Weather)
//
// The ground detail texture (assets/textures/ground/ground_detail.png, made by
// tools/textures/make_textures.py) tiles every 4 m: R = fine grain,
// G = blotches, B = crack lines, A = soft variation. Sample it in world space
// so neighbouring meshes (road, intersection, kerb) match at their seams.

global uniform float night;
global uniform int quality;
global uniform float wet;
global uniform float rain;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// Hash of a stable input (round interpolated values before hashing them).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Antialiased band: 1 inside [lo, hi] along x, soft over one pixel.
float band(float x, float lo, float hi) {
	float fw = fwidth(x) * 0.75;
	return smoothstep(lo - fw, lo + fw, x) * (1.0 - smoothstep(hi - fw, hi + fw, x));
}

// Antialiased lines of `width` centred every `period` along x. Once a line
// gets thinner than a pixel it fades to its average coverage, so far grids
// and stripes don't shimmer.
float grid_line(float x, float period, float width) {
	float fw = fwidth(x);
	float d = abs(fract(x / period + 0.5) - 0.5) * period;
	float l = 1.0 - smoothstep(width * 0.5 - fw * 0.5, width * 0.5 + fw * 0.5, d);
	return mix(l, width / period, smoothstep(width * 0.5, width * 2.0, fw));
}

// How much fine detail to show at a given view distance (m).
float detail_fade(float dist) {
	return 1.0 - smoothstep(18.0, 55.0, dist);
}

// How wet a surface is that faces `world_normal`: walls take less rain
// than the ground.
float wet_amount(vec3 world_normal) {
	return wet * mix(0.3, 1.0, smoothstep(0.2, 0.8, world_normal.y));
}

// Wet surfaces (ART_BIBLE.md §11): no SSR puddles, just darker and glossier,
// so wet roads pick up the sky and street lights. `w` = how wet (wet_amount),
// `pool` 0..1 = where water collects (dips, wheel ruts, gutters), `porous`
// 0..1 = how much water darkens it (asphalt and soil 1, concrete 0.7, paint
// and metal about 0.2). Pools form once the ground is soaked: near-mirrors
// that drown the surface's bumps. Returns how much is pool.
float wet_surface(float w, float pool, float porous, inout vec3 col, inout float rough, inout vec2 nxy) {
	if (w <= 0.0) {
		return 0.0;
	}
	float p = clamp(pool, 0.0, 1.0) * smoothstep(0.45, 0.95, w);
	col *= 1.0 - (0.5 * porous + 0.08) * w;
	col *= 1.0 - 0.2 * p;
	rough = mix(rough, rough * 0.25 + 0.04, w);
	rough = mix(rough, 0.03, p);
	nxy *= (1.0 - 0.3 * w * porous) * (1.0 - p);
	return p;
}

// Raindrops landing in a pool: thin rings spreading out (two layers of
// cells; each cell's ring lives for part of its cycle, then waits). Returns
// a normal tilt in world x,z; fades out with distance. A few ALU ops, no
// textures: High only.
vec2 rain_ripples(vec2 wp, float time, float dist) {
	vec2 n = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = wp * (layer == 0 ? 3.1 : 4.3) + float(layer) * 17.3;
		vec2 cell = floor(q);
		vec2 h = hash22(cell);
		vec2 d = q - (cell + 0.3 + 0.4 * h);
		float r = length(d);
		float life = fract(time * (1.1 + 0.5 * h.y) + h.x * 7.0) / 0.55;
		float x = (r - life * 0.3) * 45.0;
		float ring = sin(x * PI) * (1.0 - smoothstep(0.5, 1.0, abs(x))) * (1.0 - life) * step(life, 1.0);
		n += d / max(r, 1e-4) * ring;
	}
	return n * 0.12 * (1.0 - smoothstep(6.0, 20.0, dist));
}

// A view-space normal tilted by rain_ripples; `amount` = pool * rain.
vec3 rippled(vec3 n_view, mat4 view_matrix, vec2 wp, float time, float dist, float amount) {
	vec2 r = rain_ripples(wp, time, dist) * amount;
	return normalize(n_view + mat3(view_matrix) * vec3(r.x, 0.0, r.y));
}
