@tool
class_name StreetKit
extends RefCounted
## Street furniture meshes (ART_BIBLE.md §17), built in code once and shared by
## every instance. Each is a single surface on street_props.gdshader, so a prop
## costs one draw call; the material of each part rides in the vertex colour
## alpha (class constants below, table in assets/shaders/props_common.gdshaderinc).
##
## Kinds: "lamp" (street lamp, arm over the road along -Z, head at 6.3 m),
## "signal" (traffic light: mast arm along -X, head at x = -3.6 facing +Z),
## "hydrant", "bin", "bench", "bollard", "cabinet" (signal controller),
## "shelter" (bus stop), "cone", "drum" (oil drum, tinted per prop), "crate",
## "pin" (giant bowling pin).
##
## Public helpers for the other builders (landmarks, stunt park): beam, rod,
## tube_path, loft, bolt.

# Material classes (alpha of the vertex colour). Original classes are k / 15,
# the extra ones (2k + 1) / 30. Keep in sync with props_common.gdshaderinc.
const PAINTED := 0.0
const CORRUGATED := 1.0 / 30.0
const METAL := 1.0 / 15.0
const CORRUGATED_B := 3.0 / 30.0
const CONCRETE := 2.0 / 15.0
const PLATE := 5.0 / 30.0
const PLASTIC := 3.0 / 15.0
const TIMBER := 7.0 / 30.0
const RUBBER := 4.0 / 15.0
const RUST := 9.0 / 30.0
const GLASS := 5.0 / 15.0
const WORN := 11.0 / 30.0
const LAMP := 6.0 / 15.0
const BRUSHED := 13.0 / 30.0
const LAMP_COOL := 7.0 / 15.0
const SLATE := 15.0 / 30.0
const RED := 8.0 / 15.0
const AMBER := 9.0 / 15.0
const GREEN := 10.0 / 15.0
const ALUMINIUM := 17.0 / 30.0
const GLOSS := 19.0 / 30.0
const STEEL_DECK := 21.0 / 30.0
const SIGN := 11.0 / 15.0
const RETRO := 23.0 / 30.0
const FABRIC := 12.0 / 15.0
const DECKING := 25.0 / 30.0
const SLATS := 27.0 / 30.0
const WOOD := 13.0 / 15.0
const GLOW := 14.0 / 15.0
const DECK := 15.0 / 15.0

## Street furniture paint (ART_BIBLE.md §17).
const IRON := Color(0.15, 0.155, 0.16)
const SIGNAL_GREY := Color(0.2, 0.21, 0.2)
const HAZARD_YELLOW := Color(0.91, 0.71, 0.12)
const GALV := Color(0.62, 0.64, 0.66)
const BLACK_PLASTIC := Color(0.12, 0.125, 0.13)

static var _cache := {}


static func material() -> Material:
	return load("res://assets/materials/env/street_props.tres")


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var mb := MeshBuilder.new()
	match kind:
		"lamp":
			_lamp(mb)
		"signal":
			_signal(mb)
		"hydrant":
			_hydrant(mb)
		"bin":
			_bin(mb)
		"bench":
			_bench(mb)
		"bollard":
			_bollard(mb, Transform3D.IDENTITY)
		"cabinet":
			_cabinet(mb)
		"shelter":
			_shelter(mb)
		"cone":
			_cone(mb)
		"drum":
			_drum(mb)
		"crate":
			_crate(mb)
		"pin":
			_pin(mb)
		_:
			push_warning("StreetKit: unknown kind %s" % kind)
	var m := MeshBuilder.with_lods(mb.build_mesh(material()))
	_cache[kind] = m
	return m


## `rgb` with the material class `kind` in the alpha.
static func k(rgb: Color, kind: float) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, kind)


static func _c(col: Color, kind: float) -> PackedColorArray:
	return PackedColorArray([Color(col, kind)])


# ----------------------------------------------------------------- helpers ---

## A bevelled bar from a to b: `w` across, `h` deep (any orientation).
static func beam(mb: MeshBuilder, a: Vector3, b: Vector3, w: float, h: float, col: Color, bevel := 0.006) -> void:
	var y := b - a
	var len := y.length()
	if len < 1e-5:
		return
	y /= len
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	mb.add_bevel_box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, len, h), bevel, col, Color(0, 0, 0, -1), false)


## A capped cylinder / cone frustum from a (radius r0) to b (radius r1).
static func rod(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, smooth_deg := 40.0) -> void:
	var y := b - a
	var len := y.length()
	if len < 1e-5:
		return
	y /= len
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	mb.add_lathe(Transform3D(Basis(x, y, z), a), PackedVector2Array([Vector2(0.0, 0.0), Vector2(r0, 0.0), Vector2(r1, len), Vector2(0.0, len)]),
		sides, PackedColorArray([col]), smooth_deg)


## A hex bolt head or nut standing on a surface at `p` (axis `up`).
static func bolt(mb: MeshBuilder, p: Vector3, up: Vector3, r: float, col: Color) -> void:
	rod(mb, p, p + up * r * 0.7, r, r * 0.92, 6, col, 60.0)


