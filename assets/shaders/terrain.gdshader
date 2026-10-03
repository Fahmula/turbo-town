shader_type spatial;
// Island terrain (realism branch). Ground is built per pixel from CC0 scans
// (assets/textures/terrain/, made by tools/textures/fetch_terrain.py): grass,
// dry grass, dirt, rock and sand, each with albedo + normal (+ ORM), sampled in
// world space at two scales (the second one rotated and 7x larger, used as a
// luminance modulation) so tiling never shows, plus world-space macro noise.
//
// Vertex data from TerrainBuilder:
//   COLOR.r = sand weight, COLOR.g = dirt weight, COLOR.b = dry-grass weight,
//   COLOR.a = patch noise; UV.x = road influence (worn verge).
// Rock comes from the slope per pixel (triplanar). The waterline gets a wet
// band (darker, glossier) below SEA_LEVEL_Y + 0.5.
//
// Quality: Low = one albedo sample per material, no normal maps, no second
// scale. Medium = + normal maps. High = + second scale, dirt/sand macro, ORM.

#include "res://assets/shaders/world_common.gdshaderinc"
#include "res://assets/shaders/terrain_common.gdshaderinc"

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_macro : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_macro : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D churn_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D churn_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// World size (m) of one texture tile.
uniform float grass_tile = 2.0;
uniform float dry_tile = 2.5;
uniform float dirt_tile = 1.3;
uniform float rock_tile = 2.7;
uniform float sand_tile = 1.5;
uniform float churn_tile = 8.0;
uniform float churn_lum = 0.05;
// Average linear luminance of each albedo (the fetch script's targets).
uniform float grass_lum = 0.155;
uniform float dry_lum = 0.20;
uniform float dirt_lum = 0.16;
uniform float rock_lum = 0.21;
uniform float sand_lum = 0.40;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

vec2 nrm_xy(vec4 t) {
	return t.xy * 2.0 - 1.0;
}

