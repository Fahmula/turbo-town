shader_type spatial;
// Vehicle cabins (ART_BIBLE.md §12-13): the "Interior" surfaces, one shared
// material. The models build the cabin from a few dark boxes and an inner
// copy of the shell; this tells the parts apart by which way they face (in
// object space), so a cabin reads through the glass like a real one:
//   facing down (headliner, under the roof): light warm grey cloth
//   facing up (seats, floor, dash top): dark fabric with a fine weave
//   facing sideways or fore/aft (door cards, seat backs, dash face): dark
//   satin plastic
// No textures; the weave fades out with distance (no shimmer).

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(obj_normal);
	float down = smoothstep(-0.35, -0.75, n.y);
	float up = smoothstep(0.35, 0.75, n.y);
	vec3 plastic = vec3(0.022, 0.023, 0.025);   // #2A2B2E-ish
	vec3 fabric = vec3(0.028, 0.028, 0.03);
	vec3 headliner = vec3(0.2, 0.19, 0.175);
	float near = 1.0 - smoothstep(1.5, 5.0, length(VERTEX));
	float weave = vh_noise(obj_pos * 260.0) * near;
	vec3 col = plastic;
	float rough = 0.55;
	col = mix(col, fabric * (0.85 + 0.3 * weave), up);
	rough = mix(rough, 0.92, up);
	col = mix(col, headliner * (0.95 + 0.1 * weave), down);
	rough = mix(rough, 0.95, down);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.3, max(up, down));
}
