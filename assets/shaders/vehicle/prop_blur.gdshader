shader_type spatial;
// The propeller's blur disc (the "PropDisc" mesh of a plane, ART_BIBLE.md
// §13), and a helicopter's rotor discs ("RotorDisc", "TailDisc"). When the
// blades turn fast they smear into a faint disc: a soft grey veil, two
// "ghost" blades turning slowly (the stroboscopic look a camera sees) and a
// yellow ring where the painted tips run. Aircraft / Helicopter set `amount`
// (0 = invisible) and `spin` (the ghost blades' angle) every frame. The disc
// lies in the mesh's XY plane (`axis` 0: the plane's propeller), XZ plane
// (1: a main rotor) or YZ plane (2: a tail rotor), from `inner` to 1 of
// `radius`.

render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
uniform float radius = 0.9;
uniform int axis = 0;
uniform float inner = 0.36;
// How strongly the painted tips show as a ring (a big rotor shows a faint one).
uniform float tip_strength = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec2 p = axis == 1 ? obj_pos.xz : (axis == 2 ? obj_pos.yz : obj_pos.xy);
	float r = length(p) / radius;
	float a = atan(p.y, p.x);
	float ghost = pow(0.5 + 0.5 * cos(2.0 * (a - spin)), 10.0);
	float tip = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.95, 0.99, r)) * tip_strength;
	float body = smoothstep(inner - 0.03, inner + 0.04, r) * (1.0 - smoothstep(0.96, 1.0, r));
	ALBEDO = mix(vec3(0.06, 0.06, 0.065), vec3(0.85, 0.66, 0.1), tip);
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
	ALPHA = clamp(amount * body * (0.16 + 0.28 * ghost * (1.0 - r * 0.4) + 0.2 * tip), 0.0, 1.0);
}
