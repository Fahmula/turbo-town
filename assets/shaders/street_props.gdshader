shader_type spatial;
// Street furniture, stunt-park structures, landmarks and building clutter
// (ART_BIBLE.md §17): one material for every part, so a lamp post, a loop or a
// whole block's roof clutter is a single draw call. The material comes from
// the vertex colour alpha and picks a layer of three texture arrays made by
// tools/textures/fetch_props.py (CC0 scans, see assets/textures/props/SOURCES.md).
//
// COLOR.rgb = albedo (sRGB; contact AO baked in by darkening). The scan only
//             adds variation around it (grain, scratches, weave), so any paint
//             colour works on any layer.
// COLOR.a   = material class. Stored as k / 15 for the original classes
//             (0 painted ... 15 deck) or (2k + 1) / 30 for the extra ones;
//             the full table is in props_common.gdshaderinc.
//    painted metal / paint, bare metal, concrete, plastic, rubber, glass,
//    warm / cool lamps (glow at night), signal lens red / amber / green,
//    sign face, fabric, wood, always-on glow, deck panels (ramps), plus
//    corrugated steel, tread plate, weathered timber, rusty steel, worn
//    paint, brushed steel, roof slate, polished aluminium.
// UV        = metres, planar per face (MeshBuilder). UV.x across, UV.y along
//             for decks. Faces without UVs fall back to world-space planar
//             mapping.
// UV2       = (optional) per-part offset into the texture so repeated
//             boards or panels don't show the same grain.
// instance uniform `signal`: which signal lens is lit (0 red, 1 amber,
//    2 green, -1 none); set per traffic light with set_instance_shader_parameter.
// instance uniform `tint`: multiplies painted parts (class 0), e.g. a
//    random colour per oil drum.
// instance uniform `grime`: 1 on props whose origin is on the ground (KitProp):
//    dirt and spray gather in the first half metre.
//
// Quality (global `quality`): Low skips every texture (flat roughness table),
// Medium samples the three arrays, High adds the world-space dirt noise.

#include "res://assets/shaders/world_common.gdshaderinc"
#include "res://assets/shaders/props_common.gdshaderinc"

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
instance uniform int signal = -1;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float grime = 0.0;

varying vec3 world_pos;
varying float local_y;
// The class must not blend across a triangle (a cone's orange-to-white band
// would otherwise pass through every class in between): take it from one corner.
varying flat float cls;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_y = VERTEX.y;
	cls = COLOR.a;
}

// Sheets laid in running bond with a screw or bolt row along every seam.
// p = (across, along) in metres, sz = sheet size across x along, stagger =
// how far every other row shifts (0..1 of the width), sp = fastener spacing,
// inset = distance of the fasteners from the seam, rad = fastener radius.
// Returns (seam, fastener) masks and a per-sheet hash.
vec3 deck_sheets(vec2 p, vec2 sz, float stagger, float sp, float inset, float rad, float dist) {
	float row = floor(p.y / sz.y);
	float x = p.x + mod(row, 2.0) * sz.x * stagger;
	float hsh = hash12(vec2(floor(x / sz.x), row));
	float seam = max(grid_line(p.y, sz.y, 0.028), grid_line(x, sz.x, 0.028));
	vec2 d = vec2(abs(fract(x / sz.x + 0.5) - 0.5) * sz.x, abs(fract(p.y / sz.y + 0.5) - 0.5) * sz.y);
	float ysp = (fract(p.y / sp) - 0.5) * sp;
	float xsp = (fract(x / sp) - 0.5) * sp;
	float s1 = 1.0 - smoothstep(rad, rad * 1.8, length(vec2(d.x - inset, ysp)));
	float s2 = 1.0 - smoothstep(rad, rad * 1.8, length(vec2(d.y - inset, xsp)));
	float screws = max(s1, s2) * (1.0 - smoothstep(6.0, 22.0, dist));
	return vec3(seam, screws, hsh);
}

