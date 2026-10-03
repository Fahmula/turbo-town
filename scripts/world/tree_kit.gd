@tool
class_name TreeKit
extends RefCounted
## Trees, shrubs and hedges (ART_BIBLE.md §18, realism branch), built in code
## once and shared. Real leaf scans (ambientCG, composed into branch-cluster
## atlases by tools/textures/fetch_foliage.py) on cards around a skeleton of
## tapered, bark-textured limbs; every card vertex carries a soft "canopy"
## normal and an ambient-occlusion value (dark deep in the crown), so the crown
## shades like one mass while the leaves stay crisp. See foliage.gdshader.
##
## Species and their variants (each variant is its own mesh and material):
##   broadleaf  broadleaf_a (beech-like, 9 m), broadleaf_b (oak, broad, 8.6 m),
##              broadleaf_c (lilac / linden-like, tall, 10.5 m)
##   conifer    conifer_a (fir, broad cone, 12 m), conifer_b (slender, 15 m)
##   palm       palm (9.5 m)
##   shrub      shrub (a 1.3 m bush), hedge (a 2 m clipped hedge segment)
## Each mesh has three levels of detail:
##   LOD 0 near (full skeleton and ~330 cards, ~1.5k tris), LOD 1 mid (a few
##   big cards, ~250 tris, one per species), LOD 2 far (a solid canopy blob,
##   ~60 tris, one per species). TreeLod picks the level per cell from the
##   camera distance.

const CARD := 1.0
const BLOB := 0.5
const BARK := 0.0
## Flips the binormal of the bark normal map if its relief looks inverted.
const BARK_TANGENT_W := -1.0

## Per species: variants, LOD switch distances (m) and when to stop drawing.
const SPECIES := {
	"broadleaf": {"variants": ["broadleaf_a", "broadleaf_b", "broadleaf_c"], "r0": 55.0, "r1": 190.0, "cull": 3000.0,
		"trunk_r": 0.27, "trunk_h": 4.0},
	"conifer": {"variants": ["conifer_a", "conifer_b", "conifer_c"], "r0": 45.0, "r1": 190.0, "cull": 3000.0,
		"trunk_r": 0.25, "trunk_h": 5.0},
	"palm": {"variants": ["palm"], "r0": 50.0, "r1": 170.0, "cull": 3000.0, "trunk_r": 0.2, "trunk_h": 5.0},
	"shrub": {"variants": ["shrub"], "r0": 40.0, "r1": 110.0, "cull": 160.0, "trunk_r": 0.0, "trunk_h": 0.0},
	"hedge": {"variants": ["hedge"], "r0": 45.0, "r1": 120.0, "cull": 170.0, "trunk_r": 0.0, "trunk_h": 0.0},
}

## Per variant: the build recipe.
const VARIANTS := {
	"broadleaf_a": {"seed": 11, "height": 9.2, "trunk_h": 2.5, "radius": 3.9, "trunk_r": 0.28, "limbs": 4,
		"cards": 300, "size": Vector2(1.5, 2.15), "mat": "foliage_broadleaf", "wind_h": 9.0},
	"broadleaf_b": {"seed": 23, "height": 8.6, "trunk_h": 2.1, "radius": 4.8, "trunk_r": 0.36, "limbs": 5,
		"cards": 300, "size": Vector2(1.6, 2.25), "mat": "foliage_broadleaf_b", "wind_h": 9.0},
	"broadleaf_c": {"seed": 37, "height": 10.5, "trunk_h": 3.1, "radius": 3.0, "trunk_r": 0.25, "limbs": 4,
		"cards": 270, "size": Vector2(1.45, 2.05), "mat": "foliage_broadleaf_c", "wind_h": 10.0},
	"conifer_a": {"seed": 7, "height": 12.0, "base_h": 1.6, "radius": 2.7, "step": 0.5, "n_low": 7.0, "n_high": 4.0,
		"elev_low": -10.0, "elev_high": 26.0, "taper": 0.85, "mat": "foliage_conifer", "wind_h": 13.0},
	"conifer_b": {"seed": 19, "height": 15.0, "base_h": 2.2, "radius": 1.85, "step": 0.46, "n_low": 6.0, "n_high": 4.0,
		"elev_low": -4.0, "elev_high": 32.0, "taper": 0.7, "mat": "foliage_conifer", "wind_h": 15.0},
	"conifer_c": {"seed": 29, "height": 15.5, "base_h": 4.2, "radius": 2.5, "step": 0.55, "n_low": 5.0, "n_high": 3.0,
		"elev_low": 4.0, "elev_high": 40.0, "taper": 0.6, "mat": "foliage_conifer", "wind_h": 17.0},
	"palm": {"seed": 5, "height": 9.5, "lean": 1.4, "fronds": 16, "mat": "foliage_palm", "wind_h": 10.0},
	"shrub": {"seed": 3, "radius": 0.75, "height": 1.15, "cards": 40, "size": Vector2(0.55, 0.85), "mat": "foliage_shrub", "wind_h": 2.0},
	"hedge": {"seed": 9, "length": 2.0, "width": 0.85, "height": 1.1, "cards": 64, "size": Vector2(0.5, 0.75), "mat": "foliage_shrub", "wind_h": 2.0},
}

