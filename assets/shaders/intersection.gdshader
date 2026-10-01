shader_type spatial;
// City intersection square: plain asphalt with zebra crossings on the sides
// that have a road. UV = metres from the centre. COLOR.rgba = N, E, S, W flags.

uniform vec4 asphalt_color : source_color = vec4(0.275, 0.278, 0.290, 1.0);
uniform vec4 white_line : source_color = vec4(0.894, 0.886, 0.855, 1.0);
uniform float half_size = 6.0;
uniform float band = 2.4;
uniform float stripe = 0.6;

void fragment() {
	vec2 p = UV;
	vec3 col = asphalt_color.rgb;
	float inner = half_size - band - 0.3;
	float edge = half_size - 0.3;
	float m = 0.0;
	float s_x = step(fract(p.x / (stripe * 2.0)), 0.5);
	float s_z = step(fract(p.y / (stripe * 2.0)), 0.5);
	bool mid_x = abs(p.x) < inner;
	bool mid_z = abs(p.y) < inner;
	if (mid_x && p.y < -inner && p.y > -edge && COLOR.r > 0.5) m = s_x;
	if (mid_x && p.y > inner && p.y < edge && COLOR.b > 0.5) m = s_x;
	if (mid_z && p.x > inner && p.x < edge && COLOR.g > 0.5) m = s_z;
	if (mid_z && p.x < -inner && p.x > -edge && COLOR.a > 0.5) m = s_z;
	ALBEDO = mix(col, white_line.rgb, m);
	ROUGHNESS = 0.82;
}
