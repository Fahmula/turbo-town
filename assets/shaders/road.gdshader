shader_type spatial;
// Procedural road markings. UV.x = metres across the road (0 = centre),
// UV.y = metres along it. Vertex colour alpha 0 marks deck sides (plain concrete).

uniform vec4 asphalt_color : source_color = vec4(0.30, 0.31, 0.35, 1.0);
uniform vec4 concrete_color : source_color = vec4(0.78, 0.77, 0.74, 1.0);
uniform vec4 white_line : source_color = vec4(0.96, 0.96, 0.93, 1.0);
uniform vec4 yellow_line : source_color = vec4(1.0, 0.78, 0.18, 1.0);
uniform float median_half = 0.0;
uniform int lanes_per_side = 2;
uniform float lane_width = 2.8;
// 0 = none, 1 = double solid yellow, 2 = dashed yellow
uniform int center_style = 1;
uniform float dash_length = 3.0;
uniform float dash_gap = 5.0;

varying vec3 world_pos;

float line_mask(float x, float center, float width) {
	float fw = fwidth(x) * 0.75;
	return 1.0 - smoothstep(width * 0.5 - fw, width * 0.5 + fw, abs(x - center));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (COLOR.a < 0.5) {
		ALBEDO = concrete_color.rgb;
		ROUGHNESS = 0.9;
	} else {
		float x = UV.x;
		float ax = abs(x);
		float y = UV.y;
		float patch = hash(floor(world_pos.xz * 0.25)) * 0.5 + hash(floor(world_pos.xz * 0.07)) * 0.5;
		vec3 col = asphalt_color.rgb * (0.94 + 0.1 * patch);
		float dash = step(fract(y / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));
		float w = 0.0;
		float yl = 0.0;
		float inner = 0.0;
		if (median_half > 0.0) {
			col = mix(col, concrete_color.rgb * 0.85, (1.0 - smoothstep(median_half - 0.05, median_half + 0.05, ax)) * 0.6);
			yl += line_mask(ax, median_half + 0.2, 0.15);
			inner = median_half + 0.4;
		} else if (center_style == 1) {
			yl += line_mask(ax, 0.14, 0.11);
		} else if (center_style == 2) {
			yl += line_mask(x, 0.0, 0.14) * dash;
		}
		for (int k = 1; k < lanes_per_side; k++) {
			w += line_mask(ax, inner + float(k) * lane_width, 0.14) * dash;
		}
		w += line_mask(ax, inner + float(lanes_per_side) * lane_width + 0.1, 0.16);
		col = mix(col, white_line.rgb, clamp(w, 0.0, 1.0));
		col = mix(col, yellow_line.rgb, clamp(yl, 0.0, 1.0));
		ALBEDO = col;
		ROUGHNESS = 0.82 - clamp(w + yl, 0.0, 1.0) * 0.2;
	}
}
