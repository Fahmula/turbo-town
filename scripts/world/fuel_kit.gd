@tool
class_name FuelKit
extends RefCounted
## The fuel and charging props (ART_BIBLE.md §17): the hand-held fuel nozzle
## and charging plug, the hoses and cables, and the new pumps and chargers
## (the TURBO FUEL station's own pumps are part of its landmark mesh). All on
## the shared street-props material (vertex colour, material class in the
## alpha), bevelled and smooth-shaded, at real size.

const RUBBER := Color(0.07, 0.07, 0.075, StreetKit.RUBBER)
const CABLE := Color(0.1, 0.1, 0.11, StreetKit.RUBBER)
const GRIP := Color(0.12, 0.125, 0.13, StreetKit.PLASTIC)
const ALU := Color(0.7, 0.71, 0.72, StreetKit.BRUSHED)
const SPOUT := Color(0.62, 0.64, 0.66, StreetKit.METAL)
## TURBO FUEL's red (the landmark's fascia) on the nozzle boot.
const FUEL_RED := Color(0.72, 0.16, 0.12, StreetKit.PLASTIC)
## Chargers: white bodies with a green band (green = electric, ART_BIBLE §5's
## go / success colour, muted for a prop).
const CHARGER_WHITE := Color(0.86, 0.87, 0.85, StreetKit.GLOSS)
const CHARGER_GREEN := Color(0.18, 0.62, 0.34, StreetKit.GLOSS)
const SCREEN := Color(0.08, 0.1, 0.12, StreetKit.GLASS)
const SCREEN_GLOW := Color(0.45, 0.85, 0.55, StreetKit.GLOW)

## Where the hose meets the nozzle / plug (local to it: grip at the origin,
## spout along -Z).
const NOZZLE_TAIL := Vector3(0.0, -0.035, 0.115)
const HOSE_RADIUS := 0.022
const CABLE_RADIUS := 0.017

static var _meshes := {}


## The fuel nozzle (`plug` false) or charging plug, one shared mesh each.
static func handle_mesh(plug: bool) -> ArrayMesh:
	var key := "plug" if plug else "nozzle"
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	if plug:
		_plug(mb)
	else:
		_nozzle(mb)
	var m := mb.build_mesh(StreetKit.material())
	_meshes[key] = m
	return m


## A pump nozzle: an aluminium body with a black grip and guard, a red boot,
## a steel spout bent down at the tip, the hose going in at the back.
static func _nozzle(mb: MeshBuilder) -> void:
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, -0.02)), Vector3(0.05, 0.06, 0.15), 0.014, ALU)
	# Grip (under the body) and the lever guard round it.
	mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0.0, -0.03, 0.05)), Vector3(0.036, 0.07, 0.05), 0.012, GRIP)
	StreetKit.beam(mb, Vector3(0.0, -0.075, -0.06), Vector3(0.0, -0.075, 0.07), 0.024, 0.012, GRIP, 0.004)
	StreetKit.beam(mb, Vector3(0.0, -0.075, -0.06), Vector3(0.0, -0.02, -0.075), 0.024, 0.012, GRIP, 0.004)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.015, -0.1)), Vector3(0.056, 0.05, 0.03), 0.01, FUEL_RED)
	StreetKit.rod(mb, Vector3(0.0, 0.015, -0.1), Vector3(0.0, 0.0, -0.21), 0.012, 0.011, 8, SPOUT)
	StreetKit.rod(mb, Vector3(0.0, 0.0, -0.21), Vector3(0.0, -0.035, -0.26), 0.011, 0.01, 8, SPOUT)
	StreetKit.rod(mb, Vector3(0.0, 0.0, 0.055), NOZZLE_TAIL, 0.02, HOSE_RADIUS, 8, RUBBER)


## A charging plug: a chunky handle with a green band, a round connector
## head at the front, the cable going in at the back.
static func _plug(mb: MeshBuilder) -> void:
	mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0.0, -0.01, 0.02)), Vector3(0.05, 0.075, 0.15), 0.02, GRIP)
	mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0.0, -0.005, -0.02)), Vector3(0.054, 0.079, 0.025), 0.01, CHARGER_GREEN)
	StreetKit.rod(mb, Vector3(0.0, 0.02, -0.06), Vector3(0.0, 0.03, -0.11), 0.034, 0.032, 12, GRIP)
	StreetKit.rod(mb, Vector3(0.0, 0.03, -0.11), Vector3(0.0, 0.031, -0.115), 0.03, 0.026, 12, ALU)
	StreetKit.rod(mb, Vector3(0.0, -0.03, 0.08), NOZZLE_TAIL, 0.02, CABLE_RADIUS, 8, CABLE)


## Points along a hose hanging from `a` to `b` with `slack` metres more hose
## than the straight line, sagging like a rope, never through `floor_y`.
static func hose_points(a: Vector3, b: Vector3, slack: float, floor_y: float, count := 12) -> PackedVector3Array:
	var d := a.distance_to(b)
	var sag := clampf(sqrt(3.0 * maxf(d, 0.2) * maxf(slack, 0.0) / 8.0) + slack * 0.25, 0.04, 1.6)
	var pts := PackedVector3Array()
	for i in count:
		var t := float(i) / (count - 1)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		p.y = maxf(p.y, floor_y + 0.03)
		pts.append(p)
	return pts


