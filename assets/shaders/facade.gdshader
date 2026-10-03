shader_type spatial;
// Building facades (ART_BIBLE.md §15), realism branch: real wall scans, windows
// with real depth, interior mapping, weathering.
//
// UV.x  = bays along the wall (whole numbers at the wall's corners; the
//         builder fits a whole number of bays), increasing to the right
//         seen from outside (so the wall's tangent is cross(up, normal)).
// UV.y  = metres above the building's base (the sidewalk).
// UV2.x = building seed (0-1): window and room variation.
// UV2.y = facade style:
//         0 stucco, punched windows       1 limestone, tall windows with surrounds
//         2 brick, white frames, sills     3 glass curtain wall (COLOR = mullions)
//         4 ribbon windows (office)        5 roof membrane (flat roofs)
//         6 shop sign board (BuildingKit._signs; UV.x = bays, UV.y = metres up)
//         +8 = shopfronts on the ground floor (else a lobby / plain base)
// COLOR.rgb = wall colour (sRGB; tints the scans). COLOR.a: < 0.5 plain
//         surfaces (cornices, parapets, plinths, roofs); otherwise walls with
//         openings, and a = 0.5 + 0.5 * (bay width m - 2) / 4 carries the
//         bay width (BuildingKit._walls).
//
// Textures (assets/textures/building/, made by tools/textures/fetch_building.py
// and tools/blender/make_building_interiors.py):
//   wall_albedo / wall_normal / wall_orm: Texture2DArray, layers 0 brick,
//     1 stucco, 2 limestone, 3 concrete. Albedo is a de-lit ratio (x5 = ratio
//     to the scan's mean colour), multiplied by the wall colour. ORM: R AO,
//     G roughness, B mask (brick: mortar; others: joints).
//   weather: R rain streaks, G blotches, B grain, A stains.
//   rooms_atlas / shops_atlas: 8 x 8 cells of 256 px; room r, face f at cell
//     r * 5 + f (back, left, right, floor, ceiling), 4 px inset borders.
//   signs_atlas: 16 rows of 1024 x 128 (RGB board, A lettering; row = shop type).
//
// Windows are recessed boxes: the view ray is intersected with the opening
// (reveal sides, sill, frame and glass plane), so depth, frames and reveals
// are correct from every angle. Glass shows a room found by intersecting the
// same ray with a room box (interior mapping); at night about half the rooms
// are lit. On Low (quality 0) the shader drops the wall, weather and room
// textures and the recess and room maths and draws the flat look of the old
// toy facade (only the shop signs keep their one sample).

#include "res://assets/shaders/facade_common.gdshaderinc"

uniform sampler2DArray wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray wall_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weather : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rooms_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D shops_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D signs_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

uniform float ground_floor = 4.6;
uniform float floor_height = 3.4;
uniform vec4 glass_color : source_color = vec4(0.11, 0.14, 0.17, 1.0);
uniform vec4 frame_white : source_color = vec4(0.91, 0.894, 0.855, 1.0);
uniform vec4 frame_dark : source_color = vec4(0.2, 0.21, 0.22, 1.0);
// Metres covered by one repeat of each wall layer (brick, stucco, limestone, concrete).
uniform vec4 tile_m = vec4(3.0, 2.0, 3.0, 1.8);
uniform vec4 normal_gain = vec4(1.0, 1.7, 1.0, 1.0);  // per layer: brick, stucco, limestone, concrete
uniform float day_gain = 0.075;     // room brightness seen through glass by day
uniform float night_gain = 1.15;     // lit rooms at night
uniform int rooms_count = 12;
uniform int shops_count = 12;
uniform int signs_rows = 16;
// Brick courses in the scan: 39 per 3 m (windows snap to course lines).
const float COURSE = 0.0769231;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Reads one cell of a room atlas (face uv in [-1, 1]); lod caps at 2 so the
// 4 px borders absorb the bleed.
vec3 room_texel(bool shop, int room, int face, vec2 fuv, float lod) {
	int idx = room * 5 + face;
	vec2 cell = vec2(float(idx % 8), float(idx / 8));
	vec2 inner = vec2(fuv.x * 0.5 + 0.5, 0.5 - fuv.y * 0.5);
	inner = (inner * 248.0 + 4.0) / 256.0;
	vec2 at = (cell + inner) / 8.0;
	return shop ? textureLod(shops_atlas, at, lod).rgb : textureLod(rooms_atlas, at, lod).rgb;
}