## Smooth surface through rings of equal point counts (closed loops by
## default). Normals come from the surface itself and point away from each
## ring's centre (`inside` flips them for the inner skin of a thin shell).
static func loft(mb: MeshBuilder, rings: Array, col: Color, closed := true, caps := true, inside := false) -> void:
	var nr := rings.size()
	if nr < 2:
		return
	var m: int = (rings[0] as PackedVector3Array).size()
	var cen: Array[Vector3] = []
	for r in nr:
		var c := Vector3.ZERO
		for p in (rings[r] as PackedVector3Array):
			c += p
		cen.append(c / m)
	var sgn := -1.0 if inside else 1.0
	var nrm: Array = []
	var us: Array = []
	var vs := PackedFloat32Array()
	var v := 0.0
	for i in nr:
		var ri: PackedVector3Array = rings[i]
		var rn := PackedVector3Array()
		var ru := PackedFloat32Array()
		var u := 0.0
		var up: PackedVector3Array = rings[mini(i + 1, nr - 1)]
		var dn: PackedVector3Array = rings[maxi(i - 1, 0)]
		for j in m:
			var jn := (j + 1) % m if closed else mini(j + 1, m - 1)
			var jp := (j - 1 + m) % m if closed else maxi(j - 1, 0)
			var n := (ri[jn] - ri[jp]).cross(up[j] - dn[j])
			var out := ri[j] - cen[i]
			if n.length_squared() < 1e-12:
				n = out
			if n.dot(out) < 0.0:
				n = -n
			rn.append(n.normalized() * sgn)
			ru.append(u)
			u += ri[j].distance_to(ri[(j + 1) % m])
		ru.append(u)  # total, for the wrap-around quad
		nrm.append(rn)
		us.append(ru)
		if i > 0:
			v += cen[i].distance_to(cen[i - 1])
		vs.append(v)
	var white := col
	var segs := m if closed else m - 1
	for i in nr - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		var na: PackedVector3Array = nrm[i]
		var nb: PackedVector3Array = nrm[i + 1]
		var ua: PackedFloat32Array = us[i]
		var ub: PackedFloat32Array = us[i + 1]
		for j in segs:
			var j2 := (j + 1) % m
			mb.add_quad_ex(a[j], a[j2], b[j2], b[j], na[j], na[j2], nb[j2], nb[j], white, white, white, white,
				Vector2(ua[j], vs[i]), Vector2(ua[j + 1], vs[i]), Vector2(ub[j + 1], vs[i + 1]), Vector2(ub[j], vs[i + 1]))
	if not (closed and caps):
		return
	for end in [0, nr - 1]:
		var ring: PackedVector3Array = rings[end]
		var toward: Vector3 = cen[0] - cen[1] if end == 0 else cen[nr - 1] - cen[nr - 2]
		if toward.length_squared() < 1e-12:
			continue
		var n := toward.normalized()
		for j in m:
			var p0 := ring[j]
			var p1 := ring[(j + 1) % m]
			mb._tri_out(cen[end], p0, p1, n, n, n, white, white, white, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), n)


