shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, alpha_to_coverage;
// Trees, shrubs and hedges (ART_BIBLE.md §18, realism branch): cards of real
// leaf clusters (photo scans on transparent backgrounds, atlases made by
// tools/textures/fetch_foliage.py), real bark, solid canopy blobs for the
// distant LOD. One draw per MultiMesh chunk. Everything is built by TreeKit
// (scripts/world/tree_kit.gd) and drawn by TreeLod (scripts/world/tree_lod.gd).
//
// Vertex data:
//   COLOR.r   ambient occlusion 0..1 (dark deep in the crown, light at the tips)
//   COLOR.g   per-card colour wobble, 0.5 = none (<0.5 cooler, >0.5 warmer)
//   COLOR.b   leaf thinness 0..1 (how much sun shines through, backlight)
//   COLOR.a   kind: 1 leaf card, 0.5 solid canopy blob, 0 bark
//   UV        leaf atlas coordinates on cards; bark UV (u around, v along in
//             bark-tile units) on wood
//   UV2       x = per-card wind phase 0..1, y = flex 0 (trunk) .. 1 (leaf tips)
//   NORMAL    on cards: the crown's "spherical" normal (the canopy shades as one
//             soft mass); on wood: the surface normal. TANGENT: round the tube.
// Per-instance (MultiMesh custom data): x autumn amount 0..1, y random seed,
//   z brightness variation 0..1 (0.5 = none), w = which blob colour (0, 1, 2).
// Quality: Low (quality == 0) drops sway, the bark normal map and the macro
// colour noise.

#include "res://assets/shaders/world_common.gdshaderinc"
#include "res://assets/shaders/foliage_common.gdshaderinc"

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform vec3 bark_tint : source_color = vec3(1.0);
uniform vec3 blob_dark : source_color = vec3(0.12, 0.2, 0.08);
uniform vec3 blob_lit : source_color = vec3(0.3, 0.4, 0.14);
uniform float translucency = 0.5;
uniform float sway = 0.05;
uniform float tree_height = 9.0;
uniform float alpha_cut = 0.5;
// 1: thin leaves, lit from both sides with the same normal; 0: the face turned away is shaded (conifer sprays).
uniform float two_sided = 1.0;

varying vec3 v_world;
varying vec4 v_inst;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (quality > 0 && sway > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float fade = 1.0 - smoothstep(60.0, 100.0, distance(origin, CAMERA_POSITION_WORLD));
		float h = clamp(VERTEX.y / tree_height, 0.0, 1.0);
		float t = TIME * 1.1 + origin.x * 0.13 + origin.z * 0.11 + INSTANCE_CUSTOM.y * 6.28;
		float gust = sin(t) * 0.6 + sin(t * 2.3 + VERTEX.y * 0.4) * 0.4;
		float flutter = sin(TIME * 4.7 + UV2.x * 40.0 + dot(VERTEX, vec3(3.1, 1.7, 2.3))) * UV2.y * COLOR.a;
		float amp = sway * fade;
		VERTEX.xz += vec2(gust * h * h + flutter * 0.35, (gust * h * h - flutter * 0.35) * 0.6) * amp * 1.4;
	}
}

void fragment() {
	float kind = COLOR.a;
	float ao = COLOR.r;
	// The mesh normals are the canopy's; keep them on the back of a card too.
	if (!FRONT_FACING && two_sided > 0.5) {
		NORMAL = -NORMAL;
	}
	// Alpha-tested cut-out with antialiased edges (alpha to coverage under MSAA);
	// set for every kind so the opaque wood and blobs aren't touched by it.
	vec2 tsz = vec2(textureSize(leaves, 0));
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * tsz;
	if (kind > 0.75) {
		vec4 t = texture(leaves, UV);
		ALPHA = fol_leaf_alpha(t.a, UV, tsz);
		vec3 col = t.rgb * leaf_tint;
		float wob = (COLOR.g - 0.5) * 2.0;
		col *= vec3(1.0 + wob * 0.12, 1.0, 1.0 - wob * 0.15);
		col *= 0.9 + 0.2 * v_inst.z;
		if (quality > 0) {
			float n = fol_noise(v_world.xz * 0.21 + v_world.y * 0.08);
			col *= vec3(mix(0.9, 1.08, n), mix(0.94, 1.04, n), mix(1.05, 0.9, n));
		}
		col = fol_autumn(col, v_inst.x, fract(v_inst.y * 7.3));
		ALBEDO = col * mix(1.0, ao, 0.55);
		AO = ao;
		AO_LIGHT_AFFECT = 0.6;
		ROUGHNESS = 0.7;
		SPECULAR = 0.12;
		BACKLIGHT = col * COLOR.b * translucency;
	} else if (kind > 0.25) {
		ALPHA = 1.0;
		float n = quality > 0 ? fol_noise(v_world.xz * 0.6 + v_world.y * 0.4) : 0.5;
		vec3 col = mix(blob_dark, blob_lit, clamp(ao * 0.8 + (n - 0.5) * 0.7, 0.0, 1.0));
		col = fol_autumn(col, v_inst.x, fract(v_inst.y * 7.3));
		ALBEDO = col * (0.9 + 0.2 * v_inst.z);
		AO = ao;
		AO_LIGHT_AFFECT = 0.6;
		ROUGHNESS = 0.9;
		SPECULAR = 0.1;
		BACKLIGHT = ALBEDO * 0.2 * translucency;
	} else {
		ALPHA = 1.0;
		vec3 b = texture(bark_albedo, UV).rgb * bark_tint;
		ALBEDO = b * mix(0.55, 1.0, ao);
		AO = ao;
		AO_LIGHT_AFFECT = 0.5;
		ROUGHNESS = 0.92;
		SPECULAR = 0.1;
		if (quality > 0) {
			NORMAL_MAP = texture(bark_normal, UV).rgb;
			NORMAL_MAP_DEPTH = 1.0;
		}
	}
}
