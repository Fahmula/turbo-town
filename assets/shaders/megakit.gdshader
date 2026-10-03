// The Downtown City MegaKit material (experiment/quaternius-downtown-city).
// Every kit module (walls, windows, trims, roofs, sidewalks, props) is drawn
// by this one shader, so a whole building is ONE mesh surface and one draw
// call: the kit's eight texture sets are slices of two texture arrays and
// each vertex says which slice it uses.
//
// Vertex data (scripts/world/downtown/megakit_library.gd, MegaKit):
//   UV        the kit's UV0: tiling textures / trim sheets. Fake windows add
//             4 * k to u (an integer offset, invisible on tiling layers) so
//             each window instance carries its own random k (room, blinds,
//             lit at night) without extra vertex data.
//   UV2       the kit's UV1: where the face sits on the "fake bevel" corner
//             normal map (megakit_detail.rg), so box edges read as rounded
//             and chipped without bevel geometry.
//   COLOR.g   the kit's wear mask: 1 clean, 0 grimy (wall bases, gutters).
//   CUSTOM0   RGBA8 (texture layer, tint slot, kind, room variant) / 255.
//             Layers: 0 brick, 1 trim stone, 2 metal + concrete, 3 ornaments,
//             4 slate, 5 asphalt, 6 concrete, 7 soil. Slots: MegaKit.SLOT_*.
//             Kind 0 solid, 1 fake interior window, 2 painted wall sign
//             (a faded advertisement on a party wall: the brick of UV with
//             paint over it; UV2 = sign coordinates 0..1, v down; CUSTOM0.a =
//             sign atlas row + 16 * paint scheme), 3 plain glass (doors and
//             transoms: dark, reflective, a dimly lit lobby at night).
// Per instance: `palette` picks a row of palette_tex: per slot, RGB = the
// colour that slot is recoloured to and A = how strongly (0 = the kit's own
// colour). A building gets one palette (MegaKit.PALETTES).
//
// Windows: the kit's 2D one-point-perspective room photos (megakit_rooms)
// are interior mapped: the view ray is intersected with a box room behind
// the window and the hit is projected back into the photo, so rooms have
// depth and parallax. Glass is folded in: low roughness and a Fresnel sky
// reflection, the room seen through it as emission (dim by day). At night
// about half the rooms are lit (warm, some cool offices), like facade.gdshader.
// Blinds / curtains from megakit_covers hang in some windows.
//
// Quality: Low drops the bevel and drip samples, the parallax rooms (flat
// dark glass with a faint room) and the covers.

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// facade_common brings world_common (night, quality, hashes) and room_hit.
#include "res://assets/shaders/facade_common.gdshaderinc"

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray room_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2DArray cover_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
// Shop interiors behind the ground-floor windows: the city's shop room atlas
// (facade.gdshader's, tools/blender/make_building_interiors.py): 8 x 8 cells
// of 256 px, room * 5 + face (0 back, 1 left, 2 right, 3 floor, 4 ceiling).
uniform sampler2D shops_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int shops_count = 12;
// Lettering for painted wall signs: the city's shop sign atlas (16 rows of
// 1024 x 128, A = lettering).
uniform sampler2D signs_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Ground-floor windows below this world height show shops (sidewalk 0.15 m + 3 m).
uniform float shop_top = 3.2;

uniform float normal_strength = 1.0;
uniform float bevel_strength = 0.8;
uniform float grime_strength = 0.55;
// Back wall's share of the room photo (one-point perspective), and the
// room depth in metres used for parallax.
uniform float room_back = 0.59;
uniform float room_depth = 4.0;
uniform float day_room_gain = 0.26;
uniform float night_room_gain = 1.25;
uniform vec3 glass_tint : source_color = vec3(0.06, 0.07, 0.075);

instance uniform int palette = 0;

varying flat int v_layer;
varying flat int v_slot;
varying flat int v_kind;
varying flat int v_extra;
varying vec3 v_world;
varying vec3 v_wnormal;

