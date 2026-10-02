shader_type spatial;
render_mode cull_disabled;
// Sea (ART_BIBLE.md §19): calm water with two scrolling ripple normal maps
// (faded with distance), sky reflections through the low roughness (the
// engine's fresnel), turquoise shallows and a soft foam band at the shore.
// Water depth comes from `shore`, a mask baked from the terrain heights at
// startup (NatureBuilder): R = depth below sea level / 8 m, covering
// `shore_rect` (x0, z0, width, depth); beyond it the sea is deep.
// No SCREEN_TEXTURE or DEPTH_TEXTURE reads.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.118, 0.306, 0.431, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.247, 0.561, 0.584, 1.0);
uniform vec4 foam_color : source_color = vec4(0.90, 0.92, 0.92, 1.0);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore : hint_default_white, filter_linear, repeat_disable;
uniform vec4 shore_rect = vec4(-640.0, -640.0, 1280.0, 1280.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	vec2 suv = (p - shore_rect.xy) / shore_rect.zw;
	bool inside = suv.x > 0.0 && suv.y > 0.0 && suv.x < 1.0 && suv.y < 1.0;
	float depth = inside ? texture(shore, suv).r : 1.0;
	// Ripples: two scales drifting in different directions.
	vec3 n1 = texture(wave_normal, p * 0.035 + TIME * vec2(0.011, 0.006)).rgb * 2.0 - 1.0;
	vec3 n = n1;
	if (quality > 0) {
		vec3 n2 = texture(wave_normal, p * 0.09 + TIME * vec2(-0.009, 0.014)).rgb * 2.0 - 1.0;
		n = vec3(n1.xy + n2.xy, n1.z * n2.z);
	}
	float fade = 1.0 - smoothstep(60.0, 400.0, dist);
	n = normalize(mix(vec3(0.0, 0.0, 1.0), normalize(n), 0.2 + 0.4 * fade));
	NORMAL_MAP = n * 0.5 + 0.5;
	// Colour: turquoise over sand, deep blue offshore.
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.02, 0.45, depth));
	// Foam: a broken band right at the waterline, gently pulsing.
	float pulse = 0.5 + 0.5 * sin(TIME * 0.8 + p.x * 0.05 + p.y * 0.04);
	float band = 1.0 - smoothstep(0.012, 0.05 + 0.02 * pulse, depth);
	float breakup = smoothstep(0.35, 0.7, n1.x * 0.5 + 0.5 + (pulse - 0.5) * 0.3);
	float foam = inside ? band * breakup * 0.85 : 0.0;
	ALBEDO = mix(col, foam_color.rgb, foam);
	ROUGHNESS = mix(0.06, 0.7, foam);
	SPECULAR = 0.5;
}