## A round tube along `pts` with a radius at every point (tapers allowed).
static func tube_path(mb: MeshBuilder, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color, caps := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var tans: Array[Vector3] = []
	for i in n:
		tans.append((pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized())
	var nrm := tans[0].cross(Vector3.UP if absf(tans[0].y) < 0.9 else Vector3.RIGHT).normalized()
	var rings: Array = []
	for i in n:
		nrm = (nrm - tans[i] * nrm.dot(tans[i])).normalized()
		var bin := tans[i].cross(nrm)
		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(pts[i] + (nrm * cos(a) + bin * sin(a)) * radii[mini(i, radii.size() - 1)])
		rings.append(ring)
	loft(mb, rings, col, true, caps)


## A closed super-ellipse ring in the XY plane at z, offset by `at`.
static func _oval(hw: float, ht: float, hb: float, z: float, at: Vector3, sides := 16, p := 0.55) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for j in sides:
		var a := TAU * j / sides
		var cx := cos(a)
		var sy := sin(a)
		var x := hw * signf(cx) * pow(absf(cx), p)
		var y := (ht if sy >= 0.0 else hb) * signf(sy) * pow(absf(sy), p)
		ring.append(at + Vector3(x, y, z))
	return ring


# ------------------------------------------------------------------ lamp ---

static func _lamp(mb: MeshBuilder) -> void:
	var paint := Color(0.17, 0.18, 0.18)
	var low := Color(0.11, 0.115, 0.12)
	var lite := Color(0.22, 0.23, 0.23)
	# Concrete foundation collar.
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.24, 0.07), Vector2(0.0, 0.075)]), 12,
		_c(Color(0.55, 0.55, 0.53), CONCRETE), 40.0)
	# Cast base cover flaring into a tapered tubular pole (6.5 m).
	var prof := PackedVector2Array([
		Vector2(0.0, 0.06), Vector2(0.205, 0.06), Vector2(0.205, 0.1), Vector2(0.18, 0.14), Vector2(0.15, 0.3), Vector2(0.13, 0.5),
		Vector2(0.12, 0.6), Vector2(0.132, 0.62), Vector2(0.132, 0.655), Vector2(0.1, 0.675), Vector2(0.094, 0.69),
		Vector2(0.082, 3.5), Vector2(0.072, 6.38), Vector2(0.076, 6.42), Vector2(0.076, 6.48), Vector2(0.045, 6.53), Vector2(0.0, 6.55)])
	var cols := PackedColorArray()
	for i in prof.size():
		cols.append(Color(low if i < 3 else paint, PAINTED))
	mb.add_lathe(Transform3D.IDENTITY, prof, 14, cols, 30.0)
	# Anchor nuts and the hand-hole door.
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		bolt(mb, Vector3(cos(a) * 0.185, 0.1, sin(a) * 0.185), Vector3.UP, 0.016, k(GALV, METAL))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.085, 1.0, 0.0)), Vector3(0.03, 0.34, 0.1), 0.004, k(lite, PAINTED), k(lite, PAINTED), false)
	for y: float in [0.86, 1.14]:
		bolt(mb, Vector3(0.1, y, 0.0), Vector3.RIGHT, 0.009, k(GALV, METAL))
	# Arm reaching over the road (local -Z), rising then levelling.
	var arm := PackedVector3Array([Vector3(0, 6.25, 0.0), Vector3(0, 6.31, -0.3), Vector3(0, 6.39, -0.65), Vector3(0, 6.43, -1.0), Vector3(0, 6.42, -1.3)])
	tube_path(mb, arm, PackedFloat32Array([0.06, 0.05, 0.043, 0.037, 0.034]), 10, k(paint, PAINTED))
	mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.18, 0.0)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.115, 0.0), Vector2(0.115, 0.14),
		Vector2(0.0, 0.14)]), 12, _c(paint, PAINTED), 40.0)
	# Cobra-head luminaire: a lofted housing with a flat glowing lens below.
	var at := Vector3(0.0, 6.35, 0.0)
	var rings: Array = []
	for s: Array in [[-1.0, 0.1, 0.055, 0.04], [-1.1, 0.15, 0.085, 0.058], [-1.32, 0.178, 0.1, 0.066], [-1.58, 0.17, 0.092, 0.062],
			[-1.78, 0.13, 0.066, 0.048], [-1.9, 0.07, 0.036, 0.03]]:
		rings.append(_oval(s[1], s[2], s[3], s[0], at, 16))
	loft(mb, rings, k(Color(0.3, 0.31, 0.32), PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.062, -1.42)), Vector3(0.3, 0.014, 0.72), 0.004, k(Color(0.12, 0.12, 0.13), PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.066, -1.42)), Vector3(0.25, 0.012, 0.62), 0.004, k(Color(0.95, 0.93, 0.86), LAMP), Color(0, 0, 0, -1), false)
	mb.add_lathe(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.092, -1.15)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.034, 0.0), Vector2(0.034, 0.045),
		Vector2(0.0, 0.05)]), 10, _c(Color(0.14, 0.14, 0.15), PLASTIC), 40.0)


# ---------------------------------------------------------------- signal ---

