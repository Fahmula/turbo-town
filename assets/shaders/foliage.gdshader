shader_type spatial;
render_mode cull_disabled;
// New-style trees (ART_BIBLE.md §18): leaf-cluster cards with alpha scissor
// around a solid core, normals pointing out from the canopy centre (baked in
// the mesh) for soft, cloud-like light, a gentle wind sway.
//
// COLOR.rgb = colour (sRGB; the AO gradient is baked in; MultiMesh instance
//             colours multiply it for per-tree variation).
// COLOR.a   = 1 leaf card (texture alpha, scissor at 0.5),
//             0.5 solid foliage (canopy core), 0 bark.
// UV        = leaf atlas coordinates on cards.
// The vertex's height above the tree's base drives the sway (bigger up top).

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.05;

void vertex() {
	if (quality > 0) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		float reach = clamp((VERTEX.y - 2.0) / 6.0, 0.0, 1.0) * (1.0 - smoothstep(60.0, 80.0, cam_dist));
		float t = TIME * 1.1 + origin.x * 0.13 + origin.z * 0.11;
		float gust = sin(t) * 0.6 + sin(t * 2.3 + VERTEX.y) * 0.4;
		float flutter = sin(TIME * 4.7 + dot(VERTEX, vec3(3.1, 1.7, 2.3))) * 0.3 * COLOR.a;
		VERTEX.xz += vec2(gust + flutter, (gust - flutter) * 0.6) * sway * reach;
	}
}

void fragment() {
	vec3 col = srgb_to_linear(COLOR.rgb);
	float kind = COLOR.a;
	if (kind > 0.75) {
		vec4 t = texture(leaves, UV);
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		col *= 0.72 + 0.45 * t.r;
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
		BACKLIGHT = col * 0.35;
	} else if (kind > 0.25) {
		ROUGHNESS = 0.9;
		SPECULAR = 0.25;
	} else {
		ROUGHNESS = 0.92;
		SPECULAR = 0.3;
	}
	ALBEDO = col;
}
