shader_type spatial;
// Car paint (ART_BIBLE.md §13, §14): every vehicle's "Paint" and "Stripe"
// surfaces and the parked cars. VehicleBodyVisual.paint_material() makes one
// per car.
//
// * Gloss: a low base roughness plus a clear coat. Reflection probes (the
//   player's VehicleReflection) replace Godot's clear-coat reflection with the
//   base layer's, so the base itself must be glossy for crisp reflections.
// * Metallic paints: colour "flop" (brighter facing the camera, darker at
//   grazing angles) and fine flakes that glint up close (faded with distance).
// * Reflections of the ground are toned down, so the lower doors read dark
//   like a real car's instead of mirroring the sky's pale ground half.
// * Grime: `dirt` (0..1) dusts the lower body (object-space height, broken up
//   by splash noise). VehicleBodyVisual raises it while driving on dirt.
// * Damage: vertex colour, written by VehicleDamage when it dents a mesh,
//   stored inverted so meshes without colours read as clean (Godot's default
//   vertex colour is white): G = 1 - scrape, B = 1 - paint loss (R and A
//   reserved). The mask goes clean paint -> scuffed (rougher, lighter) ->
//   primer #8C8C88 -> bare steel #9A9C9E, as streaks along the body for
//   scrapes and blotches for impacts.
// Object space: origin at wheel-centre height, -Z forward, +Y up.

render_mode cull_back;

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

uniform vec4 paint_color : source_color = vec4(0.784, 0.137, 0.106, 1.0);
// 0 = solid paint, 0.35-0.6 = metallic (PaintPalette).
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float solid_roughness : hint_range(0.0, 1.0) = 0.13;
uniform float metallic_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.6;
uniform float clearcoat_gloss_roughness : hint_range(0.0, 1.0) = 0.05;
// 0 = clean, 1 = filthy.
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dirt_color : source_color = vec4(0.53, 0.48, 0.41, 1.0);
// Object-space heights (m) between which grime fades in toward the bottom.
uniform float dirt_top = 0.3;
uniform float dirt_bottom = -0.3;
// Stripes and other flat accents: no flakes or flop.
uniform bool plain = false;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 col = paint_color.rgb;
	float metal = plain ? 0.0 : metallic_amount;
	float rough = mix(solid_roughness, metallic_roughness, step(0.01, metal));
	float coat = clearcoat_amount;
	vec3 n = NORMAL;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float dist = length(VERTEX);

	if (metal > 0.0) {
		// Flop, and flakes up close.
		col *= mix(1.0, mix(0.6, 1.12, smoothstep(0.05, 0.85, ndv)), clamp(metal * 1.6, 0.0, 1.0));
		float near = 1.0 - smoothstep(0.8, 3.0, dist);
		if (near > 0.0) {
			vec3 cell = floor(obj_pos * 420.0);
			vec3 jitter = vec3(vh_hash3(cell), vh_hash3(cell + 17.0), vh_hash3(cell + 41.0)) - 0.5;
			n = normalize(n + (VIEW_MATRIX * vec4(jitter, 0.0)).xyz * 0.22 * near * metal);
		}
	}

	// Grime on the lower body.
	float low = smoothstep(dirt_top, dirt_bottom, obj_pos.y);
	float splash = vh_noise(vec3(obj_pos.x * 2.2, obj_pos.y * 7.0, obj_pos.z * 1.6));
	float grime = clamp(dirt * (low * (0.55 + 0.9 * splash) + 0.12 * splash), 0.0, 1.0);
	col = mix(col, dirt_color.rgb, grime * 0.85);
	rough = mix(rough, 0.8, grime);
	metal *= 1.0 - grime;
	coat *= 1.0 - grime;

	// Damage layers.
	float scrape = 1.0 - COLOR.g;
	float loss = 1.0 - COLOR.b;
	if (scrape + loss > 0.01) {
		float streak = vh_noise(vec3(obj_pos.x * 3.0, obj_pos.y * 38.0, obj_pos.z * 2.0));
		float blotch = vh_noise(obj_pos * 8.0) * 0.7 + vh_noise(obj_pos * 23.0) * 0.3;
		float d = max(scrape * (0.45 + 0.85 * streak), loss * (0.4 + 0.9 * blotch));
		float scuff = vh_step(0.18, d, 0.02);
		float primer = vh_step(0.42, d, 0.02);
		float bare = vh_step(0.64, d, 0.02);
		col = mix(col, col * 1.12 + 0.03, scuff * 0.7);
		rough = mix(rough, rough + 0.25, scuff);
		coat *= 1.0 - scuff;
		col = mix(col, vec3(0.262, 0.262, 0.249), primer);      // primer #8C8C88
		rough = mix(rough, 0.7, primer);
		metal *= 1.0 - primer;
		col = mix(col, vec3(0.323, 0.330, 0.337), bare);        // bare steel #9A9C9E
		rough = mix(rough, 0.35, bare);
		metal = mix(metal, 1.0, bare);
	}

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	NORMAL = n;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_gloss_roughness;
	// Tone down what reflects the ground (the sky's ground half is pale).
	vec3 r_world = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, n), 0.0)).xyz;
	SPECULAR = 0.5 * mix(0.55, 1.0, smoothstep(-0.35, 0.02, r_world.y));
}