## Adds a hose (or cable) along `pts` to `mb`.
static func add_hose(mb: MeshBuilder, pts: PackedVector3Array, plug: bool) -> void:
	StreetKit.tube_path(mb, pts, PackedFloat32Array([CABLE_RADIUS if plug else HOSE_RADIUS]), 6, CABLE if plug else RUBBER, false)


## The handle (nozzle or plug) at `xf` into `mb` (for the merged resting mesh).
static func add_handle(mb: MeshBuilder, xf: Transform3D, plug: bool) -> void:
	var m := handle_mesh(plug)
	var arrays := m.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var basis := xf.basis.orthonormalized()
	for i in v.size():
		mb.verts.append(xf * v[i])
		mb.normals.append((basis * n[i]).normalized())
		mb.colors.append(c[i])
		mb.uvs.append(uv[i] if i < uv.size() else Vector2.ZERO)


# ------------------------------------------------------------- the props --

## An EV charger at `xf` (feet; it faces -Z, the bay in front of it): a slim
## white pedestal on a concrete plinth with a green band, a screen, a plug
## holster on its right side (+X) and the cable outlet beside it. Adds its
## collider to `body`. Returns [cable outlet, plug holster transform] in
## world space.
static func add_charger(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D) -> Array:
	var b := xf.basis
	var o := xf.origin
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 0.08, 0)), Vector3(0.7, 0.16, 0.5), 0.03, Color(ArtPalette.CONCRETE, StreetKit.CONCRETE))
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 0.88, 0)), Vector3(0.42, 1.44, 0.28), 0.06, CHARGER_WHITE)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 1.62, 0)), Vector3(0.44, 0.08, 0.3), 0.03, CHARGER_GREEN)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 1.66, 0)), Vector3(0.44, 0.04, 0.3), 0.015, CHARGER_WHITE)
	# Screen on the front with a lit status bar.
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 1.28, -0.142)), Vector3(0.26, 0.2, 0.012), 0.004, SCREEN, Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 1.21, -0.149)), Vector3(0.18, 0.025, 0.004), 0.002, SCREEN_GLOW, Color(0, 0, 0, -1), false)
	# Plug holster on the right side and the cable outlet below it.
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0.235, 1.0, -0.02)), Vector3(0.06, 0.16, 0.12), 0.015, GRIP)
	StreetKit.rod(mb, o + b * Vector3(0.21, 0.62, 0.04), o + b * Vector3(0.25, 0.62, 0.04), 0.03, 0.028, 10, GRIP)
	_box_collider(body, Transform3D(b, o + b * Vector3(0, 0.85, 0)), Vector3(0.48, 1.7, 0.34))
	var outlet := o + b * Vector3(0.26, 0.62, 0.04)
	# The plug rests head-down in the holster, its cable hanging below.
	var rest := Transform3D(b * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.5), o + b * Vector3(0.3, 1.0, -0.02))
	return [outlet, rest]


## An aviation fuel cabinet at `xf` (feet; it faces -Z): a red steel cabinet
## on a concrete pad with a hose reel on its right side (+X), a meter window
## and a nozzle holster. Adds its collider to `body`. Returns [hose outlet,
## nozzle rest transform] in world space.
static func add_air_pump(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D) -> Array:
	var b := xf.basis
	var o := xf.origin
	var red := Color(0.68, 0.15, 0.11, StreetKit.PAINTED)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0, 0.08, 0)), Vector3(1.5, 0.16, 1.0), 0.03, Color(ArtPalette.CONCRETE, StreetKit.CONCRETE))
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(-0.15, 0.78, 0)), Vector3(0.8, 1.25, 0.6), 0.05, red)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(-0.15, 1.43, 0)), Vector3(0.86, 0.06, 0.66), 0.02, Color(0.2, 0.2, 0.21, StreetKit.PAINTED))
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(-0.15, 1.08, -0.305)), Vector3(0.4, 0.2, 0.012), 0.004, SCREEN, Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(-0.15, 1.08, -0.311)), Vector3(0.28, 0.08, 0.004), 0.002, Color(0.5, 0.75, 0.35, StreetKit.GLOW), Color(0, 0, 0, -1), false)
	# Hose reel: two discs on an axle, wound with hose.
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for s: float in [-0.17, 0.17]:
		StreetKit.rod(mb, o + b * Vector3(0.5 + s * 0.12, 0.62, s), o + b * Vector3(0.5 + s * 0.12, 0.62, s + 0.02 * signf(s)), 0.36, 0.36, 18, gal)
	StreetKit.rod(mb, o + b * Vector3(0.5, 0.62, -0.17), o + b * Vector3(0.5, 0.62, 0.17), 0.24, 0.24, 18, RUBBER)
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(0.27, 0.62, 0)), Vector3(0.1, 0.9, 0.12), 0.02, gal)
	# Nozzle holster on the front.
	mb.add_bevel_box(Transform3D(b, o + b * Vector3(-0.45, 0.82, -0.32)), Vector3(0.12, 0.22, 0.08), 0.015, Color(0.15, 0.15, 0.16, StreetKit.RUBBER))
	_box_collider(body, Transform3D(b, o + b * Vector3(0.05, 0.75, 0)), Vector3(1.3, 1.5, 0.75))
	var outlet := o + b * Vector3(0.5, 0.4, -0.2)
	var rest := Transform3D(b * Basis(Vector3.RIGHT, -PI * 0.5), o + b * Vector3(-0.45, 0.8, -0.4))
	return [outlet, rest]


static func _box_collider(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = xf
	body.add_child(cs)
