shader_type sky;
// Sky (ART_BIBLE.md §11): the same gradient as Godot's procedural sky (zenith,
// hazy horizon, earthy ground half) with a sun or moon disk and glow, plus
// soft fair-weather cumulus and faint cirrus from the tileable noise in
// assets/textures/sky/clouds.png (R coverage, G edge detail, B cirrus). The
// clouds are lit toward the sun (a second sample offset toward it shades the
// far side) and fade into the haze near the horizon. No TIME: the radiance
// map only re-renders when DayNight changes a colour.
// DayNight sets the colours per hour (`set_shader_parameter`).

uniform vec4 sky_top_color : source_color = vec4(0.239, 0.486, 0.788, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.839, 0.890, 0.925, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.38, 0.38, 0.35, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.839, 0.890, 0.925, 1.0);
uniform float sky_curve = 0.15;
uniform float ground_curve = 0.02;
uniform float sun_angle_max = 20.0;
uniform float sun_curve = 0.15;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
// 0 = clear, 1 = overcast.
uniform float cloud_coverage = 0.42;
uniform vec4 cloud_light : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.72, 0.77, 0.84, 1.0);
uniform vec2 cloud_offset = vec2(0.0);

void sky() {
	vec3 d = EYEDIR;
	float v_angle = acos(clamp(d.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));

	// Clouds on a plane above the island.
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.1) * 0.28 + cloud_offset;
		float cov = texture(clouds, uv).r;
		float det = texture(clouds, uv * 2.7 + vec2(0.31, 0.77)).g;
		float shape = cov - (det - 0.5) * 0.22;
		float lo = 1.0 - cloud_coverage;
		float den = smoothstep(lo, lo + 0.2, shape);
		// Self-shadowing: denser toward the sun = this side faces away from it.
		vec2 to_sun = normalize(LIGHT0_DIRECTION.xz + vec2(1e-4)) * 0.035;
		float toward = texture(clouds, uv + to_sun).r - (det - 0.5) * 0.22;
		float lit = clamp(1.0 - (toward - shape) * 5.0, 0.0, 1.0);
		lit *= 0.7 + 0.3 * smoothstep(lo, lo + 0.45, shape) ;
		float sun_side = dot(d, LIGHT0_DIRECTION) * 0.5 + 0.5;
		vec3 light = cloud_light.rgb * (0.85 + 0.3 * sun_side);
		vec3 cc = mix(cloud_shade.rgb, light, lit);
		// Fade into the haze toward the horizon.
		float fade = smoothstep(0.02, 0.22, d.y);
		sky = mix(sky, cc, den * fade);
		// Faint cirrus.
		float ci = texture(clouds, uv * 0.6 + vec2(0.5, 0.2)).b;
		sky = mix(sky, light, smoothstep(0.6, 0.95, ci) * 0.18 * fade * (1.0 - den));
	}

	// Sun (or moon) disk and glow.
	if (LIGHT0_ENABLED) {
		float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, d), -1.0, 1.0));
		vec3 disk = LIGHT0_COLOR * LIGHT0_ENERGY;
		if (sun_angle < LIGHT0_SIZE) {
			sky = disk;
		} else if (sun_angle < radians(sun_angle_max)) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (radians(sun_angle_max) - LIGHT0_SIZE);
			sky = mix(disk, sky, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}

	float cg = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(1.0 - pow(1.0 - cg, 1.0 / ground_curve), 0.0, 1.0));
	COLOR = d.y >= 0.0 ? sky : ground;
}
