shader_type spatial;
// Road surface (ART_BIBLE.md §16): asphalt with grain, wear,
// wheel paths, repairs and crack sealing, worn paint markings, and on city
// streets gutters, manholes, drains and stop lines. Deck sides are concrete.
//
// Top faces:  UV.x = metres across (0 = centre, + = right-hand side of
//             travel along +UV.y, where that traffic drives), UV.y = metres
//             along. UV2 = stop lines: x = distance from the start for the
//             -UV.y direction (0 = none), y = distance from the start for the
//             +UV.y direction (0 = none).
//             COLOR.b < 0.5 = bridge deck (expansion joints every 24 m).
// Deck sides: COLOR.a < 0.5, UV = (metres along, metres down from the edge).
// Per road type: road_*.tres in assets/materials/env/.

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 asphalt_color : source_color = vec4(0.275, 0.278, 0.290, 1.0);
uniform vec4 asphalt_dark : source_color = vec4(0.224, 0.227, 0.239, 1.0);
uniform vec4 asphalt_worn : source_color = vec4(0.353, 0.357, 0.365, 1.0);
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

float line_mask(float x, float center, float width) {
	float fw = fwidth(x) * 0.75;
	return 1.0 - smoothstep(width * 0.5 - fw, width * 0.5 + fw, abs(x - center));
}

// Soft-edged box: 1 inside |p| < half.
float box_mask(vec2 p, vec2 half_size) {
	vec2 fw = fwidth(p) * 0.75;
	vec2 m = smoothstep(half_size + fw, half_size - fw, abs(p));
	return m.x * m.y;
}

