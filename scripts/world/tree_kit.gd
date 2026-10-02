@tool
class_name TreeKit
extends RefCounted
## Tree meshes (ART_BIBLE.md §18), built in code once and shared.
## A canopy is leaf-cluster cards (alpha scissor, leaf atlas from
## tools/textures/make_textures.py) around a solid core that fills the gaps;
## every vertex's normal points out from the canopy centre, so the crown
## shades like one soft mass. Colours carry an AO gradient: dark underneath
## and inside, lighter and yellower on the sunlit top. See foliage.gdshader.
##
## Kinds: "broadleaf_a", "broadleaf_b" (street and park trees, ~7 m),
## "conifer" (~9 m), "palm" (~9 m, beach and harbour), and "_far" versions
## (core and trunk only; a palm stays a palm) for the distant LOD.

const CARD := 1.0
const CORE := 0.5
const BARK := 0.0

static var _cache := {}


static func material(kind: String) -> Material:
	if kind.begins_with("conifer"):
		return load("res://assets/materials/env/foliage_conifer.tres")
	if kind.begins_with("palm"):
		return load("res://assets/materials/env/foliage_palm.tres")
	return load("res://assets/materials/env/foliage_broadleaf.tres")


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var mb := MeshBuilder.new()
	var far := kind.ends_with("_far")
	var base := kind.trim_suffix("_far")
	match base:
		"broadleaf_a":
			_broadleaf(mb, 11, far)
		"broadleaf_b":
			_broadleaf(mb, 23, far)
		"conifer":
			_conifer(mb, 7, far)
		"palm":
			_palm(mb, 5)
	var m := MeshBuilder.with_lods(mb.build_mesh(material(kind)))
	_cache[kind] = m
	return m


static func _trunk(mb: MeshBuilder, profile: PackedVector2Array, sides: int) -> void:
	var bark := ArtPalette.BARK
	var cols := PackedColorArray()
	for p in profile:
		cols.append(Color(bark.darkened(0.35).lerp(bark, clampf(p.y / 1.5, 0.0, 1.0)), BARK))
	mb.add_lathe(Transform3D.IDENTITY, profile, sides, cols, 50.0)


## Tapered limb from `a` to `b` (a lathe with its axis turned along a -> b).
static func _limb(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var col := Color(ArtPalette.BARK.darkened(0.1), BARK)
	mb.add_lathe(Transform3D(Basis(x, y, z), a), PackedVector2Array([Vector2(r0, 0.0), Vector2(r1, d.length()), Vector2(0.0, d.length() + r1)]),
		6, PackedColorArray([col]), 50.0)


## Solid ellipsoid core with normals from `center`.
static func _core(mb: MeshBuilder, center: Vector3, radii: Vector3, dark: Color, mid: Color, kind: float) -> void:
	var rings := 6
	var segs := 10
	var pts: Array = []
	for r in rings + 1:
		var phi := PI * r / rings
		var row: Array[Vector3] = []
		for s in segs:
			var th := TAU * s / segs
			row.append(Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)))
		pts.append(row)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var dirs: Array[Vector3] = [pts[r][s], pts[r][s1], pts[r + 1][s1], pts[r + 1][s]]
			var p: Array[Vector3] = []
			var c: Array[Color] = []
			for d in dirs:
				p.append(center + d * radii)
				c.append(Color(dark.lerp(mid, clampf(d.y * 0.5 + 0.5, 0.0, 1.0)), kind))
			mb.add_quad_ex(p[0], p[1], p[2], p[3], dirs[0], dirs[1], dirs[2], dirs[3], c[0], c[1], c[2], c[3])


## A leaf card: a quad of `size` at `p`, facing `facing`, spun by `spin`;
## normals from the canopy centre `c` (scaled by `radii`); AO from height
## and depth in the canopy. `quad` picks the atlas quarter.
static func _card(mb: MeshBuilder, p: Vector3, facing: Vector3, spin: float, size: float, c: Vector3, radii: Vector3,
		dark: Color, mid: Color, lit: Color, quad: int) -> void:
	var n := facing.normalized()
	var t := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized().rotated(n, spin)
	var b := n.cross(t)
	var h := size * 0.5
	var corners: Array[Vector3] = [p - t * h - b * h, p + t * h - b * h, p + t * h + b * h, p - t * h + b * h]
	var q0 := Vector2(quad % 2, quad / 2) * 0.5
	var uv: Array[Vector2] = [q0 + Vector2(0.0, 0.5), q0 + Vector2(0.5, 0.5), q0 + Vector2(0.5, 0.0), q0]
	var ns: Array[Vector3] = []
	var cs: Array[Color] = []
	for q in corners:
		var rel := (q - c) / radii
		ns.append(rel.normalized())
		var height := clampf(rel.y * 0.5 + 0.5, 0.0, 1.0)
		var depth := clampf(rel.length(), 0.0, 1.2)
		var col := dark.lerp(mid, smoothstep(0.0, 0.55, height)).lerp(lit, smoothstep(0.55, 1.0, height) * 0.8)
		col = col.darkened((1.0 - clampf(depth, 0.0, 1.0)) * 0.35)
		cs.append(Color(col, CARD))
	mb.add_quad_ex(corners[0], corners[1], corners[2], corners[3], ns[0], ns[1], ns[2], ns[3], cs[0], cs[1], cs[2], cs[3],
		uv[0], uv[1], uv[2], uv[3])


