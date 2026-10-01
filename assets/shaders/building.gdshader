shader_type spatial;
// Stylized building walls: vertex colour = wall colour, procedural windows.
// UV = metres (u along the wall, v up from the base). COLOR.a = 0 disables
// windows (roofs, trims).

uniform vec4 glass_color : source_color = vec4(0.15, 0.21, 0.28, 1.0);
uniform vec4 glass_lit : source_color = vec4(0.36, 0.44, 0.52, 1.0);
uniform vec4 frame_color : source_color = vec4(0.88, 0.87, 0.83, 1.0);
uniform float floor_height = 3.4;
uniform float window_spacing = 3.2;
// 0 = day, 1 = night: some windows light up.
uniform float night = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 wall = srgb_to_linear(COLOR.rgb);
	ALBEDO = wall;
	ROUGHNESS = 0.85;
	if (COLOR.a > 0.5 && UV.y > 0.3) {
		vec2 cell = vec2(UV.x / window_spacing, UV.y / floor_height);
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float fw = fwidth(cell.x) + fwidth(cell.y);
		bool ground = UV.y < floor_height;
		vec2 lo = ground ? vec2(0.08, 0.12) : vec2(0.22, 0.3);
		vec2 hi = ground ? vec2(0.92, 0.78) : vec2(0.78, 0.8);
		vec2 fr = vec2(0.035, 0.05);
		float win = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y);
		float frame = step(lo.x - fr.x, f.x) * step(f.x, hi.x + fr.x) * step(lo.y - fr.y, f.y) * step(f.y, hi.y + fr.y);
		// Fade window detail out at distance to avoid shimmer.
		float fade = 1.0 - smoothstep(0.25, 0.6, fw);
		// Per-building seed from the wall colour, rounded first: the hash
		// amplifies the tiny per-pixel wobble of an interpolated colour into
		// static-like speckles otherwise.
		vec2 seed = floor(COLOR.rg * 255.0 + 0.5);
		float h = hash(id + seed * 0.37);
		vec3 glass = mix(glass_color.rgb, glass_lit.rgb, step(0.78, h) * 0.6 + 0.25 * f.y);
		vec3 c = mix(wall, frame_color.rgb, (frame - win) * fade * 0.8);
		c = mix(c, glass, win * fade);
		ALBEDO = c;
		ROUGHNESS = mix(0.85, 0.1, win * fade);
		float lit = step(0.45, hash(id * 1.7 + seed.yx * 0.53));
		// Mostly warm rooms, some cool-white offices, varied brightness.
		vec3 room = mix(vec3(1.0, 0.68, 0.36), vec3(0.8, 0.88, 1.0), step(0.85, fract(h * 13.7)));
		EMISSION = room * win * lit * night * (0.9 + 0.5 * fract(h * 7.3));
	}
}
