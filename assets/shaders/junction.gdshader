shader_type spatial;
// City junction square (ART_BIBLE.md §16, realism experiment): the same
// scanned asphalt as road_surface.gdshader (sampled in world space so the
// seams match), worn zebra crossings on the sides that have a road, and a
// darker, oilier, polished middle where cars wait and turn.
// UV = metres from the centre. COLOR.rgba = road on the N, E, S, W side.

#include "res://assets/shaders/road_common.gdshaderinc"

uniform vec4 white_line : source_color = vec4(0.894, 0.886, 0.855, 1.0);
uniform float half_size = 6.0;
uniform float band_width = 2.4;
uniform float stripe = 0.6;
uniform float wear = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec2 p = UV;

	Surf s = asphalt_surface(wp, asphalt_base, wear, 1.0);
	vec3 col = s.col;
	float rough = s.rough;
	vec2 nxy = s.nxy;

	// Darker, smoother middle (oil drips, tyre polish, rubber).
	float mid = 1.0 - smoothstep(1.5, 4.8, length(p));
	col *= 1.0 - mid * (0.1 + 0.08 * s.film);
	rough -= mid * 0.08;
	float oil = smoothstep(0.25, 0.65, s.oil) * mid;
	col *= 1.0 - oil * 0.5;
	rough = mix(rough, 0.3, oil);

	// Zebra crossings: bars along the traffic direction.
	float inner = half_size - band_width - 0.3;
	float edge = half_size - 0.3;
	float jit = (s.stone - 1.0) * 0.012 * near;
	float fwx = fwidth(p.x) * 0.75 + 1e-5;
	float fwy = fwidth(p.y) * 0.75 + 1e-5;
	float period = stripe * 2.0;
	float bars_x = paint_cover(abs(mod(p.x + stripe, period) - stripe) - stripe * 0.5, fwx, jit);
	float bars_z = paint_cover(abs(mod(p.y + stripe, period) - stripe) - stripe * 0.5, fwy, jit);
	float in_x = band(p.x, -inner, inner);
	float in_z = band(p.y, -inner, inner);
	float zebra = 0.0;
	zebra += COLOR.r * in_x * band(p.y, -edge, -inner) * bars_x;
	zebra += COLOR.b * in_x * band(p.y, inner, edge) * bars_x;
	zebra += COLOR.g * in_z * band(p.x, inner, edge) * bars_z;
	zebra += COLOR.a * in_z * band(p.x, -edge, -inner) * bars_z;
	// Zebras are driven over more than lane lines, so they chip and grime.
	float chip = smoothstep(0.68, 1.0, s.film * 0.55 + (s.stone - 0.6) * 0.5 + s.tone * 0.2) * near * (0.3 + 0.6 * wear);
	zebra = clamp(zebra, 0.0, 1.0) * (1.0 - clamp(chip * 1.0 + 0.15 * (1.0 - s.film), 0.0, 0.85));
	vec3 paint_w = white_line.rgb * 0.82 * (0.78 + 0.22 * s.tone);
	col = mix(col, paint_w, zebra);
	rough = mix(rough, 0.58, zebra);
	nxy *= 1.0 - zebra * 0.5;

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.25, 1.0);
	AO = s.ao;
	if (!low) {
		NORMAL = bump_normal(NORMAL, VERTEX, wp / asph_tile, nxy);
	}
}
