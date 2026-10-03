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
//         plain pieces are road paint (car park stall lines)

#include "res://assets/shaders/road_common.gdshaderinc"

// Concrete is lit as the scan says; the palette colours are brighter than
// real concrete, so scale them down a little.
uniform float concrete_albedo_scale = 0.82;

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
	} else {
		float chroma = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
		if (lum(base) > 0.5 && chroma < 0.12) {
			// Road paint (stall lines): thermoplastic, chipped and dirty.
			float chip = smoothstep(0.55, 0.95, mc.a * 0.8 + 0.2 * mc.r) * near;
			col = base * 0.86 * (0.78 + 0.22 * mc.g);
			col = mix(col, vec3(0.03), chip * 0.45);
			rough = 0.58;
		} else {
			// Plain ground (lawns etc.): clumps and faint mowing stripes.
			float lawn = clamp((COLOR.g - COLOR.r) * 10.0, 0.0, 1.0);
			float grain = low ? 0.0 : texture(asph_albedo, wp / 0.7).g * (1.0 / ALB_MEAN) - 1.0;
			col *= 0.88 + 0.24 * mc.g;
			col *= 1.0 + grain * 0.18;
			col *= 1.0 - smoothstep(0.55, 0.85, mc.a) * 0.14 * near * lawn;
			float stripe = grid_line(wp.x, 5.0, 2.5);
			col *= 1.0 + (stripe - 0.5) * 0.07 * lawn;
			rough = 0.95;
			spec = 0.3;
		}
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	SPECULAR = spec;
	AO = ao;
	if (!low && kind != 0) {
		NORMAL = bump_normal(NORMAL, VERTEX, kind == 1 ? wp / asph_tile : uvw / slab_tile, nxy);
	}
}
