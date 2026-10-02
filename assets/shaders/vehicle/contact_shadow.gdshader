shader_type spatial;
// Contact shadow under a vehicle (ART_BIBLE.md §10: a dark multiply-blend
// quad with a soft falloff is allowed as extra grounding). A rounded
// rectangle that darkens the ground most under the middle of the car, so it
// sits on the road even in shade, where the sun's shadow can't help.
// `strength` (per instance, VehicleBodyVisual) fades it out in the air.
render_mode unshaded, blend_mul, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform float strength = 1.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	// Rounded-rectangle distance, 0 inside the core, 1 at the edge.
	vec2 q = max(p - vec2(0.55, 0.7), 0.0) / vec2(0.45, 0.3);
	float d = length(q);
	float mask = 1.0 - smoothstep(0.0, 1.0, d);
	mask *= mask;
	ALBEDO = vec3(1.0 - darkness * mask * strength);
}