static func _broadleaf(mb: MeshBuilder, seed: int, far: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var c := Vector3(0.0, 4.9, 0.0)
	var radii := Vector3(2.7, 2.2, 2.7)
	var dark := ArtPalette.BROADLEAF.darkened(0.3)
	var mid := ArtPalette.BROADLEAF
	var lit := ArtPalette.FOLIAGE_LIT
	_trunk(mb, PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.22, 0.12), Vector2(0.17, 0.6), Vector2(0.14, 2.6),
		Vector2(0.1, 4.2), Vector2(0.0, 4.6)]), 8)
	if far:
		_core(mb, c, radii * 0.98, dark, mid.lerp(lit, 0.4), CORE)
		return
	# Main limbs into the crown.
	for k in 4:
		var ang := TAU * k / 4.0 + rng.randf_range(-0.4, 0.4)
		var a := Vector3(0.0, rng.randf_range(2.3, 3.0), 0.0)
		var b := c + Vector3(cos(ang) * radii.x * 0.55, rng.randf_range(-0.6, 0.6), sin(ang) * radii.z * 0.55)
		_limb(mb, a, b, 0.09, 0.035)
	_core(mb, c + Vector3(0, -0.1, 0), radii * 0.7, dark.darkened(0.15), mid, CORE)
	# Leaf clusters around the crown: one on top, a ring at mid height, a lower ring.
	var clusters: Array[Vector3] = [c + Vector3(0.0, radii.y * 0.55, 0.0)]
	for k in 6:
		var ang := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		clusters.append(c + Vector3(cos(ang) * radii.x * 0.55, rng.randf_range(0.0, 0.6), sin(ang) * radii.z * 0.55))
	for k in 4:
		var ang := TAU * k / 4.0 + 0.6 + rng.randf_range(-0.3, 0.3)
		clusters.append(c + Vector3(cos(ang) * radii.x * 0.45, -radii.y * 0.45, sin(ang) * radii.z * 0.45))
	for q in clusters:
		for i in 13:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var p := q + dir * rng.randf_range(0.4, 1.25)
			# Face mostly outward from the crown, with some randomness.
			var facing := ((p - c) / radii).normalized() + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			_card(mb, p, facing, rng.randf() * TAU, rng.randf_range(1.4, 1.9), c, radii, dark, mid, lit, rng.randi() % 4)


static func _conifer(mb: MeshBuilder, seed: int, far: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dark := ArtPalette.CONIFER.darkened(0.25)
	var mid := ArtPalette.CONIFER
	var lit := ArtPalette.CONIFER_LIT.lerp(ArtPalette.FOLIAGE_LIT, 0.25)
	var top := 9.2
	var base := 1.5
	var r0 := 2.2
	_trunk(mb, PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.2, 0.12), Vector2(0.15, 0.8), Vector2(0.05, top - 0.6), Vector2(0.0, top - 0.3)]), 7)
	var core_prof := PackedVector2Array()
	for k in 7:
		var t := k / 6.0
		core_prof.append(Vector2(r0 * 0.78 * pow(1.0 - t, 1.1), lerpf(base + 0.3, top, t)))
	var core_cols := PackedColorArray()
	for k in core_prof.size():
		core_cols.append(Color(dark.darkened(0.15).lerp(mid, float(k) / core_prof.size()), CORE))
	if far:
		core_prof[0] = Vector2(r0 * 0.98, base)
		for k in range(1, core_prof.size()):
			core_prof[k].x /= 0.78
		mb.add_lathe(Transform3D.IDENTITY, core_prof, 10, core_cols, 50.0)
		return
	core_prof.insert(0, Vector2(0.0, base + 0.2))
	core_cols.insert(0, core_cols[0])
	mb.add_lathe(Transform3D.IDENTITY, core_prof, 10, core_cols, 50.0)
	# Tiers of drooping needle sprays, shorter toward the top.
	var y := base + 0.1
	var tier := 0
	while y < top - 0.4:
		var t := (y - base) / (top - base)
		var rt := r0 * pow(1.0 - t, 0.95) + 0.3
		var count := 7 if t < 0.6 else 5
		for k in count:
			var ang := TAU * k / count + tier * 0.7 + rng.randf_range(-0.25, 0.25)
			var radial := Vector3(cos(ang), 0.0, sin(ang))
			var tangent := Vector3(-sin(ang), 0.0, cos(ang))
			var droop := rng.randf_range(0.25, 0.45) * rt
			var inner := Vector3(0.0, y + 0.25, 0.0) + radial * 0.1
			var outer := Vector3(0.0, y - droop + 0.25, 0.0) + radial * rt
			var half := tangent * rt * rng.randf_range(0.42, 0.55)
			# Tilt the spray a little around its own axis.
			var lift := Vector3.UP * rng.randf_range(-0.15, 0.15) * rt
			var corners: Array[Vector3] = [inner - half * 0.3 + lift, inner + half * 0.3 - lift, outer + half - lift, outer - half + lift]
			var q := rng.randi() % 4
			var q0 := Vector2(q % 2, q / 2) * 0.5
			var uv: Array[Vector2] = [q0 + Vector2(0.15, 0.46), q0 + Vector2(0.35, 0.46), q0 + Vector2(0.5, 0.0), q0 + Vector2(0.0, 0.0)]
			var ns: Array[Vector3] = []
			var cs: Array[Color] = []
			for p in corners:
				var rad := Vector3(p.x, 0.0, p.z)
				ns.append((rad.normalized() if rad.length() > 0.01 else radial) + Vector3.UP * 0.55)
				ns[ns.size() - 1] = ns[ns.size() - 1].normalized()
				var outness := clampf(rad.length() / maxf(rt, 0.01), 0.0, 1.0)
				var col := dark.lerp(mid, outness).lerp(lit, smoothstep(0.3, 1.0, t) * 0.5 + outness * 0.25)
				cs.append(Color(col, CARD))
			mb.add_quad_ex(corners[0], corners[1], corners[2], corners[3], ns[0], ns[1], ns[2], ns[3], cs[0], cs[1], cs[2], cs[3],
				uv[0], uv[1], uv[2], uv[3])
		y += 0.55 + t * 0.15
		tier += 1