static var _cache := {}


## The species a variant belongs to.
static func species_of(variant: String) -> String:
	for s: String in SPECIES:
		if (SPECIES[s]["variants"] as Array).has(variant):
			return s
	return ""


static func material(variant: String) -> Material:
	var v: Dictionary = VARIANTS.get(variant, VARIANTS["broadleaf_a"])
	return load("res://assets/materials/env/%s.tres" % v["mat"])


## Mesh of a variant at a level of detail 0 (near). Levels 1 (mid) and 2 (far)
## are per species (its first variant): pass the species name or any variant.
static func mesh(kind: String, lod: int) -> ArrayMesh:
	var variant := kind
	if lod >= 1:
		# Mid and far detail: one mesh per species (its first variant), keyed by the species.
		var sp := kind if SPECIES.has(kind) else species_of(kind)
		variant = SPECIES[sp]["variants"][0]
		kind = sp
	var key := "%s@%d" % [kind, lod]
	if _cache.has(key):
		return _cache[key]
	var tb := TB.new()
	var v: Dictionary = VARIANTS[variant]
	match species_of(variant):
		"broadleaf":
			_broadleaf(tb, v, lod)
		"conifer":
			_conifer(tb, v, lod)
		"palm":
			_palm(tb, v, lod)
		"shrub":
			_shrub(tb, v, lod)
		"hedge":
			_hedge(tb, v, lod)
	var m := tb.build(material(variant))
	_cache[key] = m
	return m


# --------------------------------------------------------------- builder ---

