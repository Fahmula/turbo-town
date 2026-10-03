// Shared helpers for the road and paving shaders (realism experiment,
// ART_BIBLE.md §16): real asphalt and concrete scans plus generated crack and
// wear maps. Includes world_common.gdshaderinc (include only this file).
//
// Textures (assets/textures/road/, made by tools/textures/fetch_road.py):
//   *_albedo   neutral colour, mean linear luminance 0.18; the shader multiplies
//              it by base / 0.18, so the palette colour sets the average albedo
//   *_nra      R,G = normal x,y (tangent space, OpenGL), B = roughness, A = AO
//   road_cracks  RGBA, 12 m tile: R open cracks, G crack sealant, B pits, A mottling
//   road_macro   RGBA, 30 m tile: R scuffs and stains, G large-scale tone,
//                B oil drip spots, A fine film
// Quality (global `quality`): Low = albedo + macro only; Medium adds the
// normal/roughness map and one crack sample; High adds the second asphalt
// scale and the second crack sample.

#include "res://assets/shaders/world_common.gdshaderinc"

const float ALB_MEAN = 0.18;
const mat2 ROT_A = mat2(vec2(0.8391, 0.5440), vec2(-0.5440, 0.8391));
const mat2 ROT_B = mat2(vec2(0.2837, 0.9589), vec2(-0.9589, 0.2837));

uniform sampler2D asph_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asph_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_cracks : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_macro : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cast_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cast_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Metres per asphalt tile and per concrete tile.
uniform float asph_tile = 1.5;
uniform float slab_tile = 1.8;
uniform float cast_tile = 2.0;
// Normal map strength (1 = as scanned).
uniform float bump_strength = 1.0;
// How many cracks (0 none .. 1 city streets).
uniform float crack_density = 0.75;
// Average asphalt albedo (linear, sRGB-hinted so it can be edited as a colour).
uniform vec3 asphalt_base : source_color = vec3(0.36, 0.355, 0.35);

struct Surf {
	vec3 col;      // linear albedo
	float rough;
	float ao;
	vec2 nxy;      // tangent-space normal x,y (scaled), uv-aligned
	float tone;    // 0 fresh/dark .. 1 sun-bleached
	float stone;   // fine luminance ratio (aggregate peaks), around 1
	float film;    // fine noise 0..1
	float oil;     // oil spot field 0..1
};

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Normal perturbed by a tangent-space normal (x,y from an OpenGL normal map
// sampled with texture coordinates `uv`). The tangent frame comes from
// screen-space derivatives, so meshes need no tangents.
vec3 bump_normal(vec3 N, vec3 pos, vec2 uv, vec2 nxy) {
	vec3 dp1 = dFdx(pos);
	vec3 dp2 = dFdy(pos);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float inv = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
	float nz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));
	return normalize((T * nxy.x - B * nxy.y) * inv + N * nz);
}

// Asphalt: scanned aggregate at two scales, large-scale tone and scuffs,
// cracks with sealant, pits. `crack_mul` (0..1) hides cracks (repair patches).
Surf asphalt_surface(vec2 wp, vec3 base, float wear, float crack_mul) {
	Surf s;
	bool low = quality == 0;
	bool high = quality >= 2;
	vec2 uv = wp / asph_tile;
	vec3 ratio = texture(asph_albedo, uv).rgb * (1.0 / ALB_MEAN);
	vec4 nra = vec4(0.5, 0.5, 0.86, 1.0);
	if (!low) {
		nra = texture(asph_nra, uv);
	}
	if (high) {
		vec3 r2 = texture(asph_albedo, ROT_A * wp / (asph_tile * 0.61) + vec2(0.37, 0.71)).rgb * (1.0 / ALB_MEAN);
		ratio *= mix(vec3(1.0), r2, 0.5);
	}
	s.stone = lum(ratio);
	vec4 mc = texture(road_macro, wp / 30.0 + vec2(0.13, 0.37));
	vec4 c1 = vec4(0.0, 0.0, 0.0, mc.g);
	vec4 c2 = vec4(0.0);
	if (!low) {
		c1 = texture(road_cracks, wp / 12.0);
	}
	if (high) {
		c2 = texture(road_cracks, ROT_B * wp / 8.3 + vec2(0.5, 0.2));
	}
	float w = clamp(wear, 0.0, 1.0);
	float tone = mix(mc.g, c1.a, 0.3);
	s.tone = tone;
	s.film = mc.a;
	s.oil = mc.b;

	// Large-scale tone: darker where fresh or oily, lighter where the binder
	// has worn off; less variation on newer roads.
	float tv = mix(0.7, 1.45, smoothstep(0.1, 0.9, tone));
	tv = mix(1.0, tv, 0.35 + 0.65 * w);
	ratio = mix(vec3(1.0), ratio, 1.2);                                   // a little more aggregate contrast
	vec3 col = base * ratio * tv;
	col *= 1.0 + (mc.r - 0.5) * 1.1;

	// Cracks only where the road is old: open cracks, sealed bands, pits.
	float wc = w * crack_density;
	float area = smoothstep(0.95 - 0.6 * wc, 1.15 - 0.6 * wc, mix(mc.g, c1.a, 0.5)) * crack_mul;
	float open = max(c1.r, c2.r) * area;
	float seal = max(c1.g, c2.g) * area;
	float pit = max(c1.b, c2.b) * area;
	col = mix(col, col * 0.15, open * 0.9);
	col = mix(col, vec3(0.02, 0.02, 0.022), seal * 0.92);
	col *= 1.0 - pit * 0.5;

	s.col = col;
	s.rough = mix(nra.b, 0.68, seal);
	s.ao = nra.a * (1.0 - open * 0.7) * (1.0 - pit * 0.3);
	s.nxy = low ? vec2(0.0) : (nra.rg * 2.0 - 1.0) * bump_strength;
	return s;
}

