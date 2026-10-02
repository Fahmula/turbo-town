shader_type spatial;
// See-through vehicle glass; everything is in vehicle_glass.gdshaderinc.
render_mode blend_mix, cull_back, depth_draw_opaque;

#include "res://assets/shaders/vehicle/vehicle_glass.gdshaderinc"

void fragment() {
	vec3 albedo;
	float alpha;
	float rough;
	glass_fragment(albedo, alpha, rough, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
