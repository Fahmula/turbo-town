shader_type spatial;
// Road surface (ART_BIBLE.md §16, realism experiment): scanned asphalt with
// cracks and sealant, wear, wheel paths, oil, repairs, thermoplastic paint
// with chips, and on city streets gutters, drains, manholes and stop lines.
// Deck sides are cast concrete. Layers and textures: road_common.gdshaderinc.
//
// Top faces:  UV.x = metres across (0 = centre, + = right-hand side of
//             travel along +UV.y, where that traffic drives), UV.y = metres
//             along. UV2 = stop lines: x = distance from the start for the
//             -UV.y direction (0 = none), y = distance from the start for the
//             +UV.y direction (0 = none).
//             COLOR.b < 0.5 = bridge deck (expansion joints every 24 m).
// Deck sides: COLOR.a < 0.5, UV = (metres along, metres down from the edge).
// Per road type: road_*.tres in assets/materials/env/.

#include "res://assets/shaders/road_common.gdshaderinc"

uniform vec4 concrete_color : source_color = vec4(0.706, 0.690, 0.655, 1.0);
uniform vec4 white_line : source_color = vec4(0.894, 0.886, 0.855, 1.0);
uniform vec4 yellow_line : source_color = vec4(0.851, 0.643, 0.129, 1.0);
uniform float half_width = 6.0;
uniform float median_half = 0.0;
uniform int lanes_per_side = 2;
uniform float lane_width = 2.8;
// 0 = none, 1 = double solid yellow, 2 = dashed yellow
uniform int center_style = 1;
uniform float dash_length = 3.0;
uniform float dash_gap = 5.0;
// How worn and patched the surface is (city 1, highway ~0.4).
uniform float wear = 1.0;
// City street furniture in the surface: gutters, manholes, drains.
uniform bool street = true;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Soft-edged box: 1 inside |p| < half.
float box_mask(vec2 p, vec2 half_size) {
	vec2 fw = fwidth(p) * 0.75 + 1e-5;
	vec2 m = smoothstep(half_size + fw, half_size - fw, abs(p));
	return m.x * m.y;
}

// Dashed stripe along y (period = dash_length + gap): coverage with jitter.
float dash_cover(float y, float length_m, float period, float jit) {
	float fw = fwidth(y) * 0.75 + 1e-5;
	float p = mod(y, period);
	float sd = p < length_m ? max(-p, p - length_m) : min(p - length_m, period - p);
	return paint_cover(sd, fw, jit);
}

