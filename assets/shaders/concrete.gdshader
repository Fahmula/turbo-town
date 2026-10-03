shader_type spatial;
// Cast concrete (ART_BIBLE.md §16, realism experiment): Jersey barriers,
// overpass piers, girders and fascias, retaining walls. A scan of weathered
// formed concrete (pores, cloudy mottling) at two scales, rain streaks running
// down vertical faces (more near the top edges, where water runs off), barrier
// joints and formwork lines. Texture coordinates come from the world position
// (picked by the face's direction), so nothing needs unwrapping; layers and
// textures: road_common.gdshaderinc.
//
// COLOR.rgb = base colour (sRGB; stained bases and contact AO baked in).
// COLOR.a   = 1.0 cast concrete (faint formwork lines every 1.25 m, UV.y =
//             metres up), 0.5 barrier segments (UV.x = metres along: a joint
//             every 6 m), 0.0 plain.

#include "res://assets/shaders/road_common.gdshaderinc"

// The palette concrete is brighter than real weathered concrete.
uniform float cast_albedo_scale = 0.8;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(VERTEX);
	float near = detail_fade(dist);
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	bool vertical = an.y < 0.7;
	// Planar projection along the dominant axis.
	vec2 uvw = an.y >= 0.7 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
	float across = an.x > an.z ? world_pos.z : world_pos.x;
	bool low = quality == 0;
	vec2 dx_w = dFdx(uvw);
	vec2 dy_w = dFdy(uvw);
	vec4 mc = texture(road_macro, uvw / 30.0 + vec2(0.53, 0.29));

	Surf s = concrete_surface(cast_albedo, cast_nra, uvw, dx_w, dy_w, vec2(2.0, 7.0), cast_tile, srgb_to_linear(COLOR.rgb) * cast_albedo_scale);
	vec3 col = s.col;
	if (!low) {
		// A second, smaller and rotated sample breaks up the tiling.
		vec3 r2 = texture(cast_albedo, ROT_A * uvw / (cast_tile * 0.57) + vec2(0.21, 0.67)).rgb * (1.0 / ALB_MEAN);
		col *= mix(vec3(1.0), r2, 0.45);
	}
	col *= mix(0.84, 1.14, mc.g);
	col *= 0.94 + 0.1 * mc.a;
	if (vertical && !low) {
		// Rain streaks: noise stretched down the face, darker near the top.
		float st = texture(road_macro, vec2(across * 0.17, world_pos.y * 0.012) + vec2(0.11, 0.47)).a;
		float top = 1.0 - smoothstep(0.0, 2.2, 6.0 - world_pos.y);
		col *= 1.0 - smoothstep(0.5, 0.82, st) * 0.18;
	}
	// Dirt from the road: darker near the ground (splash, exhaust), a little more where oily.
	float splash = 1.0 - smoothstep(0.0, 0.7, world_pos.y);
	col *= 1.0 - splash * (0.12 + 0.12 * mc.b);
	float ao = s.ao;

	int kind = int(round(COLOR.a * 2.0));
	if (kind == 2 && vertical) {
		// Formwork joints: a faint dark line and a slight step.
		float fl = clamp(grid_line(UV.y, 1.25, 0.012), 0.0, 1.0);
		col *= 1.0 - fl * 0.28;
		ao *= 1.0 - fl * 0.3;
	} else if (kind == 1) {
		float joint = clamp(grid_line(UV.x, 6.0, 0.02), 0.0, 1.0);
		col *= 1.0 - joint * 0.6;
		ao *= 1.0 - joint * 0.5;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(s.rough, 0.65, 1.0);
	AO = ao;
	if (!low) {
		NORMAL = bump_normal(NORMAL, VERTEX, uvw / cast_tile, s.nxy);
	}
}
