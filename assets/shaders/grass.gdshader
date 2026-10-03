shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, diffuse_lambert, specular_disabled;
// 3D grass tufts (realism branch). A MultiMesh holds a fixed lattice of crossed
// grass cards around the camera (GrassField moves it in whole lattice steps);
// this shader decides, per lattice slot, whether a tuft grows there and where:
//   * slot -> world lattice cell (stable identity) -> jittered position
//   * terrain height from `heights` (R32F, same triangulation as the mesh)
//   * `mask`: R = grass density (not on roads, dirt, sand, rock, paved sites),
//     G = dry-grass weight, B = patch noise (all from TerrainBuilder)
//   * density thins out with distance (random threshold per tuft), tufts shrink
//     to nothing at the fade-out distance; unlucky slots are clipped away
//   * the city parks' lawns (`parks`) get tufts at lawn height
// Colour comes from the card atlas (assets/textures/terrain/grass_cards.png,
// 2x2 tufts), tinted with the same macro variation as the ground
// (terrain_common.gdshaderinc) and dried to straw where the ground is dry;
// darker at the root. Wind sway grows with height squared. No shadows cast
// (GrassField), normals = the ground's (soft, consistent light).
// Alpha scissor (not alpha-to-coverage: rejected pixels skip the lighting), Lambert
// diffuse and no specular: grass is the most overdrawn thing on the island.
//
// Mesh: x in [-0.5, 0.5], y in [0, 1] (COLOR.r = height fraction), UV = card.
// Quality: Low draws nothing.

#include "res://assets/shaders/world_common.gdshaderinc"
#include "res://assets/shaders/terrain_common.gdshaderinc"

uniform sampler2D cards : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform sampler2D mask : filter_linear, repeat_disable;

uniform float t_half = 640.0;
uniform float t_cell = 4.0;
uniform int t_n = 321;
// Lattice spacing of this ring (m); fade-in (start, end) and fade-out (start, end) distances.
uniform float spacing = 0.5;
uniform vec2 fade_in = vec2(0.0, 0.0);
uniform vec2 fade_out = vec2(14.0, 22.0);
// Tuft size (width, height) in metres at scale 1.
uniform vec2 tuft_size = vec2(0.55, 0.42);
uniform float wind = 1.0;
uniform float grass_lum = 0.155;
// Park lawns: (x0, z0, x1, z1); lawn height; count.
uniform vec4 parks[4];
uniform int park_count = 0;
uniform float park_y = 0.154;

varying vec3 v_tint;
varying float v_dry;
varying float v_h;
varying vec3 v_ground_n;
varying vec2 v_uv;
varying float v_var;

