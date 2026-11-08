shader_type spatial;
// Far cars (ART_BIBLE.md §27): beyond CarLod.NEAR a parked car or a traffic
// car is one merged mesh with this one shared material, and the same mesh
// (without its see-through glass) casts the car's shadow at every distance.
// The parts' looks are baked into the vertices by CarLod:
//   COLOR.rgb = linear albedo, COLOR.a = roughness,
//   UV2.x = metallic, UV2.y = 1 on paint,
//   UV.x = lamp code (below), UV.y = where grime collects on the paint
//   (car_paint's lower-body falloff, baked from the part's own height).
// Per car, through instance uniforms: the paint, its grime, and the lamp
// states VehicleBodyVisual drives (parked cars: lights forced off).
// Paint follows car_paint (solid / metallic gloss, clear coat, metallic flop,
// toned-down ground reflection, grime; no flakes: they fade out long before
// this distance). Lamps follow vehicle_lamp's energies, with the lens's
// average 0.8 for its ring and hot core.

render_mode cull_back;

global uniform float night;

instance uniform vec4 paint_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
instance uniform float paint_metallic = 0.0;
instance uniform float dirt = 0.0;
// >= 0 forces the head and position lights (parked: 0); < 0 follows `night`.
instance uniform float lights = -1.0;
instance uniform float brake = 0.0;
instance uniform float reverse = 0.0;
instance uniform vec2 blink = vec2(0.0);  // left, right

// Lamp codes (CarLod._lamp_look): 1 headlight beam, 2 DRL, 3 / 4 left / right
// indicator, 5 aux (night only), 6 tail lamp, 7 position light, 8 brake only,
// 9 reverse.
const vec3 HEAD = vec3(1.0, 0.95, 0.86);
const vec3 TAIL = vec3(1.0, 0.035, 0.02);
const vec3 AMBER = vec3(1.0, 0.42, 0.04);
const vec3 REVERSE = vec3(1.0, 0.98, 0.95);
const vec3 DIRT = vec3(0.243, 0.196, 0.140);  // car_paint's dirt_color, linear

varying vec3 glow;

void vertex() {
	int code = int(UV.x + 0.5);
	glow = vec3(0.0);
	if (code > 0) {
		float on = lights >= 0.0 ? lights : smoothstep(0.25, 0.7, night);
		float running = mix(0.25, 1.4, on);
		if (code == 1) {
			glow = HEAD * on * 6.0;
		} else if (code == 2) {
			glow = HEAD * mix(2.4, 1.6, on);
		} else if (code == 3) {
			glow = AMBER * blink.x * 5.0;
		} else if (code == 4) {
			glow = AMBER * blink.y * 5.0;
		} else if (code == 5) {
			glow = HEAD * on * 3.5;
		} else if (code == 6) {
			glow = TAIL * max(running, brake * 5.5);
		} else if (code == 7) {
			glow = TAIL * running;
		} else if (code == 8) {
			glow = TAIL * brake * 5.5;
		} else {
			glow = REVERSE * reverse * 3.5;
		}
		glow *= 0.8;
	}
}

void fragment() {
	float paint = UV2.y;
	float metal = paint_metallic;
	vec3 col = paint_color.rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col *= mix(1.0, mix(0.6, 1.12, smoothstep(0.05, 0.85, ndv)), clamp(metal * 1.6, 0.0, 1.0));
	float rough = mix(0.13, 0.2, step(0.01, metal));
	float coat = 0.6;
	// Grime: car_paint's splash noise averages out at this distance.
	float grime = clamp(dirt * (UV.y + 0.06), 0.0, 1.0);
	col = mix(col, DIRT, grime * 0.85);
	rough = mix(rough, 0.8, grime);
	metal *= 1.0 - grime;
	coat *= 1.0 - grime;
	ALBEDO = mix(COLOR.rgb, col, paint);
	METALLIC = mix(UV2.x, metal, paint);
	ROUGHNESS = mix(COLOR.a, rough, paint);
	CLEARCOAT = coat * paint;
	CLEARCOAT_ROUGHNESS = 0.05;
	EMISSION = glow;
	vec3 r_world = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	SPECULAR = 0.5 * mix(1.0, mix(0.55, 1.0, smoothstep(-0.35, 0.02, r_world.y)), paint);
}
