// Road and sidewalk markings of the Downtown City MegaKit (crosswalks,
// arrows, STOP / SLOW / ONLY, bike lanes, kerb stripes), laid a few mm over
// the surface. UV = the kit's markings atlas (megakit_decals.png: white or
// yellow paint, alpha = coverage). Alpha-blended, no shadows, drawn after
// the road (render_priority). COLOR.g = the kit's wear (fades paint).

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D decal_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float opacity = 0.92;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(decal_tex, UV);
	// Paint wears off in patches (stable world-space hash on a 0.5 m grid,
	// smoothed), more in the wheel paths.
	vec2 cell = floor(v_world.xz * 2.0);
	float wear = hash12(cell) * 0.35;
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity * (1.0 - wear) * mix(0.75, 1.0, COLOR.g);
	ROUGHNESS = 0.62;
	SPECULAR = 0.45;
}
