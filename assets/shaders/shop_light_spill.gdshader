// Light from lit shop windows spilling onto the sidewalk at night (the
// MegaKit downtown experiment): a soft additive glow on a quad laid just over
// the paving in front of each shopfront, no real light (ART_BIBLE §9 keeps
// local lights for lamps). UV.x = 0..1 along the shopfront, UV.y = metres out
// from the wall, UV2 = the wall's outward normal (x, z). COLOR.rgb = tint.
// A shop glows only if megakit.gdshader lights it: the same hash of the 6 m
// shop cell along the wall. Reads the global `night`; invisible by day.

shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://assets/shaders/world_common.gdshaderinc"

uniform float strength = 0.32;
uniform float reach = 2.6;  // metres out from the wall where it has faded

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 nw = normalize(vec3(UV2.x, 0.0, UV2.y));
	vec3 tw = normalize(cross(vec3(0.0, 1.0, 0.0), nw));
	float cell = floor(dot(v_world, tw) / 6.0);
	float plane = dot(v_world, nw) - UV.y - 0.1;  // back at the wall
	float sh = hash12(vec2(cell, floor(plane + 0.5)) + 3.7);
	float lit = step(0.15, fract(sh * 17.3));
	float along = smoothstep(0.0, 0.1, UV.x) * smoothstep(1.0, 0.9, UV.x);
	float out_fade = 1.0 - smoothstep(0.0, reach, UV.y);
	float k = along * out_fade * out_fade * lit * night * strength;
	ALBEDO = COLOR.rgb * k;
}
