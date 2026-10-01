@tool
class_name StreetKit
extends RefCounted
## New-style street furniture meshes (ART_BIBLE.md §17), built in code once
## and shared by every instance. Each is a single surface on
## street_props.gdshader, so a prop costs one draw call; the material type of
## each part rides in the vertex colour alpha (see that shader).
##
## Kinds: "lamp" (street lamp, arm over the road along -Z, head at 6.3 m),
## "signal" (traffic light: mast arm along -X, head at x = -3.6 facing +Z),
## "hydrant", "bin", "bench", "bollard", "cabinet" (signal controller),
## "shelter" (bus stop), "sign_stop", "sign_speed", "sign_name".

const PAINTED := 0.0
const METAL := 1.0 / 15.0
const CONCRETE := 2.0 / 15.0
const PLASTIC := 3.0 / 15.0
const RUBBER := 4.0 / 15.0
const GLASS := 5.0 / 15.0
const LAMP := 6.0 / 15.0
const RED := 8.0 / 15.0
const AMBER := 9.0 / 15.0
const GREEN := 10.0 / 15.0
const SIGN := 11.0 / 15.0
const WOOD := 13.0 / 15.0

## Street furniture paint (ART_BIBLE.md §17).
const IRON := Color(0.13, 0.135, 0.14)
const SIGNAL_GREY := Color(0.2, 0.21, 0.2)
const HAZARD_YELLOW := Color(0.91, 0.71, 0.12)

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
		_:
			push_warning("StreetKit: unknown kind %s" % kind)
	var m := mb.build_mesh(material())
	_cache[kind] = m
	return m


static func _c(col: Color, kind: float) -> PackedColorArray:
	return PackedColorArray([Color(col, kind)])


## A tube along `path` (sections stay upright, so keep paths fairly level).
static func _tube(mb: MeshBuilder, path: PackedVector3Array, r: float, col: Color, sides := 8, kind := PAINTED) -> void:
	var prof := PackedVector2Array()
	for i in sides + 1:
		var a := PI - TAU * i / sides
		prof.append(Vector2(cos(a), sin(a)) * r)
	mb.add_sweep(path, prof, _c(col, kind), 60.0)


# ------------------------------------------------------------------ lamp ---

static func _lamp(mb: MeshBuilder) -> void:
	var iron := IRON
	# Flared base, tapered pole, collar, cap.
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.21, 0.0), Vector2(0.21, 0.06), Vector2(0.17, 0.12), Vector2(0.15, 0.45),
		Vector2(0.12, 0.52), Vector2(0.1, 0.58), Vector2(0.085, 3.2), Vector2(0.1, 3.24), Vector2(0.1, 3.34),
		Vector2(0.08, 3.38), Vector2(0.065, 6.45), Vector2(0.08, 6.5), Vector2(0.08, 6.6), Vector2(0.0, 6.66),
	]), 10, _c(iron, PAINTED), 40.0)
	# Arm reaching over the road (local -Z), bowing up a little.
	var arm := PackedVector3Array()
	for i in 7:
		var t := i / 6.0
		arm.append(Vector3(0.0, 6.42 + sin(t * PI) * 0.12 - t * 0.04, -0.02 - t * 1.32))
	_tube(mb, arm, 0.045, iron)
	# Luminaire: a slim housing with a glowing lens underneath.
	var head := Transform3D(Basis(Vector3.RIGHT, 0.05), Vector3(0.0, 6.36, -1.45))
	mb.add_bevel_box(head, Vector3(0.34, 0.13, 0.78), 0.05, Color(0.2, 0.205, 0.21, PAINTED), Color(0.12, 0.12, 0.13, PAINTED), false)
	mb.add_bevel_box(head * Transform3D(Basis.IDENTITY, Vector3(0, -0.07, 0.03)), Vector3(0.26, 0.03, 0.56), 0.012, Color(0.95, 0.93, 0.86, LAMP), Color(0, 0, 0, -1), false)


# ---------------------------------------------------------------- signal ---

