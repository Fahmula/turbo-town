// Helpers shared by terrain.gdshader and grass.gdshader (realism branch).
// Functions only, no uniforms, so each shader keeps its own parameters.
//
// `noise` is assets/textures/terrain/grass_noise.png (tileable): R = 22-180 m
// features, G = 6-30 m, B = 2-9 m, A = 250-1000 m, all around 0.5.

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
// Sea level (MapLayout.SEA_LEVEL).
const float SEA_LEVEL_Y = -1.2;

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Large-scale ground variation, identical for the ground and for the grass
// tufts standing on it. x = dry (straw) amount, y = lush (deep green) amount,
// z = mid-scale patchiness 0..1. `dry_w` is the dry weight baked into the
// terrain (the mountain top).
vec3 ground_macro(sampler2D noise, vec2 wp, float dry_w) {
	vec4 a = textureLod(noise, wp / 190.0, 0.0);
	vec4 b = textureLod(noise, wp / 1100.0 + vec2(0.37, 0.11), 0.0);
	float dry = clamp(dry_w + smoothstep(0.2, 0.42, (b.a - 0.5) * 0.9 + (a.r - 0.5) * 0.5 + (a.g - 0.5) * 0.25) * 0.9, 0.0, 1.0);
	float lush = smoothstep(-0.02, -0.2, (a.g - 0.5) * 0.7 + (b.a - 0.5) * 0.3) * (1.0 - dry);
	return vec3(dry, lush, a.g);
}

// The tint multiplier the macro variation gives grass colour.
vec3 grass_tint(vec3 macro, float patch_cn) {
	vec3 t = mix(vec3(0.82, 0.93, 0.78), vec3(1.12, 1.08, 0.92), patch_cn);
	t = mix(t, vec3(0.74, 0.96, 0.66), macro.y * 0.8);
	return t;
}

// Tangent-space normal map sample (OpenGL convention, RG only) to a vector
// in the world XZ plane for a texture projected from above: +U along +X,
// image-up (+Y) along -Z. `r` is the UV rotation that was applied to the world
// position (identity for the first scale).
vec3 ts_to_world_top(vec2 tn, mat2 r) {
	vec2 w = transpose(r) * vec2(tn.x, -tn.y);
	return vec3(w.x, 0.0, w.y);
}
