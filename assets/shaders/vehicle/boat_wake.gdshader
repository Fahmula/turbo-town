shader_type spatial;
// A boat's wake (BoatEffects): a ribbon laid on the sea behind the transom.
// Each point of it widens as it ages (the Kelvin wake opens at about 19.5
// degrees), so the trail spreads into a V. Drawn here: two bright foam arms
// along its edges, churned white water in the middle close behind the boat,
// both broken up by the sea's foam texture and fading with age. Per vertex: COLOR.r =
// age (0 new .. 1 gone), COLOR.g = how fast the boat went there (0..1);
// UV.x = across (0..1), UV.y = metres along.
// Alpha blended over the sea (render_priority 1 draws it after the water),
// lit like the sea so it greys under clouds and darkens at night.

render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;

varying float v_age;
varying float v_speed;
varying vec2 v_world;

void vertex() {
	v_age = COLOR.r;
	v_speed = COLOR.g;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Seconds the ribbon lives (BoatEffects.WAKE_LIFE): `age` is a fraction of it.
const float LIFE = 7.0;

void fragment() {
	float edge = min(UV.x, 1.0 - UV.x);
	float age = clamp(v_age, 0.0, 1.0);
	float fade = 1.0 - age;
	float secs = age * LIFE;
	// The sea's own foam texture (lace, bubbles, soft blobs), as on the shore.
	vec3 f = texture(foam_tex, v_world / 5.5 + TIME * vec2(0.012, -0.008)).rgb;
	vec3 g = texture(foam_tex, v_world / 2.1 + vec2(0.37, 0.61) - TIME * vec2(0.006, 0.0)).rgb;
	float lace = f.r * 0.6 + g.r * 0.4;
	// How much foam there is: arms just inside the edges (thinner as the V
	// opens, soft on both sides), white water churned up right behind the
	// boat (gone in a second or two), a fainter trail down the middle.
	float arm_w = mix(0.16, 0.07, age);
	float arms = smoothstep(0.005, 0.04, edge) * (1.0 - smoothstep(arm_w * 0.5, arm_w, edge)) * pow(fade, 1.3);
	float mid = 1.0 - smoothstep(0.1, 0.48, abs(UV.x - 0.5));
	float churn = mid * exp(-secs / 0.5);
	float trail = mid * 0.17 * fade * fade * fade;
	float body = clamp(max(arms, max(churn, trail)), 0.0, 1.0);
	float pattern = smoothstep(0.38, 0.72, lace * 0.75 + f.g * 0.45 + (f.b - 0.5) * 0.5 + body * 0.45);
	float a = body * pattern * smoothstep(0.05, 0.35, v_speed);
	ALBEDO = vec3(0.95, 0.96, 0.97);
	ROUGHNESS = 0.8;
	ALPHA = clamp(a * 1.15, 0.0, 0.92);
}
