// Helpers for foliage.gdshader (trees, shrubs, hedges). Needs world_common.gdshaderinc
// first (for hash12 and the global `quality`).

// Smooth value noise in 2D (cheap: four hashes), 0..1.
float fol_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Which mip level a texture lookup at `uv` will use (for a texture of `size` texels).
float fol_mip(vec2 uv, vec2 size) {
	vec2 dx = dFdx(uv * size);
	vec2 dy = dFdy(uv * size);
	return max(0.0, 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8)));
}

// Leaf mask with coverage compensation: the cut-out shrinks as mip levels blur
// thin leaves toward the average alpha, so boost it a little per mip level and
// canopies keep their density at a distance.
float fol_leaf_alpha(float a, vec2 uv, vec2 size) {
	return clamp(a * (1.0 + fol_mip(uv, size) * 0.3), 0.0, 1.0);
}

// Hue shift towards autumn (ochre / rust) by `amount` 0..1.
vec3 fol_autumn(vec3 c, float amount, float k) {
	vec3 ochre = vec3(c.g * 1.25, c.g * 0.9, c.b * 0.35);
	vec3 rust = vec3(c.g * 1.1, c.g * 0.5, c.b * 0.3);
	return mix(c, mix(ochre, rust, k), amount);
}