static func _signal(mb: MeshBuilder) -> void:
	var g := SIGNAL_GREY
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.24, 0.08), Vector2(0.19, 0.16), Vector2(0.15, 0.5),
		Vector2(0.13, 0.56), Vector2(0.115, 5.75), Vector2(0.13, 5.8), Vector2(0.0, 5.9),
	]), 10, _c(g, PAINTED), 40.0)
	# Mast arm along -X with a diagonal brace.
	_tube(mb, PackedVector3Array([Vector3(0.0, 5.5, 0), Vector3(-2.0, 5.52, 0), Vector3(-4.0, 5.54, 0)]), 0.06, g)
	_tube(mb, PackedVector3Array([Vector3(-0.05, 4.8, 0), Vector3(-0.7, 5.15, 0), Vector3(-1.4, 5.5, 0)]), 0.035, g)
	# Signal head: housing, backplate with a yellow reflective border, visors, lenses.
	var hx := -3.6
	var hy := 4.72
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, hy, 0.0)), Vector3(0.36, 1.04, 0.26), 0.04, Color(0.11, 0.115, 0.12, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, hy, -0.165)), Vector3(0.62, 1.32, 0.02), 0.005, Color(0.1, 0.1, 0.11, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, hy, -0.15)), Vector3(0.62, 1.32, 0.012), 0.004, Color(HAZARD_YELLOW, SIGN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, hy, -0.14)), Vector3(0.54, 1.24, 0.012), 0.004, Color(0.1, 0.1, 0.11, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hx, 5.3, 0.0)), Vector3(0.06, 0.3, 0.06), 0.01, Color(g, PAINTED))
	var face := Basis(Vector3.RIGHT, PI * 0.5)  # lathe axis (Y) to +Z
	var lens_kinds := [RED, AMBER, GREEN]
	for k in 3:
		var y := hy + 0.32 - k * 0.32
		var lc: Color = [Color(0.6, 0.1, 0.08), Color(0.6, 0.4, 0.05), Color(0.08, 0.55, 0.3)][k]
		mb.add_lathe(Transform3D(face, Vector3(hx, y, 0.13)), PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(0.115, 0.0), Vector2(0.11, 0.025), Vector2(0.0, 0.035)]), 14, _c(lc, lens_kinds[k]), 50.0)
		# Visor: a hood over the top of the lens.
		var visor := PackedVector2Array()
		for i in 7:
			var a := PI * i / 6.0
			visor.append(Vector2(cos(a) * 0.14, sin(a) * 0.14))
		var vpath := PackedVector3Array([Vector3(hx, y, 0.12), Vector3(hx, y, 0.32)])
		# add_sweep keeps sections upright: a horizontal path along +Z gives an
		# arch over the lens. Both sides, since it's a thin shell.
		mb.add_sweep(vpath, visor, _c(Color(0.1, 0.1, 0.11), PAINTED), 60.0, false, false)
		var back := visor.duplicate()
		back.reverse()
		mb.add_sweep(vpath, back, _c(Color(0.06, 0.06, 0.065), PAINTED), 60.0, false, false)
	# Street name blade on the arm and a pedestrian push-button box.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 5.82, 0.0)), Vector3(1.3, 0.24, 0.03), 0.01, Color(0.12, 0.42, 0.24, SIGN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 5.82, 0.0)), Vector3(1.22, 0.04, 0.034), 0.0, Color(0.9, 0.9, 0.88, SIGN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.14)), Vector3(0.12, 0.2, 0.08), 0.015, Color(HAZARD_YELLOW, PAINTED), Color(0, 0, 0, -1), false)
	# Pedestrian signal on the pole.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.2)), Vector3(0.34, 0.34, 0.2), 0.03, Color(0.11, 0.115, 0.12, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.3)), Vector3(0.26, 0.26, 0.02), 0.005, Color(0.95, 0.55, 0.2, 14.0 / 15.0), Color(0, 0, 0, -1), false)


# ----------------------------------------------------------- small props ---

