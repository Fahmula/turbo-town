shader_type spatial;
// Rain streaks (RainFx, ART_BIBLE.md §23): one thin quad per drop, stretched
// along the drop's velocity (the particle's Y axis, align_y) and turned
// round it to face the camera. Far drops widen to stay about a pixel across
// and fade by the same amount, so they don't shimmer; near ones fade out
// (the hood camera sits inside the car, and drops right at the lens look
// like scratches). Lit by the ambient light plus a glint toward any light
// behind the drop: rain shows up in headlights and under street lamps.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform float length_m = 0.9;
uniform float width_m = 0.012;
uniform float opacity = 0.5;
uniform vec3 drop_color : source_color = vec3(0.8, 0.83, 0.88);

varying float v_alpha;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float dist = max(length(to_cam), 0.01);
	vec3 side = normalize(cross(axis, to_cam / dist));
	// One pixel's width at this distance (from the projection's vertical scale).
	float px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width_m, dist * px * 1.3);
	vec3 world = center + side * VERTEX.x * w + axis * VERTEX.y * length_m;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
	v_alpha = opacity * (width_m / w) * smoothstep(1.0, 2.5, dist) * (1.0 - smoothstep(11.0, 17.0, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float ends = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	ALBEDO = drop_color;
	ALPHA = v_alpha * smoothstep(0.0, 0.7, across) * ends;
	ROUGHNESS = 0.4;
	SPECULAR = 0.0;
}

void light() {
	// Forward scattering: brightest when the light shines through the drop
	// toward the camera.
	float through = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 6.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (0.15 + 2.0 * through) / PI;
}
