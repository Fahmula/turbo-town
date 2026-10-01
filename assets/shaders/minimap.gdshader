shader_type canvas_item;
// Round, heading-up minimap: shows the part of the world map around `center`
// (map UV), rotated so the player's heading points up.

uniform sampler2D map_tex : source_color, filter_linear;
uniform vec2 center = vec2(0.5);
uniform float angle = 0.0;
// Map UV distance from the middle of the minimap to its edge.
uniform float radius = 0.1;
uniform vec4 sea_color : source_color = vec4(0.24, 0.52, 0.82, 1.0);
uniform vec4 ring_color : source_color = vec4(0.05, 0.08, 0.15, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 q = vec2(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y);
	vec2 uv = center + q * radius;
	vec4 c = texture(map_tex, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = sea_color;
	}
	c = mix(c, ring_color, smoothstep(0.90, 0.93, r));
	COLOR = vec4(c.rgb, 1.0 - smoothstep(0.985, 1.0, r));
}
