shader_type spatial;
render_mode cull_disabled;
// Sea (realism branch): calm open water with three scrolling wave-normal
// scales (spectral map from tools/textures/fetch_terrain.py, faded with
// distance so nothing shimmers), sky reflection from the engine's fresnel at
// low roughness (sun glints from the normals), depth-based colour and
// transparency (you see the sandy sea floor in the shallows), and a pulsing,
// lacy foam sheet along the shore.
//
// Water depth comes from `shore`, a mask baked from the terrain heights at
// startup (NatureBuilder): R = depth below sea level / 8 m, covering
// `shore_rect` (x0, z0, width, depth); beyond it the sea is deep.
// Alpha blended (water is one of the allowed transparent surfaces, ART_BIBLE
// §6) with no SCREEN_TEXTURE or DEPTH_TEXTURE reads.
// Quality: Low = two normal scales, no foam texture; Medium = + ripples;
// High = + foam lace and wave-crest sparkle.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.035, 0.17, 0.27, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.52, 0.5, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.94, 0.93, 1.0);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore : hint_default_white, filter_linear, repeat_disable;
uniform vec4 shore_rect = vec4(-640.0, -640.0, 1280.0, 1280.0);
// How fast the colour gives way to deep water, and how fast the sea floor
// disappears (per metre of depth).
uniform float colour_depth = 2.2;
uniform float clarity = 0.85;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 slope(vec2 uv) {
	return texture(wave_normal, uv).xy * 2.0 - 1.0;
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	vec2 suv = (p - shore_rect.xy) / shore_rect.zw;
	bool inside = suv.x > 0.0 && suv.y > 0.0 && suv.x < 1.0 && suv.y < 1.0;
	float d_m = inside ? texture(shore, suv).r * 8.0 : 8.0;

	// ---- waves: swell, chop and ripples drifting in different directions ----
	vec2 s1 = slope(p / 63.0 + TIME * vec2(0.011, 0.006));
	vec2 s2 = slope(p / 17.0 + TIME * vec2(-0.017, 0.013));
	float f2 = 1.0 - smoothstep(50.0, 320.0, dist);
	float f1 = 1.0 - 0.65 * smoothstep(80.0, 500.0, dist);
	vec2 sl = s1 * 0.55 * f1 + s2 * 0.5 * f2;
	if (quality > 0) {
		vec2 s3 = slope(p / 4.6 + TIME * vec2(0.021, -0.016));
		float f3 = 1.0 - smoothstep(15.0, 110.0, dist);
		sl += s3 * 0.38 * f3;
	}
	// Flatter in the shallows (the swell dies as it reaches the beach).
	float calm = mix(0.35, 1.0, smoothstep(0.0, 1.5, d_m));
	vec3 n = normalize(vec3(sl * 0.62 * calm, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;

	// ----------------------------------------------------------- colour ----
	vec3 deep = deep_color.rgb;
	vec3 shallow = shallow_color.rgb;
	float k = smoothstep(0.0, colour_depth * 2.0, d_m);
	vec3 col = mix(shallow, deep, k);
	// Slow, broad colour drift (plankton, sand banks) so the sea isn't one flat tone.
	col *= 0.93 + 0.14 * texture(foam_tex, p / 330.0).b;

	// Alpha: the sea floor shows through the shallows; at grazing angles the
	// surface turns mirror-like, so the view-dependent term raises the alpha.
	float view = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - view, 4.0);
	float alpha = 1.0 - exp(-d_m * clarity * 1.35);
	alpha = clamp(max(alpha, fres * 0.85), 0.0, 1.0);

	// ------------------------------------------------------------- foam ----
	float foam = 0.0;
	if (inside && d_m < 1.6) {
		float t = TIME;
		float lace = 0.5;
		float bubbles = 0.0;
		float soft = 0.5;
		if (quality > 0) {
			vec3 f = texture(foam_tex, p / 6.5 + t * vec2(0.004, -0.003) + sl * 0.01).rgb;
			vec3 g = texture(foam_tex, p / 2.3 + vec2(0.37, 0.61)).rgb;
			lace = f.r * 0.6 + g.r * 0.4;
			bubbles = f.g;
			soft = f.b;
		}
		// The sheet surges up the beach and slides back, out of step along the shore.
		float surge = 0.5 + 0.5 * sin(t * 0.85 + p.x * 0.05 + p.y * 0.041 + soft * 5.0);
		float reach = 0.12 + 0.42 * surge;
		float sheet = 1.0 - smoothstep(0.0, reach, d_m);
		// Thin foam lines left behind by the previous waves.
		float trail = (1.0 - smoothstep(reach * 0.4, reach * 1.1 + 0.55, d_m)) * smoothstep(reach * 0.55, reach * 1.2, d_m);
		float body = clamp(sheet * 1.1 + trail * 0.45, 0.0, 1.0);
		float pattern = smoothstep(0.38, 0.72, lace * 0.75 + bubbles * 0.45 + (soft - 0.5) * 0.5 + body * 0.45);
		foam = body * pattern * smoothstep(0.0, 0.03, d_m + 0.02);
		foam = clamp(foam * 1.1, 0.0, 0.92);
	}
	ALBEDO = mix(col, foam_color.rgb, foam);
	ALPHA = mix(alpha, 1.0, foam);
	ROUGHNESS = mix(mix(0.035, 0.22, smoothstep(40.0, 600.0, dist)), 0.7, foam);
	SPECULAR = mix(0.5, 0.25, foam);
}