void fragment() {
	int c = clamp(int(round(cls * 30.0)), 0, 30);
	int layer = PROPS_LAYER[c];
	vec3 col = srgb_to_linear(COLOR.rgb);
	float rough = PROPS_ROUGH[c];
	float metal = 0.0;
	float spec = 0.5;
	float ao = 1.0;
	vec3 emit = vec3(0.0);
	float dist = length(VERTEX);
	float near = detail_fade(dist);

	// Planar mapping in metres; faces that have no UVs use world space.
	vec2 uvm = UV;
	float uv_grad = abs(dFdx(UV.x)) + abs(dFdy(UV.x)) + abs(dFdx(UV.y)) + abs(dFdy(UV.y));
	if (uv_grad < 1e-7) {
		vec3 wn = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		uvm = wn.y >= wn.x && wn.y >= wn.z ? world_pos.xz : (wn.x >= wn.z ? world_pos.zy : world_pos.xy);
	}

	// Deck: plywood sheets, the grain runs along the ramp.
	vec3 sheet = vec3(0.0);
	if (c == 30) {
		sheet = deck_sheets(UV, vec2(1.22, 2.44), 0.5, 0.305, 0.04, 0.005, dist);
		uvm = vec2(UV.y + sheet.z * 7.31, UV.x + sheet.z * 3.17);
	} else if (c == 21) {
		// Steel deck: 1.5 x 2 m painted plates, bolted along the seams.
		sheet = deck_sheets(UV, vec2(1.5, 2.0), 0.0, 0.25, 0.035, 0.011, dist);
		uvm = UV + vec2(sheet.z * 5.3, sheet.z * 2.9);
	} else if (c == 25 || c == 27) {
		// Decking (152 mm) and crate slats (210 mm): boards across UV.x, each
		// with its own grain and tone.
		float pitch = c == 25 ? 0.152 : 0.21;
		float idx = floor(UV.x / pitch);
		float h = hash12(vec2(idx, 3.7 + UV2.x * 11.0));
		sheet = vec3(grid_line(UV.x + pitch * 0.5, pitch, 0.012), 0.0, h);
		uvm = vec2(UV.x + h * 7.1, UV.y + h * 3.3);
	}

	if (quality > 0) {
		int lyr = max(layer, 0);
		vec2 uv = (uvm + UV2 * 13.7) / PROPS_TILE[lyr];
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		vec3 nt = vec3(0.0, 0.0, 1.0);
		if (layer >= 0) {
			vec3 lz = vec3(uv, float(lyr));
			vec3 ratio = textureGrad(tex_albedo, lz, dx, dy).rgb * 5.0;
			vec3 orm = textureGrad(tex_orm, lz, dx, dy).rgb;
			col *= mix(vec3(1.0), ratio, PROPS_ALBEDO_K[lyr]);
			rough = orm.g;
			ao = mix(1.0, orm.r, 0.7);
			if (c == 9) {
				metal = orm.b;
			}
			nt = props_decode_normal(textureGrad(tex_normal, lz, dx, dy).rg, PROPS_NORMAL_K[lyr]);
		}
		NORMAL = props_perturb(NORMAL, VERTEX, uv, nt);
	}
	if (quality >= 2) {
		float macro = texture(detail, (world_pos.xz + world_pos.y * 0.7) * 0.37).g;
		col *= 1.0 + (macro - 0.5) * 0.14;
		rough = clamp(rough + (0.5 - macro) * 0.08, 0.04, 1.0);
	}

	if (c == 2 || c == 13 || c == 17) {
		metal = 1.0;
		if (c == 17) {
			rough = 0.18;
		}
	} else if (c == 10) {
		rough = 0.05;
	} else if (c == 12 || c == 14) {
		rough = 0.2;
		vec3 lamp = c == 12 ? vec3(1.0, 0.886, 0.69) : vec3(0.91, 0.941, 1.0);
		col = mix(col, lamp, night);
		emit = lamp * night * 5.0;
	} else if (c == 16 || c == 18 || c == 20) {
		rough = 0.12;
		vec3 lens = c == 16 ? vec3(1.0, 0.12, 0.08) : (c == 18 ? vec3(1.0, 0.62, 0.05) : vec3(0.1, 1.0, 0.45));
		bool on = signal == (c - 16) / 2;
		col = on ? lens : lens * 0.12 + 0.02;
		emit = on ? lens * 3.0 : vec3(0.0);
	} else if (c == 19) {
		rough = min(rough * 0.45, 0.3);
	} else if (c == 21) {
		col *= 1.0 - sheet.x * 0.45;
		col *= 1.0 + (sheet.z - 0.5) * 0.06;
		col = mix(col, vec3(0.5, 0.5, 0.52), sheet.y * 0.8);
		rough = mix(rough, 0.35, sheet.y);
		rough = max(rough, sheet.x * 0.8);
		metal = sheet.y;
	} else if (c == 22) {
		rough = 0.3;
	} else if (c == 23) {
		rough = 0.22;
		spec = 0.8;
	} else if (c == 24) {
		spec = 0.3;
	} else if (c == 25 || c == 27) {
		col *= 1.0 - sheet.x * 0.55;
		col *= 0.78 + sheet.z * 0.44;
		rough = max(rough, sheet.x * 0.9);
	} else if (c == 28) {
		rough = 0.3;
		emit = col * (0.8 + 1.2 * night);
	} else if (c == 30) {
		// Sheets differ a little in tint; rubber has polished two wheel paths.
		col *= 1.0 - sheet.x * 0.3;
		col *= 1.0 + (sheet.z - 0.5) * 0.14;
		float wheel = 1.0 - smoothstep(0.1, 0.32, abs(abs(UV.x) - 0.95));
		float scuff = quality > 0 ? texture(detail, UV * 0.37).g : 0.5;
		wheel *= 0.5 + 0.5 * scuff;
		col *= 1.0 - wheel * 0.16;
		col = mix(col, vec3(0.2, 0.2, 0.21), sheet.y * 0.75);
		rough = mix(rough * 0.92, 0.45, sheet.y);
		rough = max(rough, sheet.x * 0.85);
		rough = mix(rough, 0.82, wheel * 0.5);
	} else if (c == 0) {
		col *= tint.rgb;
	}

	// Dirt and road spray gather low on props that stand on the ground.
	float dirt = grime * (1.0 - smoothstep(0.0, 0.5, local_y));
	col *= 1.0 - 0.3 * dirt;
	rough = mix(rough, 0.92, dirt * 0.4);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = metal;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	EMISSION = emit;
}