static func _signal(mb: MeshBuilder) -> void:
	var g := SIGNAL_GREY
	var low := Color(0.12, 0.125, 0.125)
	var black := BLACK_PLASTIC
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.26, 0.0), Vector2(0.26, 0.06), Vector2(0.235, 0.085)]), 12,
		_c(Color(0.55, 0.55, 0.53), CONCRETE), 40.0)
	var prof := PackedVector2Array([
		Vector2(0.0, 0.06), Vector2(0.22, 0.06), Vector2(0.22, 0.12), Vector2(0.19, 0.16), Vector2(0.16, 0.35), Vector2(0.14, 0.55),
		Vector2(0.13, 0.64), Vector2(0.14, 0.66), Vector2(0.14, 0.7), Vector2(0.115, 0.72), Vector2(0.11, 0.74),
		Vector2(0.092, 5.78), Vector2(0.098, 5.82), Vector2(0.098, 5.88), Vector2(0.05, 5.93), Vector2(0.0, 5.95)])
	var cols := PackedColorArray()
	for i in prof.size():
		cols.append(Color(low if i < 3 else g, PAINTED))
	mb.add_lathe(Transform3D.IDENTITY, prof, 14, cols, 30.0)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		bolt(mb, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2), Vector3.UP, 0.018, k(GALV, METAL))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.1, 1.45, 0.0)), Vector3(0.03, 0.36, 0.12), 0.004, k(g.lightened(0.12), PAINTED), Color(0, 0, 0, -1), false)
	# Mast arm along -X, tapering, with a clamp at the pole and a diagonal brace.
	var arm := PackedVector3Array([Vector3(0.0, 5.5, 0), Vector3(-1.0, 5.52, 0), Vector3(-2.0, 5.55, 0), Vector3(-3.1, 5.58, 0), Vector3(-4.1, 5.6, 0)])
	tube_path(mb, arm, PackedFloat32Array([0.09, 0.072, 0.058, 0.048, 0.04]), 10, k(g, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-0.02, 5.5, 0.0)), Vector3(0.26, 0.34, 0.3), 0.02, k(g.lightened(0.08), PAINTED), Color(0, 0, 0, -1), false)
	rod(mb, Vector3(-0.1, 4.75, 0), Vector3(-1.7, 5.46, 0), 0.036, 0.03, 8, k(g, PAINTED))
	# Signal head: three black polycarbonate sections, backplate with a retroreflective border.
	var hx := -3.6
	var hy := 4.72
	for kk in 3:
		var y := hy + 0.345 - kk * 0.345
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, y, 0.0)), Vector3(0.36, 0.335, 0.27), 0.035, k(black, PLASTIC), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, hy, -0.165)), Vector3(0.66, 1.36, 0.024), 0.006, k(Color(0.1, 0.1, 0.11), PLASTIC), Color(0, 0, 0, -1), false)
	for sx: float in [-1.0, 1.0]:
		beam(mb, Vector3(hx + sx * 0.31, hy - 0.66, -0.149), Vector3(hx + sx * 0.31, hy + 0.66, -0.149), 0.036, 0.008, k(HAZARD_YELLOW, RETRO), 0.002)
	for sy: float in [-1.0, 1.0]:
		beam(mb, Vector3(hx - 0.31, hy + sy * 0.66, -0.149), Vector3(hx + 0.31, hy + sy * 0.66, -0.149), 0.036, 0.008, k(HAZARD_YELLOW, RETRO), 0.002)
	var face := Basis(Vector3.RIGHT, PI * 0.5)  # lathe axis (Y) to +Z
	var lens_kinds := [RED, AMBER, GREEN]
	for kk in 3:
		var y := hy + 0.345 - kk * 0.345
		var lc: Color = [Color(0.6, 0.1, 0.08), Color(0.6, 0.4, 0.05), Color(0.08, 0.55, 0.3)][kk]
		mb.add_lathe(Transform3D(face, Vector3(hx, y, 0.13)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.15, 0.0), Vector2(0.15, 0.012), Vector2(0.128, 0.012), Vector2(0.0, 0.012)]),
			14, _c(Color(0.06, 0.06, 0.065), RUBBER), 40.0)
		mb.add_lathe(Transform3D(face, Vector3(hx, y, 0.14)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.128, 0.0), Vector2(0.124, 0.014), Vector2(0.09, 0.03), Vector2(0.0, 0.036)]),
			14, _c(lc, lens_kinds[kk]), 50.0)
		# Tunnel visor: an open arc hood over the top of the lens, with an inner skin.
		var outer: Array = []
		var inner: Array = []
		for zz: float in [0.15, 0.27, 0.4]:
			var drop := (zz - 0.15) * 0.18
			for skin in 2:
				var rr := 0.158 if skin == 0 else 0.15
				var ring := PackedVector3Array()
				for q in 11:
					var phi := deg_to_rad(-115.0 + 230.0 * q / 10.0)
					ring.append(Vector3(hx + sin(phi) * rr, y + cos(phi) * rr - drop, zz))
				(outer if skin == 0 else inner).append(ring)
		loft(mb, outer, k(black, PLASTIC), false, false, false)
		loft(mb, inner, k(Color(0.05, 0.05, 0.055), PLASTIC), false, false, true)
	# Brackets from the arm to the head.
	rod(mb, Vector3(hx, 5.2, 0.0), Vector3(hx, 5.56, 0.0), 0.028, 0.028, 8, k(g, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, 5.2, 0.0)), Vector3(0.12, 0.05, 0.16), 0.01, k(g, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, 4.2, 0.0)), Vector3(0.12, 0.05, 0.16), 0.01, k(g, PAINTED), Color(0, 0, 0, -1), false)
	# Street-name blade (hung under brackets) and a pedestrian push-button box.
	for bx: float in [-1.15, -2.05]:
		beam(mb, Vector3(bx, 5.64, 0.0), Vector3(bx, 5.74, 0.0), 0.03, 0.03, k(g, PAINTED), 0.004)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 5.86, 0.0)), Vector3(1.3, 0.24, 0.03), 0.008, k(Color(0.12, 0.42, 0.24), SIGN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 5.86, 0.0)), Vector3(1.24, 0.19, 0.036), 0.004, k(Color(0.14, 0.46, 0.27), RETRO), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.15)), Vector3(0.12, 0.2, 0.09), 0.015, k(HAZARD_YELLOW, PLASTIC), Color(0, 0, 0, -1), false)
	mb.add_lathe(Transform3D(face, Vector3(0.0, 1.12, 0.195)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.024, 0.014), Vector2(0.0, 0.016)]), 10,
		_c(Color(0.1, 0.1, 0.11), RUBBER), 40.0)
	# Pedestrian signal on the pole: a black case, a visor and an orange hand.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.22)), Vector3(0.34, 0.34, 0.2), 0.03, k(black, PLASTIC), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.325)), Vector3(0.27, 0.27, 0.022), 0.005, k(Color(0.95, 0.55, 0.2), GLOW), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.1, 0.36)), Vector3(0.36, 0.025, 0.18), 0.008, k(black, PLASTIC), Color(0, 0, 0, -1), false)


# ----------------------------------------------------------- small props ---