class TB extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, n: Vector3, c: Color, uv: Vector2, uv2: Vector2, tan := Vector3.RIGHT) -> int:
		verts.append(p)
		norms.append(n)
		cols.append(c)
		uvs.append(uv)
		uv2s.append(uv2)
		tans.append(tan.x)
		tans.append(tan.y)
		tans.append(tan.z)
		tans.append(TreeKit.BARK_TANGENT_W)
		return verts.size() - 1

	func quad(a: int, b: int, c: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)
		idx.append(a)
		idx.append(c)
		idx.append(d)

	## A quad whose front face (clockwise) looks along `n`.
	func quad_n(a: int, b: int, c: int, d: int, n: Vector3) -> void:
		var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if g.dot(n) > 0.0:
			quad(a, d, c, b)
		else:
			quad(a, b, c, d)

	func tri(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	func triangle_count() -> int:
		return idx.size() / 3

	func build(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tans
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		return mesh

	## Tapered tube along `pts` (radii per point). UV u goes `urep` times round
	## (whole number), v is `vscale` per metre along. AO and wind flex run
	## linearly along the tube.
	func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, urep: int, vscale: float,
			ao0: float, ao1: float, flex0 := 0.0, flex1 := 0.0) -> void:
		var n := pts.size()
		var fr := TreeKit._frames(pts)
		var base := verts.size()
		var v := 0.0
		for i in n:
			if i > 0:
				v += pts[i].distance_to(pts[i - 1]) * vscale
			var f := float(i) / maxf(n - 1, 1)
			var ao := lerpf(ao0, ao1, f)
			var fl := lerpf(flex0, flex1, f)
			var nn: Vector3 = fr[1][i]
			var bb: Vector3 = (fr[0][i] as Vector3).cross(nn)
			for s in sides + 1:
				var a := TAU * s / sides
				var d := nn * cos(a) + bb * sin(a)
				var tg := -nn * sin(a) + bb * cos(a)
				vert(pts[i] + d * radii[i], d, Color(ao, 0.5, 0.5, TreeKit.BARK), Vector2(urep * float(s) / sides, v), Vector2(0.0, fl), tg)
		var stride := sides + 1
		for i in n - 1:
			for s in sides:
				var a0 := base + i * stride + s
				quad(a0, a0 + stride, a0 + stride + 1, a0 + 1)

	## A leaf card standing on `base`, `w` wide along `side` and `h` tall along
	## `up`, showing atlas tile `tile` of a `grid` atlas. Vertex normals blend
	## the card's own (`n_card`) with the crown's soft normal by `blend`.
	func card(base: Vector3, up: Vector3, side: Vector3, w: float, h: float, tile: Vector2i, grid: Vector2i,
			crown: Crown, n_card: Vector3, blend: float, wob: float, phase: float) -> void:
		var q := [base - side * (w * 0.5), base + side * (w * 0.5), base + side * (w * 0.5) + up * h, base - side * (w * 0.5) + up * h]
		var inset := 0.0015
		var u0 := float(tile.x) / grid.x + inset
		var u1 := float(tile.x + 1) / grid.x - inset
		var v0 := float(tile.y) / grid.y + inset
		var v1 := float(tile.y + 1) / grid.y - inset
		var uv := [Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]
		var ids: Array[int] = []
		for i in 4:
			var p: Vector3 = q[i]
			var nrm := n_card.lerp(crown.normal(p), blend).normalized()
			ids.append(vert(p, nrm, Color(crown.ao(p), 0.5 + wob, crown.thin(p), TreeKit.CARD), uv[i],
				Vector2(phase, clampf(0.25 + crown.depth(p) * 0.75, 0.0, 1.0))))
		quad(ids[0], ids[1], ids[2], ids[3])

	## A solid lumpy ellipsoid (the canopy blob) with soft normals from its centre.
	func blob(c: Vector3, r: Vector3, rings: int, segs: int, crown: Crown, rng: RandomNumberGenerator, lump := 0.12) -> void:
		var base := verts.size()
		var phase := rng.randf() * TAU
		for ri in rings + 1:
			var phi := PI * ri / rings
			for si in segs + 1:
				var th := TAU * si / segs
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var k := 1.0 + lump * sin(th * 3.0 + phase + phi * 2.0) * sin(phi * 2.0 + phase)
				var p := c + d * r * k
				vert(p, (d + Vector3.UP * 0.12).normalized(), Color(crown.ao(p), 0.5, 0.5, TreeKit.BLOB), Vector2.ZERO, Vector2(0.0, 0.3))
		for ri in rings:
			for si in segs:
				var a0 := base + ri * (segs + 1) + si
				quad(a0, a0 + segs + 1, a0 + segs + 2, a0 + 1)


## The crown as an ellipsoid: soft normals, AO and leaf thinness at a point.
class Crown extends RefCounted:
	var c: Vector3
	var r: Vector3

	func _init(center: Vector3, radii: Vector3) -> void:
		c = center
		r = radii

	func rel(p: Vector3) -> Vector3:
		return (p - c) / r

	func depth(p: Vector3) -> float:
		return clampf(rel(p).length(), 0.0, 1.3)

	func normal(p: Vector3) -> Vector3:
		var d := rel(p)
		return (d.normalized() + Vector3.UP * 0.15).normalized() if d.length_squared() > 1e-6 else Vector3.UP

	func ao(p: Vector3) -> float:
		var d := rel(p)
		var depth := clampf(d.length(), 0.0, 1.1)
		var a := lerpf(0.3, 1.0, smoothstep(0.1, 1.0, depth))
		return a * lerpf(0.7, 1.0, smoothstep(-1.0, 0.5, d.y))

	func thin(p: Vector3) -> float:
		return smoothstep(0.35, 1.0, depth(p))


## Parallel-transport frames along a polyline: [tangents, normals].
static func _frames(pts: PackedVector3Array) -> Array:
	var n := pts.size()
	var ts: Array[Vector3] = []
	var ns: Array[Vector3] = []
	for i in n:
		ts.append((pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized())
	var ref := Vector3.RIGHT if absf(ts[0].x) < 0.9 else Vector3.FORWARD
	ns.append(ts[0].cross(ref).normalized())
	for i in range(1, n):
		var prev := ns[i - 1]
		var nn := prev - ts[i] * prev.dot(ts[i])
		ns.append(nn.normalized() if nn.length_squared() > 1e-8 else prev)
	return [ts, ns]


static func _bezier(a: Vector3, b: Vector3, c: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


static func _radii(n: int, r0: float, r1: float, power := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(lerpf(r0, r1, pow(float(i) / maxf(n - 1, 1), power)))
	return out


static func _rand_unit(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()


## Position on a polyline at height y (the polyline rises monotonically).
static func _at_height(pts: PackedVector3Array, y: float) -> Vector3:
	for i in range(1, pts.size()):
		if pts[i].y >= y:
			var t := inverse_lerp(pts[i - 1].y, pts[i].y, y)
			return pts[i - 1].lerp(pts[i], clampf(t, 0.0, 1.0))
	return pts[pts.size() - 1]


# --------------------------------------------------------------- broadleaf ---

static func _broadleaf(tb: TB, v: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"] + lod * 101
	var tr_h: float = v["trunk_h"]
	var R: float = v["radius"]
	var crown_h: float = float(v["height"]) - tr_h + 0.8
	var c := Vector3(0.0, tr_h - 0.4 + crown_h * 0.5, 0.0)
	var crown := Crown.new(c, Vector3(R, crown_h * 0.5, R))
	var grid := Vector2i(4, 4)
	var detail := lod == 0
	if lod >= 2:
		_broadleaf_far(tb, v, crown, rng)
		return
	# Trunk: a gentle S, flared at the foot, up into the crown.
	var y_top := c.y + crown.r.y * 0.45
	var n_t := 9 if detail else 4
	var trunk := PackedVector3Array()
	var ph := rng.randf() * TAU
	for i in n_t:
		var t := float(i) / (n_t - 1)
		var y := y_top * t
		trunk.append(Vector3(0.18 * sin(y * 0.8 + ph) * t, y, 0.18 * cos(y * 0.7 + ph) * t))
	var rb: float = v["trunk_r"]
	var rad := PackedFloat32Array()
	for i in n_t:
		var t := float(i) / (n_t - 1)
		rad.append(lerpf(rb, 0.07, pow(t, 0.8)) + 0.1 * exp(-trunk[i].y * 2.5))
	tb.tube(trunk, rad, 10 if detail else 5, 2, 0.8, 0.8, 0.6, 0.0, 0.1)
	# Limbs arching out into the crown; branches off them; anchors for cards.
	var anchors: Array[Vector3] = []
	var nl: int = v["limbs"]
	var a0 := rng.randf() * TAU
	for k in nl:
		var az := a0 + TAU * k / nl + rng.randf_range(-0.35, 0.35)
		var ys := tr_h - 0.3 + rng.randf() * crown_h * 0.3
		var s := _at_height(trunk, ys)
		var reach := R * rng.randf_range(0.8, 1.0)
		var e := c + Vector3(cos(az) * reach, rng.randf_range(-0.7, 0.75) * crown.r.y, sin(az) * reach)
		var ctrl := Vector3(lerpf(s.x, e.x, 0.3), maxf(s.y, e.y) + 0.7, lerpf(s.z, e.z, 0.3))
		var seg := 7 if detail else 3
		var limb := _bezier(s, ctrl, e, seg)
		var lr0 := rb * rng.randf_range(0.5, 0.62)
		tb.tube(limb, _radii(limb.size(), lr0, 0.035, 0.9), 6 if detail else 3, 1, 1.0, 0.6, 0.45, 0.1, 0.5)
		anchors.append(e)
		anchors.append(limb[seg - 1])
		if not detail:
			anchors.append(limb[1])
			continue
		anchors.append(limb[seg - 4])
		var nb := rng.randi_range(3, 4)
		for b in nb:
			var tt := 0.3 + 0.6 * float(b + 1) / (nb + 1) + rng.randf_range(-0.05, 0.05)
			var idx := clampi(int(tt * seg), 1, seg - 1)
			var b0 := limb[idx]
			var pd := (limb[mini(idx + 1, seg)] - limb[idx - 1]).normalized()
			var cd := (pd * 0.45 + _rand_unit(rng) * 0.75 + Vector3.UP * 0.2).normalized()
			var lb := R * rng.randf_range(0.3, 0.5) * (1.0 - tt * 0.35)
			var bp := PackedVector3Array()
			for j in 5:
				var f := float(j) / 4.0
				bp.append(b0 + cd * (lb * f) + Vector3.DOWN * (0.3 * lb * f * f) + Vector3.UP * (0.2 * lb * f))
			tb.tube(bp, _radii(5, lr0 * lerpf(0.6, 0.35, tt), 0.02, 0.9), 4, 1, 1.2, 0.5, 0.4, 0.3, 0.8)
			anchors.append(bp[4])
			anchors.append(bp[2])
			# virtual twigs off the branch end carry a cluster each
			for j in 3:
				var td := (cd + _rand_unit(rng) * 0.8).normalized()
				anchors.append(bp[4] + td * rng.randf_range(0.5, 0.9))
				anchors.append(bp[3] + td * rng.randf_range(0.3, 0.6))
	# A dark core so the crown's heart isn't see-through (only where cards are few).
	if not detail:
		tb.blob(c + Vector3(0, -0.1, 0), crown.r * 0.6, 3, 6, crown, rng, 0.08)
	# Cards: clusters at the anchors, plus fill on the crown's shell.
	var total: int = int(v["cards"]) if detail else int(float(v["cards"]) * 0.2)
	var size: Vector2 = v["size"] if detail else (v["size"] as Vector2) * 2.1
	var per := maxi(1, int(ceil(float(total) * 0.25 / anchors.size())))
	var placed := 0
	for a in anchors:
		for j in per:
			_leaf_card(tb, rng, a + _rand_unit(rng) * 0.35, crown, size, grid, 1.0)
			placed += 1
	# the rest spread over the crown's shell (uniform in direction, a little more
	# on top than underneath), which gives the round, full crown of a planted tree
	while placed < total:
		var d := _rand_unit(rng)
		if d.y < -0.2:
			d.y *= 0.45
			d = d.normalized()
		var p := crown.c + d * crown.r * rng.randf_range(0.62, 1.0)
		_leaf_card(tb, rng, p, crown, size, grid, 1.0)
		placed += 1


## One cluster card at `p`: its tile "up" points outward (and up), its face
## looks outward-ish.
static func _leaf_card(tb: TB, rng: RandomNumberGenerator, p: Vector3, crown: Crown, size: Vector2, grid: Vector2i,
		blend_scale: float) -> void:
	# Half of the cards lie on the crown's surface like shingles, seen face-on
	# from outside (the face looks outward, the tile's "up" runs along the
	# surface, mostly upwards, tipped out a little); the other half stand
	# radially (their twig grows outward), which fills the volume when seen from
	# the side.
	var nc: Vector3
	var up: Vector3
	var out := crown.normal(p)
	if rng.randf() < 0.5:
		nc = (out + _rand_unit(rng) * 0.5).normalized()
		var tang := Vector3.UP - nc * nc.dot(Vector3.UP)
		if tang.length() < 0.25:
			tang = nc.cross(_rand_unit(rng))
		tang = tang.normalized().rotated(nc, rng.randf_range(-1.1, 1.1))
		up = (tang + nc * 0.3).normalized()
	else:
		up = (out * 0.75 + Vector3.UP * 0.35 + _rand_unit(rng) * 0.45).normalized()
		nc = _rand_unit(rng)
		nc = (nc - up * nc.dot(up)).normalized()
		if nc.dot(out) < -0.1:
			nc = -nc
	var side := up.cross(nc).normalized()
	var w := lerpf(size.x, size.y, rng.randf())
	var tile := Vector2i(rng.randi() % grid.x, rng.randi() % grid.y)
	tb.card(p - up * (w * 0.4), up, side, w, w, tile, grid, crown, nc, 0.6 * blend_scale, rng.randf_range(-0.5, 0.5), rng.randf())


static func _broadleaf_far(tb: TB, v: Dictionary, crown: Crown, rng: RandomNumberGenerator) -> void:
	var tr_h: float = v["trunk_h"]
	var trunk := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, tr_h + 1.0, 0)])
	tb.tube(trunk, PackedFloat32Array([0.3, 0.12]), 4, 1, 1.0, 0.8, 0.6)
	tb.blob(crown.c, crown.r, 4, 8, crown, rng, 0.14)


# ------------------------------------------------------------------ conifer ---

static func _conifer(tb: TB, v: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"] + lod * 101
	var H: float = v["height"]
	var Rm: float = v["radius"]
	var base_h: float = v["base_h"]
	if lod >= 2:
		_conifer_far(tb, v)
		return
	var detail := lod == 0
	# Trunk with a slight bend.
	var n_t := 8 if detail else 3
	var trunk := PackedVector3Array()
	var ph := rng.randf() * TAU
	for i in n_t:
		var t := float(i) / (n_t - 1)
		trunk.append(Vector3(0.12 * sin(t * 4.0 + ph) * t, H * 0.985 * t, 0.12 * cos(t * 3.0 + ph) * t))
	var rad := PackedFloat32Array()
	for i in n_t:
		var t := float(i) / (n_t - 1)
		rad.append(lerpf(0.27, 0.025, pow(t, 0.7)) + 0.09 * exp(-trunk[i].y * 2.0))
	tb.tube(trunk, rad, 8 if detail else 4, 2, 0.8, 0.8, 0.7, 0.0, 0.05)
	# A dark cone inside, so the tree reads solid.
	if detail:
		_cone_core(tb, base_h + 0.4, H - 0.8, Rm * 0.2, 9, 6, 0.35, 0.7)
	else:
		# mid detail: the cone carries the silhouette, a few big sprays break it up
		_cone_core(tb, base_h * 0.6, H - 0.3, Rm * 0.62, 6, 3, 0.6, 0.95)
	var grid := Vector2i(2, 4)
	var y := base_h
	var whorl := 0
	while y < H - 0.7:
		var t := (y - base_h) / (H - base_h)
		var n := roundi(lerpf(float(v["n_low"]), float(v["n_high"]), t))
		var az0 := rng.randf() * TAU
		var skip := not detail and whorl % 3 != 0
		if not skip:
			for k in n:
				var az := az0 + TAU * k / n + rng.randf_range(-0.25, 0.25)
				var L := Rm * pow(1.0 - t, float(v["taper"])) * rng.randf_range(0.85, 1.12) + 0.45
				if not detail:
					L *= 1.1
				var elev := deg_to_rad(lerpf(float(v["elev_low"]), float(v["elev_high"]), t) + rng.randf_range(-6.0, 6.0))
				_spray(tb, rng, _trunk_at(trunk, y), az, L, elev, t, tile_of(rng), grid, detail, H, Rm)
		y += lerpf(float(v["step"]), float(v["step"]) * 0.65, t)
		whorl += 1
	# The top: a few upright sprays.
	for k in 4:
		var az := TAU * k / 4.0 + rng.randf() * 0.5
		_spray(tb, rng, _trunk_at(trunk, H - 1.3), az, 0.9, deg_to_rad(68.0), 1.0, tile_of(rng), grid, detail, H, Rm)


static func tile_of(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi() % 2, rng.randi() % 4)


static func _trunk_at(trunk: PackedVector3Array, y: float) -> Vector3:
	return _at_height(trunk, y)


## A conifer branch: a strip along the branch with the stem along its ridge
## and two wings hanging steeply either side (a tent), so it shows area from
## the side as well as from above. The tile's stem runs base to tip.
static func _spray(tb: TB, rng: RandomNumberGenerator, root: Vector3, az: float, L: float, elev: float, t: float,
		tile: Vector2i, grid: Vector2i, detail: bool, H: float, Rm: float) -> void:
	var dirh := Vector3(cos(az), 0.0, sin(az))
	var across := Vector3(-dirh.z, 0.0, dirh.x)
	var segs := 2 if detail else 1
	var W := L * (0.62 if detail else 0.95)
	var roll := deg_to_rad(rng.randf_range(42.0, 58.0))
	var droop := L * (0.2 + 0.1 * (1.0 - t)) if elev < 0.3 else L * 0.06
	var ids: Array[int] = []
	var u0 := float(tile.x) / grid.x + 0.002
	var u1 := float(tile.x + 1) / grid.x - 0.002
	var vt := float(tile.y) / grid.y + 0.002
	var vb := float(tile.y + 1) / grid.y - 0.002
	var vm := (vt + vb) * 0.5
	var phase := rng.randf()
	for i in segs + 1:
		var f := float(i) / segs
		var p := root + dirh * (L * f * cos(elev)) + Vector3.UP * (L * f * sin(elev) - droop * f * f)
		var wing := W * 0.5 * lerpf(0.6, 1.0, sin(f * PI * 0.9 + 0.2))
		for col in 3:
			var q := p
			var vv := vm
			var side := 0.0
			if col == 0:
				side = -1.0
				vv = vt
			elif col == 2:
				side = 1.0
				vv = vb
			q = p + across * (side * wing * cos(roll)) - Vector3.UP * (absf(side) * wing * sin(roll))
			var out := Vector3(q.x, 0.0, q.z)
			var rn := out.normalized() if out.length() > 0.05 else dirh
			# lighting normal: up and outward, so the crown's top is lit and its underside shaded
			var nrm := (Vector3.UP * 0.75 + rn * 0.45 + across * (side * 0.3)).normalized()
			var radial := clampf(out.length() / maxf(Rm, 0.1), 0.0, 1.0)
			var ao := lerpf(0.55, 1.0, smoothstep(0.0, 0.9, radial)) * lerpf(0.8, 1.0, clampf(q.y / (H * 0.8), 0.0, 1.0))
			ids.append(tb.vert(q, nrm, Color(ao, 0.5, clampf(0.25 + f * 0.5, 0.0, 1.0), TreeKit.CARD),
				Vector2(lerpf(u0, u1, f), vv), Vector2(phase, 0.3 + 0.7 * f)))
	for i in segs:
		for col in 2:
			var a := ids[i * 3 + col]
			var b := ids[i * 3 + col + 1]
			var c2 := ids[(i + 1) * 3 + col + 1]
			var d := ids[(i + 1) * 3 + col]
			tb.quad_n(a, b, c2, d, Vector3.UP + across * (float(col) * 2.0 - 1.0) * 0.6)


## A dark cone of foliage inside the tree.
static func _cone_core(tb: TB, y0: float, y1: float, r0: float, sides: int, rings: int, shade0: float, shade1: float) -> void:
	var base := tb.verts.size()
	for ri in rings + 1:
		var t := float(ri) / rings
		var y := lerpf(y0, y1, t)
		var r := r0 * pow(1.0 - t, 1.1) + 0.02
		for si in sides + 1:
			var a := TAU * si / sides
			var d := Vector3(cos(a), 0.0, sin(a))
			tb.vert(Vector3(d.x * r, y, d.z * r), (d + Vector3.UP * 0.5).normalized(), Color(lerpf(shade0, shade1, t), 0.5, 0.5, TreeKit.BLOB),
				Vector2.ZERO, Vector2(0.0, 0.2))
	for ri in rings:
		for si in sides:
			var a0 := base + ri * (sides + 1) + si
			tb.quad(a0, a0 + sides + 1, a0 + sides + 2, a0 + 1)


static func _conifer_far(tb: TB, v: Dictionary) -> void:
	var H: float = v["height"]
	var Rm: float = v["radius"]
	var base_h: float = v["base_h"]
	# Two stacked, overlapping cones, darker below.
	for k in 2:
		var y0 := lerpf(base_h * 0.8, H * 0.5, float(k) / 2.0)
		var y1 := y0 + (H - y0) * (0.62 + 0.25 * k)
		var r := Rm * lerpf(1.0, 0.6, float(k) / 2.0) * 0.95
		var rings := 2
		var sides := 6
		var base := tb.verts.size()
		for ri in rings + 1:
			var t := float(ri) / rings
			var y := lerpf(y0, y1, t)
			var rr := r * pow(1.0 - t, 0.9) + 0.01
			for si in sides + 1:
				var a := TAU * si / sides + k * 0.5
				var d := Vector3(cos(a), 0.0, sin(a))
				tb.vert(Vector3(d.x * rr, y, d.z * rr), (d + Vector3.UP * 0.55).normalized(),
					Color(lerpf(0.4, 1.0, t * 0.7 + float(k) / 2.0 * 0.4), 0.5, 0.5, TreeKit.BLOB), Vector2.ZERO, Vector2(0.0, 0.2))
		for ri in rings:
			for si in sides:
				var a0 := base + ri * (sides + 1) + si
				tb.quad(a0, a0 + sides + 1, a0 + sides + 2, a0 + 1)


# --------------------------------------------------------------------- palm ---

static func _palm(tb: TB, v: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"] + lod * 101
	var height: float = v["height"]
	var lean: float = v["lean"]
	var n_t := 12 if lod == 0 else (5 if lod == 1 else 3)
	var spine := PackedVector3Array()
	for k in n_t:
		var t := float(k) / (n_t - 1)
		spine.append(Vector3(lean * t * t, height * t, 0.35 * sin(t * 3.0)))
	var rad := PackedFloat32Array()
	for k in n_t:
		var t := float(k) / (n_t - 1)
		rad.append(lerpf(0.23, 0.15, t) + 0.1 * exp(-spine[k].y * 1.8))
	tb.tube(spine, rad, 8 if lod == 0 else (5 if lod == 1 else 4), 2, 0.85, 0.85, 1.0, 0.0, 0.2)
	var top := spine[n_t - 1]
	var crown := Crown.new(top + Vector3(0, 0.3, 0), Vector3(2.4, 1.3, 2.4))
	if lod == 0:
		tb.blob(top + Vector3(0, 0.15, 0), Vector3(0.42, 0.4, 0.42), 4, 7, crown, rng, 0.1)
	var count: int = int(v["fronds"]) if lod == 0 else (8 if lod == 1 else 5)
	var segs := 6 if lod == 0 else (3 if lod == 1 else 2)
	for f in count:
		var az := TAU * f / count + rng.randf_range(-0.18, 0.18)
		var kind := f % 3
		var rise := 0.0
		var droop := 0.0
		var L := rng.randf_range(3.6, 4.6)
		if kind == 0:
			rise = rng.randf_range(1.3, 2.2)
			droop = rng.randf_range(1.0, 1.8)
		elif kind == 1:
			rise = rng.randf_range(0.2, 0.9)
			droop = rng.randf_range(1.8, 2.6)
			L *= 1.04
		else:
			rise = rng.randf_range(-0.4, 0.2)
			droop = rng.randf_range(2.6, 3.4)
			L *= 0.95
		_frond(tb, rng, top + Vector3(0, 0.2, 0), az, L, rise, droop, f % 2, segs, top)


static func _frond(tb: TB, rng: RandomNumberGenerator, root: Vector3, az: float, L: float, rise: float, droop: float,
		tile_row: int, segs: int, crown_top: Vector3) -> void:
	var dirh := Vector3(cos(az), 0.0, sin(az))
	var across0 := Vector3(-dirh.z, 0.0, dirh.x)
	var W := L * 0.5
	var bank := rng.randf_range(-0.25, 0.25)
	var phase := rng.randf()
	var v_top := float(tile_row) * 0.5 + 0.004
	var v_bot := float(tile_row + 1) * 0.5 - 0.004
	var v_mid := (v_top + v_bot) * 0.5
	var ids: Array[int] = []
	var prev := root
	for i in segs + 1:
		var f := float(i) / segs
		var p := root + dirh * (L * f) + Vector3.UP * (rise * f - droop * f * f)
		var tan_dir := (root + dirh * (L * minf(f + 0.05, 1.0)) + Vector3.UP * (rise * minf(f + 0.05, 1.0) - droop * pow(minf(f + 0.05, 1.0), 2.0)) - p)
		var across := (across0 + Vector3.UP * bank).normalized()
		var rel := (p - crown_top)
		var ao := lerpf(0.5, 1.0, pow(f, 0.6))
		for col in 3:
			var q := p
			var vv := v_mid
			if col == 0:
				q = p - across * (W * 0.5) - Vector3.UP * (W * 0.16)
				vv = v_top
			elif col == 2:
				q = p + across * (W * 0.5) - Vector3.UP * (W * 0.16)
				vv = v_bot
			var gn := tan_dir.cross(across)
			gn = gn.normalized() if gn.length() > 1e-5 else Vector3.UP
			if gn.y < 0.0:
				gn = -gn
			var nrm := (gn * 0.5 + rel.normalized() * 0.25 + Vector3.UP * 0.5).normalized()
			ids.append(tb.vert(q, nrm, Color(ao, 0.5, 0.45 + 0.4 * f, TreeKit.CARD),
				Vector2(lerpf(0.004, 0.996, f), vv), Vector2(phase, 0.2 + 0.8 * f)))
	for i in segs:
		for col in 2:
			tb.quad(ids[i * 3 + col], ids[i * 3 + col + 1], ids[(i + 1) * 3 + col + 1], ids[(i + 1) * 3 + col])


# ------------------------------------------------------------------- shrubs ---

static func _shrub(tb: TB, v: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"] + lod * 101
	var R: float = v["radius"]
	var Hh: float = v["height"]
	var crown := Crown.new(Vector3(0, Hh * 0.5, 0), Vector3(R, Hh * 0.55, R))
	var grid := Vector2i(4, 4)
	tb.blob(crown.c, crown.r * (0.55 if lod == 0 else 0.95), 4 if lod == 0 else 3, 7 if lod == 0 else 6, crown, rng, 0.1)
	if lod >= 2:
		return
	var total: int = int(v["cards"]) if lod == 0 else int(float(v["cards"]) * 0.25)
	var size: Vector2 = v["size"] if lod == 0 else (v["size"] as Vector2) * 1.9
	for i in total:
		var d := _rand_unit(rng)
		d.y = absf(d.y) * 0.9
		var p := crown.c + d * crown.r * rng.randf_range(0.55, 1.0)
		p.y = maxf(p.y, 0.12)
		_leaf_card(tb, rng, p, crown, size, grid, 1.0)


static func _hedge(tb: TB, v: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"] + lod * 101
	var Lh: float = v["length"]
	var Wd: float = v["width"]
	var Hh: float = v["height"]
	var crown := Crown.new(Vector3(0, Hh * 0.5, 0), Vector3(Lh * 0.6, Hh * 0.7, Wd * 0.8))
	var grid := Vector2i(4, 4)
	# Solid, softly rounded core (a squashed blob stretched along the hedge).
	tb.blob(crown.c, Vector3(Lh * 0.5, Hh * 0.5, Wd * 0.42) * (1.0 if lod == 0 else 1.05), 5 if lod == 0 else 3, 10 if lod == 0 else 6, crown, rng, 0.04)
	if lod >= 2:
		return
	var total: int = int(v["cards"]) if lod == 0 else int(float(v["cards"]) * 0.25)
	var size: Vector2 = v["size"] if lod == 0 else (v["size"] as Vector2) * 1.9
	for i in total:
		# a point on the clipped box surface: front, back, top, or an end
		var face := rng.randf()
		var p := Vector3(rng.randf_range(-Lh * 0.5, Lh * 0.5), rng.randf_range(0.05, Hh), 0.0)
		var nc := Vector3.ZERO
		if face < 0.36:
			p.z = Wd * 0.5
			nc = Vector3(0, 0.15, 1)
		elif face < 0.72:
			p.z = -Wd * 0.5
			nc = Vector3(0, 0.15, -1)
		elif face < 0.94:
			p.y = Hh
			p.z = rng.randf_range(-Wd * 0.5, Wd * 0.5)
			nc = Vector3.UP
		else:
			p.x = Lh * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			p.z = rng.randf_range(-Wd * 0.5, Wd * 0.5)
			nc = Vector3(signf(p.x), 0.1, 0)
		nc = nc.normalized()
		var up := (Vector3.UP * 0.6 + nc * 0.3 + _rand_unit(rng) * 0.35).normalized()
		var side := up.cross(nc).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var w := lerpf(size.x, size.y, rng.randf())
		var tile := Vector2i(rng.randi() % 4, rng.randi() % 4)
		tb.card(p - up * (w * 0.4), up, side, w, w, tile, grid, crown, nc, 0.35, rng.randf_range(-0.4, 0.4), rng.randf())
