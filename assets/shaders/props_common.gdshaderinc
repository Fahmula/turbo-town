// Helpers and tables for street_props.gdshader (ART_BIBLE.md §17).
//
// The material class of a vertex rides in COLOR.a: class30 = round(a * 30).
// Even numbers are the original classes (class15 * 2, so a mesh that stores
// k / 15 keeps working), odd numbers are the extra classes added for the
// realism pass (a mesh stores (2k + 1) / 30 for those).
//
//  class30  name                 texture layer   notes
//     0     painted metal / paint     0 paint     colour from the vertex, tint instance uniform
//     1     corrugated steel A        8 corrug_a  shipping containers
//     2     bare / galvanised metal   1 galv      metallic 1
//     3     corrugated steel B        9 corrug_b  hangar cladding
//     4     concrete / stone          2 concrete
//     5     tread plate (painted)    10 plate
//     6     plastic                   3 plastic
//     7     weathered timber         11 timber
//     8     rubber, black trim        4 rubber
//     9     rusty steel              12 rust      metallic from the scan
//    10     glass, lens (dark)         -
//    11     worn paint               13 worn      chips and scuffs
//    12     warm lamp (glows)          -
//    13     brushed steel            14 brushed   metallic 1
//    14     cool LED lamp (glows)      -
//    15     roof slate               15 slate
//    16/18/20  signal lens red / amber / green (instance uniform `signal`)
//    17     polished aluminium / chrome (no texture)
//    19     glossy plastic / lacquer    3 plastic   roughness x 0.45 (pins, buoys)
//    21     steel deck panels           0 paint     bolted plates (loop, bowl)
//    22     sign face (glossy sheeting)
//    23     retroreflective sheeting (signs, reflectors)
//    24     fabric (awnings)          5 fabric
//    25     decking planks           11 timber    0.152 m boards along UV.x, grooves, tint per board
//    26     wood                      6 wood
//    28     always-on glow (screens, beacons)
//    30     deck panels (ramps)       7 deck     plywood sheets with seams and screws

const int PROPS_LAYER[31] = int[31](
	0, 8, 1, 9, 2, 10, 3, 11, 4, 12,
	-1, 13, -1, 14, -1, 15, -1, -1, -1, 3,
	-1, 0, -1, -1, 5, 11, 6, -1, -1, -1,
	7);

// Tile size in metres per texture layer.
const float PROPS_TILE[16] = float[16](
	1.0, 1.0, 2.0, 0.7, 0.5, 0.35, 1.0, 1.0,
	1.94, 2.0, 0.6, 1.5, 1.0, 1.0, 0.8, 1.2);

// How much of the scan's albedo variation shows (0 = none, 1 = as scanned).
const float PROPS_ALBEDO_K[16] = float[16](
	0.6, 0.8, 1.0, 0.7, 0.6, 0.9, 1.0, 0.45,
	0.8, 0.8, 0.7, 1.0, 1.0, 0.9, 0.6, 1.0);

// Normal map strength per layer.
const float PROPS_NORMAL_K[16] = float[16](
	0.55, 0.7, 0.9, 0.5, 0.9, 1.2, 0.8, 0.7,
	1.0, 1.0, 1.0, 1.0, 0.9, 0.7, 0.4, 1.2);

// Roughness when there is no texture (Low quality, or classes without a layer).
const float PROPS_ROUGH[31] = float[31](
	0.5, 0.5, 0.42, 0.46, 0.88, 0.45, 0.55, 0.88, 0.85, 0.65,
	0.06, 0.55, 0.2, 0.34, 0.2, 0.72, 0.12, 0.2, 0.12, 0.3,
	0.12, 0.3, 0.3, 0.3, 0.95, 0.85, 0.8, 0.3, 0.3, 0.3,
	0.62);

// Decodes a tangent-space normal stored in RG (OpenGL, Y+), rebuilding Z.
vec3 props_decode_normal(vec2 rg, float strength) {
	vec2 xy = (rg * 2.0 - 1.0) * strength;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Perturbs the view-space normal `n` with the tangent-space normal `nt`
// without needing tangents on the mesh: the tangent frame comes from the
// screen-space derivatives of the view-space position `p` and the UV
// (Schüler, "Followup: Normal Mapping Without Precomputed Tangents").
// Godot / glTF normal maps have +Y toward decreasing V, hence the minus.
vec3 props_perturb(vec3 n, vec3 p, vec2 uv, vec3 nt) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float inv = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-14));
	return normalize(t * (inv * nt.x) - b * (inv * nt.y) + n * nt.z);
}