void fragment() {
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec2 dUVx = dFdx(UV);
	vec2 dUVy = dFdy(UV);
	vec2 dWx = dFdx(wp);
	vec2 dWy = dFdy(wp);

	if (COLOR.a < 0.5) {
		// Cast concrete deck side: scanned concrete, drip streaks from the edge.
		Surf c = concrete_surface(cast_albedo, cast_nra, UV, dUVx, dUVy, vec2(floor(UV.x / 6.0), 5.0), cast_tile, concrete_color.rgb * 0.8);
		vec4 mc = texture(road_macro, wp / 30.0 + vec2(0.31, 0.57));
		float streak = smoothstep(0.45, 0.8, texture(road_macro, vec2(UV.x * 0.1, UV.y * 0.012) + vec2(0.11, 0.47)).a) * (1.0 - smoothstep(0.2, 1.6, UV.y));
		vec3 col = c.col * mix(0.82, 1.1, mc.g) * (1.0 - streak * 0.22);
		ALBEDO = col;
		ROUGHNESS = clamp(c.rough, 0.6, 1.0);
		AO = c.ao;
		if (!low) {
			NORMAL = bump_normal(NORMAL, VERTEX, UV / cast_tile, c.nxy);
		}
	} else {
		float x = UV.x;
		float ax = abs(x);
		float y = UV.y;
		float fwx = fwidth(x) * 0.75 + 1e-5;

		// Lane layout.
		float inner = median_half > 0.0 ? median_half + 0.4 : 0.0;
		float lanes_edge = inner + float(lanes_per_side) * lane_width;
		bool in_lanes = ax > inner && ax < lanes_edge;
		float side = x > 0.0 ? 1.0 : 0.0;
		float lane_id = floor(max(ax - inner, 0.0) / lane_width);

		// Repair patches (a trench or a block of fresh asphalt now and then).
		float patch = 0.0;
		float patch_edge = 0.0;
		vec2 pq = vec2(0.0);
		float cell = floor(y / 9.0);
		float hsh = hash12(vec2(cell, lane_id * 2.0 + side + 7.0));
		if (hsh < 0.12 * wear && in_lanes) {
			vec2 hh = hash22(vec2(cell, lane_id + side * 5.0));
			vec2 c0 = vec2((lane_id + 0.5) * lane_width + inner, (cell + 0.5) * 9.0);
			vec2 half_size = vec2(0.6 + hh.x * 0.6, 0.9 + hh.y * 2.4);
			pq = vec2(ax, y) - c0;
			patch = box_mask(pq, half_size);
			patch_edge = patch * (1.0 - box_mask(pq, half_size - 0.04));
		}

		Surf s = asphalt_surface(wp, asphalt_base, wear, 1.0 - patch);
		vec3 col = s.col;
		float rough = s.rough;
		float ao = s.ao;
		vec2 nxy = s.nxy;

		// Fresh patch: darker, smoother, edged with sealant.
		col = mix(col, col * 0.84, patch);
		col = mix(col, vec3(0.02), patch_edge * 0.8);
		rough = mix(rough, 0.9, patch * 0.5);
		rough = mix(rough, 0.45, patch_edge);
		nxy *= 1.0 - patch * 0.45;

		float wheel = 0.0;
		if (in_lanes) {
			float lp = mod(ax - inner, lane_width) - lane_width * 0.5;
			// Wheel paths: rubber-darkened, polished bands where tyres run; the
			// ridge between them stays a little paler.
			wheel = 1.0 - smoothstep(0.16, 0.42, abs(abs(lp) - 0.8));
			float ridge = 1.0 - smoothstep(0.05, 0.3, abs(lp));
			col *= 1.0 - wheel * 0.2 * (0.4 + wear * 0.6);
			col *= 1.0 + ridge * 0.05;
			rough -= wheel * 0.08;
			// Oil and drips along the lane centre.
			float centre = 1.0 - smoothstep(0.12, 0.4, abs(lp));
			float oil = smoothstep(0.2, 0.65, s.oil) * centre * (0.35 + 0.65 * wear);
			col *= 1.0 - oil * 0.6;
			rough = mix(rough, 0.3, oil);
		}

		// Braking zone before a stop line: rubber darkens the wheel paths.
		float brake = 0.0;
		if (UV2.y > 0.0 && x > inner && x < lanes_edge) {
			brake = 1.0 - smoothstep(0.0, 22.0, UV2.y - y);
			brake *= step(y, UV2.y);
		} else if (UV2.x > 0.0 && x < -inner && x > -lanes_edge) {
			brake = 1.0 - smoothstep(0.0, 22.0, y - UV2.x);
			brake *= step(UV2.x, y);
		}
		col *= 1.0 - brake * wheel * 0.14;
		rough -= brake * wheel * 0.05;

		// Bridge deck: expansion joints across (a dark gap between two steel strips).
		if (COLOR.b < 0.5) {
			float gap = grid_line(y, 24.0, 0.05);
			float strip = clamp(grid_line(y, 24.0, 0.2) - gap, 0.0, 1.0);
			col = mix(col, vec3(0.012), gap * 0.9);
			col = mix(col, vec3(0.2, 0.205, 0.21) * (0.7 + 0.3 * s.stone), strip * 0.75);
			rough = mix(rough, 0.5, strip);
			nxy *= 1.0 - strip;
		}

		// Markings: thermoplastic paint, chipped where stones poke through.
		float jit = (s.stone - 1.0) * 0.02 * near;
		float w = 0.0;
		float yl = 0.0;
		if (median_half > 0.0) {
			// The median strip is concrete: sampled from the cast concrete scan.
			float med = 1.0 - smoothstep(median_half - 0.04, median_half + 0.04, ax);
			vec3 mcol = textureGrad(cast_albedo, wp / cast_tile, dWx / cast_tile, dWy / cast_tile).rgb * (1.0 / ALB_MEAN) * concrete_color.rgb * 0.75;
			col = mix(col, mcol * (0.9 + 0.2 * s.tone), med);
			rough = mix(rough, 0.9, med);
			yl += paint_cover(abs(ax - (median_half + 0.2)) - 0.075, fwx, jit);
		} else if (center_style == 1) {
			yl += paint_cover(abs(ax - 0.14) - 0.055, fwx, jit);
		} else if (center_style == 2) {
			yl += paint_cover(abs(x) - 0.07, fwx, jit) * dash_cover(y, dash_length, dash_length + dash_gap, jit);
		}
		for (int k = 1; k < lanes_per_side; k++) {
			w += paint_cover(abs(ax - (inner + float(k) * lane_width)) - 0.065, fwx, jit) * dash_cover(y, dash_length, dash_length + dash_gap, jit);
		}
		w += paint_cover(abs(ax - (lanes_edge + 0.1)) - 0.075, fwx, jit);
		// Stop lines before junctions (incoming lanes only).
		float stop = 0.0;
		float fwy = fwidth(y) * 0.75 + 1e-5;
		if (UV2.y > 0.0 && x > inner && x < lanes_edge) {
			stop += paint_cover(abs(y - (UV2.y - 0.225)) - 0.225, fwy, jit);
		}
		if (UV2.x > 0.0 && x < -inner && x > -lanes_edge) {
			stop += paint_cover(abs(y - (UV2.x + 0.225)) - 0.225, fwy, jit);
		}
		// Paint wears off the stone tops and where tyres run (stop lines most).
		float wornp = 0.3 + 0.6 * wear;
		float chipn = s.film * 0.4 + (s.stone - 0.5) * 0.6 + s.tone * 0.15;
		float chip = smoothstep(0.55, 0.9, chipn) * mix(0.4, 1.0, near) * wornp;
		float keep_line = (1.0 - chip * 0.85) * mix(0.8, 1.0, smoothstep(0.2, 0.6, s.film));
		// Stop lines wear away where tyres brake over them.
		float keep_stop = (1.0 - clamp(chip * 1.25 + wheel * 0.3 * smoothstep(0.35, 0.8, chipn + 0.35), 0.0, 0.92)) * mix(0.72, 1.0, smoothstep(0.25, 0.7, s.film));
		w = clamp(w, 0.0, 1.0) * keep_line + clamp(stop, 0.0, 1.0) * keep_stop;
		yl = clamp(yl, 0.0, 1.0) * keep_line;
		w = clamp(w, 0.0, 1.0);
		// Paint: patchy thickness, dirt, and the aggregate showing through.
		float dirt = (0.74 + 0.26 * s.tone) * (0.86 + 0.14 * smoothstep(0.2, 0.8, s.film));
		float grain = 0.9 + 0.1 * s.stone;
		vec3 paint_w = white_line.rgb * 0.8 * dirt * grain;
		vec3 paint_y = yellow_line.rgb * 0.8 * dirt * grain;
		col = mix(col, paint_w, w);
		col = mix(col, paint_y, yl);
		float paint = max(w, yl);
		rough = mix(rough, 0.6, paint);
		nxy *= 1.0 - paint * 0.5;
		float paint_h = paint * 0.0025 * near;

		if (!street) {
			// Rural edge: dust and grit washed onto the shoulder, fraying the edge.
			float edge = smoothstep(half_width - 0.5, half_width - 0.05, ax);
			float frayed = edge * smoothstep(0.25, 0.7, s.film + 0.3 * (s.stone - 1.0));
			col = mix(col, vec3(0.2, 0.17, 0.13) * (0.8 + 0.4 * s.stone * 0.5), frayed * 0.55);
			col *= 1.0 - edge * 0.1;
			rough = mix(rough, 0.97, edge * 0.5);
		}
		if (street) {
			// Gutter along the kerb: damp, dirty, a little sandy grit.
			float gutter = smoothstep(half_width - 0.55, half_width - 0.25, ax);
			col *= 1.0 - gutter * (0.16 + 0.12 * s.film);
			float grit = smoothstep(0.45, 0.8, s.film) * gutter;
			col = mix(col, col * vec3(1.35, 1.28, 1.15), grit * 0.5);
			rough = mix(rough, 0.97, gutter * 0.5);
			// Storm drains in the gutter every few cells: frame, bars, deep slots.
			float dcell = floor(y / 27.0);
			if (hash12(vec2(dcell, side + 3.0)) < 0.5) {
				vec2 q = vec2(ax - (half_width - 0.3), y - (dcell + 0.5) * 27.0);
				float frame = box_mask(q, vec2(0.24, 0.47));
				float inside = box_mask(q, vec2(0.2, 0.43));
				float bars = clamp(grid_line(q.x, 0.062, 0.034), 0.0, 1.0);
				float slot = inside * bars;
				col = mix(col, vec3(0.045, 0.043, 0.04) * (0.8 + 0.4 * s.film), frame);
				col = mix(col, vec3(0.004), slot * near + slot * (1.0 - near) * 0.5);
				rough = mix(rough, 0.55, frame);
				ao = mix(ao, 0.3, slot);
				nxy *= 1.0 - frame;
			}
			// Manholes in the lanes: cast-iron lid, dark gap, frame, patched asphalt round it.
			float mcell = floor(y / 31.0);
			vec2 mh = hash22(vec2(mcell, side + 11.0));
			if (mh.x < 0.55 && in_lanes) {
				float lane_c = inner + (floor(mh.y * float(lanes_per_side)) + 0.5) * lane_width;
				vec2 q = vec2(ax - lane_c, y - (mcell + 0.5) * 31.0);
				float r = length(q);
				float fw = fwidth(r) + 1e-5;
				float round_patch = 1.0 - smoothstep(0.55 - fw, 0.6 + fw, r);
				float disc = 1.0 - smoothstep(0.405 - fw, 0.405 + fw, r);
				float lid = 1.0 - smoothstep(0.31 - fw, 0.31 + fw, r);
				float gap = lid - (1.0 - smoothstep(0.285 - fw, 0.285 + fw, r));
				gap = clamp(gap, 0.0, 1.0);
				col = mix(col, col * 0.8, round_patch * (1.0 - disc));
				vec3 iron = vec3(0.055, 0.052, 0.05) * (0.8 + 0.4 * s.film);
				// Anti-slip studs on a diagonal grid, a groove ring and a plain hub.
				vec2 g = vec2(q.x + q.y, q.x - q.y) / 0.05;
				float stud = 1.0 - smoothstep(0.22, 0.4, length(fract(g) - 0.5));
				float groove = 1.0 - smoothstep(0.0, 0.012, abs(r - 0.2));
				float hub = 1.0 - smoothstep(0.075, 0.09, r);
				float diamond = mix(1.0, (0.62 + 0.7 * stud) * (1.0 - groove * 0.5) * (1.0 + hub * 0.2), near * lid);
				col = mix(col, iron * 1.25, disc);
				col = mix(col, iron * diamond, lid * (1.0 - gap));
				col = mix(col, vec3(0.006), gap);
				rough = mix(rough, 0.5, disc);
				ao = mix(ao, 0.45, gap);
				nxy *= 1.0 - disc;
			}
		}

		ALBEDO = col;
		ROUGHNESS = clamp(rough, 0.25, 1.0);
		AO = ao;
		if (!low) {
			NORMAL = bump_normal(NORMAL, VERTEX, wp / asph_tile, nxy);
			NORMAL = height_bump(NORMAL, VERTEX, paint_h, 1.0);
		}
	}
}