// Normal perturbed by a height field `h` (metres) known only per pixel: uses
// screen-space derivatives (Mikkelsen's bump mapping), for thin features such
// as paint ridges.
vec3 height_bump(vec3 N, vec3 pos, float h, float k) {
	vec3 sx = dFdx(pos);
	vec3 sy = dFdy(pos);
	vec3 r1 = cross(sy, N);
	vec3 r2 = cross(N, sx);
	float det = dot(sx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * N - k * grad);
}

// Smooth coverage of a paint stripe: `sd` = signed distance in metres
// (negative inside), `fw` = pixel footprint of that distance, `jit` = edge
// jitter in metres (stones breaking the line).
float paint_cover(float sd, float fw, float jit) {
	return 1.0 - smoothstep(-fw, fw, sd + jit);
}

// Concrete: scanned texture sampled with a per-cell offset / rotation to hide
// tiling. `cell` = integer cell id (slab, kerb stone...), `uvw` = continuous
// metric coordinates of the plane, `dx`/`dy` = its screen derivatives (taken
// outside any branch). The returned normal xy is aligned to uvw (feed it to
// bump_normal with uvw / tile).
Surf concrete_surface(sampler2D alb, sampler2D nra_tex, vec2 uvw, vec2 dx_w, vec2 dy_w, vec2 cell, float tile, vec3 base) {
	Surf s;
	bool low = quality == 0;
	vec2 h = hash22(cell + 3.7);
	float r = floor(h.x * 4.0);
	float m = h.y < 0.5 ? 1.0 : -1.0;
	float c = (r == 0.0) ? 1.0 : ((r == 2.0) ? -1.0 : 0.0);
	float sn = (r == 1.0) ? 1.0 : ((r == 3.0) ? -1.0 : 0.0);
	mat2 rot = mat2(vec2(c, sn * m), vec2(-sn, c * m));
	vec2 uv = rot * uvw / tile + hash22(cell + 11.1) * 13.0;
	vec2 dx = rot * dx_w / tile;
	vec2 dy = rot * dy_w / tile;
	vec3 ratio = textureGrad(alb, uv, dx, dy).rgb * (1.0 / ALB_MEAN);
	vec4 nra = vec4(0.5, 0.5, 0.88, 1.0);
	if (!low) {
		nra = textureGrad(nra_tex, uv, dx, dy);
	}
	s.col = base * ratio;
	s.rough = nra.b;
	s.ao = nra.a;
	// Rotate the sampled normal back into the plane's uv axes (n = S R^T S n').
	vec2 nt = (nra.rg * 2.0 - 1.0) * bump_strength;
	nt = transpose(rot) * vec2(-nt.x, nt.y);
	s.nxy = low ? vec2(0.0) : vec2(-nt.x, nt.y);
	s.stone = lum(ratio);
	s.tone = 0.5;
	s.film = 0.5;
	s.oil = 0.0;
	return s;
}
