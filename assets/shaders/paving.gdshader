shader_type spatial;
// Paved ground (ART_BIBLE.md §16): sidewalks, kerbs, plazas, car
// parks and other flat ground inside the city blocks. Patterns are in world
// space, so pieces of the same surface join without seams.
//
// COLOR.rgb = base colour (sRGB; contact AO is baked in by darkening it).
// COLOR.a   = surface (in steps of 0.25):
//   1.0   concrete sidewalk slabs, 0.9 m grid
//   0.75  kerb stones: UV.x = metres along the kerb (joints every 1.2 m)
//   0.5   plaza stone tiles, 1.5 m, two tones
//   0.25  asphalt (car parks)
//   0.0   plain: lawn, soil, gravel (grain and blotches only)

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float near = detail_fade(length(VERTEX));
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec4 d = low ? vec4(0.5) : texture(detail, wp * 0.25);
	vec4 m = texture(detail, wp * 0.043 + vec2(0.71, 0.19));
	float grain = (d.r - 0.5) * near;
	int kind = int(round(COLOR.a * 4.0));
	vec3 col = srgb_to_linear(COLOR.rgb);
	float rough = 0.85;
	float spec = 0.5;

	if (kind == 4) {
		// Concrete slabs: per-slab tint, joints, pores and a few stains.
		vec2 slab = floor(wp / 0.9);
		float h = hash12(slab + 17.0);
		col *= 0.955 + 0.09 * h;
		col *= 1.0 + grain * 0.14;
		col *= 1.0 - smoothstep(0.62, 0.9, d.g) * 0.07 * near;
		float joint = max(grid_line(wp.x, 0.9, 0.014), grid_line(wp.y, 0.9, 0.014));
		col *= 1.0 - joint * 0.35;
		col *= 0.96 + 0.08 * m.a;
		rough = 0.86 + joint * 0.06;
	} else if (kind == 3) {
		// Kerb stones.
		float joint = grid_line(UV.x, 1.2, 0.012);
		float h = hash12(vec2(floor(UV.x / 1.2), 3.0));
		col *= 0.96 + 0.07 * h;
		col *= 1.0 + grain * 0.12;
		col *= 1.0 - joint * 0.4;
		col *= 0.95 + 0.08 * m.a;
		rough = 0.82;
	} else if (kind == 2) {
		// Plaza stone tiles.
		vec2 tile = floor(wp / 1.5);
		float h = hash12(tile + 5.0);
		float checker = mod(tile.x + tile.y, 2.0);
		col *= 0.95 + 0.05 * checker + 0.05 * h;
		col *= 1.0 + grain * 0.1;
		float joint = max(grid_line(wp.x, 1.5, 0.01), grid_line(wp.y, 1.5, 0.01));
		col *= 1.0 - joint * 0.35;
		col *= 0.96 + 0.08 * m.a;
		rough = 0.74;
	} else if (kind == 1) {
		// Car park asphalt.
		col *= 1.0 + grain * 0.28;
		col *= 0.93 + 0.14 * m.g;
		float crack = low ? 0.0 : texture(detail, wp * 0.083 + vec2(0.13, 0.71)).b * smoothstep(0.4, 0.7, m.g);
		col = mix(col, vec3(0.045, 0.045, 0.05), crack * 0.8);
		rough = mix(0.9 - grain * 0.08, 0.55, crack);
	} else {
		// Plain ground (lawns etc.). Green ground gets clumps and faint mowing stripes.
		float lawn = clamp((COLOR.g - COLOR.r) * 10.0, 0.0, 1.0);
		col *= 0.88 + 0.24 * m.g;
		col *= 1.0 + grain * 0.3;
		col *= 1.0 - smoothstep(0.55, 0.85, d.g) * 0.14 * near * lawn;
		float stripe = grid_line(wp.x, 5.0, 2.5);
		col *= 1.0 + (stripe - 0.5) * 0.07 * lawn;
		rough = 0.95;
		spec = 0.3;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