## Fire hydrant, 0.8 m: base flange, barrel, bonnet, two hose outlets and a
## pumper outlet with chained caps, a pentagon operating nut.
static func _hydrant(mb: MeshBuilder) -> void:
	var red := Color(0.68, 0.12, 0.09)
	var low := Color(0.3, 0.08, 0.06)
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.165, 0.0), Vector2(0.165, 0.025), Vector2(0.15, 0.045), Vector2(0.125, 0.06), Vector2(0.112, 0.1),
		Vector2(0.108, 0.46), Vector2(0.13, 0.475), Vector2(0.13, 0.515), Vector2(0.115, 0.53), Vector2(0.115, 0.6), Vector2(0.1, 0.68),
		Vector2(0.07, 0.745), Vector2(0.03, 0.775), Vector2(0.0, 0.78)])
	var cols := PackedColorArray()
	for i in prof.size():
		cols.append(Color(low if i < 3 else red, WORN))
	mb.add_lathe(Transform3D.IDENTITY, prof, 16, cols, 30.0)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		bolt(mb, Vector3(cos(a) * 0.135, 0.045, sin(a) * 0.135), Vector3.UP, 0.014, k(GALV, METAL))
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.775), Vector2(0.032, 0.775), Vector2(0.032, 0.815), Vector2(0.0, 0.815)]), 5,
		_c(Color(0.45, 0.42, 0.36), RUST), 60.0)
	# Outlets: (direction, radius, length) with a chained cap on each.
	for o: Array in [[Vector3.RIGHT, 0.058, 0.15], [Vector3.LEFT, 0.058, 0.15], [Vector3.BACK, 0.075, 0.17]]:
		var d: Vector3 = o[0]
		var r: float = o[1]
		var l: float = o[2]
		var base := Vector3(0.0, 0.34, 0.0)
		rod(mb, base, base + d * l, r, r, 14, k(red, WORN))
		rod(mb, base + d * (l - 0.02), base + d * (l + 0.012), r + 0.014, r + 0.014, 14, k(red.lightened(0.04), WORN))
		rod(mb, base + d * (l + 0.012), base + d * (l + 0.026), r * 0.8, r * 0.7, 14, k(Color(0.45, 0.42, 0.36), RUST))
		bolt(mb, base + d * (l + 0.026), d, 0.014, k(GALV, METAL))
	# Chains: a few small links hanging from the sides to the barrel.
	for s: float in [-1.0, 1.0]:
		var chain := PackedVector3Array([Vector3(s * 0.12, 0.3, 0.0), Vector3(s * 0.15, 0.25, 0.01), Vector3(s * 0.135, 0.2, 0.02)])
		tube_path(mb, chain, PackedFloat32Array([0.005, 0.005, 0.005]), 5, k(GALV, METAL), false)


## Park litter bin, 1.0 m: timber slats between two steel hoops on a steel base,
## a rain lid with an opening.
static func _bin(mb: MeshBuilder) -> void:
	var green := Color(0.13, 0.24, 0.19)
	var wood := Color(0.46, 0.31, 0.19)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.26, 0.0), Vector2(0.27, 0.03), Vector2(0.27, 0.07), Vector2(0.0, 0.07)]), 16,
		_c(green.darkened(0.2), PAINTED), 40.0)
	for i in 12:
		var a := TAU * i / 12.0
		mb.set_uv2(Vector2(fmod(i * 0.381, 1.0), fmod(i * 0.173, 1.0)))
		var basis := Basis(Vector3.UP, PI * 0.5 - a)
		mb.add_bevel_box(Transform3D(basis, Vector3(cos(a) * 0.262, 0.48, sin(a) * 0.262)), Vector3(0.076, 0.8, 0.026), 0.007, k(wood, WOOD), Color(0, 0, 0, -1), false)
	mb.set_uv2(Vector2.ZERO)
	for y: float in [0.13, 0.5, 0.83]:
		mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.282, 0.0), Vector2(0.282, 0.024), Vector2(0.2, 0.024)]), 24,
			_c(green, PAINTED), 40.0)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.15, 0.865), Vector2(0.295, 0.865), Vector2(0.3, 0.9), Vector2(0.3, 0.94), Vector2(0.27, 0.985),
		Vector2(0.2, 1.015), Vector2(0.15, 1.02), Vector2(0.15, 0.99)]), 24, _c(green, PAINTED), 35.0)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.86), Vector2(0.17, 0.86), Vector2(0.17, 0.87), Vector2(0.0, 0.87)]), 16,
		_c(Color(0.12, 0.12, 0.12), RUBBER), 40.0)


