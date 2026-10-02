shader_type spatial;
// Island terrain (ART_BIBLE.md §19). COLOR = the ground colour blend from
// TerrainBuilder (grass, dry grass, dirt, rock, sand; sRGB). On top: grass
// clumps and grain that fade with distance, slow macro variation toward dry
// and lush patches, and rock with strata on steep slopes.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 grass_dry : source_color = vec4(0.541, 0.541, 0.290, 1.0);
uniform vec4 grass_lush : source_color = vec4(0.30, 0.44, 0.19, 1.0);
uniform vec4 rock : source_color = vec4(0.541, 0.522, 0.502, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 col = srgb_to_linear(COLOR.rgb);
	vec2 wp = world_pos.xz;
	float near = 1.0 - smoothstep(25.0, 90.0, length(VERTEX));
	bool low = quality == 0;
	vec4 d = low ? vec4(0.5) : texture(detail, wp * 0.3);
	vec4 m = texture(detail, wp * 0.012 + vec2(0.17, 0.83));
	vec4 m2 = texture(detail, wp * 0.0041 + vec2(0.61, 0.07));
	float greenness = clamp((col.g - col.r) * 12.0, 0.0, 1.0);
	// Macro variation: dry and lush patches on grass, lighter/darker elsewhere.
	vec3 dry = srgb_to_linear(grass_dry.rgb);
	vec3 lush = srgb_to_linear(grass_lush.rgb);
	col = mix(col, dry * (0.9 + 0.2 * m.a), smoothstep(0.55, 0.85, m2.g) * 0.35 * greenness);
	col = mix(col, lush, smoothstep(0.5, 0.15, m.g) * 0.25 * greenness);
	col *= 0.92 + 0.16 * m.a;
	// Grass clumps and grain near the camera.
	col *= 1.0 - smoothstep(0.55, 0.85, d.g) * 0.1 * near * greenness;
	col *= 1.0 + (d.r - 0.5) * 0.35 * near;
	// Rock on steep slopes, with strata.
	vec3 n = normalize(world_normal);
	float steep = 1.0 - smoothstep(0.72, 0.86, n.y);
	if (steep > 0.0) {
		vec3 r = srgb_to_linear(rock.rgb);
		float strata = texture(detail, vec2((wp.x + wp.y) * 0.08, world_pos.y * 0.35)).g;
		r *= 0.85 + 0.3 * strata;
		r *= 1.0 + (d.r - 0.5) * 0.2 * near;
		col = mix(col, r, steep * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = mix(0.5, 0.3, greenness);
}