## A palm: a gently leaning, ringed trunk and a crown of arching fronds (strips
## along the frond texture: base at u = 0, tip at u = 1, one frond per half).
static func _palm(mb: MeshBuilder, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var height := 9.0
	var lean := 1.3
	var segs := 10
	var bark := Color(0.5, 0.44, 0.36)
	var spine: Array[Vector3] = []
	for k in segs + 1:
		var t := float(k) / segs
		spine.append(Vector3(lean * t * t, height * t, 0.0))
	for k in segs:
		var r0 := lerpf(0.27, 0.17, float(k) / segs)
		var r1 := lerpf(0.27, 0.17, float(k + 1) / segs)
		var a := spine[k]
		var b := spine[k + 1]
		var y := (b - a).normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		var z := x.cross(y)
		var c0 := Color(bark.darkened(0.12 if k % 2 == 0 else 0.0), BARK)
		var c1 := Color(bark.darkened(0.25), BARK)
		# A ring: flared at the bottom of each segment.
		mb.add_lathe(Transform3D(Basis(x, y, z), a), PackedVector2Array([Vector2(r0 * 1.08, 0.0), Vector2(r1, a.distance_to(b) * 0.85),
			Vector2(r1 * 1.04, a.distance_to(b))]), 8, PackedColorArray([c1, c0, c0]), 30.0)
	var top := spine[segs]
	var green := Color(0.369, 0.478, 0.204)  # palm
	_core(mb, top + Vector3(0, 0.15, 0), Vector3(0.55, 0.45, 0.55), green.darkened(0.45), green.darkened(0.2), CORE)
	var fronds := 12
	for f in fronds:
		var ang := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var across := Vector3(-dir.z, 0.0, dir.x)
		var length := rng.randf_range(3.6, 4.6)
		var rise := rng.randf_range(0.5, 1.4) if f % 2 == 0 else rng.randf_range(-0.2, 0.6)
		var droop := rng.randf_range(1.8, 2.8)
		var width := 2.3
		var bank := rng.randf_range(-0.25, 0.25)
		var half := 0.5 * float(f % 2)
		var steps := 5
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in steps + 1:
			var t := float(k) / steps
			var p := top + dir * (length * t) + Vector3.UP * (rise * t - droop * t * t)
			var side := (across + Vector3.UP * bank).normalized() * width * 0.5
			var l := p - side
			var r := p + side
			if k > 0:
				var t0 := float(k - 1) / steps
				var cols: Array[Color] = []
				var ns: Array[Vector3] = []
				for q: Vector3 in [prev_l, prev_r, r, l]:
					var rel := q - top
					ns.append((rel.normalized() + Vector3.UP * 1.2).normalized())
					var tip := clampf(rel.length() / length, 0.0, 1.0)
					cols.append(Color(green.darkened(0.25).lerp(ArtPalette.FOLIAGE_LIT.lerp(green, 0.4), tip * 0.8), CARD))
				mb.add_quad_ex(prev_l, prev_r, r, l, ns[0], ns[1], ns[2], ns[3], cols[0], cols[1], cols[2], cols[3],
					Vector2(0.02 + 0.96 * t0, half), Vector2(0.02 + 0.96 * t0, half + 0.5), Vector2(0.02 + 0.96 * t, half + 0.5), Vector2(0.02 + 0.96 * t, half))
			prev_l = l
			prev_r = r
