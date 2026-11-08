shader_type spatial;
// Far parked cars (ART_BIBLE.md §27): beyond ParkedCarLod.NEAR a parked-car
// prop is one merged mesh with this one shared material, and the same mesh
// (without its see-through glass) casts the car's shadow at every distance.
// The parts' looks are baked into the vertices by ParkedCarLod:
//   COLOR.rgb = linear albedo, COLOR.a = roughness,
//   UV2.x = metallic, UV2.y = 1 on paint,
//   UV.x / UV.y = how strongly a lamp glows white / red (the DRLs and tail
//   lights glow a little even on parked cars, as in vehicle_lamp).
// The paint comes per car from instance uniforms, and follows car_paint's
// solid / metallic gloss, clear coat, metallic flop and toned-down ground
// reflection (no flakes: they fade out long before this distance).

render_mode cull_back;

instance uniform vec4 paint_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
instance uniform float paint_metallic = 0.0;

void fragment() {
	float paint = UV2.y;
	float metal = paint_metallic;
	vec3 col = paint_color.rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col *= mix(1.0, mix(0.6, 1.12, smoothstep(0.05, 0.85, ndv)), clamp(metal * 1.6, 0.0, 1.0));
	ALBEDO = mix(COLOR.rgb, col, paint);
	METALLIC = mix(UV2.x, metal, paint);
	ROUGHNESS = mix(COLOR.a, mix(0.13, 0.2, step(0.01, metal)), paint);
	CLEARCOAT = 0.6 * paint;
	CLEARCOAT_ROUGHNESS = 0.05;
	vec3 r_world = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	EMISSION = vec3(1.0, 0.95, 0.86) * UV.x + vec3(1.0, 0.035, 0.02) * UV.y;
	SPECULAR = 0.5 * mix(1.0, mix(0.55, 1.0, smoothstep(-0.35, 0.02, r_world.y)), paint);
}
