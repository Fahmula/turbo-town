shader_type spatial;
// Tyre rubber (ART_BIBLE.md §6, §13): the wheels' "Tire" surfaces, shared
// (one material per dirt level). From the object-space radius (every wheel
// model is built at 0.37 m round the X axis and scaled in the scene): a
// darker, rougher tread, a sidewall about 5% lighter with a slightly glossy
// moulded band, and road dust that settles on the sidewall when `dust` > 0.

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

uniform float dust : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dust_color : source_color = vec4(0.5, 0.46, 0.4, 1.0);

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float r = length(obj_pos.yz);
	float tread = smoothstep(0.345, 0.36, r);
	float band = smoothstep(0.268, 0.272, r) * (1.0 - smoothstep(0.3, 0.304, r));
	vec3 col = mix(vec3(0.0135), vec3(0.0098), tread);           // #1F1F21 sidewall, #1A1A1C tread
	float rough = mix(0.82, 0.93, tread) - band * 0.12;
	float grit = vh_noise(obj_pos * 60.0);
	float d = dust * (0.55 + 0.45 * grit) * (1.0 - tread * 0.5);
	col = mix(col, dust_color.rgb * 0.55, d * 0.6);
	rough = mix(rough, 0.95, d);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
