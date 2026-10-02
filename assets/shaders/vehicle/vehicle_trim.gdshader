shader_type spatial;
// Black trim plastic (ART_BIBLE.md §6, §13): the "Trim" surfaces, shared by
// every vehicle (one material). Panel gaps, sills, pillars and bumpers are
// plain satin plastic. Grille patches tagged by body_kit (UV0, see
// vehicle_lamp.gdshader for the encoding) get depth without geometry:
//   6 GRILLE_MESH: a honeycomb of 22 mm cells, dark holes behind thin webs
//   7 GRILLE_SLATS: horizontal louvres every 26 mm, tilted so their tops
//     catch the light, dark gaps between
// The holes are near-black with no specular, so they read as depth. Both
// patterns fade to their average where they'd alias.

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

uniform vec4 plastic : source_color = vec4(0.133, 0.137, 0.149, 1.0);
uniform float plastic_roughness = 0.6;

void fragment() {
	float kind;
	vec2 st;
	vh_kind(UV, kind, st);
	vec3 col = plastic.rgb;
	float rough = plastic_roughness;
	float spec = 0.5;
	float hole = 0.0;
	if (kind > 5.5 && kind < 6.5) {
		// Honeycomb: distance to the nearest hex centre.
		vec2 p = st / 0.022;
		vec2 grid = vec2(1.0, 1.732);
		vec2 a = mod(p, grid) - grid * 0.5;
		vec2 b = mod(p - grid * 0.5, grid) - grid * 0.5;
		vec2 g = dot(a, a) < dot(b, b) ? a : b;
		vec2 h = abs(g);
		float edge = max(dot(h, normalize(vec2(1.0, 1.732))), h.x);
		float fade = smoothstep(0.25, 0.6, fwidth(edge));
		hole = mix(1.0 - smoothstep(0.36, 0.42, edge), 0.62, fade);
	} else if (kind > 6.5 && kind < 7.5) {
		float y = st.y / 0.026;
		float f = fract(y);
		float fade = smoothstep(0.25, 0.6, fwidth(y));
		hole = mix(smoothstep(0.62, 0.72, f) * (1.0 - smoothstep(0.92, 0.99, f)), 0.3, fade);
		// Slat faces tilt up: brighter top half.
		col *= mix(1.0, 1.0 + 0.6 * (1.0 - f), 1.0 - fade);
	}
	col = mix(col, vec3(0.004), hole);
	rough = mix(rough, 1.0, hole);
	spec = mix(spec, 0.0, hole);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;
	AO = 1.0 - hole * 0.9;
}