## Park bench, 1.9 m x 0.6 m: three seat slats and two back slats on cast-iron ends.
static func _bench(mb: MeshBuilder) -> void:
	var iron := k(Color(0.13, 0.14, 0.14), PAINTED)
	var wood := Color(0.5, 0.34, 0.2)
	for s: float in [-0.82, 0.82]:
		# Side frame in the YZ plane: legs, seat rail, backrest post, armrest.
		var fz := 0.24
		var bz := -0.2
		beam(mb, Vector3(s, 0.0, fz), Vector3(s, 0.42, fz - 0.02), 0.045, 0.05, iron, 0.01)
		beam(mb, Vector3(s, 0.0, bz), Vector3(s, 0.42, bz - 0.01), 0.045, 0.05, iron, 0.01)
		beam(mb, Vector3(s, 0.42, bz - 0.01), Vector3(s, 0.9, bz - 0.1), 0.04, 0.045, iron, 0.01)
		beam(mb, Vector3(s, 0.405, fz - 0.03), Vector3(s, 0.405, bz - 0.02), 0.045, 0.03, iron, 0.008)
		beam(mb, Vector3(s, 0.62, fz + 0.01), Vector3(s, 0.62, bz - 0.04), 0.05, 0.035, iron, 0.012)
		beam(mb, Vector3(s, 0.42, fz - 0.02), Vector3(s, 0.62, fz + 0.01), 0.035, 0.035, iron, 0.008)
		for z: float in [fz, bz]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(s, 0.012, z)), Vector3(0.09, 0.024, 0.11), 0.006, iron, Color(0, 0, 0, -1), false)
	for kk in 3:
		mb.set_uv2(Vector2(0.31 * kk, 0.17 * kk))
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.2 - kk * 0.14)), Vector3(1.82, 0.04, 0.115), 0.01, k(wood, WOOD))
	for kk in 2:
		mb.set_uv2(Vector2(0.5 + 0.23 * kk, 0.4 + 0.11 * kk))
		var y := 0.68 + kk * 0.17
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, y, -0.25 - kk * 0.035)), Vector3(1.82, 0.13, 0.035), 0.01, k(wood, WOOD))
	mb.set_uv2(Vector2.ZERO)


static func _bollard(mb: MeshBuilder, xf: Transform3D) -> void:
	var steel := Color(0.16, 0.165, 0.17)
	mb.add_lathe(xf, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.125, 0.0), Vector2(0.115, 0.04), Vector2(0.11, 0.06), Vector2(0.105, 0.88), Vector2(0.1, 0.95),
		Vector2(0.075, 0.985), Vector2(0.04, 1.0), Vector2(0.0, 1.002),
	]), 12, PackedColorArray([k(Color(0.1, 0.1, 0.1), PAINTED), k(Color(0.1, 0.1, 0.1), PAINTED), k(steel, PAINTED)]), 40.0)
	mb.add_lathe(xf, PackedVector2Array([Vector2(0.108, 0.76), Vector2(0.108, 0.768), Vector2(0.108, 0.84), Vector2(0.108, 0.848)]), 12, _c(Color(0.9, 0.9, 0.85), RETRO), 40.0)


## Roadside marker post (trails, hill roads): white, with an orange reflector.
static func add_marker(mb: MeshBuilder, xf: Transform3D) -> void:
	mb.add_bevel_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(0.12, 1.1, 0.12), 0.02,
		Color(0.9, 0.89, 0.85, PLASTIC), Color(0.6, 0.59, 0.56, PLASTIC))
	mb.add_bevel_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), Vector3(0.125, 0.14, 0.125), 0.005,
		Color(0.91, 0.42, 0.1, RETRO), Color(0, 0, 0, -1), false)


## Traffic signal controller cabinet: powder-coated box on a concrete plinth with
## louvres, a hinged door, a handle and a hazard sticker.
static func _cabinet(mb: MeshBuilder) -> void:
	var grey := Color(0.56, 0.585, 0.58)
	var dark := Color(0.1, 0.105, 0.11)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), Vector3(0.95, 0.16, 0.65), 0.02, Color(ArtPalette.CONCRETE, CONCRETE))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.87, 0)), Vector3(0.8, 1.42, 0.5), 0.03, k(grey, PAINTED), k(grey.darkened(0.25), PAINTED), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0)), Vector3(0.88, 0.05, 0.58), 0.018, k(grey.lightened(0.04), PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.665, 0)), Vector3(0.7, 0.04, 0.44), 0.015, k(grey.lightened(0.04), PAINTED), Color(0, 0, 0, -1), false)
	# Door: the seam all round, louvres in the lower half, a lock bar and handle.
	var zf := 0.252
	for sx: float in [-1.0, 1.0]:
		beam(mb, Vector3(sx * 0.37, 0.3, zf), Vector3(sx * 0.37, 1.5, zf), 0.008, 0.004, k(dark, PAINTED), 0.001)
	for y: float in [0.3, 1.5]:
		beam(mb, Vector3(-0.37, y, zf), Vector3(0.37, y, zf), 0.008, 0.004, k(dark, PAINTED), 0.001)
	for kk in 8:
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, 0.42 + kk * 0.035, zf + 0.004)), Vector3(0.42, 0.012, 0.03), 0.002, k(dark, PAINTED), Color(0, 0, 0, -1), false)
	beam(mb, Vector3(0.3, 0.8, zf + 0.012), Vector3(0.3, 1.05, zf + 0.012), 0.02, 0.016, k(GALV, BRUSHED), 0.004)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.3, 0.92, zf + 0.004)), Vector3(0.07, 0.15, 0.012), 0.004, k(Color(0.45, 0.46, 0.47), BRUSHED), Color(0, 0, 0, -1), false)
	for y: float in [0.45, 0.9, 1.35]:
		rod(mb, Vector3(-0.38, y - 0.05, zf), Vector3(-0.38, y + 0.05, zf), 0.011, 0.011, 8, k(Color(0.45, 0.46, 0.47), BRUSHED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-0.15, 1.3, zf + 0.002)), Vector3(0.14, 0.1, 0.004), 0.001, k(HAZARD_YELLOW, RETRO), Color(0, 0, 0, -1), false)
	for kk in 5:
		mb.add_bevel_box(Transform3D(Basis(Vector3.BACK, 0.45), Vector3(-0.19 + kk * 0.03, 1.3, zf + 0.0045)), Vector3(0.007, 0.1, 0.0015), 0.0, k(Color(0.08, 0.08, 0.08), RETRO), Color(0, 0, 0, -1), false)
	# Side vent panels.
	for sx: float in [-1.0, 1.0]:
		for kk in 5:
			mb.add_bevel_box(Transform3D(Basis(Vector3.BACK, 0.0), Vector3(sx * 0.402, 0.5 + kk * 0.04, 0.0)), Vector3(0.006, 0.014, 0.3), 0.002, k(dark, PAINTED), Color(0, 0, 0, -1), false)


