shader_type spatial;
// Underglow (ART_BIBLE.md §12): a soft pool of neon light on the ground under
// the player's car, an additive quad like the contact shadow (no real light
// and no decal: a Decal measured ~1 ms on the iGPU at Medium, this ~0).
// A rounded rectangle, brightest under the sills. `strength` (per instance,
// Underglow) fades it out in the air; `energy` is higher at night.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.2, 0.4, 1.0, 1.0);
uniform float energy = 0.6;
instance uniform float strength = 1.0;

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	// 0 inside the car's footprint, 1 at the quad's edge.
	vec2 q = max(p - vec2(0.42, 0.62), 0.0) / vec2(0.58, 0.38);
	float d = length(q);
	float mask = 1.0 - smoothstep(0.0, 1.0, d);
	mask *= mask;
	// A little brighter along the sides, where the tubes are.
	mask *= 0.75 + 0.25 * smoothstep(0.1, 0.6, p.x);
	ALBEDO = glow_color.rgb * energy * mask * strength;
}