// Wall scan at layer `l`: ratio colour (x1 = the scan's mean), normal (xy, z
// rebuilt), AO, roughness, mask.
void wall_scan(float l, vec2 uv, out vec3 ratio, out vec3 nrm, out vec3 orm) {
	ratio = texture(wall_albedo, vec3(uv, l)).rgb * RATIO_SCALE;
	vec2 nxy = (texture(wall_normal, vec3(uv, l)).xy * 2.0 - 1.0) * normal_gain[int(l)];
	nrm = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	orm = texture(wall_orm, vec3(uv, l)).rgb;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 ray_v = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(ray_v);
	vec3 ray = ray_v / max(dist, 1e-3);
	bool low = quality == 0;
	bool high = quality >= 2;
	float v = UV.y;
	float seed = floor(UV2.x * 1000.0 + 0.5) * 0.001;  // rounded: hash only stable inputs
	int style_full = int(round(UV2.y));
	bool shops = style_full >= 8;
	int style = style_full % 8;
	bool is_roof = style == 5;
	bool is_sign = style == 6;
	bool horiz = abs(n.y) > 0.7;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 T = horiz ? vec3(1.0, 0.0, 0.0) : normalize(cross(up, n));
	vec3 Bt = horiz ? vec3(0.0, 0.0, -1.0) : up;
	float perp = abs(n.x) > abs(n.z) ? world_pos.x : world_pos.z;
	if (is_sign) {
		perp -= (abs(n.x) > abs(n.z) ? n.x : n.z) * 0.16;  // the board stands 0.16 m off the wall
	}
	float wall_id = floor(perp + 0.37);

	vec3 wall = srgb_to_linear(COLOR.rgb);
	wall = mix(vec3(luma(wall)), wall, style == 0 ? 0.82 : 0.92);  // a touch less candy
	wall *= 0.95 + 0.1 * hash12(vec2(seed * 91.7, 3.1));   // per-building tone

	// ------------------------------------------------------------ shop sign boards
	if (is_sign) {
		// One board per pair of shop bays (BuildingKit._signs); the word matches the
		// shop interior behind the glass (same hash as the room choice).
		float grp = floor(UV.x / 2.0);
		float su = clamp((UV.x - grp * 2.0 - 0.12) / 1.76, 0.0, 1.0);
		float sv = clamp(1.0 - (UV.y - 3.725) / 0.5, 0.03, 0.97);
		vec2 swk = vec2(grp, -1.0) + seed * 53.0 + wall_id * 0.917;
		int sroom = int(floor(hash12(swk + 11.3) * float(shops_count)));
		float alt = hash12(swk + 61.0);
		float row = alt > 0.8 ? 12.0 + floor(fract(alt * 37.0) * 4.0) : float(sroom);
		vec4 sg = texture(signs_atlas, vec2(su, (row + sv) / float(signs_rows)));
		float slit_h = hash12(swk);
		float slit = step(0.18, slit_h);
		vec3 slamp = mix(vec3(1.0, 0.78, 0.55), vec3(0.88, 0.95, 1.0), step(0.85, fract(slit_h * 13.7)));
		float sdirt = 1.0 - 0.15 * smoothstep(0.55, 0.9, texture(weather, vec2(world_pos.x + world_pos.z, world_pos.y * 0.2) * 0.3).r);
		ALBEDO = sg.rgb * sdirt;
		ROUGHNESS = 0.55;
		METALLIC = 0.0;
		SPECULAR = 0.6;
		EMISSION = (slamp * sg.a * 1.3 + sg.rgb * 0.1) * night * slit;
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	} else if (COLOR.a < 0.5 || horiz) {
	// ------------------------------------------------------------ plain surfaces
		vec3 col = wall;
		float rough = 0.88;
		vec3 nrm_w = n;
		if (!low) {
			float layer = is_roof ? 1.0 : (style == 1 ? 2.0 : (style >= 3 ? 3.0 : 1.0));
			float tile = tile_m[int(layer)] * (is_roof ? 0.6 : 1.0);
			float uc = dot(world_pos, T) + seed * 37.1;
			float vc = horiz ? world_pos.z : -world_pos.y;
			vec3 ratio, nm, orm;
			wall_scan(layer, vec2(uc, vc) / tile, ratio, nm, orm);
			col = tint_scan(ratio, wall, 1.0);
			col *= mix(1.0, orm.r, 0.6);
			rough = clamp(orm.g * 1.05, 0.5, 1.0);
			nrm_w = normalize(T * nm.x + Bt * nm.y + n * nm.z);
			vec4 wt = texture(weather, vec2(uc, vc) * 0.11 + seed * 5.0);
			vec4 wt2 = texture(weather, vec2(uc, vc) * 0.012 + seed * 3.0);
			col *= 0.9 + 0.2 * wt2.g;
			if (is_roof) {
				// Roof membrane / ballast: grain, patchy wear, lighter dust.
				col *= 0.8 + 0.4 * wt.b;
				col = mix(col, col * 0.7, wt.a * 0.6);
				col *= 0.9 + 0.2 * wt.g;
			} else {
				// Ledges collect dirt; undersides and faces get rain streaks.
				float ledge = horiz ? 1.0 : 0.0;
				col *= 1.0 - ledge * 0.28 * (0.4 + 0.6 * wt.g);
				col *= 1.0 - (1.0 - ledge) * 0.1 * smoothstep(0.35, 0.8, wt.r) * wt2.g;
			}
		} else {
			col *= 0.94 + 0.12 * hash12(floor(vec2(world_pos.x + world_pos.z, world_pos.y) * 1.3));
		}
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = 0.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);
	} else {
		// ------------------------------------------------------ walls with openings
		float bw = clamp(2.0 + (COLOR.a - 0.5) * 8.0, 2.0, 6.0);  // metres per bay
		float bay = UV.x;
		float bay_id = floor(bay);
		float px = fract(bay) * bw;               // metres from the bay's left edge
		vec2 fwm = vec2(fwidth(bay) * bw, fwidth(v));  // pixel footprint, metres
		bool gf = v < ground_floor;
		float level = gf ? -1.0 : floor((v - ground_floor) / floor_height);
		float fv = gf ? v : v - ground_floor - level * floor_height;  // metres within the floor
		bool curtain = style == 3;
		bool ribbon = style == 4;
		bool brick = style == 2;
		vec2 wk = vec2(bay_id, level) + seed * 97.0 + wall_id * 0.731;
		float rh = hash12(wk);                      // per window

		// Opening layout, metres: lo / hi corners, recess depth, frame width.
		vec2 lo = vec2(0.0);
		vec2 hi = vec2(0.0);
		float rdepth = 0.2;
		float fr_w = 0.06;
		vec3 frame_col = frame_white.rgb;
		bool door = false;
		bool cont = false;  // continuous band (curtain wall, ribbon windows)
		int pat = int(floor(hash12(vec2(seed * 31.0, 5.0)) * 3.99));
		if (gf && shops) {
			door = hash12(vec2(bay_id, seed * 13.0) + wall_id) < 0.3;
			lo = vec2(0.07 * bw, door ? 0.02 : 0.55);
			hi = vec2(0.93 * bw, 3.5);
			rdepth = door ? 0.5 : 0.14;
			fr_w = 0.05;
			frame_col = frame_dark.rgb;
		} else if (curtain && !gf) {
			cont = true;
			lo = vec2(-1000.0, 0.9);
			hi = vec2(1000.0, floor_height - 0.1);
			rdepth = 0.06;
			fr_w = 0.03;
			frame_col = wall;
		} else if (ribbon && !gf) {
			cont = true;
			lo = vec2(-1000.0, 0.95);
			hi = vec2(1000.0, 2.75);
			rdepth = 0.14;
			fr_w = 0.04;
			frame_col = frame_dark.rgb;
		} else if (gf) {
			door = hash12(vec2(bay_id, seed * 7.0) + wall_id) < 0.2;
			lo = vec2(0.25 * bw, door ? 0.02 : 0.9);
			hi = vec2(0.75 * bw, 3.2);
			rdepth = door ? 0.35 : 0.2;
			frame_col = style == 3 || style == 4 ? frame_dark.rgb : frame_white.rgb;
		} else {
			float ww = style == 1 ? 0.65 : (style == 2 ? 0.6 : 0.62 + 0.15 * step(0.5, seed));
			ww = min(ww, 0.46 * bw);
			float cx = 0.5 * bw;
			lo = vec2(cx - ww, style == 1 ? 0.75 : 0.9);
			hi = vec2(cx + ww, style == 1 ? 2.85 : 2.5);
			rdepth = style == 1 ? 0.24 : 0.2;
			frame_col = style == 0 && seed > 0.6 ? frame_dark.rgb : frame_white.rgb;
			if (brick) {
				// Windows sit on whole brick courses.
				float y0 = ground_floor + level * floor_height;
				lo.y = floor((y0 + lo.y) / COURSE + 0.5) * COURSE - y0;
				hi.y = floor((y0 + hi.y) / COURSE + 0.5) * COURSE - y0;
			}
		}
		bool wide_room = cont || (gf && shops);
		float nb = wide_room ? 2.0 : 1.0;

		// -------------------------------------------------- wall material
		float layer = brick ? 0.0 : (style == 1 ? 2.0 : (style >= 3 ? 3.0 : 1.0));
		float tile = tile_m[int(layer)];
		float uc = dot(world_pos, T) + seed * 37.1;
		float vc = -v;
		vec3 col = wall;
		float rough = 0.9;
		float metal = 0.0;
		float ao = 1.0;
		vec3 nrm_w = n;
		vec4 wt = vec4(0.5, 0.5, 0.5, 0.0);
		vec4 wt2 = vec4(0.5);
		float mortar = 0.0;
		if (!low) {
			vec3 ratio, nm, orm;
			wall_scan(layer, vec2(uc, vc) / tile, ratio, nm, orm);
			if (brick) {
				mortar = orm.b;
				vec3 b = tint_scan(mix(vec3(1.0), ratio, 0.85), wall, 0.6);
				vec3 m = vec3(0.4, 0.38, 0.34) * (0.35 + 0.65 * luma(ratio)) * mix(vec3(1.0), wall * 3.0, 0.12);
				col = mix(b, m, mortar);
				rough = mix(0.88, 0.95, mortar);
			} else {
				col = tint_scan(ratio, wall, 1.0);
				rough = clamp(orm.g * 1.05, 0.55, 1.0);
				col *= 1.0 - orm.b * 0.12;
			}
			ao = orm.r;
			col *= mix(1.0, ao, 0.55);
			nrm_w = normalize(T * nm.x + Bt * nm.y + n * nm.z);
			wt = texture(weather, vec2(uc, vc) * 0.11 + seed * 5.0);
			wt2 = texture(weather, vec2(uc, vc) * 0.012 + seed * 3.0);
			// Large blotches: damp, repairs, sun-bleach; fine grain on plaster and stone.
			col *= 0.9 + 0.2 * wt2.g;
			col *= brick ? 1.0 : 0.93 + 0.14 * wt.b;
		} else {
			if (brick) {
				float course = floor(v / 0.077);
				float bx = (uc) / 0.23 + mod(course, 2.0) * 0.5;
				float mtr = max(grid_line(v, 0.077, 0.011), grid_line(bx, 1.0, 0.045));
				col = mix(col, wall * 1.6 + 0.05, mtr * 0.55);
			} else if (style == 1) {
				float course = floor(v / 0.6);
				float bx = uc / 1.2 + mod(course, 2.0) * 0.5;
				float joint = max(grid_line(v, 0.6, 0.012), grid_line(bx, 1.0, 0.01));
				col *= 1.0 - joint * 0.12;
			}
			col *= 0.95 + 0.1 * hash12(floor(vec2(uc, v) * 0.7));
		}
		// Grime near the ground, splash dust above it.
		float ground_dirt = 1.0 - smoothstep(0.0, 1.6, v);
		col *= 1.0 - 0.32 * ground_dirt * (0.55 + 0.45 * wt2.g);
		col *= 0.8 + 0.2 * smoothstep(0.0, 1.0, v);
		if (!low) {
			col = mix(col, col * 0.78, wt.a * (1.0 - smoothstep(0.0, 3.0, v)) * 0.45);  // damp / salts at the base
		}
		rough = mix(rough, 0.95, ground_dirt * 0.4);

		// --------------------------------------------------- window plane
		vec2 P0 = vec2(px, fv);
		float dN = max(dot(ray, -n), 0.03);
		vec2 sl = clamp(vec2(dot(ray, T), dot(ray, up)) / dN, vec2(-12.0), vec2(12.0));  // lateral shift per metre of depth
		float open0 = rect_mask(P0, lo, hi, fwm);
		bool shop_win = gf && shops;
		// Sill and lintel bands (outside the opening), shaded stone.
		float sill = 0.0;
		float lintel = 0.0;
		if (!cont && !shop_win) {
			sill = rect_mask(P0, vec2(lo.x - 0.05, lo.y - 0.11), vec2(hi.x + 0.05, lo.y + 0.01), fwm) * (1.0 - open0);
			if (style == 1 || brick) {
				lintel = rect_mask(P0, vec2(lo.x - 0.05, hi.y - 0.01), vec2(hi.x + 0.05, hi.y + (brick ? 0.17 : 0.2)), fwm) * (1.0 - open0);
			}
		}
		vec3 stone = srgb_to_linear(vec3(0.78, 0.75, 0.68));
		if (sill > 0.0) {
			col = mix(col, stone * (0.9 + 0.2 * wt.b), sill);
			rough = mix(rough, 0.8, sill);
			nrm_w = normalize(mix(nrm_w, normalize(n + up * 0.9), sill));
		}
		if (lintel > 0.0) {
			col = mix(col, brick ? col * 1.35 + 0.02 : stone * 0.95, lintel * 0.9);
		}
		if (style == 1 && !gf) {
			// Stone surround on limestone.
			float sur = rect_mask(P0, lo - vec2(0.12, 0.02), hi + vec2(0.12, 0.2), fwm) * (1.0 - open0);
			col = mix(col, col * 1.1, sur * 0.6);
		}
		if (!cont && !shop_win) {
			// Shadow line under the sill.
			float under = rect_mask(P0, vec2(lo.x - 0.03, lo.y - 0.19), vec2(hi.x + 0.03, lo.y - 0.11), fwm) * (1.0 - open0) * (1.0 - sill);
			col *= 1.0 - under * 0.35;
		}
		if (!low) {
			// Rain streaks run down from each sill, fading with distance below it.
			float d_above = fv < lo.y ? lo.y - fv : lo.y + floor_height - fv;
			float colm = cont ? 0.0 : rect_mask(vec2(P0.x, 0.0), vec2(lo.x, -1.0), vec2(hi.x, 1.0), fwm);
			float streak = smoothstep(0.35, 0.85, wt.r) * colm * exp(-d_above * 0.55) * (0.6 + 0.8 * hash12(wk + 3.0));
			col *= 1.0 - 0.22 * streak * (1.0 - open0);
			rough = mix(rough, 0.97, streak * 0.5);
		}

		vec3 emit = vec3(0.0);
		float spec = 0.5;
		float far = smoothstep(0.06, 0.2, fwm.x / bw);
		float far_i = smoothstep(0.04, 0.1, fwm.x / bw);  // room detail fades earlier

		if (open0 > 0.002) {
			vec3 o_col = col;
			float o_rough = rough;
			float o_metal = 0.0;
			vec3 o_nrm = nrm_w;
			vec3 o_emit = vec3(0.0);
			float o_spec = 0.5;
			vec2 P1 = P0;
			bool hit_reveal = false;
			vec3 rev_n = n;
			float rev_depth = 0.0;
			if (!low) {
				// Does the ray leave through a reveal side before the glass plane?
				vec2 tex_ = vec2(sl.x > 0.0 ? (hi.x - P0.x) / max(sl.x, 1e-4) : (lo.x - P0.x) / min(sl.x, -1e-4),
					sl.y > 0.0 ? (hi.y - P0.y) / max(sl.y, 1e-4) : (lo.y - P0.y) / min(sl.y, -1e-4));
				float zexit = min(tex_.x, tex_.y);
				if (zexit < rdepth) {
					hit_reveal = true;
					rev_depth = zexit;
					if (tex_.x < tex_.y) {
						rev_n = sl.x > 0.0 ? -T : T;
					} else {
						rev_n = sl.y > 0.0 ? -up : up;
					}
				}
				P1 = P0 + sl * rdepth;
			}

			if (hit_reveal) {
				// Reveal surface: the wall material, darker with depth.
				float dk = 1.0 - 0.5 * smoothstep(0.0, rdepth, rev_depth);
				o_col = col * 0.85 * dk;
				o_nrm = normalize(mix(n, rev_n, 0.85));
				o_rough = 0.9;
			} else {
				// Frame, muntins and glass at the recess plane.
				vec2 gl = lo + vec2(fr_w);
				vec2 gh = hi - vec2(fr_w);
				float g = rect_mask(P1, gl, gh, fwm);
				float frame = clamp(rect_mask(P1, lo - vec2(0.01), hi + vec2(0.01), fwm) - g, 0.0, 1.0);
				vec2 wsz = hi - lo;
				float hw = 0.02;  // muntin half width
				float bars = 0.0;
				if (cont) {
					// Mullions every half bay.
					float mx = (fract(P1.x / (bw * 0.5) + 0.5) - 0.5) * bw * 0.5;
					bars = soft_bar(mx, curtain ? 0.035 : 0.025, fwm.x) * g;
				} else if (shop_win) {
					float vb = door ? 0.0 : soft_bar(P1.x - 0.5 * bw, hw, fwm.x) * step(P1.y, 2.7);
					float tr = soft_bar(P1.y - 2.72, hw, fwm.y);
					bars = max(vb, tr);
					if (door) {
						// Kick plate and a push bar.
						bars = max(bars, soft_lt(P1.y, 0.3, fwm.y));
						bars = max(bars, soft_bar(P1.x - 0.62 * bw, 0.015, fwm.x) * step(1.0, P1.y) * step(P1.y, 1.6));
					}
					bars *= g;
				} else {
					float vb = 9.0;
					float hb = 9.0;
					float cxm = lo.x + wsz.x * 0.5;
					if (pat == 0) {
						vb = P1.x - cxm;
						hb = P1.y - (lo.y + wsz.y * 0.72);
					} else if (pat == 1) {
						hb = P1.y - (lo.y + wsz.y * 0.5);
					} else if (pat == 2) {
						vb = min(abs(P1.x - (lo.x + wsz.x * 0.333)), abs(P1.x - (lo.x + wsz.x * 0.667)));
					} else {
						hb = P1.y - (lo.y + wsz.y * 0.8);
					}
					bars = max(soft_bar(vb, hw, fwm.x), soft_bar(hb, hw, fwm.y)) * g;
				}
				bars = clamp(bars, 0.0, 1.0) * (1.0 - smoothstep(0.02, 0.06, fwm.x / bw));
				float gl_f = g * (1.0 - bars);

				// ------ glass: reflective, with a room behind it
				vec3 room_rgb = vec3(0.12, 0.1, 0.08);
				float cover = 0.0;
				vec3 cover_col = vec3(0.0);
				vec2 wk2 = vec2(floor(bay_id / nb), level) + seed * 53.0 + wall_id * 0.917;
				float lit_h = hash12(wk2);
				float lit = shop_win ? step(0.18, lit_h) : step(0.5, lit_h);
				float lvl = 0.75 + 0.5 * fract(lit_h * 7.3);
				vec3 lamp = mix(vec3(1.0, 0.78, 0.55), vec3(0.88, 0.95, 1.0), step(0.85, fract(lit_h * 13.7)));
				if (!low && gl_f > 0.01 && far_i < 0.99) {
					float rh2 = hash12(wk2 + 11.3);
					float rh3 = hash12(wk2 + 23.7);
					int ridx = int(floor(rh2 * float(shop_win ? shops_count : rooms_count)));
					float Wr = bw * nb;
					float Hr = gf ? 4.1 : 3.1;
					float Dr = mix(3.8, 6.2, rh3);
					float rx = mod(bay_id, nb) * bw + P1.x;
					vec3 p = vec3(rx / Wr * 2.0 - 1.0, (P1.y - 0.1) / Hr * 2.0 - 1.0, -1.0 + 2.0 * rdepth / Dr);
					p.xy = clamp(p.xy, vec2(-0.995), vec2(0.995));
					vec3 dn = vec3(dot(ray, T) / (Wr * 0.5), dot(ray, up) / (Hr * 0.5), dN / (Dr * 0.5));
					float mir = fract(rh3 * 5.7) > 0.5 ? -1.0 : 1.0;
					p.x *= mir;
					dn.x *= mir;
					int face;
					vec2 fuv;
					float tr;
					room_hit(p, dn, face, fuv, tr);
					float tpx = max(fwm.x / Wr * 2.0, fwm.y / Hr * 2.0) * 124.0;
					float lod = clamp(log2(max(tpx, 1.0)), 0.0, 2.5);
					room_rgb = room_texel(shop_win, ridx, face, clamp(fuv, vec2(-1.0), vec2(1.0)), lod);
					room_rgb = mix(room_rgb, vec3(0.22, 0.2, 0.18), far_i);
					// Blinds and curtains in front of the room (houses and flats).
					float cov_h = hash12(wk2 + 41.9);
					if (!cont && !shop_win && cov_h > 0.5 && high) {
						float wdt = gh.x - gl.x;
						float hgt = gh.y - gl.y;
						if (cov_h < 0.75) {
							// Venetian blind pulled down part way.
							float drop = 0.2 + 0.7 * fract(cov_h * 31.0);
							float bl_y = gh.y - hgt * drop;
							float bm = soft_lt(bl_y, P1.y, fwm.y);
							float slat = 0.8 + 0.2 * smoothstep(0.35, 0.65, abs(fract(P1.y * 38.0) - 0.5) * 2.0);
							vec3 bc = mix(vec3(0.62, 0.6, 0.55), vec3(0.45, 0.42, 0.36), step(0.5, fract(cov_h * 17.0)));
							cover = bm * (1.0 - far_i);
							cover_col = bc * slat;
						} else {
							// Curtains drawn in from both sides.
							float fold = 0.55 + 0.45 * cloth_folds(P1.x, cov_h * 20.0);
							float w1 = wdt * (0.18 + 0.25 * fract(cov_h * 13.0));
							float cm = max(soft_lt(P1.x, gl.x + w1, fwm.x), soft_gt(P1.x, gh.x - w1, fwm.x));
							vec3 fab = srgb_to_linear(mix(vec3(0.74, 0.7, 0.62), vec3(0.45, 0.3, 0.3), step(0.5, fract(cov_h * 9.0))));
							if (fract(cov_h * 23.0) > 0.5) {
								fab = srgb_to_linear(vec3(0.35, 0.42, 0.5));
							}
							cover = cm * (1.0 - far_i);
							cover_col = fab * fold;
						}
					}
				} else if (low) {
					room_rgb = vec3(0.2, 0.18, 0.15);
				}
				vec3 day_rgb = room_rgb * day_gain * (shop_win ? 2.4 : 1.0) * vec3(0.9, 1.0, 1.1);
				vec3 night_rgb = room_rgb * lamp * night_gain * lvl;
				vec3 glass_emit = mix(day_rgb, mix(vec3(0.01, 0.012, 0.018), night_rgb, lit), night);
				// A few lit rooms by day (offices): slightly brighter.
				glass_emit += (1.0 - night) * lit * step(0.8, fract(lit_h * 3.1)) * room_rgb * lamp * 0.05;
				vec3 cover_emit = cover_col * lamp * night * lit * 0.55;
				vec3 gcol = curtain ? glass_color.rgb * 0.25 : glass_color.rgb * 0.15;
				// Dust and rain marks on the glass: dirtier toward the bottom edge, varying per pane.
				float g_dirt = (0.5 + hash12(wk + 9.0)) * (0.06 + 0.22 * (1.0 - smoothstep(0.0, 0.5, P1.y - lo.y)) * step(0.5, hash12(wk + 4.0)));
				float g_rough = 0.035 + 0.09 * hash12(wk + 9.0) + g_dirt * 0.5;

				// Frame and mullions.
				float frame_rough = curtain ? 0.35 : 0.5;
				float frame_metal = curtain ? 1.0 : 0.0;
				float fbm = clamp(frame + bars, 0.0, 1.0);

				vec3 oc = mix(col * 0.8, gcol, gl_f);
				oc = mix(oc, cover_col, cover * gl_f);
				oc = mix(oc, frame_col * 0.95, fbm);
				// Ambient occlusion in the corner between frame and reveal.
				float cornerao = 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.08, rect_dist(P1, lo, hi)));
				oc *= cornerao;
				vec3 oe = (glass_emit * (1.0 - cover) + cover_emit * cover) * gl_f;
				float orough = mix(0.6, g_rough, gl_f);
				orough = mix(orough, 0.8, cover * gl_f);
				orough = mix(orough, frame_rough, fbm);
				// Panes bow slightly, so each reflects a different patch of sky.
				vec3 onrm = n;
				if (!low && high) {
					float jx = (hash12(wk + 5.3) - 0.5) * 0.04;
					float jy = (hash12(wk + 8.1) - 0.5) * 0.03;
					float jc = curtain ? 1.8 : 1.0;
					onrm = normalize(n + T * jx * jc + up * jy * jc);
				}
				// Fade to the far average: windows smaller than a pixel.
				vec3 far_col = mix(col, glass_color.rgb, curtain ? 0.75 : 0.3);
				o_col = mix(oc, far_col, far);
				o_rough = mix(orough, 0.6, far);
				o_metal = frame_metal * fbm * (1.0 - far);
				o_spec = mix(0.5, 1.0, gl_f * (1.0 - cover) * (1.0 - far));
				o_nrm = normalize(mix(mix(nrm_w, onrm, gl_f), nrm_w, far));
				o_emit = oe * (1.0 - far);
			}
			col = mix(col, o_col, open0);
			rough = mix(rough, o_rough, open0);
			metal = mix(metal, o_metal, open0);
			nrm_w = normalize(mix(nrm_w, o_nrm, open0));
			emit = o_emit * open0;
			spec = mix(spec, o_spec, open0);
		}
		// Far away: an even glow, varying slowly by floor and bay group.
		float group = hash12(vec2(floor(bay / 4.0), level) + seed * 31.0);
		emit += vec3(1.0, 0.74, 0.44) * far * night * (curtain ? 0.22 : 0.14) * (0.3 + 0.7 * group) * (gf ? 0.0 : 1.0);

		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
		AO = ao;
		AO_LIGHT_AFFECT = 0.3;
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);
	}
}