## Bus shelter: a dark aluminium frame, tinted glass back and ends, a pitched roof,
## a lit advert panel and a perforated steel bench.
static func _shelter(mb: MeshBuilder) -> void:
	var frame := Color(0.2, 0.21, 0.22)
	var glass := Color(0.3, 0.38, 0.4)
	for x: float in [-1.6, 1.6]:
		for z: float in [-0.6, 0.6]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.25, z)), Vector3(0.08, 2.5, 0.08), 0.015, k(frame, PAINTED), Color(0, 0, 0, -1), false)
	# Roof: a thick panel with a rain edge, tilted a little toward the back.
	var roof := Basis(Vector3.RIGHT, 0.04)
	mb.add_bevel_box(Transform3D(roof, Vector3(0, 2.56, 0)), Vector3(3.6, 0.1, 1.6), 0.03, k(frame.lightened(0.12), PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(roof, Vector3(0, 2.62, 0)), Vector3(3.4, 0.04, 1.4), 0.01, k(Color(0.55, 0.56, 0.57), METAL), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(roof, Vector3(0, 2.48, 0.7)), Vector3(3.5, 0.04, 0.08), 0.01, k(frame, PAINTED), Color(0, 0, 0, -1), false)
	# Glass back and left end in thin frames.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.6)), Vector3(3.1, 2.0, 0.02), 0.004, k(glass, GLASS), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 1.3, 0.0)), Vector3(0.02, 2.0, 1.1), 0.004, k(glass, GLASS), Color(0, 0, 0, -1), false)
	for y: float in [0.28, 2.32]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, y, -0.6)), Vector3(3.14, 0.05, 0.04), 0.008, k(frame, PAINTED), Color(0, 0, 0, -1), false)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, y, 0.0)), Vector3(0.04, 0.05, 1.14), 0.008, k(frame, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, -0.6)), Vector3(0.05, 2.0, 0.045), 0.008, k(frame, PAINTED), Color(0, 0, 0, -1), false)
	# Advert panel on the right end (lit at night): frame, poster, a stripe of colour.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.6, 1.3, 0.0)), Vector3(0.12, 1.9, 1.15), 0.02, k(Color(0.18, 0.19, 0.2), PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.535, 1.3, 0.0)), Vector3(0.02, 1.68, 0.95), 0.004, k(Color(0.86, 0.83, 0.72), GLOW), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.524, 1.55, 0.0)), Vector3(0.006, 0.7, 0.8), 0.0, k(Color(0.9, 0.42, 0.18), GLOW), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.524, 0.92, 0.0)), Vector3(0.006, 0.4, 0.8), 0.0, k(Color(0.2, 0.42, 0.62), GLOW), Color(0, 0, 0, -1), false)
	# Perforated steel bench with two legs.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.46, -0.38)), Vector3(2.2, 0.04, 0.34), 0.01, k(Color(0.58, 0.6, 0.61), METAL), Color(0, 0, 0, -1), false)
	for x: float in [-1.1, 0.7]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.23, -0.38)), Vector3(0.05, 0.46, 0.3), 0.01, k(frame, PAINTED), Color(0, 0, 0, -1), false)


# ---------------------------------------------------------- stunt props ---

## Traffic cone, 0.72 m: orange PVC on a square black rubber base, two retroreflective collars.
static func _cone(mb: MeshBuilder) -> void:
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.021, 0)), Vector3(0.44, 0.042, 0.44), 0.03, k(Color(0.12, 0.12, 0.13), RUBBER), Color(0, 0, 0, -1), false)
	var orange := k(Color(0.92, 0.36, 0.07), PLASTIC)
	var white := k(Color(0.92, 0.92, 0.88), RETRO)
	var r_at := func(h: float) -> float: return lerpf(0.185, 0.033, (h - 0.04) / 0.67)
	var prof := PackedVector2Array([Vector2(0.2, 0.04), Vector2(0.185, 0.05)])
	var cols := PackedColorArray([orange, orange])
	var bands := [[0.3, 0.42], [0.5, 0.58]]
	for b: Array in bands:
		var h0: float = b[0]
		var h1: float = b[1]
		prof.append(Vector2(r_at.call(h0 - 0.001), h0 - 0.001)); cols.append(orange)
		prof.append(Vector2(r_at.call(h0) + 0.003, h0)); cols.append(white)
		prof.append(Vector2(r_at.call(h1) + 0.003, h1)); cols.append(white)
		prof.append(Vector2(r_at.call(h1 + 0.001), h1 + 0.001)); cols.append(orange)
	prof.append(Vector2(0.03, 0.705)); cols.append(orange)
	prof.append(Vector2(0.026, 0.72)); cols.append(orange)
	prof.append(Vector2(0.0, 0.722)); cols.append(orange)
	mb.add_lathe(Transform3D.IDENTITY, prof, 16, cols, 28.0)