// Average linear albedo of each slice (tools/megakit/build_megakit_textures.py),
// the reference the palette recolours against. Metal: its painted band.
const vec3 LAYER_AVG[8] = vec3[8](
	vec3(0.1543, 0.0843, 0.0561), vec3(0.3675, 0.3318, 0.1939), vec3(0.0478, 0.0368, 0.0283),
	vec3(0.3003, 0.2761, 0.1939), vec3(0.0681, 0.0681, 0.0681), vec3(0.0428, 0.0419, 0.0396),
	vec3(0.2134, 0.2046, 0.1941), vec3(0.1015, 0.0779, 0.0613));

void vertex() {
	v_layer = int(CUSTOM0.r * 255.0 + 0.5);
	v_slot = int(CUSTOM0.g * 255.0 + 0.5);
	v_kind = int(CUSTOM0.b * 255.0 + 0.5);
	v_extra = int(CUSTOM0.a * 255.0 + 0.5);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Cotangent frame from screen derivatives (no tangent arrays needed):
// columns = dP/du, dP/dv (normalised to the larger), N. All in view space.
mat3 cotangent_frame(vec3 n, vec3 dp1, vec3 dp2, vec2 duv1, vec2 duv2) {
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-20));
	return mat3(t * invmax, b * invmax, n);
}

vec3 unpack_xy(vec2 xy, float strength) {
	vec2 v = (xy * 2.0 - 1.0) * strength;
	return vec3(v, sqrt(max(1.0 - dot(v, v), 0.0)));
}

vec3 shop_texel(int room, int face, vec2 fuv, float lod) {
	int idx = room * 5 + face;
	vec2 cell = vec2(float(idx % 8), float(idx / 8));
	vec2 inner = vec2(fuv.x * 0.5 + 0.5, 0.5 - fuv.y * 0.5);
	inner = (inner * 248.0 + 4.0) / 256.0;
	return textureLod(shops_atlas, (cell + inner) / 8.0, lod).rgb;
}

// Screen derivatives of UV with the per-window offsets (multiples of 4 in u)
// taken out, so a 2x2 pixel quad straddling two modules doesn't see a jump
// (that picks the smallest mip and bends normals: bright dots along seams).
vec2 unwrap4(vec2 d) {
	return vec2(d.x - 4.0 * round(d.x * 0.25), d.y);
}

