shader_type sky;
// Sky (ART_BIBLE.md §11): real photographed skies (Poly Haven's CC0 "pure
// sky" HDRIs, made into textures by tools/textures/fetch_sky.py). DayNight
// crossfades two of them through the day (`sky_a` -> `sky_b` by `sky_mix`),
// sets each one's brightness (`energy_*`) and turns each round the vertical
// axis (`rot_*`) so its photographed sun sits where the directional light
// is. The sun's own core is clamped out of the textures; a small disc is
// drawn here instead (`disc`). Below the horizon: the haze colour fading
// into an earthy ground (what paint and glass reflect).
//
// Texture layout: equirect upper hemisphere, u = atan(x, -z) / 2pi + 0.5,
// v = 0 at the zenith to 1 at the horizon.
// No TIME: the radiance map only re-renders when DayNight changes something.

uniform sampler2D sky_a : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_b : source_color, filter_linear, repeat_enable;
uniform float sky_mix : hint_range(0.0, 1.0) = 0.0;
uniform float energy_a = 1.0;
uniform float energy_b = 1.0;
uniform float rot_a = 0.0;
uniform float rot_b = 0.0;
// Linear colours.
uniform vec3 ground_bottom = vec3(0.12, 0.12, 0.11);
// The haze the distant land and sea fade into (DayNight: the fog colour);
// the lowest few degrees of sky fade into it too, so the horizon melts.
uniform vec3 haze = vec3(0.6, 0.65, 0.7);
uniform float haze_amount = 0.65;
uniform float disc = 1.0;

vec3 sample_sky(sampler2D tex, vec3 d, float rot, float energy) {
	float u = atan(d.x, -d.z) / TAU + 0.5 + rot / TAU;
	float v = acos(clamp(d.y, 0.0, 1.0)) / (PI * 0.5);
	return textureLod(tex, vec2(u, clamp(v, 0.0, 0.999)), 0.0).rgb * energy;
}

vec3 sky_at(vec3 d) {
	vec3 a = sample_sky(sky_a, d, rot_a, energy_a);
	if (sky_mix <= 0.001) {
		return a;
	}
	return mix(a, sample_sky(sky_b, d, rot_b, energy_b), sky_mix);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col;
	if (d.y >= 0.0) {
		col = sky_at(d);
		col = mix(col, haze, haze_amount * (1.0 - smoothstep(0.0, 0.09, d.y)));
		if (LIGHT0_ENABLED && disc > 0.0) {
			float a = acos(clamp(dot(LIGHT0_DIRECTION, d), -1.0, 1.0));
			float s = 1.0 - smoothstep(LIGHT0_SIZE * 0.8, LIGHT0_SIZE * 1.2, a);
			col = mix(col, LIGHT0_COLOR * LIGHT0_ENERGY * 6.0, s * disc);
		}
	} else {
		// Haze at the horizon fading into the ground.
		vec3 h = mix(sky_at(normalize(vec3(d.x, 0.0, d.z))), haze, haze_amount);
		col = mix(h, ground_bottom, smoothstep(0.0, 0.25, -d.y));
	}
	COLOR = col;
}