static func _hydrant(mb: MeshBuilder) -> void:
	var red := Color(0.72, 0.14, 0.1)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.16, 0.06), Vector2(0.12, 0.1), Vector2(0.11, 0.55),
		Vector2(0.14, 0.57), Vector2(0.14, 0.62), Vector2(0.1, 0.64), Vector2(0.09, 0.72), Vector2(0.03, 0.8), Vector2(0.0, 0.81),
	]), 12, _c(red, PAINTED), 40.0)
	var side := Basis(Vector3.FORWARD, PI * 0.5)
	for s: float in [-1.0, 1.0]:
		mb.add_lathe(Transform3D(side.rotated(Vector3.UP, 0.0 if s > 0 else PI), Vector3(0.0, 0.42, 0.0)), PackedVector2Array([
			Vector2(0.0, 0.08), Vector2(0.05, 0.08), Vector2(0.05, 0.17), Vector2(0.065, 0.17), Vector2(0.065, 0.2), Vector2(0.0, 0.2)]), 8,
			_c(Color(0.75, 0.73, 0.7), METAL), 40.0)


static func _bin(mb: MeshBuilder) -> void:
	var green := Color(0.16, 0.24, 0.2)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(0.0, 0.02), Vector2(0.24, 0.02), Vector2(0.27, 0.06), Vector2(0.28, 0.9), Vector2(0.3, 0.92),
		Vector2(0.3, 0.98), Vector2(0.16, 1.02), Vector2(0.0, 1.03),
	]), 12, PackedColorArray([Color(green.darkened(0.3), PAINTED), Color(green, PAINTED)]), 30.0)


static func _bench(mb: MeshBuilder) -> void:
	var wood := Color(0.5, 0.36, 0.24, WOOD)
	var iron := Color(IRON, PAINTED)
	for s: float in [-0.8, 0.8]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(s, 0.22, 0.0)), Vector3(0.06, 0.44, 0.5), 0.015, iron)
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(s, 0.7, -0.24)), Vector3(0.06, 0.5, 0.05), 0.015, iron)
	for k in 3:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -0.17 + k * 0.17)), Vector3(1.9, 0.04, 0.13), 0.012, wood)
	for k in 2:
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.66 + k * 0.17, -0.26 - k * 0.035)), Vector3(1.9, 0.12, 0.035), 0.01, wood)


static func _bollard(mb: MeshBuilder, xf: Transform3D) -> void:
	mb.add_lathe(xf, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.11, 0.0), Vector2(0.11, 0.88), Vector2(0.09, 0.95), Vector2(0.05, 0.99), Vector2(0.0, 1.0),
	]), 10, PackedColorArray([Color(IRON, PAINTED)]), 40.0)
	mb.add_lathe(xf, PackedVector2Array([Vector2(0.112, 0.78), Vector2(0.112, 0.84)]), 10, _c(Color(0.85, 0.85, 0.8), SIGN), 40.0)


static func _cabinet(mb: MeshBuilder) -> void:
	var grey := Color(0.62, 0.64, 0.63)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), Vector3(0.95, 0.16, 0.65), 0.02, Color(ArtPalette.CONCRETE, CONCRETE))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.86, 0)), Vector3(0.8, 1.4, 0.5), 0.03, Color(grey, PAINTED), Color(grey.darkened(0.2), PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), Vector3(0.86, 0.06, 0.56), 0.02, Color(grey, PAINTED))


static func _shelter(mb: MeshBuilder) -> void:
	var frame := Color(0.3, 0.31, 0.32, METAL)
	for x: float in [-1.6, 1.6]:
		for z: float in [-0.6, 0.6]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.25, z)), Vector3(0.08, 2.5, 0.08), 0.015, frame)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 2.55, 0)), Vector3(3.5, 0.12, 1.5), 0.03, frame)
	# Glass back and sides (tinted, opaque so there's no transparency cost).
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.35, -0.6)), Vector3(3.1, 2.0, 0.03), 0.005, Color(0.35, 0.42, 0.45, GLASS))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-1.6, 1.35, 0.0)), Vector3(0.03, 2.0, 1.1), 0.005, Color(0.35, 0.42, 0.45, GLASS))
	# Advert panel (lit at night) and a bench.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.6, 1.3, 0.0)), Vector3(0.12, 1.8, 1.1), 0.02, Color(0.24, 0.25, 0.26, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(1.53, 1.3, 0.0)), Vector3(0.02, 1.6, 0.95), 0.005, Color(0.85, 0.82, 0.7, 14.0 / 15.0))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.45, -0.4)), Vector3(2.2, 0.05, 0.35), 0.01, Color(0.6, 0.62, 0.63, METAL))