void fragment() {
	bool low = quality == 0;
	vec3 n_geo = normalize(NORMAL);
	vec3 view_dir = normalize(-VERTEX);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 duv1 = unwrap4(dFdx(UV));
	vec2 duv2 = unwrap4(dFdy(UV));
	vec2 d2uv1 = dFdx(UV2);
	vec2 d2uv2 = dFdy(UV2);

	if (v_kind == 3) {
		// ------------------------------------------------------ plain glass
		float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(n_geo, view_dir), 0.0, 1.0), 5.0);
		ALBEDO = glass_tint;
		ROUGHNESS = 0.05;
		METALLIC = 0.0;
		SPECULAR = 0.5;
		EMISSION = mix(vec3(0.012, 0.011, 0.01), vec3(1.0, 0.8, 0.58) * 0.35, night) * (1.0 - fres);
	} else if (v_kind == 1) {
		// ---------------------------------------------------------- windows
		// u carries 4 * k (the instance's random number), see the header.
		float k = floor((UV.x + 0.5) * 0.25);
		vec2 wuv = vec2(UV.x - 4.0 * k, UV.y);
		float h1 = hash12(vec2(k, 7.13));
		float h2 = hash12(vec2(k, 19.7));
		float h3 = hash12(vec2(k, 31.1));
		float h4 = hash12(vec2(k, 47.9));

		// Window frame in view space: T = dP/du, B = dP/dv (metres per UV).
		float det = duv1.x * duv2.y - duv1.y * duv2.x;
		vec3 Tm = (dp1 * duv2.y - dp2 * duv1.y) / det;
		vec3 Bm = (dp2 * duv1.x - dp1 * duv2.x) / det;
		float W = max(length(Tm), 0.2);
		float H = max(length(Bm), 0.2);
		vec3 Tn = Tm / W;
		vec3 Bn = Bm / H;  // points down the window (v grows downwards)
		vec3 ray = -view_dir;
		// Room box: x, y in [-1, 1] across the window (y up), z 0..1 into it.
		vec3 d = vec3(dot(ray, Tn) / (W * 0.5), -dot(ray, Bn) / (H * 0.5), dot(ray, -n_geo) / room_depth);
		vec2 p0 = vec2(wuv.x * 2.0 - 1.0, 1.0 - wuv.y * 2.0);
		int room = int(h1 * 2.999);  // 0, 1 lit offices; 2 dark room (picked below)
		float mir = h2 > 0.5 ? -1.0 : 1.0;
		vec3 room_rgb;
		if (!low) {
			d.z = max(d.z, 1e-3);
			vec2 sg = vec2(d.x >= 0.0 ? 1.0 : -1.0, d.y >= 0.0 ? 1.0 : -1.0);
			vec2 inv = 1.0 / (abs(d.xy) + 1e-4) * sg;
			vec2 txy = (sg - p0) * inv;
			float t = min(min(txy.x, txy.y), 1.0 / d.z);
			vec3 h = vec3(p0, 0.0) + d * t;
			vec2 img = h.xy / (1.0 + h.z * (1.0 - room_back) / room_back);
			img.x *= mir;
			vec2 ruv = vec2(img.x * 0.5 + 0.5, 0.5 - img.y * 0.5);
			// Lit rooms by day are offices; the dark photo reads as a flat.
			int layer = h3 < 0.22 ? 2 : (room > 1 ? 0 : room);
			room_rgb = textureLod(room_tex, vec3(clamp(ruv, 0.002, 0.998), float(layer)),
				clamp(log2(max(max(length(duv1), length(duv2)) * 512.0, 1.0)), 0.0, 4.0)).rgb;
		} else {
			room_rgb = vec3(0.09, 0.08, 0.07);
		}
		// Blinds or curtains in about 40% of the windows.
		float cover = 0.0;
		vec3 cover_rgb = vec3(0.0);
		if (!low && h4 > 0.6) {
			vec2 cuv;
			float which;
			if (h4 > 0.82) {
				// Curtains: the tied-back pair (top left of the atlas) or the
				// closed curtain (top right).
				which = 1.0;
				cuv = vec2((h2 > 0.75 ? 0.5 : 0.0) + wuv.x * 0.5, wuv.y * 0.5);
			} else {
				// A blind pulled part way down: a tall panel of the atlas.
				which = 0.0;
				float drop = 0.25 + 0.65 * h3;
				cuv = vec2(0.03 + wuv.x * 0.1, 0.52 + (wuv.y / drop) * 0.44);
				cuv = wuv.y > drop ? vec2(-1.0) : cuv;
			}
			if (cuv.x >= 0.0) {
				vec4 c = textureGrad(cover_tex, vec3(cuv, which), duv1 * 0.5, duv2 * 0.5);
				cover = c.a;
				cover_rgb = c.rgb;
			}
		}
		float lit = step(0.48, fract(h1 * 7.31 + h3));
		float level = 0.75 + 0.5 * h2;
		vec3 lamp = mix(vec3(1.0, 0.78, 0.55), vec3(0.88, 0.95, 1.0), step(0.85, fract(h4 * 13.7)));
		float gain = day_room_gain;
		if (v_world.y < shop_top && !low) {
			// A shop: one box room per 6 m of frontage (so a shop shows
			// through several windows), in world space along the wall.
			vec3 nw = normalize(v_wnormal);
			vec3 tw = normalize(cross(vec3(0.0, 1.0, 0.0), nw));
			float along = dot(v_world, tw);
			float cell = floor(along / 6.0);
			vec3 rp = vec3((along - cell * 6.0) / 3.0 - 1.0, (v_world.y - 0.15) / 1.5 - 1.0, -1.0);
			rp.xy = clamp(rp.xy, vec2(-0.995), vec2(0.995));
			vec3 rw = normalize(v_world - CAMERA_POSITION_WORLD);
			vec3 rd = vec3(dot(rw, tw) / 3.0, rw.y / 1.5, max(dot(rw, -nw), 1e-3) / 2.6);
			int face;
			vec2 fuv;
			float tr;
			room_hit(rp, rd, face, fuv, tr);
			float sh = hash12(vec2(cell, floor(dot(v_world, nw) + 0.5)) + 3.7);
			float lod = clamp(log2(max(max(length(duv1), length(duv2)) * 256.0, 1.0)), 0.0, 2.0);
			room_rgb = shop_texel(int(sh * float(shops_count)) % shops_count, face, clamp(fuv, vec2(-1.0), vec2(1.0)), lod);
			lit = step(0.15, fract(sh * 17.3));  // most shops are lit at night
			gain = day_room_gain * 2.2;  // shops are bright inside by day
			cover = 0.0;
		}
		vec3 day_rgb = room_rgb * gain;
		vec3 night_rgb = room_rgb * lamp * night_room_gain * level;
		vec3 room_emit = mix(day_rgb, mix(room_rgb * 0.015, night_rgb, lit), night);
		vec3 cover_emit = cover_rgb * mix(vec3(0.25), lamp * 0.9 * lit + 0.02, night);
		ALBEDO = mix(glass_tint, cover_rgb * 0.6, cover * 0.5);
		// What the glass lets through: Schlick's Fresnel (F0 0.04) takes it
		// away at grazing angles, where the reflection of the sky takes over.
		float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(n_geo, view_dir), 0.0, 1.0), 5.0);
		EMISSION = mix(room_emit, cover_emit, cover) * (1.0 - fres);
		METALLIC = 0.0;
		ROUGHNESS = mix(0.04 + 0.04 * h2, 0.6, cover * 0.3);
		SPECULAR = 0.5;
		// Panes sit at slightly different angles, so they mirror different sky.
		NORMAL = normalize(n_geo + (Tn * (h3 - 0.5) + Bn * (h2 - 0.5)) * 0.03);
	} else {
		// ------------------------------------------------------------ solid
		int layer = v_layer;
		vec3 uvw = vec3(UV, float(layer));
		vec3 base = textureGrad(albedo_tex, uvw, duv1, duv2).rgb;
		vec4 nra = textureGrad(nrm_tex, uvw, duv1, duv2);
		float rough = nra.b;
		float ao = nra.a;

		// Palette: recolour this slot towards the building's colour, keeping
		// the texture's own variation as a ratio to the slice's average.
		vec4 pal = texelFetch(palette_tex, ivec2(v_slot, palette), 0);
		if (pal.a > 0.0) {
			vec3 avg = LAYER_AVG[layer];
			vec3 ratio = base / max(avg, vec3(1e-3));
			vec3 lw = vec3(0.2126, 0.7152, 0.0722);
			float lum_ratio = dot(base, lw) / max(dot(avg, lw), 1e-3);
			vec3 recol = pal.rgb * mix(vec3(lum_ratio), ratio, 0.35);
			float k = pal.a;
			if (layer == 2) {
				// Only the painted metal band; the concrete stays concrete.
				k *= 1.0 - smoothstep(0.06, 0.12, dot(base, vec3(0.2126, 0.7152, 0.0722)));
			}
			base = mix(base, recol, k);
		}

		mat3 tbn = cotangent_frame(n_geo, dp1, dp2, duv1, duv2);
		// OpenGL normal maps: +Y is up the image, i.e. towards -v.
		// No normal map where UV doesn't really change across the pixel.
		float uv_k = smoothstep(2e-6, 2e-5, max(length(duv1), length(duv2)));
		vec3 nt = unpack_xy(nra.rg, normal_strength * uv_k);
		nt.y = -nt.y;
		vec3 n = tbn * nt;
		float grime = 1.0 - COLOR.g;
		float dist = length(VERTEX);
		if (!low && v_kind != 2) {
			// Fake bevels: only where UV2 really spans the face (constant UV2
			// interpolates with float noise, and a frame built from that noise
			// points anywhere: TV-static speckle), and only up close.
			vec2 g2 = vec2(length(d2uv1), length(d2uv2));
			float g1 = max(length(duv1), length(duv2));
			float bevel_k = smoothstep(0.02, 0.1, max(g2.x, g2.y) / max(g1, 1e-6)) * (1.0 - smoothstep(25.0, 45.0, dist));
			vec4 det = textureGrad(detail_tex, UV2, d2uv1, d2uv2);
			if (bevel_k > 0.0) {
				mat3 tbn2 = cotangent_frame(n_geo, dp1, dp2, d2uv1, d2uv2);
				vec3 bt = unpack_xy(det.rg, bevel_strength);
				bt.y = -bt.y;
				n = normalize(n + tbn2 * vec3(bt.xy, 0.0) * bevel_k);
			}
			// Drip streaks in world space (2.5 m tiles, running down walls).
			vec2 wuv = vec2(v_world.x + v_world.z, v_world.y * 0.7) * 0.4;
			float drip = texture(detail_tex, wuv).b;
			grime = clamp(grime * (0.55 + 0.9 * (1.0 - drip)), 0.0, 1.0);
			// A whisper of streaking on every wall, darker low down.
			float wall = 1.0 - abs(v_wnormal.y);
			grime = max(grime, wall * (1.0 - drip) * 0.18 * (1.0 - smoothstep(0.0, 14.0, v_world.y - 0.15)));
		}
		if (v_kind == 2) {
			// Faded painted advertisement: a panel with a border and the
			// lettering, worn away in streaks so the brick shows through.
			int scheme = v_extra / 16;
			float row = float(v_extra % 16);
			vec3 bg = scheme == 0 ? vec3(0.42, 0.13, 0.1) : (scheme == 1 ? vec3(0.14, 0.27, 0.18)
				: (scheme == 2 ? vec3(0.12, 0.17, 0.3) : vec3(0.1, 0.1, 0.1)));
			vec3 ink = scheme == 2 ? vec3(0.85, 0.72, 0.35) : vec3(0.86, 0.82, 0.7);
			// Sun-faded: pulled toward a chalky grey.
			bg = srgb_to_linear(mix(bg, vec3(0.55, 0.53, 0.5), 0.3));
			ink = srgb_to_linear(mix(ink, vec3(0.75, 0.73, 0.68), 0.25));
			vec2 sc = UV2;
			float border = 1.0 - band(sc.x, 0.03, 0.97) * band(sc.y, 0.06, 0.94);
			float inner = band(sc.x, 0.05, 0.95) * band(sc.y, 0.1, 0.9) * (1.0 - band(sc.x, 0.06, 0.94) * band(sc.y, 0.12, 0.88));
			float tv = (sc.y - 0.22) / 0.56;
			float letters = 0.0;
			if (tv > 0.0 && tv < 1.0) {
				letters = textureGrad(signs_atlas, vec2(sc.x, (row + tv) / 16.0), d2uv1, d2uv2 / 16.0).a;
			}
			vec3 paint = mix(bg, ink, clamp(max(letters, max(border, inner) * 0.85), 0.0, 1.0));
			vec2 wuv = vec2(v_world.x + v_world.z, v_world.y * 0.7) * 0.4;
			float worn = texture(detail_tex, wuv * 0.6 + 0.37).b;
			float cover = smoothstep(0.25, 0.65, worn) * 0.62;
			vec3 lw = vec3(0.2126, 0.7152, 0.0722);
			paint *= 0.7 + 0.6 * clamp(dot(base, lw) / max(dot(LAYER_AVG[0], lw), 1e-3), 0.0, 1.5) * 0.5;
			base = mix(base, paint, cover);
			rough = mix(rough, 0.8, cover);
		}
		base *= 1.0 - grime * grime_strength;
		rough = mix(rough, min(rough + 0.15, 1.0), grime);
		ALBEDO = base;
		ROUGHNESS = rough;
		METALLIC = 0.0;
		AO = ao;
		AO_LIGHT_AFFECT = 0.3;
		NORMAL = normalize(n);
	}
}
