shader_type spatial;
// Vehicle lamps (ART_BIBLE.md §13): the "Headlight", "TailLight" and
// "ReverseLight" surfaces. VehicleBodyVisual gives each car its own copy and
// sets the state uniforms (brake, reverse, indicators, broken).
//
// One surface holds several lamps: body_kit tags each patch in UV0 (kind and
// (s, t) metres from the patch centre, decoded by vh_kind):
//   0 untagged = 1 LAMP: headlight beam / tail-and-brake / reverse lamp
//   2 DRL: daytime running light in front, position light at the back
//   3 INDICATOR: amber; left side = object x < 0
//   4 AUX: fog lamps and light bars, lit at night only
//   5 BRAKE_ONLY: third brake light
// Unlit, a lamp is a glossy lens over a chrome reflector (it reflects the
// street like a real headlight in daylight); lit, it glows with a hot core.
// Headlights and position lights come on with the global `night` (DayNight)
// unless `lights` forces them (>= 0).

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

global uniform float night;

// 0 = headlight, 1 = tail light, 2 = reverse lamp.
uniform int lamp = 0;
uniform float brake : hint_range(0.0, 1.0) = 0.0;
uniform float reverse : hint_range(0.0, 1.0) = 0.0;
uniform float blink_left : hint_range(0.0, 1.0) = 0.0;
uniform float blink_right : hint_range(0.0, 1.0) = 0.0;
uniform float lights = -1.0;
uniform float broken : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float kind;
	vec2 st;
	vh_kind(UV, kind, st);
	kind = max(kind, 1.0);
	float on = lights >= 0.0 ? lights : smoothstep(0.25, 0.7, night);
	float blink = obj_pos.x < 0.0 ? blink_left : blink_right;

	vec3 lens;
	vec3 glow;
	float energy = 0.0;
	float metal = 0.0;
	float rough = 0.08;
	if (kind > 2.5 && kind < 3.5) {
		lens = vec3(0.62, 0.2, 0.012);
		glow = vec3(1.0, 0.42, 0.04);
		energy = blink * 5.0;
	} else if (lamp == 1) {
		lens = vec3(0.16, 0.006, 0.006);
		glow = vec3(1.0, 0.035, 0.02);
		float running = mix(0.25, 1.4, on);
		if (kind < 1.5) {
			energy = max(running, brake * 5.5);
		} else if (kind < 2.5) {
			energy = running;
		} else {
			energy = brake * 5.5;
		}
	} else if (lamp == 2) {
		lens = vec3(0.7);
		glow = vec3(1.0, 0.98, 0.95);
		energy = reverse * 3.5;
		metal = 1.0;
		rough = 0.12;
	} else {
		lens = vec3(0.78, 0.79, 0.8);
		glow = vec3(1.0, 0.95, 0.86);
		metal = 1.0;
		rough = 0.1;
		if (kind < 1.5) {
			energy = on * 6.0;
		} else if (kind < 2.5) {
			energy = mix(2.4, 1.6, on);
		} else {
			energy = on * 3.5;
		}
	}

	// Inside the lens: reflector ribs (rect lamps) or a projector ring (round
	// ones) from the patch coordinates, and a hotter core when lit.
	float r = length(st);
	float ribs = 0.5 + 0.5 * sin(st.x * 520.0);
	float rib_fade = 1.0 - smoothstep(0.3, 0.9, fwidth(st.x * 520.0));
	float ring = smoothstep(0.018, 0.022, r) * (1.0 - smoothstep(0.026, 0.032, r));
	float core = 1.0 - smoothstep(0.0, 0.05, r);
	rough += (ribs - 0.5) * 0.12 * rib_fade;
	vec3 albedo = lens * (1.0 - ring * 0.5);
	vec3 emit = glow * energy * (0.75 + 0.35 * core) * (1.0 - ring * 0.4);

	if (broken > 0.0) {
		// Smashed: a dark, dull housing with a few lens shards left.
		float shard = step(0.72, vh_hash3(floor(obj_pos * 38.0)));
		albedo = mix(albedo, mix(vec3(0.028), lens * 0.6, shard), broken);
		rough = mix(rough, mix(0.85, 0.2, shard), broken);
		metal *= 1.0 - broken;
		emit *= 1.0 - broken;
	}
	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	EMISSION = emit;
}
