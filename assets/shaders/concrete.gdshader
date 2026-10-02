shader_type spatial;
// Cast concrete (ART_BIBLE.md §16): Jersey barriers, overpass
// piers, girders and fascias, retaining walls. Matte, with fine pores, soft
// blotches and drip streaks running down vertical faces (more near the top
// edges, where rain runs off). Texture coordinates come from the world
// position (picked by the face's direction), so nothing needs unwrapping.
//
// COLOR.rgb = base colour (sRGB; stained bases and contact AO baked in).
// COLOR.a   = 1.0 cast concrete (faint formwork lines every 1.25 m, UV.y =
//             metres up), 0.5 barrier segments (UV.x = metres along: a joint
//             every 6 m), 0.0 plain.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float near = detail_fade(length(VERTEX));
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	bool vertical = an.y < 0.7;
	// Planar projection along the dominant axis.
	vec2 uv = an.y >= 0.7 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
	float across = an.x > an.z ? world_pos.z : world_pos.x;
	bool low = quality == 0;
	vec4 d = low ? vec4(0.5) : texture(detail, uv * 0.25 + vec2(0.31, 0.17));
	vec4 m = texture(detail, uv * 0.05 + vec2(0.53, 0.29));
	vec3 col = srgb_to_linear(COLOR.rgb);
	col *= 0.92 + 0.14 * m.a;
	col *= 1.0 - smoothstep(0.6, 0.9, m.g) * 0.08;
	col *= 1.0 + (d.r - 0.5) * 0.14 * near;
	if (vertical && !low) {
		// Drip streaks: noise stretched down the face.
		float s = texture(detail, vec2(across * 0.35, world_pos.y * 0.025) + vec2(0.11, 0.47)).g;
		col *= 1.0 - smoothstep(0.58, 0.88, s) * 0.13;
	}
	int kind = int(round(COLOR.a * 2.0));
	if (kind == 2 && vertical) {
		col *= 1.0 - grid_line(UV.y, 1.25, 0.02) * 0.12;
	} else if (kind == 1) {
		float joint = grid_line(UV.x, 6.0, 0.025);
		col *= 1.0 - joint * 0.45;
	}
	ALBEDO = col;
	ROUGHNESS = 0.88 - (d.r - 0.5) * 0.06;
}
