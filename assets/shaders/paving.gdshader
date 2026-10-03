shader_type spatial;
// Paved ground (ART_BIBLE.md §16, realism experiment): sidewalks, kerbs,
// plazas, car parks and other flat ground inside the city blocks. Patterns
// are in world space, so pieces of the same surface join without seams.
// Concrete is a scan sampled per slab with a random offset and rotation, so
// no two slabs match; layers and textures: road_common.gdshaderinc.
//
// COLOR.rgb = base colour (sRGB; contact AO is baked in by darkening it).
// COLOR.a   = surface (in steps of 0.25):
//   1.0   concrete sidewalk slabs, 0.9 m grid
//   0.75  kerb stones: UV.x = metres along the kerb (joints every 1.2 m)
//   0.5   plaza tiles, 1.5 m, two tones
//   0.25  asphalt (car parks)
//   0.0   plain: lawn, soil, gravel (grain and blotches only); near-white
//         plain pieces are road paint (car park stall lines); brown ones
//         (r - b of 0.17-0.32, like ArtPalette.DIRT) are the trail's packed dirt;
//         green ones (g - r > 0.03, ArtPalette.LAWN) are lawns: the same grass
//         scan, macro variation and tint as the terrain (terrain.gdshader), so
//         they match the grass tufts standing on them (grass.gdshader).

#include "res://assets/shaders/road_common.gdshaderinc"
#include "res://assets/shaders/terrain_common.gdshaderinc"

// Concrete is lit as the scan says; the palette colours are brighter than
// real concrete, so scale them down a little.
uniform float concrete_albedo_scale = 0.82;

// Packed dirt of the mountain trail (plain pieces coloured like the dirt palette).
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nra : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_tile = 1.3;

// Lawns: the terrain's grass scan (assets/textures/terrain/), its macro noise.
// Low = albedo only (no normal map, no second scale).
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_noise : filter_linear_mipmap, repeat_enable;
uniform float grass_tile = 2.0;
uniform float grass_lum = 0.155;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Groove profile (depth d, width w) across a joint: signed distance `dd` to the
// joint line; returns the slope of the surface along dd (for normals) and sets
// `mask` to the groove coverage.
float groove(float dd, float w, float depth, out float mask) {
	float t = dd / w;
	float e = exp(-t * t);
	mask = e;
	return -depth * 2.0 * t / w * e;
}

