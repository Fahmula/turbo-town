// Vehicle glass (ART_BIBLE.md §13), shared by vehicle_glass.gdshader
// (see-through, alpha-blended) and vehicle_glass_opaque.gdshader (the bus,
// which has no interior).
//
// * Tinted glass whose opacity rises toward grazing angles (Fresnel), so
//   side windows seen edge-on mirror the street and the cabin shows through
//   when you look straight in.
// * Cracks: `crack` (0..1) draws a spiderweb centred on `crack_center`
//   (object space, set by VehicleDamage to the glass nearest the hit):
//   radial cracks with jittered angles and lengths, broken concentric rings,
//   a milky crushed spot in the middle and a light frosting around it. Lines
//   are antialiased with fwidth.

#include "res://assets/shaders/vehicle/vehicle_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.118, 0.157, 0.2, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.62;
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform vec3 crack_center = vec3(0.0);
// Size of the web (m).
uniform float crack_radius = 0.75;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

// 0..1 coverage of crack lines and frosting at this point.
vec2 crack_web(vec3 p, vec3 nrm) {
	vec3 rel = p - crack_center;
	vec3 n = normalize(nrm);
	vec3 t = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(n, t);
	vec2 q = vec2(dot(rel, t), dot(rel, b));
	float r = length(q) + 1e-4;
	if (r > crack_radius * 1.15) {
		return vec2(0.0);
	}
	float a = atan(q.y, q.x) / TAU + 0.5;
	// Radial cracks.
	const float SPOKES = 13.0;
	float sector = a * SPOKES;
	float id = floor(sector);
	float h = vh_hash2(vec2(id, 3.7));
	float along = fract(sector) - (0.25 + 0.5 * h);
	float wiggle = (vh_noise(vec3(r * 30.0, id, 1.0)) - 0.5) * 0.18;
	float d_spoke = abs(along + wiggle) * TAU * r / SPOKES;
	float reach = crack_radius * (0.45 + 0.55 * vh_hash2(vec2(id, 9.1)));
	float spoke = (1.0 - smoothstep(0.0, fwidth(d_spoke) * 1.5 + 0.0015, d_spoke)) * (1.0 - smoothstep(reach * 0.8, reach, r));
	// Broken rings between the spokes.
	float rr = r * (1.0 + 0.12 * (vh_noise(vec3(a * 40.0, 2.0, 0.0)) - 0.5));
	float ring_i = floor(sqrt(rr / 0.012));
	float ring_r = ring_i * ring_i * 0.012;
	float d_ring = abs(rr - ring_r);
	float keep = step(0.45, vh_hash2(vec2(id, ring_i))) * step(0.06, ring_r) * (1.0 - smoothstep(crack_radius * 0.5, crack_radius * 0.75, r));
	float ring = (1.0 - smoothstep(0.0, fwidth(d_ring) * 1.5 + 0.0012, d_ring)) * keep;
	// Crushed centre and frosting.
	float centre = 1.0 - smoothstep(0.025, 0.07, r);
	float frost = (1.0 - smoothstep(0.05, crack_radius * 0.6, r)) * 0.35;
	return vec2(clamp(max(max(spoke, ring), centre), 0.0, 1.0), frost);
}

void glass_fragment(inout vec3 albedo, inout float alpha, inout float rough, float ndv) {
	float fresnel = pow(1.0 - ndv, 4.0);
	albedo = tint.rgb;
	alpha = mix(base_alpha, 0.96, fresnel);
	rough = 0.04;
	if (crack > 0.0) {
		vec2 web = crack_web(obj_pos, obj_normal) * crack;
		albedo = mix(albedo, vec3(0.72, 0.75, 0.78), max(web.x, web.y * 0.6));
		alpha = mix(alpha, 0.95, max(web.x, web.y));
		rough = mix(rough, 0.6, max(web.x, web.y));
	}
}
