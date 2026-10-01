// Shared helpers for the new-style world shaders (ART_BIBLE.md §7).
//
// Global shader uniforms (Project Settings > Shader Globals):
//   night     0 = day, 1 = night (set by DayNight)
//   quality   0 = Low, 1 = Medium, 2 = High (set by GraphicsQuality.apply)
//   art_zone  x0, z0, x1, z1 of the environment art preview (ArtZone);
//             all zero when it's off
//
// The ground detail texture (assets/textures/ground/ground_detail.png, made by
// tools/textures/make_textures.py) tiles every 4 m: R = fine grain,
// G = blotches, B = crack lines, A = soft variation. Sample it in world space
// so neighbouring meshes (road, intersection, kerb) match at their seams.

global uniform float night;
global uniform int quality;
global uniform vec4 art_zone;

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

bool in_art_zone(vec2 xz) {
	return xz.x >= art_zone.x && xz.x < art_zone.z && xz.y >= art_zone.y && xz.y < art_zone.w;
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