## Painted steel oil drum with rolling hoops (colour from the prop's tint).
static func _drum(mb: MeshBuilder) -> void:
	var paint := k(Color(0.92, 0.92, 0.92), PAINTED)
	var low := k(Color(0.6, 0.6, 0.6), PAINTED)
	var bare := k(Color(0.55, 0.56, 0.57), WORN)
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.282, 0.0), Vector2(0.298, 0.012), Vector2(0.298, 0.04), Vector2(0.292, 0.05), Vector2(0.292, 0.26), Vector2(0.3, 0.27), Vector2(0.3, 0.29),
		Vector2(0.292, 0.3), Vector2(0.292, 0.62), Vector2(0.3, 0.63), Vector2(0.3, 0.65), Vector2(0.292, 0.66), Vector2(0.292, 0.88), Vector2(0.298, 0.89), Vector2(0.298, 0.92),
		Vector2(0.308, 0.93), Vector2(0.308, 0.945), Vector2(0.285, 0.945), Vector2(0.272, 0.93), Vector2(0.0, 0.93)])
	var cols := PackedColorArray([low, low, low, paint, paint, paint, paint, paint, paint, paint, paint, paint, paint, paint, paint, paint, bare, bare, paint, paint, paint])
	mb.add_lathe(Transform3D.IDENTITY, prof, 16, cols, 28.0)
	# Bungs on the lid.
	for o: Array in [[Vector3(0.14, 0.93, 0.08), 0.034], [Vector3(-0.1, 0.93, -0.12), 0.024]]:
		var p: Vector3 = o[0]
		rod(mb, p, p + Vector3.UP * 0.012, o[1] + 0.006, o[1], 12, k(GALV, METAL))


## Wooden crate, 1.2 m: boards with gaps inside a frame of corner battens.
static func _crate(mb: MeshBuilder) -> void:
	var board := Color(0.66, 0.5, 0.32)
	var batten := Color(0.5, 0.36, 0.22)
	var e := 0.55
	# The faces are slatted boards drawn by the shader (class 27: 0.21 m boards
	# with gaps and their own grain), inside a frame of corner battens.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(1.14, 1.14, 1.14), 0.012, k(board, SLATS), Color(0, 0, 0, -1), false)
	for a: float in [-1.0, 1.0]:
		for b: float in [-1.0, 1.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(a * e, 0.6, b * e)), Vector3(0.1, 1.2, 0.1), 0.012, k(batten, WOOD), Color(0, 0, 0, -1), false)
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.6 + a * e, b * e)), Vector3(1.2, 0.1, 0.1), 0.012, k(batten, WOOD), Color(0, 0, 0, -1), false)
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(a * e, 0.6 + b * e, 0)), Vector3(0.1, 0.1, 1.2), 0.012, k(batten, WOOD), Color(0, 0, 0, -1), false)


## Giant bowling pin (1.9 m): glossy white lacquer with two red neck stripes.
static func _pin(mb: MeshBuilder) -> void:
	var white := k(Color(0.93, 0.92, 0.88), GLOSS)
	var red := k(Color(0.7, 0.1, 0.09), GLOSS)
	# (height, radius) of the pin, smoothed with a Catmull-Rom spline.
	var key := [Vector2(0.0, 0.24), Vector2(0.03, 0.27), Vector2(0.18, 0.34), Vector2(0.42, 0.405), Vector2(0.66, 0.4), Vector2(0.95, 0.31),
		Vector2(1.15, 0.215), Vector2(1.27, 0.19), Vector2(1.4, 0.205), Vector2(1.55, 0.245), Vector2(1.7, 0.235), Vector2(1.82, 0.16), Vector2(1.88, 0.0)]
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.24, 0.0)])
	var cols := PackedColorArray([white, white])
	var steps := 28
	for i in steps + 1:
		var u := float(i) / steps * (key.size() - 1)
		var s := mini(int(u), key.size() - 2)
		var f := u - s
		var p0: Vector2 = key[maxi(s - 1, 0)]
		var p1: Vector2 = key[s]
		var p2: Vector2 = key[s + 1]
		var p3: Vector2 = key[mini(s + 2, key.size() - 1)]
		var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)
		var stripe := (q.x > 1.2 and q.x < 1.27) or (q.x > 1.33 and q.x < 1.4)
		prof.append(Vector2(maxf(q.y, 0.0), q.x))
		cols.append(red if stripe else white)
	prof.append(Vector2(0.0, 1.885))
	cols.append(white)
	mb.add_lathe(Transform3D.IDENTITY, prof, 20, cols, 50.0)
