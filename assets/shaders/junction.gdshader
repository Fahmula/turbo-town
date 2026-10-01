shader_type spatial;
// New-style city junction square (ART_BIBLE.md §16): the same asphalt as
// road_surface.gdshader (sampled in world space so the seams match), worn
// zebra crossings on the sides that have a road, and a darker, oilier
// middle where cars wait and turn.
// UV = metres from the centre. COLOR.rgba = road on the N, E, S, W side.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 asphalt_color : source_color = vec4(0.275, 0.278, 0.290, 1.0);
uniform vec4 asphalt_dark : source_color = vec4(0.224, 0.227, 0.239, 1.0);
uniform vec4 asphalt_worn : source_color = vec4(0.353, 0.357, 0.365, 1.0);
uniform vec4 white_line : source_color = vec4(0.894, 0.886, 0.855, 1.0);
uniform float half_size = 6.0;
uniform float band_width = 2.4;
uniform float stripe = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float near = detail_fade(length(VERTEX));
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec4 d = low ? vec4(0.5) : texture(detail, wp * 0.25);
	vec4 m = texture(detail, wp * 0.031 + vec2(0.37, 0.61));
	float grain = (d.r - 0.5) * near;

	vec3 col = asphalt_color.rgb;
	float worn = smoothstep(0.5, 0.9, m.g * 0.65 + d.g * 0.35);
	col = mix(col, asphalt_worn.rgb, worn * 0.5);
	col = mix(col, asphalt_dark.rgb, smoothstep(0.45, 0.15, m.a) * 0.4);
	col *= 0.95 + 0.1 * mix(0.5, d.g, near);
	col *= 1.0 + grain * 0.3;
	float rough = 0.9 - grain * 0.08;
	// Darker, smoother middle (oil drips, tyre polish).
	vec2 p = UV;
	float mid = 1.0 - smoothstep(1.5, 4.5, length(p));
	col *= 1.0 - mid * (0.08 + 0.06 * d.g);
	rough -= mid * 0.08;
	// Crack sealing.
	float crack = low ? 0.0 : texture(detail, wp * 0.083 + vec2(0.13, 0.71)).b * smoothstep(0.35, 0.65, m.g);
	col = mix(col, vec3(0.045, 0.045, 0.05), crack * 0.85);
	rough = mix(rough, 0.55, crack);

	// Zebra crossings: bars along the traffic direction.
	float inner = half_size - band_width - 0.3;
	float edge = half_size - 0.3;
	float bars_x = grid_line(p.x, stripe * 2.0, stripe);
	float bars_z = grid_line(p.y, stripe * 2.0, stripe);
	float in_x = band(p.x, -inner, inner);
	float in_z = band(p.y, -inner, inner);
	float zebra = 0.0;
	zebra += COLOR.r * in_x * band(p.y, -edge, -inner) * bars_x;
	zebra += COLOR.b * in_x * band(p.y, inner, edge) * bars_x;
	zebra += COLOR.g * in_z * band(p.x, inner, edge) * bars_z;
	zebra += COLOR.a * in_z * band(p.x, -edge, -inner) * bars_z;
	float chips = smoothstep(0.62, 0.7, d.r + d.g * 0.25 + worn * 0.12 - 0.12) * near;
	float keep = 1.0 - chips * 0.85;
	zebra = clamp(zebra, 0.0, 1.0) * keep;
	col = mix(col, white_line.rgb * (0.9 + 0.1 * m.a), zebra);
	rough = mix(rough, 0.66, zebra);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
}