void fragment() {
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec4 d = low ? vec4(0.5) : texture(detail, wp * 0.25);
	vec4 m = texture(detail, wp * 0.031 + vec2(0.37, 0.61));

	if (COLOR.a < 0.5) {
		// Concrete deck side: grain, soft blotches and drip streaks from the edge.
		vec4 s = low ? vec4(0.5) : texture(detail, vec2(UV.x * 0.21, UV.y * 0.04));
		vec3 c = concrete_color.rgb * (0.93 + 0.12 * m.a);
		c *= 1.0 + (d.r - 0.5) * 0.12 * near;
		float streak = smoothstep(0.55, 0.85, s.g) * (1.0 - smoothstep(0.2, 1.6, UV.y));
		c *= 1.0 - streak * 0.18;
		ALBEDO = c;
		ROUGHNESS = 0.88;
	} else {
		float x = UV.x;
		float ax = abs(x);
		float y = UV.y;
		float grain = (d.r - 0.5) * near;

		// Base asphalt: sun-worn and darker patches at two scales, fine grain.
		vec3 col = asphalt_color.rgb;
		float worn = smoothstep(0.5, 0.9, m.g * 0.65 + d.g * 0.35);
		col = mix(col, asphalt_worn.rgb, worn * 0.5 * wear);
		col = mix(col, asphalt_dark.rgb, smoothstep(0.45, 0.15, m.a) * 0.4);
		col *= 0.95 + 0.1 * mix(0.5, d.g, near);
		col *= 1.0 + grain * 0.3;
		float rough = 0.9 - grain * 0.08;

		// Lane layout.
		float inner = median_half > 0.0 ? median_half + 0.4 : 0.0;
		float lanes_edge = inner + float(lanes_per_side) * lane_width;
		bool in_lanes = ax > inner && ax < lanes_edge;
		// Wheel paths: slightly darker, smoother bands where tyres run.
		if (in_lanes) {
			float lp = mod(ax - inner, lane_width) - lane_width * 0.5;
			float wheel = 1.0 - smoothstep(0.18, 0.42, abs(abs(lp) - 0.8));
			col *= 1.0 - wheel * 0.07 * (0.5 + wear * 0.5);
			rough -= wheel * 0.06;
		}

		// Repair patches and a utility trench now and then (streets mostly).
		float side = x > 0.0 ? 1.0 : 0.0;
		float lane_id = floor(max(ax - inner, 0.0) / lane_width);
		float cell = floor(y / 9.0);
		float h = hash12(vec2(cell, lane_id * 2.0 + side + 7.0));
		if (h < 0.12 * wear && in_lanes) {
			vec2 hh = hash22(vec2(cell, lane_id + side * 5.0));
			vec2 c0 = vec2((lane_id + 0.5) * lane_width + inner, (cell + 0.5) * 9.0);
			vec2 half_size = vec2(0.6 + hh.x * 0.6, 0.9 + hh.y * 2.4);
			float p = box_mask(vec2(ax, y) - c0, half_size);
			col = mix(col, asphalt_dark.rgb * (1.0 + grain * 0.15), p);
			rough = mix(rough, 0.84, p);
		}

		// Crack sealing: thin dark tar lines in older areas.
		float crack = low ? 0.0 : texture(detail, wp * 0.083 + vec2(0.13, 0.71)).b;
		crack *= smoothstep(0.35, 0.65, m.g) * wear;
		col = mix(col, vec3(0.045, 0.045, 0.05), crack * 0.85);
		rough = mix(rough, 0.55, crack);

		// Bridge deck: expansion joints across.
		if (COLOR.b < 0.5) {
			float j = grid_line(y, 24.0, 0.06);
			float edge = clamp(grid_line(y, 24.0, 0.16) - j, 0.0, 1.0);
			col = mix(col, vec3(0.05), j * 0.8);
			col = mix(col, vec3(0.24, 0.245, 0.25), edge * 0.6);
			rough = mix(rough, 0.5, edge);
		}

		// Markings.
		float dash = step(fract(y / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));
		float w = 0.0;
		float yl = 0.0;
		if (median_half > 0.0) {
			col = mix(col, concrete_color.rgb * 0.8, (1.0 - smoothstep(median_half - 0.05, median_half + 0.05, ax)) * 0.55);
			yl += line_mask(ax, median_half + 0.2, 0.15);
		} else if (center_style == 1) {
			yl += line_mask(ax, 0.14, 0.11);
		} else if (center_style == 2) {
			yl += line_mask(x, 0.0, 0.14) * dash;
		}
		for (int k = 1; k < lanes_per_side; k++) {
			w += line_mask(ax, inner + float(k) * lane_width, 0.13) * dash;
		}
		w += line_mask(ax, lanes_edge + 0.1, 0.15);
		// Stop lines before junctions (incoming lanes only).
		if (UV2.y > 0.0 && x > inner && x < lanes_edge) {
			w += band(y, UV2.y - 0.45, UV2.y);
		}
		if (UV2.x > 0.0 && x < -inner && x > -lanes_edge) {
			w += band(y, UV2.x, UV2.x + 0.45);
		}
		// Worn paint: small chips where the stones poke through, more in
		// worn areas (5-15%).
		float chips = smoothstep(0.64, 0.72, d.r + d.g * 0.25 + worn * 0.1 - 0.12) * wear * near;
		float paint_keep = 1.0 - chips * 0.85;
		w = clamp(w, 0.0, 1.0) * paint_keep;
		yl = clamp(yl, 0.0, 1.0) * paint_keep;
		float dirt = 0.9 + 0.1 * m.a;
		col = mix(col, white_line.rgb * dirt, w);
		col = mix(col, yellow_line.rgb * dirt, yl);
		rough = mix(rough, 0.66, max(w, yl));

		if (street) {
			// Gutter along the kerb: darker, dirtier.
			float gutter = smoothstep(half_width - 0.5, half_width - 0.3, ax);
			col *= 1.0 - gutter * (0.12 + 0.1 * d.g);
			// Drains in the gutter every few cells.
			float dcell = floor(y / 27.0);
			if (hash12(vec2(dcell, side + 3.0)) < 0.5) {
				vec2 q = vec2(ax - (half_width - 0.3), y - (dcell + 0.5) * 27.0);
				float grate = box_mask(q, vec2(0.22, 0.45));
				float slots = step(0.5, fract(q.y * 8.0)) * box_mask(q, vec2(0.16, 0.39));
				col = mix(col, vec3(0.16, 0.16, 0.17) * (1.0 - slots * 0.7), grate);
				rough = mix(rough, 0.6, grate);
			}
			// Manholes in the lanes.
			float mcell = floor(y / 31.0);
			vec2 mh = hash22(vec2(mcell, side + 11.0));
			if (mh.x < 0.55 && in_lanes) {
				float lane_c = inner + (floor(mh.y * float(lanes_per_side)) + 0.5) * lane_width;
				vec2 q = vec2(ax - lane_c, y - (mcell + 0.5) * 31.0);
				float r = length(q);
				float fw = fwidth(r);
				float disc = 1.0 - smoothstep(0.34 - fw, 0.34 + fw, r);
				float ring = disc * smoothstep(0.27 - fw, 0.27 + fw, r);
				float pattern = step(0.5, fract(r * 9.0)) * 0.25;
				col = mix(col, vec3(0.13, 0.13, 0.14) * (1.0 + pattern - ring * 0.3), disc);
				rough = mix(rough, 0.6, disc);
			}
		}

		ALBEDO = col;
		ROUGHNESS = clamp(rough, 0.3, 1.0);
	}
}
