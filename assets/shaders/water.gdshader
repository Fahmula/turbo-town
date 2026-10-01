shader_type spatial;
render_mode cull_disabled;
// Stylized sea: flat colour with gentle animated normals and a lighter shoreline tint.

uniform vec4 deep_color : source_color = vec4(0.05, 0.45, 0.72, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.25, 0.78, 0.85, 1.0);
uniform float wave_scale = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float n1 = sin(p.x * 0.12 + t * 0.9) * cos(p.y * 0.1 - t * 0.7);
	float n2 = sin(p.x * 0.31 - p.y * 0.23 + t * 1.6);
	// Fade ripples with distance to avoid aliasing streaks.
	float fade = 1.0 - smoothstep(40.0, 300.0, length(VERTEX));
	vec3 n = normalize(vec3((n1 * 0.6 + n2 * 0.3) * fade, 8.0, (n2 * 0.5 - n1 * 0.4) * fade));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float dist = length(p);
	float shallow = 1.0 - smoothstep(560.0, 700.0, dist);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shallow * 0.6);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.4;
}