void fragment() {
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	vec2 wp = world_pos.xz;
	bool low = quality == 0;
	vec3 N = normalize(world_normal);
	vec3 an = abs(N);
	// Planar projection along the dominant axis (kerb faces are vertical).
	vec2 uvw = an.y >= 0.7 ? wp : (an.x > an.z ? world_pos.zy : world_pos.xy);
	vec2 dx_w = dFdx(uvw);
	vec2 dy_w = dFdy(uvw);
	vec4 mc = texture(road_macro, wp / 30.0 + vec2(0.61, 0.23));
	int kind = int(round(COLOR.a * 4.0));
	vec3 base = srgb_to_linear(COLOR.rgb);
	float rough = 0.85;
	float spec = 0.5;
	float ao = 1.0;
	vec2 nxy = vec2(0.0);
	vec3 col = base;
	float fade = 1.0 - smoothstep(3.0, 14.0, dist);
	float rb = COLOR.r - COLOR.b;
	float lawn_w = 0.0;
	bool is_dirt = kind == 0 && rb > 0.17 && rb < 0.32 && COLOR.g > COLOR.b + 0.1 && COLOR.g < COLOR.r;

	if (kind == 4 || kind == 2) {
		// Concrete slabs (sidewalk 0.9 m; plaza tiles 1.5 m, two tones).
		float size = kind == 4 ? 0.9 : 1.5;
		vec2 cell = floor(uvw / size);
		float h = hash12(cell + 17.0);
		float checker = mod(cell.x + cell.y, 2.0);
		Surf s = concrete_surface(slab_albedo, slab_nra, uvw, dx_w, dy_w, cell, slab_tile, base * concrete_albedo_scale);
		col = s.col;
		col *= kind == 4 ? (0.94 + 0.12 * h) : (0.92 + 0.03 * checker + 0.12 * h);
		col *= mix(0.88, 1.1, mc.g);
		// Gum, oil and dirt spots; faint stains from the macro film.
		col *= 1.0 - smoothstep(0.35, 0.85, mc.b) * 0.3;
		col *= 0.95 + 0.1 * mc.a;
		rough = s.rough;
		ao = s.ao;
		nxy = s.nxy;
		// Joints: a narrow dirty groove with a soft shoulder.
		vec2 f = uvw / size;
		float jw = kind == 4 ? 0.0065 : 0.006;
		float mx;
		float mz;
		vec2 dd = (fract(f + 0.5) - 0.5) * size;
		float sx = groove(dd.x, jw, 0.0035, mx);
		float sz = groove(dd.y, jw, 0.0035, mz);
		float joint = clamp(max(grid_line(uvw.x, size, jw * 2.0), grid_line(uvw.y, size, jw * 2.0)), 0.0, 1.0);
		col *= 1.0 - joint * 0.45;
		ao *= 1.0 - joint * 0.4;
		rough = mix(rough, 0.95, joint);
		if (an.y >= 0.7) {
			nxy += vec2(sx, -sz) * fade;
		}
		if (kind == 2) {
			// Plaza: every fourth joint is a wider expansion joint.
			float big = clamp(max(grid_line(uvw.x, 6.0, 0.022), grid_line(uvw.y, 6.0, 0.022)), 0.0, 1.0);
			col *= 1.0 - big * 0.3;
			ao *= 1.0 - big * 0.3;
		}
	} else if (kind == 3) {
		// Kerb stones, 1.2 m, a bit darker where the road splashes them.
		float cellx = floor(UV.x / 1.2);
		Surf s = concrete_surface(slab_albedo, slab_nra, uvw, dx_w, dy_w, vec2(cellx, 3.0), slab_tile, base * concrete_albedo_scale * 0.95);
		col = s.col;
		col *= 0.93 + 0.12 * hash12(vec2(cellx, 3.0));
		col *= mix(0.86, 1.08, mc.g);
		float low_band = 1.0 - smoothstep(0.0, 0.12, world_pos.y);
		col *= 1.0 - low_band * 0.28 * (0.5 + 0.5 * mc.a);
		float jl = clamp(grid_line(UV.x, 1.2, 0.012), 0.0, 1.0);
		col *= 1.0 - jl * 0.55;
		ao = s.ao * (1.0 - jl * 0.4);
		rough = mix(s.rough, 0.95, jl);
		nxy = s.nxy;
	} else if (kind == 1) {
		// Car park asphalt: older and paler than the streets.
		Surf s = asphalt_surface(wp, asphalt_base * 1.12, 0.8, 1.0);
		col = s.col;
		rough = s.rough;
		ao = s.ao;
		nxy = s.nxy;
		uvw = wp;
	} else if (is_dirt) {
		// Packed dirt: a pebbly scan at two scales; the ruts are in the vertex colours.
		vec2 uvd = wp / dirt_tile;
		vec3 ratio = texture(dirt_albedo, uvd).rgb * (1.0 / ALB_MEAN);
		vec4 nra = low ? vec4(0.5, 0.5, 0.93, 1.0) : texture(dirt_nra, uvd);
		if (!low) {
			vec3 r2 = texture(dirt_albedo, ROT_A * wp / (dirt_tile * 0.53) + vec2(0.3, 0.8)).rgb * (1.0 / ALB_MEAN);
			ratio *= mix(vec3(1.0), r2, 0.5);
		}
		col = base * ratio * mix(0.85, 1.15, mc.g);
		rough = nra.b;
		ao = nra.a;
		spec = 0.35;
		nxy = low ? vec2(0.0) : (nra.rg * 2.0 - 1.0) * bump_strength;
	} else {
		float chroma = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
		if (lum(base) > 0.5 && chroma < 0.12) {
			// Road paint (stall lines): thermoplastic, chipped and dirty.
			float chip = smoothstep(0.55, 0.95, mc.a * 0.8 + 0.2 * mc.r) * near;
			col = base * 0.86 * (0.78 + 0.22 * mc.g);
			col = mix(col, vec3(0.03), chip * 0.45);
			rough = 0.58;
		} else {
			// Plain ground (lawns etc.). Lawns are the terrain's grass.
			float lawn = clamp((COLOR.g - COLOR.r) * 10.0, 0.0, 1.0);
			col *= 0.88 + 0.24 * mc.g;
			rough = 0.95;
			spec = 0.3;
			if (lawn > 0.01) {
				lawn_w = lawn;
				float inv = 1.0 / grass_tile;
				vec3 g = textureGrad(grass_albedo, wp * inv, dx_w * inv, dy_w * inv).rgb;
				vec3 macro = vec3(0.0, 0.2, 0.5);
				if (!low) {
					macro = ground_macro(grass_noise, wp, 0.0);
					// Second, rotated, much larger scale: breaks the tile up.
					mat2 r2 = rot2(0.54);
					float i2 = inv / 7.3;
					vec3 b2 = textureGrad(grass_albedo, r2 * wp * i2 + vec2(0.31, 0.57), r2 * dx_w * i2, r2 * dy_w * i2).rgb;
					g *= mix(1.0, clamp(dot(b2, LUMA) / grass_lum, 0.55, 1.5), 0.6 * (1.0 - smoothstep(60.0, 220.0, dist)));
					nxy = (textureGrad(grass_normal, wp * inv, dx_w * inv, dy_w * inv).xy * 2.0 - 1.0) * 0.9 * lawn;
				}
				vec3 green = g * grass_tint(macro, 0.55);
				// Dry patches, as on the terrain (same noise, so tufts and lawn agree).
				float dry = smoothstep(0.35, 0.65, macro.x);
				vec3 straw = vec3(0.36, 0.29, 0.125) * clamp(dot(g, LUMA) / grass_lum, 0.5, 1.6);
				vec3 lawn_col = mix(green, straw, dry);
				// Faint mowing stripes.
				float stripe = grid_line(wp.x, 5.0, 2.5);
				lawn_col *= 1.0 + (stripe - 0.5) * 0.06;
				col = mix(col, lawn_col, lawn);
				rough = mix(rough, 0.9, lawn);
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	SPECULAR = spec;
	AO = ao;
	if (!low && (kind != 0 || is_dirt || lawn_w > 0.01)) {
		NORMAL = bump_normal(NORMAL, VERTEX, lawn_w > 0.01 ? wp / grass_tile : (is_dirt ? wp / dirt_tile : (kind == 1 ? wp / asph_tile : uvw / slab_tile)), nxy);
	}
}