void fragment() {
	vec3 N = normalize(world_normal);
	vec2 wp = world_pos.xz;
	float dist = length(VERTEX);
	bool low = quality == 0;
	bool high = quality >= 2;
	// Derivatives in uniform control flow, for the textureGrad calls below.
	vec2 dx = dFdx(wp);
	vec2 dy = dFdy(wp);
	float nfade = 1.0 - smoothstep(25.0, 140.0, dist);

	// ------------------------------------------------------------ weights --
	vec3 macro = ground_macro(noise, wp, COLOR.b);
	vec4 nz = textureLod(noise, wp / 24.0, 0.0);
	float jitter = (nz.g - 0.5) * 0.5 + (nz.b - 0.5) * 0.4;
	float w_sand = smoothstep(0.4, 0.62, COLOR.r + jitter * 0.6);
	float w_dirt = smoothstep(0.28, 0.5, COLOR.g + jitter * 0.55);
	float dry = smoothstep(0.35, 0.65, macro.x + jitter * 0.3);
	float steep = (1.0 - smoothstep(0.70, 0.86, N.y + (nz.b - 0.5) * 0.1)) * (1.0 - w_dirt * 0.85);

	// ------------------------------------------------------------- grass ---
	vec2 uvg = wp / grass_tile;
	vec2 uvg2 = (rot2(0.54) * wp) / (grass_tile * 7.3) + vec2(0.31, 0.57);
	vec3 col;
	float g_l = 1.0;
	vec2 tn = vec2(0.0);
	float rough = 0.9;
	float ao = 1.0;
	float spec = 0.3;
	{
		vec3 a = textureGrad(grass_albedo, uvg, dx / grass_tile, dy / grass_tile).rgb;
		if (!low) {
			vec3 b = textureGrad(grass_albedo, uvg2, rot2(0.54) * dx / (grass_tile * 7.3), rot2(0.54) * dy / (grass_tile * 7.3)).rgb;
			a *= mix(1.0, clamp(dot(b, LUMA) / grass_lum, 0.55, 1.5), 0.6 * (1.0 - smoothstep(60.0, 220.0, dist)));
		}
		g_l = clamp(dot(a, LUMA) / grass_lum, 0.5, 1.6);
		col = a * grass_tint(macro, COLOR.a);
		if (!low) {
			tn = nrm_xy(textureGrad(grass_normal, uvg, dx / grass_tile, dy / grass_tile));
		}
		if (high) {
			vec4 o = textureGrad(grass_orm, uvg, dx / grass_tile, dy / grass_tile);
			ao = o.r;
			rough = max(o.g, 0.9);
		}
	}
	// --------------------------------------------------------------- dry ---
	if (dry > 0.001) {
		vec2 uv = wp / dry_tile;
		float dl = dot(textureGrad(dry_albedo, uv, dx / dry_tile, dy / dry_tile).rgb, LUMA) / dry_lum;
		// Dry grass: straw colour with the structure of the grass and of the dry turf scan.
		vec3 a = vec3(0.36, 0.29, 0.125) * mix(g_l, clamp(dl, 0.5, 1.6), 0.5) * mix(0.9, 1.1, COLOR.a);
		col = mix(col, a, dry);
		if (!low) {
			tn = mix(tn, nrm_xy(textureGrad(dry_normal, uv, dx / dry_tile, dy / dry_tile)), dry);
		}
		rough = mix(rough, 0.92, dry);
	}
	// -------------------------------------------------------------- dirt ---
	if (w_dirt > 0.001) {
		vec2 uv = wp / dirt_tile;
		vec3 a = textureGrad(dirt_albedo, uv, dx / dirt_tile, dy / dirt_tile).rgb;
		if (high) {
			// Scuffs and worn patches at two scales (20 m and a rotated 53 m) so the tile never shows.
			mat2 rm = rot2(0.83);
			vec3 m = textureGrad(dirt_macro, wp / 20.0, dx / 20.0, dy / 20.0).rgb;
			vec3 m2 = textureGrad(dirt_macro, (rm * wp) / 53.0 + vec2(0.4, 0.2), rm * dx / 53.0, rm * dy / 53.0).rgb;
			float ml = dot(m, LUMA) * 0.6 + dot(m2, LUMA) * 0.4;
			a *= mix(1.0, clamp(ml / 0.2, 0.6, 1.5), 1.0 - smoothstep(150.0, 450.0, dist));
		} else if (!low) {
			a *= 0.5 + dirt_lum * 2.5 * (nz.r + 0.5);
		}
		col = mix(col, a, w_dirt);
		if (!low) {
			tn = mix(tn, nrm_xy(textureGrad(dirt_normal, uv, dx / dirt_tile, dy / dirt_tile)), w_dirt);
		}
		float r = 0.9;
		if (high) {
			r = max(textureGrad(dirt_orm, uv, dx / dirt_tile, dy / dirt_tile).g, 0.84);
			ao = mix(ao, textureGrad(dirt_orm, uv, dx / dirt_tile, dy / dirt_tile).r, w_dirt);
		}
		rough = mix(rough, r, w_dirt);
		spec = mix(spec, 0.4, w_dirt);
	}
	// ----------------------------------------------------- churned mud -----
	// Tyre tracks and ruts over the dirt fields, in patches (high only).
	if (high && w_dirt > 0.3) {
		float patch = smoothstep(0.42, 0.66, nz.g * 0.6 + macro.z * 0.5 + 0.05 + (1.0 - N.y) * 1.5) * smoothstep(0.3, 0.7, w_dirt);
		if (patch > 0.001) {
			mat2 rc = rot2(0.35 + 1.3 * step(0.5, nz.r));
			vec2 cuv = (rc * wp) / churn_tile;
			vec2 cdx = rc * dx / churn_tile;
			vec2 cdy = rc * dy / churn_tile;
			float cl = dot(textureGrad(churn_albedo, cuv, cdx, cdy).rgb, LUMA);
			vec2 ctn = nrm_xy(textureGrad(churn_normal, cuv, cdx, cdy));
			col *= mix(1.0, 0.7 * clamp(cl / churn_lum, 0.45, 1.7), patch);
			tn = mix(tn, tn * 0.4 + vec2(ctn.x, ctn.y) * 1.2, patch);
			rough = mix(rough, 0.72, patch);
		}
	}
	// -------------------------------------------------------------- sand ---
	if (w_sand > 0.001) {
		vec2 uv = wp / sand_tile;
		vec3 a = textureGrad(sand_albedo, uv, dx / sand_tile, dy / sand_tile).rgb;
		if (!low) {
			vec3 m = textureGrad(sand_macro, wp / 30.0, dx / 30.0, dy / 30.0).rgb;
			a *= clamp(dot(m, LUMA) / sand_lum, 0.7, 1.3);
		}
		col = mix(col, a, w_sand);
		if (!low) {
			tn = mix(tn, nrm_xy(textureGrad(sand_normal, uv, dx / sand_tile, dy / sand_tile)), w_sand);
		}
		float r = 0.88;
		if (high) {
			r = max(textureGrad(sand_orm, uv, dx / sand_tile, dy / sand_tile).g, 0.8);
		}
		rough = mix(rough, r, w_sand);
		spec = mix(spec, 0.45, w_sand);
	}
	// -------------------------------------------------- compose normal ----
	vec3 n_out = N;
	if (!low) {
		n_out = normalize(N + vec3(tn.x, 0.0, -tn.y) * 0.9 * nfade);
	}
	// -------------------------------------------------------------- rock ---
	if (steep > 0.001) {
		vec3 bw = pow(abs(N), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec2 uvx = world_pos.zy / rock_tile;
		vec2 uvy = wp / rock_tile;
		vec2 uvz = world_pos.xy / rock_tile;
		vec2 dpx = dFdx(world_pos.zy) / rock_tile;
		vec2 dqx = dFdy(world_pos.zy) / rock_tile;
		vec2 dpy = dx / rock_tile;
		vec2 dqy = dy / rock_tile;
		vec2 dpz = dFdx(world_pos.xy) / rock_tile;
		vec2 dqz = dFdy(world_pos.xy) / rock_tile;
		vec3 rx = textureGrad(rock_albedo, uvx, dpx, dqx).rgb;
		vec3 ry = textureGrad(rock_albedo, uvy, dpy, dqy).rgb;
		vec3 rz = textureGrad(rock_albedo, uvz, dpz, dqz).rgb;
		vec3 r = rx * bw.x + ry * bw.y + rz * bw.z;
		r *= 0.85 + 0.35 * nz.r;
		float rr = 0.9;
		vec3 rn = N;
		if (!low) {
			vec2 tx = nrm_xy(textureGrad(rock_normal, uvx, dpx, dqx));
			vec2 ty = nrm_xy(textureGrad(rock_normal, uvy, dpy, dqy));
			vec2 tz = nrm_xy(textureGrad(rock_normal, uvz, dpz, dqz));
			// Whiteout-style blend: each projection tilts the normal across its plane.
			vec3 nx = vec3(0.0, tx.y, -tx.x) * sign(N.x);   // YZ plane: U = +Z, image-up = +Y
			vec3 ny = vec3(ty.x, 0.0, -ty.y);               // XZ plane
			vec3 nzv = vec3(tz.x, tz.y, 0.0) * sign(N.z);   // XY plane: U = +X, image-up = +Y
			rn = normalize(N + (nx * bw.x + ny * bw.y + nzv * bw.z) * 1.1);
			if (high) {
				rr = max(textureGrad(rock_orm, uvy, dpy, dqy).g, 0.82);
			}
		}
		// Rock darkens slightly in cracks and where it is wet.
		col = mix(col, r, steep);
		rough = mix(rough, rr, steep);
		n_out = normalize(mix(n_out, rn, steep));
		spec = mix(spec, 0.5, steep);
		ao = mix(ao, 1.0, steep);
	}
	// ----------------------------------------------------------- wetness ---
	float wet = 1.0 - smoothstep(SEA_LEVEL_Y - 0.1, SEA_LEVEL_Y + 0.55, world_pos.y + (nz.b - 0.5) * 0.18);
	col *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.28, wet);
	spec = mix(spec, 0.55, wet);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_out, 0.0)).xyz);
}
