// The car paint, shared by car_paint.gdshader (every vehicle, traffic and
// parked cars) and car_paint_custom.gdshader (the player's garage paint:
// finishes, two-tone, decals, race numbers; defines PAINT_CUSTOM). See
// car_paint.gdshader for the look.
#ifdef PAINT_CUSTOM
#define FLAKES_AMOUNT flakes
#else
#define FLAKES_AMOUNT 1.0
#endif

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

#ifdef PAINT_CUSTOM
// --- Garage paint (the player's car only: car_paint_custom.gdshader) ---
// Finish extras: pearl tints grazing angles toward pearl_color; chrome is a
// bright metallic mirror without flakes.
uniform float pearl = 0.0;
uniform vec4 pearl_color : source_color = vec4(1.0);
uniform float flakes = 1.0;
// Two-tone: 0 off, 1 roof, 2 bonnet, 3 bonnet + roof, 4 lower half.
uniform int tone_mode = 0;
uniform vec4 tone_color : source_color = vec4(0.165, 0.173, 0.188, 1.0);
// Body lines in object space (VehicleBodyVisual measures them from the
// model): x = belt (bottom of the side windows), y = roof (top of the
// glass), z = windscreen base (front-most glass), w = rear window base.
uniform vec4 body_lines = vec4(0.47, 0.85, -0.62, 1.58);
// x = underbody height, y = nose, z = tail (object space).
uniform vec3 body_ends = vec3(-0.24, -2.2, 2.2);
// Side graphics: a strip from decal_atlas (decal_rows rows of 4:1), as high
// as the side between sill and belt. decal_mode: 0 starts at the nose,
// 1 at the tail, 2 stretches nose to tail.
uniform sampler2D decal_atlas : hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int decal_row = -1;
uniform int decal_rows = 6;
uniform int decal_mode = 0;
uniform vec4 decal_color : source_color = vec4(1.0);
// Race number: a white roundel with digits on both doors (and the bonnet
// if hood_number). digits holds 0-9 in one row.
uniform sampler2D digits : hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int number = -1;
uniform vec4 number_color : source_color = vec4(0.11, 0.11, 0.12, 1.0);
// x = roundel centre z on the doors, y = its diameter, z = bonnet roundel
// centre z, w = bonnet roundel diameter (0 = none).
uniform vec4 number_place = vec4(0.1, 0.42, -1.4, 0.5);
// Height of the door roundel's centre (object space).
uniform float number_y = 0.15;
// Bottom of the side graphics: just above the painted body's lowest point.
uniform float side_bottom = -0.17;
varying vec3 obj_normal;

// 1 where x is above `edge` (x varies per pixel; edge is a uniform),
// anti-aliased over a pixel.
float pc_above(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return clamp((x - edge) / w + 0.5, 0.0, 1.0);
}

float pc_below(float edge, float x) {
	return 1.0 - pc_above(edge, x);
}

// Coverage of the digits of `n` at roundel coordinates p (-0.5..0.5, +y up).
float pc_digits(vec2 p, int n) {
	int count = n >= 10 ? 2 : 1;
	float gw = 0.3, gh = 0.46;   // glyph box (x roundel diameter)
	float total = gw * float(count) * 0.92;
	float a = 0.0;
	// Both glyphs are always sampled (masked after), so mipmaps pick the
	// same level across a pixel quad.
	for (int k = 0; k < 2; k++) {
		int d = count == 2 ? (k == 0 ? n / 10 : n % 10) : n;
		float x0 = -total * 0.5 + float(k) * gw * 0.92;
		vec2 g = vec2((p.x - x0) / gw, 0.5 - p.y / gh);
		float inside = step(0.0, g.x) * step(g.x, 1.0) * step(0.0, g.y) * step(g.y, 1.0) * step(float(k), float(count) - 0.5);
		vec2 c = clamp(g, vec2(0.02), vec2(0.98));
		a = max(a, texture(digits, vec2((float(d) + c.x) / 10.0, c.y)).r * inside);
	}
	return a;
}

