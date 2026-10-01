shader_type spatial;
// New-style building facades (ART_BIBLE.md §15): base / middle / top grammar
// with the windows drawn here. Window reveals tilt the normal, so the real
// sun lights one side of each recess and the lintel shades the glass top;
// glass is glossy and reflects the sky. At night about half the rooms light up.
//
// UV.x  = bays along the wall (whole numbers at the wall's corners; the
//         builder fits a whole number of bays), increasing to the right
//         seen from outside (so the wall's tangent is cross(up, normal)).
// UV.y  = metres above the building's base (the sidewalk).
// UV2.x = building seed (0-1): window and room variation.
// UV2.y = facade style:
//         0 stucco, punched windows       1 limestone, tall windows with surrounds
//         2 brick, white frames, sills     3 glass curtain wall (COLOR = mullions)
//         4 ribbon windows (office)
//         +8 = shopfronts on the ground floor (else a lobby / plain base)
// COLOR.rgb = wall colour (sRGB). COLOR.a = 1 walls with openings,
//         0 plain surfaces (cornices, parapets, plinths, roofs).

#include "res://assets/shaders/world_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ground_floor = 4.6;
uniform float floor_height = 3.4;
uniform vec4 glass_color : source_color = vec4(0.11, 0.14, 0.17, 1.0);
uniform vec4 frame_white : source_color = vec4(0.91, 0.894, 0.855, 1.0);
uniform vec4 frame_dark : source_color = vec4(0.2, 0.21, 0.22, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Rectangle mask with soft edges in "a" (local) units; fw = pixel size.
float rect(vec2 p, vec2 lo, vec2 hi, vec2 fw) {
	vec2 a = smoothstep(lo - fw, lo + fw, p);
	vec2 b = 1.0 - smoothstep(hi - fw, hi + fw, p);
	return a.x * a.y * b.x * b.y;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	bool low = quality == 0;
	float v = UV.y;
	float seed = floor(UV2.x * 1000.0 + 0.5) * 0.001;  // rounded: hash only stable inputs
	int style_full = int(round(UV2.y));
	bool shops = style_full >= 8;
	int style = style_full % 8;
	vec3 wall = srgb_to_linear(COLOR.rgb);
	// Horizontal metres along the wall from the world position (axis-aligned buildings).
	float hm = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
	vec4 d = low ? vec4(0.5) : texture(detail, vec2(hm, v) * 0.25 + vec2(seed * 3.7, 0.0));
	vec4 m = texture(detail, vec2(hm, v) * 0.045 + vec2(seed * 1.3, 0.21));

	vec3 col = wall;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 nrm_w = n;

	if (COLOR.a < 0.5 || abs(n.y) > 0.7) {
		// Plain surfaces: plaster/stone grain, soft weathering.
		col *= 0.94 + 0.12 * m.a;
		col *= 1.0 + (d.r - 0.5) * 0.12 * near;
		rough = 0.88;
	} else {
		vec3 tangent = normalize(cross(vec3(0.0, 1.0, 0.0), n));
		// Wall material: grain, weathering, grime at the base.
		col *= 0.95 + 0.1 * m.a;
		col *= 1.0 + (d.r - 0.5) * 0.1 * near;
		if (style == 2) {
			// Brick: running bond, lighter mortar, per-brick tint (fades with distance).
			float course = floor(v / 0.077);
			float bx = hm / 0.23 + mod(course, 2.0) * 0.5;
			float mortar = max(grid_line(v, 0.077, 0.011), grid_line(bx, 1.0, 0.045));
			float bh = hash12(vec2(floor(bx), course));
			col *= mix(1.0, 0.9 + 0.2 * bh, near);
			col = mix(col, wall * 1.6 + 0.05, mortar * 0.55);
		} else if (style == 1) {
			// Limestone: ashlar joints (block courses).
			float course = floor(v / 0.6);
			float bx = hm / 1.2 + mod(course, 2.0) * 0.5;
			float joint = max(grid_line(v, 0.6, 0.012), grid_line(bx, 1.0, 0.01));
			col *= 1.0 - joint * 0.12;
			col *= 0.97 + 0.06 * hash12(vec2(floor(bx), course));
		}
		col *= 0.78 + 0.22 * smoothstep(0.0, 0.9, v);
		rough = style == 1 ? 0.8 : 0.9;

		// Window layout: a bay is one unit of UV.x.
		float bay = UV.x;
		float fb = fract(bay);
		float bay_id = floor(bay);
		vec2 fw = vec2(fwidth(bay), fwidth(v));
		bool gf = v < ground_floor;
		float level = gf ? -1.0 : floor((v - ground_floor) / floor_height);
		float fv = gf ? v : v - ground_floor - level * floor_height;  // metres within the floor
		float rh = hash12(vec2(bay_id, level) + seed * 97.0);  // per window
		float glass = 0.0;
		float frame = 0.0;
		float reveal = 0.0;
		vec2 lo = vec2(0.0);
		vec2 hi = vec2(0.0);
		vec3 frame_col = frame_white.rgb;
		bool curtain = style == 3;
		bool ribbon = style == 4;

		if (gf && shops) {
			// Shopfront: big glazing on a low stone riser, transom, door in some bays.
			bool door = hash12(vec2(bay_id, seed * 13.0)) < 0.3;
			lo = vec2(0.06, door ? 0.02 : 0.55);
			hi = vec2(0.94, 3.5);
			frame_col = frame_dark.rgb;
		} else if (curtain && !gf) {
			lo = vec2(-1.0, -1.0);
			hi = vec2(2.0, floor_height + 1.0);
		} else if (ribbon && !gf) {
			// Continuous bands: no vertical edges between bays.
			lo = vec2(-1.0, 0.95);
			hi = vec2(2.0, 2.75);
			frame_col = frame_dark.rgb;
		} else if (gf) {
			// Lobby / residential base: tall windows, a door in some bays.
			bool door = hash12(vec2(bay_id, seed * 7.0)) < 0.2;
			lo = vec2(0.25, door ? 0.02 : 0.9);
			hi = vec2(0.75, 3.2);
			frame_col = style == 3 || style == 4 ? frame_dark.rgb : frame_white.rgb;
		} else {
			float ww = style == 1 ? 0.22 : (style == 2 ? 0.26 : 0.24 + 0.06 * step(0.5, seed));
			lo = vec2(0.5 - ww, style == 1 ? 0.75 : 0.9);
			hi = vec2(0.5 + ww, style == 1 ? 2.75 : 2.45);
			frame_col = style == 0 && seed > 0.6 ? frame_dark.rgb : frame_white.rgb;
		}
		vec2 p = vec2(fb, fv);
		// Bays per metre: both UV.x and hm grow linearly along the wall.
		float bm = length(vec2(dFdx(bay), dFdy(bay))) / max(length(vec2(dFdx(hm), dFdy(hm))), 1e-5);
		bm = clamp(bm, 0.2, 0.5);
		vec2 rev = vec2(0.12 * bm, 0.12);
		glass = rect(p, lo, hi, fw);
		float open_in = rect(p, lo + rev, hi - rev, fw);
		reveal = glass - open_in;
		float frame_in = rect(p, lo + rev + vec2(0.05 * bm, 0.05), hi - rev - vec2(0.05 * bm, 0.05), fw);
		frame = open_in - frame_in;
		glass = frame_in;
		// Mullions and transoms.
		float bars = 0.0;
		if (curtain && !gf) {
			bars = max(grid_line(bay, 0.5, 0.04), rect(p, vec2(-1.0, -0.1), vec2(2.0, 0.85), fw));
			bars = max(bars, rect(p, vec2(-1.0, floor_height - 0.06), vec2(2.0, floor_height + 0.1), fw));
			reveal = 0.0;
			frame = 0.0;
		} else if (ribbon && !gf) {
			bars = grid_line(bay, 0.5, 0.025) * glass;
		} else if (gf && shops) {
			bars = max(grid_line(fb, 0.5, 0.03) * step(p.y, 2.7), rect(p, vec2(0.0, 2.68), vec2(1.0, 2.78), fw)) * glass;
		} else {
			bars = max(grid_line(fb - 0.5, 1.0, 0.02), rect(p, vec2(0.0, lo.y + (hi.y - lo.y) * 0.62), vec2(1.0, lo.y + (hi.y - lo.y) * 0.62 + 0.04), fw)) * glass;
		}
		bars = clamp(bars, 0.0, 1.0) * (1.0 - smoothstep(0.02, 0.06, fw.x));

		// Sills under punched windows, a stone surround on limestone, grime streaks.
		if (!curtain && !ribbon && !gf) {
			float sill = rect(p, vec2(lo.x - 0.03, lo.y - 0.09), vec2(hi.x + 0.03, lo.y), fw);
			col = mix(col, style == 2 ? srgb_to_linear(vec3(0.78, 0.74, 0.66)) : frame_white.rgb * 0.95, sill);
			if (style == 1) {
				float surround = rect(p, lo - vec2(0.05, 0.12), hi + vec2(0.05, 0.12), fw) - rect(p, lo, hi, fw);
				col = mix(col, wall * 1.08, surround * 0.8);
			}
			float below = rect(p, vec2(lo.x, 0.0), vec2(hi.x, lo.y - 0.09), fw);
			float streak = low ? 0.5 : texture(detail, vec2(hm * 0.6, v * 0.05) + seed).g;
			col *= 1.0 - below * smoothstep(0.55, 0.9, streak) * 0.12 * smoothstep(lo.y - 1.2, lo.y - 0.1, fv);
		}

		// Glass: dark, glossy, a little variation; blinds in some windows.
		vec3 glass_c = glass_color.rgb * (0.85 + 0.3 * rh);
		if (curtain) {
			glass_c = mix(srgb_to_linear(vec3(0.15, 0.2, 0.235)), srgb_to_linear(vec3(0.2, 0.24, 0.26)), rh * 0.5);
		}
		float blind = step(0.72, rh) * step(hi.y - (hi.y - lo.y) * (0.25 + 0.5 * fract(rh * 7.0)), fv);
		glass_c = mix(glass_c, srgb_to_linear(vec3(0.62, 0.6, 0.55)), blind * (curtain ? 0.0 : 0.8));
		// Spandrels on curtain walls are opaque.
		float spandrel = curtain && !gf ? rect(p, vec2(-1.0, -0.1), vec2(2.0, 0.85), fw) : 0.0;

		// Far away the windows are smaller than a pixel: fade to their average.
		float far = smoothstep(0.06, 0.2, fw.x);
		glass *= 1.0 - far;
		frame *= 1.0 - far;
		reveal *= 1.0 - far;
		bars *= 1.0 - far;
		spandrel *= 1.0 - far;
		col = mix(col, mix(col, glass_color.rgb, curtain ? 0.75 : 0.3), far);
		float g = glass * (1.0 - bars) * (1.0 - spandrel);
		col = mix(col, frame_col * (curtain ? 1.0 : 0.95), clamp(frame + bars * glass, 0.0, 1.0));
		if (curtain && !gf) {
			col = mix(col, wall, clamp(bars + spandrel, 0.0, 1.0));
			col = mix(col, wall * 0.75, spandrel * 0.6);
		}
		col = mix(col, glass_c, g);
		// Reveal: wall material, darker (ambient occlusion in the recess).
		col *= 1.0 - reveal * 0.35;
		rough = mix(rough, 0.05, g);
		rough = mix(rough, 0.45, (curtain ? bars : 0.0));
		metal = curtain ? bars * (1.0 - spandrel) : 0.0;

		// Reveal normals: the recess sides face into the opening.
		if (!low && reveal > 0.01) {
			vec2 c = (lo + hi) * 0.5;
			vec2 q = (p - c) / max((hi - lo) * 0.5, vec2(1e-3));
			vec3 rn;
			if (abs(q.x) > abs(q.y)) {
				rn = -tangent * sign(q.x);
			} else {
				rn = -vec3(0.0, 1.0, 0.0) * sign(q.y);
			}
			nrm_w = normalize(mix(n, normalize(n * 0.35 + rn), reveal));
		}

		// Night: about half the rooms lit, mostly warm; shops brighter.
		float lit_h = hash12(vec2(bay_id * 1.7 + 3.0, level * 2.3) + seed * 53.0);
		float lit = gf && shops ? step(0.2, lit_h) : step(0.45, lit_h);
		vec3 room = mix(vec3(1.0, 0.68, 0.36), vec3(0.8, 0.88, 1.0), step(0.85, fract(lit_h * 13.7)));
		float energy = (gf && shops ? 0.9 : (curtain ? 0.32 : 0.42)) + 0.3 * fract(lit_h * 7.3);
		// Brighter toward the ceiling, where the room light is.
		float ceiling = 0.55 + 0.45 * smoothstep(lo.y, hi.y, fv);
		emit = room * g * lit * night * energy * ceiling * (1.0 - blind * 0.4);
		// Far away: an even glow, varying slowly by floor and bay group.
		float group = hash12(vec2(floor(bay / 4.0), level) + seed * 31.0);
		emit += vec3(1.0, 0.74, 0.44) * far * night * (curtain ? 0.22 : 0.14) * (0.3 + 0.7 * group) * (gf ? 0.0 : 1.0);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);
}
