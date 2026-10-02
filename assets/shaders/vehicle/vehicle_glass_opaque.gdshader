shader_type spatial;
// Opaque dark vehicle glass (the bus has no interior to see); same look and
// cracks as vehicle_glass.gdshader (vehicle_glass.gdshaderinc).
render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_glass.gdshaderinc"

void fragment() {
	vec3 albedo;
	float alpha;
	float rough;
	glass_fragment(albedo, alpha, rough, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	// Opaque: darker tint stands in for the cabin you can't see.
	ALBEDO = albedo * mix(0.55, 1.0, alpha);
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