// A roundel at coordinates p (in diameters from its centre): white disc,
// digits in number_color. Returns rgb in .rgb, coverage in .a.
vec4 pc_roundel(vec2 p) {
	float r = length(p);
	float w = max(fwidth(r), 1e-4);
	float disc = clamp((0.5 - r) / w + 0.5, 0.0, 1.0);
	float ink = pc_digits(p, number);
	return vec4(mix(vec3(0.9, 0.9, 0.88), number_color.rgb, ink), disc);
}
#endif

void vertex() {
	obj_pos = VERTEX;
#ifdef PAINT_CUSTOM
	obj_normal = NORMAL;
#endif
}

void fragment() {
	vec3 col = paint_color.rgb;
#ifdef PAINT_CUSTOM
	vec3 on = normalize(obj_normal);
	float up = smoothstep(0.5, 0.65, on.y);
	if (tone_mode > 0) {
		float tone = 0.0;
		if (tone_mode == 1 || tone_mode == 3) {
			tone = max(tone, up * pc_above(body_lines.y - 0.04, obj_pos.y)
				* pc_above(body_lines.z, obj_pos.z) * pc_below(body_lines.w, obj_pos.z));
		}
		if (tone_mode == 2 || tone_mode == 3) {
			tone = max(tone, up * pc_below(body_lines.z - 0.02, obj_pos.z)
				* pc_above(mix(body_ends.x, body_lines.x, 0.3), obj_pos.y));
		}
		if (tone_mode == 4) {
			tone = pc_below(mix(body_ends.x, body_lines.x, 0.5), obj_pos.y);
		}
		col = mix(col, tone_color.rgb, tone);
	}
#endif
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
			n = normalize(n + (VIEW_MATRIX * vec4(jitter, 0.0)).xyz * 0.22 * near * metal * FLAKES_AMOUNT);
		}
	}
#ifdef PAINT_CUSTOM
	// Pearl: grazing angles shift toward the pearl tint.
	col = mix(col, pearl_color.rgb, pearl * pow(1.0 - ndv, 2.5) * 0.6);

	// Side graphics and race numbers (painted on: under grime and damage).
	float side = smoothstep(0.35, 0.6, abs(on.x));
	float y0 = side_bottom;
	float h = max(body_lines.x - 0.03 - y0, 0.1);
	if (decal_row >= 0) {
		float v = (obj_pos.y - y0) / h;
		float len = decal_mode == 2 ? (body_ends.z - body_ends.y) : h * 4.0;
		float u = decal_mode == 1 ? (body_ends.z - obj_pos.z) / len : (obj_pos.z - body_ends.y) / len;
		float inside = step(0.0, u) * step(u, 1.0) * step(0.0, v) * step(v, 1.0);
		vec2 uv = vec2(clamp(u, 0.0, 1.0), (float(decal_row) + clamp(1.0 - v, 0.01, 0.99)) / float(decal_rows));
		col = mix(col, decal_color.rgb, texture(decal_atlas, uv).r * side * inside);
	}
	if (number >= 0) {
		// Read the right way round from each side: screen right is the
		// front on the right side, the rear on the left.
		vec2 ps = vec2((obj_pos.x > 0.0 ? -1.0 : 1.0) * (obj_pos.z - number_place.x), obj_pos.y - number_y) / number_place.y;
		vec4 rs = pc_roundel(ps);
		col = mix(col, rs.rgb, rs.a * side);
		if (number_place.w > 0.0 && up > 0.0) {
			// On the bonnet, read from in front of the car.
			vec4 rb = pc_roundel(vec2(-obj_pos.x, obj_pos.z - number_place.z) / number_place.w);
			col = mix(col, rb.rgb, rb.a * up * pc_below(body_lines.z - 0.05, obj_pos.z));
		}
	}
#endif

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
