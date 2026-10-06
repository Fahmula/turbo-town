shader_type spatial;
// Aircraft lights (ART_BIBLE.md §13): a plane's "NavLight" surface.
// make_plane.py tags each lamp in UV0 (vh_kind): 1 red position light (left
// wing tip), 2 green (right wing tip), 3 white strobe (wing tips, tail),
// 4 red beacon (top of the fin). Position lights glow steadily (brighter at
// night); strobes double-flash about once a second and the beacon pulses,
// all timed by TIME so no script touches them per frame. `lights` 0 = the
// engine is off (parked planes are dark).

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

global uniform float night;

uniform float lights : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float kind;
	vec2 st;
	vh_kind(UV, kind, st);
	float t = TIME;
	vec3 lens;
	vec3 glow;
	float energy;
	if (kind < 1.5) {
		lens = vec3(0.42, 0.03, 0.025);
		glow = vec3(1.0, 0.05, 0.03);
		energy = mix(3.0, 9.0, night);
	} else if (kind < 2.5) {
		lens = vec3(0.03, 0.36, 0.1);
		glow = vec3(0.08, 1.0, 0.3);
		energy = mix(3.0, 9.0, night);
	} else if (kind < 3.5) {
		lens = vec3(0.78, 0.78, 0.8);
		glow = vec3(1.0, 0.98, 0.95);
		float c = fract(t * 0.9);
		energy = (step(c, 0.035) + step(0.11, c) * step(c, 0.145)) * 16.0;
	} else {
		lens = vec3(0.38, 0.03, 0.02);
		glow = vec3(1.0, 0.07, 0.03);
		float c = fract(t * 0.75 + 0.5);
		energy = smoothstep(0.0, 0.06, c) * (1.0 - smoothstep(0.1, 0.32, c)) * 9.0;
	}
	ALBEDO = lens;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	EMISSION = glow * energy * lights;
}