void vertex() {
	vec3 slot = MODEL_MATRIX[3].xyz;
	vec2 cell = floor(slot.xz / spacing + 0.5);
	vec2 h1 = hash22(cell);
	vec2 h2 = hash22(cell + vec2(17.31, 5.77));
	vec2 pos = (cell + (h1 - 0.5) * 0.96) * spacing;
	float d = distance(pos, CAMERA_POSITION_WORLD.xz);

	// ---- terrain at this spot ----
	vec2 tg = (pos + t_half) / t_cell;
	ivec2 ti = clamp(ivec2(floor(tg)), ivec2(0), ivec2(t_n - 2));
	vec2 f = clamp(tg - vec2(ti), 0.0, 1.0);
	float h00 = texelFetch(heights, ti, 0).r;
	float h10 = texelFetch(heights, ti + ivec2(1, 0), 0).r;
	float h01 = texelFetch(heights, ti + ivec2(0, 1), 0).r;
	float h11 = texelFetch(heights, ti + ivec2(1, 1), 0).r;
	float gh;
	vec2 grad;
	if (f.x >= f.y) {
		gh = h00 + (h10 - h00) * f.x + (h11 - h10) * f.y;
		grad = vec2(h10 - h00, h11 - h10) / t_cell;
	} else {
		gh = h00 + (h11 - h01) * f.x + (h01 - h00) * f.y;
		grad = vec2(h11 - h01, h01 - h00) / t_cell;
	}
	vec3 mk = texture(mask, (tg + 0.5) / float(t_n)).rgb;
	float dens = mk.r;
	vec3 gn = normalize(vec3(-grad.x, 1.0, -grad.y));

	// ---- park lawns ----
	for (int i = 0; i < 4; i++) {
		if (i < park_count) {
			vec4 r = parks[i];
			if (pos.x > r.x && pos.x < r.z && pos.y > r.y && pos.y < r.w) {
				vec2 c = (r.xy + r.zw) * 0.5;
				bool path = abs(pos.x - c.x) < 2.3 || abs(pos.y - c.y) < 2.3;
				bool pond = distance(pos, c + vec2(12.0)) < 7.6;
				bool edge = pos.x < r.x + 0.5 || pos.x > r.z - 0.5 || pos.y < r.y + 0.5 || pos.y > r.w - 0.5;
				dens = (path || pond || edge) ? 0.0 : 1.0;
				gh = park_y;
				gn = vec3(0.0, 1.0, 0.0);
				mk = vec3(dens, 0.0, 0.55);
			}
		}
	}

	// Clumpy meadow: patches of thick tall grass between thinner areas.
	vec4 nn = textureLod(noise, pos / 29.0, 0.0);
	dens *= mix(0.55, 1.0, smoothstep(0.35, 0.62, nn.g * 0.7 + nn.b * 0.5 + 0.1));
	float fin = fade_in.y > fade_in.x ? smoothstep(fade_in.x, fade_in.y, d) : 1.0;
	float keep = dens * (1.0 - smoothstep(fade_out.x, fade_out.y, d)) * fin;
	if (quality == 0 || h2.x >= keep) {
		POSITION = vec4(0.0, 0.0, -2.0, 1.0);
		v_tint = vec3(1.0);
		v_dry = 0.0;
		v_h = 0.0;
		v_ground_n = gn;
		v_uv = vec2(0.0);
		v_var = 1.0;
	} else {
		float shrink = 1.0 - smoothstep(fade_out.y - (fade_out.y - fade_out.x) * 0.3, fade_out.y, d);
		float sc = mix(0.55, 1.5, h2.y * h2.y) * mix(0.75, 1.25, nn.r) * mix(0.8, 1.0, shrink) * shrink;
		float yaw = h1.x * 6.2832 + h1.y * 3.0;
		float cy = cos(yaw);
		float sy = sin(yaw);
		// The card's direction is baked into the mesh (x, z); turn the whole tuft about Y.
		vec2 off = vec2(VERTEX.x * cy - VERTEX.z * sy, VERTEX.x * sy + VERTEX.z * cy) * tuft_size.x * sc;
		vec3 world = vec3(pos.x + off.x, gh + VERTEX.y * tuft_size.y * sc, pos.y + off.y);
		// Wind: a bending sway growing with height squared, plus a lean per tuft.
		float hf = VERTEX.y;
		float bend = hf * hf;
		float t = TIME * 1.6;
		float gust = sin(t + pos.x * 0.21 + pos.y * 0.17) * 0.6 + sin(t * 2.3 + pos.x * 0.9 + pos.y * 0.7 + h2.x * 6.0) * 0.25;
		vec2 w = vec2(gust + 0.4, gust * 0.5 - 0.2) * 0.11 * wind * bend * sc;
		w += (h1 - 0.5) * 0.18 * bend * sc;
		world.xz += w;
		world.y -= bend * 0.01;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = (VIEW_MATRIX * vec4(gn, 0.0)).xyz;
		POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);

		// ---- colour per tuft ----
		vec3 macro = ground_macro(noise, pos, mk.g);
		v_tint = grass_tint(macro, mk.b) * mix(0.88, 1.12, h2.y);
		v_dry = smoothstep(0.35, 0.65, macro.x);
		v_h = hf;
		v_ground_n = gn;
		v_var = mix(0.85, 1.12, hash12(cell + 3.3));
		int idx = int(floor(h2.x / max(keep, 0.001) * 4.0)) & 3;
		vec2 uv = UV;
		if (h1.y > 0.5) {
			uv.x = 1.0 - uv.x;
		}
		v_uv = (uv + vec2(float(idx & 1), float(idx >> 1))) * 0.5;
	}
}

void fragment() {
	vec4 t = texture(cards, v_uv);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	vec3 c = t.rgb;
	float l = dot(c, LUMA);
	vec3 green = c * v_tint;
	vec3 dry = vec3(0.36, 0.29, 0.125) * (l / grass_lum) * 0.9;
	vec3 col = mix(green, dry, v_dry);
	// Darker at the root, lighter at the tips.
	float ao = mix(0.3, 1.0, smoothstep(0.0, 0.6, v_h));
	ALBEDO = col * ao * v_var;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_ground_n, 0.0)).xyz);
}
