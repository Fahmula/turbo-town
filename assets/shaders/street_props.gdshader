shader_type spatial;
// Street furniture and building clutter (ART_BIBLE.md §17): one
// material for every part, so a lamp post or a whole block's roof clutter is
// a single draw call. The material type comes from the vertex colour alpha.
//
// COLOR.rgb = albedo (sRGB; contact AO baked in by darkening).
// COLOR.a   = material, class / 15:
//    0 painted metal / painted anything   1 bare or galvanised metal
//    2 concrete / stone                   3 plastic
//    4 rubber, black trim                 5 glass, lens
//    6 warm lamp (glows at night)         7 cool LED lamp (glows at night)
//    8 / 9 / 10 signal lens red / amber / green (lit by `signal`)
//    11 sign face (slightly glossy)       12 fabric (awnings)
//    13 wood                              14 always-on glow (screens, beacons)
//    15 deck panels (ramps): paint with a panel seam every 1.22 m along UV.y
// instance uniform `signal`: which signal lens is lit (0 red, 1 amber,
//    2 green, -1 none); set per traffic light with set_instance_shader_parameter.
// instance uniform `tint`: multiplies painted parts (class 0), e.g. a
//    random colour per oil drum.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
instance uniform int signal = -1;
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int kind = int(round(COLOR.a * 15.0));
	vec3 col = srgb_to_linear(COLOR.rgb);
	float rough = 0.55;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	float near = detail_fade(length(VERTEX));
	float g = quality == 0 ? 0.5 : texture(detail, (world_pos.xz + world_pos.y * 0.7) * 0.5).r;
	if (kind == 1) {
		metal = 1.0;
		rough = 0.42 + (g - 0.5) * 0.1;
	} else if (kind == 2) {
		rough = 0.88;
		col *= 1.0 + (g - 0.5) * 0.12 * near;
	} else if (kind == 4) {
		rough = 0.85;
	} else if (kind == 5) {
		rough = 0.08;
	} else if (kind == 6 || kind == 7) {
		rough = 0.2;
		vec3 lamp = kind == 6 ? vec3(1.0, 0.886, 0.69) : vec3(0.91, 0.941, 1.0);
		col = mix(col, lamp, night);
		emit = lamp * night * 5.0;
	} else if (kind >= 8 && kind <= 10) {
		rough = 0.12;
		vec3 lens = kind == 8 ? vec3(1.0, 0.12, 0.08) : (kind == 9 ? vec3(1.0, 0.62, 0.05) : vec3(0.1, 1.0, 0.45));
		bool on = signal == kind - 8;
		col = on ? lens : lens * 0.12 + 0.02;
		emit = on ? lens * 3.0 : vec3(0.0);
	} else if (kind == 11) {
		rough = 0.35;
	} else if (kind == 12) {
		rough = 0.95;
		spec = 0.3;
		col *= 1.0 + (g - 0.5) * 0.1 * near;
	} else if (kind == 13) {
		rough = 0.8;
		col *= 1.0 + (g - 0.5) * 0.2 * near;
	} else if (kind == 14) {
		rough = 0.3;
		emit = col * (0.8 + 1.2 * night);
	} else if (kind == 3) {
		rough = 0.55;
	} else if (kind == 15) {
		float seam = grid_line(UV.y, 1.22, 0.012);
		col *= 1.0 + (g - 0.5) * 0.16 * near;
		col *= 1.0 - seam * 0.35;
		rough = 0.62 + seam * 0.2;
	} else {
		col *= tint.rgb;
		rough = 0.5 + (g - 0.5) * 0.1;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
