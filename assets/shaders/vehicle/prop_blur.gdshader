shader_type spatial;
// The propeller's blur disc (the "PropDisc" mesh of a plane, ART_BIBLE.md
// §13). When the propeller turns fast its blades smear into a faint disc:
// a soft grey veil, two "ghost" blades turning slowly (the stroboscopic look
// a camera sees) and a yellow ring where the painted tips run. Aircraft sets
// `amount` (0 = invisible, below ~250 rpm) and `spin` (the ghost blades'
// angle) every frame. The disc lies in the mesh's XY plane, radius 0.3..0.9.

render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
uniform float radius = 0.9;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float r = length(obj_pos.xy) / radius;
	float a = atan(obj_pos.y, obj_pos.x);
	float ghost = pow(0.5 + 0.5 * cos(2.0 * (a - spin)), 10.0);
	float tip = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.95, 0.99, r));
	float body = smoothstep(0.33, 0.4, r) * (1.0 - smoothstep(0.96, 1.0, r));
	ALBEDO = mix(vec3(0.06, 0.06, 0.065), vec3(0.85, 0.66, 0.1), tip);
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
	ALPHA = clamp(amount * body * (0.16 + 0.28 * ghost * (1.0 - r * 0.4) + 0.2 * tip), 0.0, 1.0);
}
