shader_type spatial;
// A lightning bolt (Lightning): vertex colours, brighter than white so it
// blooms. Seen through the storm's haze, so no fog.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float energy = 6.0;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a;
}
