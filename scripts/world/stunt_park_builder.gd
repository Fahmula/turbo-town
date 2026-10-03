@tool
class_name StuntParkBuilder
extends RefCounted
## The stunt park south of the city: a big concrete pad full of ramps, a gap
## jump, a mega ramp, quarter/half pipes, bumps and things to knock over.
## Everything here is placed as spawn requests so it can later be moved into
## a hand-edited scene if wanted.

const PI_ROT := PI  # rotate a ramp 180° so it faces south (+Z)

# Loop-the-loop (east side): enter heading south at LOOP_X from LOOP_Z, come
# out LOOP_SHIFT metres further east (a gentle helix, so the way down doesn't
# land on the way in). Like a real coaster loop it's tighter at the top
# (radius LOOP_R_TOP) than at the bottom (LOOP_R_BOTTOM): gentler g's going
# in, still easy to make it over the top. Needs about 70 km/h.
const LOOP_X := 160.0
const LOOP_Z := 372.0
const LOOP_R_BOTTOM := 10.0
const LOOP_R_TOP := 5.0
const LOOP_WIDTH := 7.0
const LOOP_SHIFT := 8.0
const LOOP_STEPS := 120
# Wall-ride bowl: the floor curves up into a vertical wall; the opening faces
# north, right where the loop comes out.
const BOWL_CENTER := Vector2(165.0, 487.0)
const BOWL_FLOOR := 9.0
const BOWL_CURVE := 8.0

var prop_spawns: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 4242


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "StuntPark"
	parent.add_child(root)
	_build_pad(root)
	_build_gate(root)
	_build_loop(root)
	_build_bowl(root)
	_place_ramps()
	_place_props()


func _ramp(pos: Vector3, yaw: float, shape: int, length: float, height: float, width: float, deck := 0.0, color := Color(1.0, 0.74, 0.22)) -> void:
	prop_spawns.append({
		"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, yaw), pos),
		"shape": shape, "length": length, "height": height, "width": width, "deck": deck, "color": color,
	})


## The arena floor: concrete tiles (paving.gdshader) with hazard-orange
## bands along the north and south edges.
func _build_pad(root: Node3D) -> void:
	var mn := MapLayout.PARK_MIN
	var mx := MapLayout.PARK_MAX
	var mb := MeshBuilder.new()
	var y := 0.03
	var floor_col := Color(0.62, 0.61, 0.58, 0.5)
	mb.add_quad(Vector3(mn.x, y, mn.y), Vector3(mn.x, y, mx.y), Vector3(mx.x, y, mx.y), Vector3(mx.x, y, mn.y), floor_col)
	var band := 1.2
	var o := Color(0.91, 0.42, 0.11, 0.0)
	for z0: float in [mn.y, mx.y - band]:
		mb.add_quad(Vector3(mn.x, y + 0.005, z0), Vector3(mn.x, y + 0.005, z0 + band), Vector3(mx.x, y + 0.005, z0 + band), Vector3(mx.x, y + 0.005, z0), o)
	var body := StaticBody3D.new()
	body.name = "Pad"
	body.set_meta("surface_grip", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(load("res://assets/materials/env/paving.tres"))
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(mx.x - mn.x, 1.0, mx.y - mn.y)
	cs.shape = box
	cs.position = Vector3((mn.x + mx.x) * 0.5, y - 0.5, (mn.y + mx.y) * 0.5)
	body.add_child(cs)
	root.add_child(body)


func _build_gate(root: Node3D) -> void:
	var z := MapLayout.PARK_MIN.y + 2.0
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Gate"
	var red := Color(0.72, 0.18, 0.14, StreetKit.WORN)
	var galv := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for sx in [-1.0, 1.0]:
		var xf := Transform3D(Basis.IDENTITY, Vector3(sx * 9.0, 4.0, z))
		mb.add_bevel_box(xf, Vector3(1.2, 8.0, 1.2), 0.1, red, Color(0.45, 0.12, 0.1, StreetKit.WORN))
		# Concrete footing, base plate with four bolts, a hand-hole cover.
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * 9.0, 0.15, z)), Vector3(2.0, 0.3, 2.0), 0.05, Color(ArtPalette.CONCRETE, StreetKit.CONCRETE))
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * 9.0, 0.33, z)), Vector3(1.6, 0.06, 1.6), 0.01, galv)
		for bx in [-1.0, 1.0]:
			for bz in [-1.0, 1.0]:
				StreetKit.bolt(mb, Vector3(sx * 9.0 + bx * 0.68, 0.36, z + bz * 0.68), Vector3.UP, 0.05, galv)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * 9.0 + 0.0, 1.0, z + 0.605)), Vector3(0.5, 0.7, 0.025), 0.005, Color(0.8, 0.2, 0.15, StreetKit.WORN))
		# Floodlights on top of each column.
		for fz in [-0.25, 0.25]:
			StreetKit.beam(mb, Vector3(sx * 9.0, 8.0, z + fz), Vector3(sx * 9.0, 8.5, z + fz * 1.6), 0.08, 0.08, galv, 0.01)
			mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.5 * signf(fz)), Vector3(sx * 9.0, 8.6, z + fz * 1.8)), Vector3(0.5, 0.3, 0.12), 0.03, Color(0.2, 0.21, 0.22, StreetKit.PAINTED))
			mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, 0.5 * signf(fz)), Vector3(sx * 9.0, 8.6, z + fz * 1.8 + 0.07 * signf(fz))), Vector3(0.42, 0.22, 0.02), 0.004, Color(0.95, 0.93, 0.86, StreetKit.LAMP))
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.2, 8.0, 1.2)
		cs.shape = sh
		cs.transform = xf
		body.add_child(cs)
	# Sign board on a steel frame: the face is retroreflective sheeting, with a
	# white band below it and a catwalk rail above.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.6, z)), Vector3(20.0, 2.4, 1.0), 0.1, Color(0.18, 0.36, 0.64, StreetKit.PAINTED))
	for side in [-1.0, 1.0]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.6, z + side * 0.505)), Vector3(19.6, 2.1, 0.02), 0.005, Color(0.18, 0.36, 0.64, StreetKit.RETRO))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 7.32, z)), Vector3(20.0, 0.16, 1.02), 0.03, Color(0.9, 0.89, 0.86, StreetKit.PAINTED))
	StreetKit.beam(mb, Vector3(-9.8, 10.5, z), Vector3(9.8, 10.5, z), 0.06, 0.06, galv, 0.01)
	StreetKit.beam(mb, Vector3(-9.8, 10.1, z), Vector3(9.8, 10.1, z), 0.04, 0.04, galv, 0.01)
	for rx in range(-9, 10, 3):
		StreetKit.beam(mb, Vector3(rx, 9.8, z), Vector3(rx, 10.5, z), 0.05, 0.05, galv, 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(StreetKit.material())
	body.add_child(mi)
	root.add_child(body)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "STUNT PARK"
		label.font_size = 200
		label.pixel_size = 0.01
		label.modulate = Color(1, 1, 1)
		label.outline_modulate = Color(0.1, 0.2, 0.5)
		label.outline_size = 24
		label.position = Vector3(0, 8.6, z + 0.55 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		label.double_sided = false
		root.add_child(label)


## Quad visible from the side `facing` points to (MeshBuilder wants CCW).
static func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(facing) >= 0.0:
		mb.add_quad(a, b, c, d, col)
	else:
		mb.add_quad(a, d, c, b, col)


## Centre line of the loop track: LOOP_STEPS + 1 points from the way in to
## the way out (the heading turns a full circle; radius of curvature
## a + b*cos(heading) blends from LOOP_R_BOTTOM to LOOP_R_TOP).
static func loop_points() -> PackedVector3Array:
	var a := (LOOP_R_BOTTOM + LOOP_R_TOP) * 0.5
	var b := (LOOP_R_BOTTOM - LOOP_R_TOP) * 0.5
	var pts := PackedVector3Array()
	var z := LOOP_Z
	var y := 0.04
	var sub := 8
	for i in LOOP_STEPS + 1:
		var th := TAU * i / LOOP_STEPS
		pts.append(Vector3(LOOP_X + LOOP_SHIFT * (th - sin(th)) / TAU, y, z))
		for k in sub:
			var t := TAU * (i + (k + 0.5) / sub) / LOOP_STEPS
			var ds := (a + b * cos(t)) * TAU / LOOP_STEPS / sub
			z += cos(t) * ds
			y += sin(t) * ds
	return pts


## Unit normal of the track at step i (pointing at the inside of the loop).
static func loop_normal(i: int) -> Vector3:
	var th := TAU * i / LOOP_STEPS
	return Vector3(0, cos(th), -sin(th))


func _build_loop(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var pts := loop_points()
	var hw := LOOP_WIDTH * 0.5
	var thick := 0.35
	# U-shaped cross-section: flat in the middle, the edges curving up, so a car
	# that drifts off the line (the loop shifts sideways as it goes round) is
	# steered back to the middle without needing grip.
	var prof: Array[Vector2] = []  # (sideways, height above the surface)
	for k in 9:
		var u := -hw + LOOP_WIDTH * k / 8.0
		var e := maxf(absf(u) - 1.8, 0.0) / (hw - 1.8)
		prof.append(Vector2(u, 1.2 * e * e))
	# Surface normals across the U profile (2D: sideways, along the track normal).
	var pn: Array[Vector2] = []
	for k in prof.size():
		var d := prof[mini(k + 1, prof.size() - 1)] - prof[maxi(k - 1, 0)]
		pn.append(Vector2(-d.y, d.x).normalized())
	var along := 0.0
	for i in LOOP_STEPS:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var n0 := loop_normal(i)
		var n1 := loop_normal(i + 1)
		var seg := p0.distance_to(p1)
		# Painted steel deck panels in blue and white blocks, red-and-white kerbs.
		var col := Color(0.2, 0.42, 0.72, StreetKit.STEEL_DECK) if (i / 5) % 2 == 0 else Color(0.9, 0.9, 0.88, StreetKit.STEEL_DECK)
		var edge_col := Color(0.72, 0.18, 0.14, StreetKit.STEEL_DECK) if (i / 5) % 2 == 0 else Color(0.9, 0.9, 0.88, StreetKit.STEEL_DECK)
		var n_mid := (n0 + n1).normalized()
		var steel := Color(0.3, 0.32, 0.34, StreetKit.PAINTED)
		for k in prof.size() - 1:
			var a := prof[k]
			var b := prof[k + 1]
			var v00 := p0 + Vector3.RIGHT * a.x + n0 * a.y
			var v01 := p0 + Vector3.RIGHT * b.x + n0 * b.y
			var v10 := p1 + Vector3.RIGHT * a.x + n1 * a.y
			var v11 := p1 + Vector3.RIGHT * b.x + n1 * b.y
			var c := col if absf((a.x + b.x) * 0.5) < 1.9 else edge_col
			var na0 := (Vector3.RIGHT * pn[k].x + n0 * pn[k].y).normalized()
			var nb0 := (Vector3.RIGHT * pn[k + 1].x + n0 * pn[k + 1].y).normalized()
			var na1 := (Vector3.RIGHT * pn[k].x + n1 * pn[k].y).normalized()
			var nb1 := (Vector3.RIGHT * pn[k + 1].x + n1 * pn[k + 1].y).normalized()
			mb.add_quad_ex(v00, v01, v11, v10, na0, nb0, nb1, na1, c, c, c, c,
				Vector2(a.x, along), Vector2(b.x, along), Vector2(b.x, along + seg), Vector2(a.x, along + seg))
			# Underside.
			mb.add_quad_ex(v00 - n0 * thick, v10 - n1 * thick, v11 - n1 * thick, v01 - n0 * thick, -n0, -n1, -n1, -n0, steel, steel, steel, steel)
		along += seg
		# Close off the edges.
		for side: float in [-1.0, 1.0]:
			var e: Vector2 = prof[0] if side < 0.0 else prof[prof.size() - 1]
			var t0: Vector3 = p0 + Vector3.RIGHT * e.x + n0 * e.y
			var t1: Vector3 = p1 + Vector3.RIGHT * e.x + n1 * e.y
			_quad(mb, t0 - n0 * thick, t1 - n1 * thick, t1, t0, Vector3.RIGHT * side, Color(0.62, 0.64, 0.66, StreetKit.METAL))
	var top := pts[LOOP_STEPS / 2]
	# Gantry holding up the top: pillars outside both lanes (the top of the
	# loop is right above the way in), joined by a beam over the track.
	var grey := Color(0.62, 0.64, 0.66, StreetKit.METAL)
	var top_y := top.y + thick + 0.4
	var left := LOOP_X - hw - 1.3
	var right := LOOP_X + LOOP_SHIFT + hw + 1.3
	for z in [top.z - 3.0, top.z + 3.0]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(left, top_y * 0.5, z)), Vector3(0.7, top_y, 0.7), 0.06, grey)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(right, top_y * 0.5, z)), Vector3(0.7, top_y, 0.7), 0.06, grey)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3((left + right) * 0.5, top_y + 0.35, z)), Vector3(right - left + 0.7, 0.7, 0.7), 0.06, grey)
	# Looks only (not in the collider): floor beams under the deck, base plates
	# and bolts on the gantry, bracing between its legs.
	var shape := mb.build_collision_shape()
	var steel := Color(0.3, 0.32, 0.34, StreetKit.PAINTED)
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for i in range(0, LOOP_STEPS, 3):
		var n := loop_normal(i)
		var t := (pts[mini(i + 1, LOOP_STEPS)] - pts[maxi(i - 1, 0)]).normalized()
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, n, t), pts[i] - n * (thick + 0.06)), Vector3(LOOP_WIDTH + 0.1, 0.12, 0.12), 0.015, steel, Color(0, 0, 0, -1), false)
	for gx: float in [left, right]:
		for z in [top.z - 3.0, top.z + 3.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(gx, 0.04, z)), Vector3(1.1, 0.08, 1.1), 0.01, gal)
			for bx in [-1.0, 1.0]:
				for bz in [-1.0, 1.0]:
					StreetKit.bolt(mb, Vector3(gx + bx * 0.45, 0.08, z + bz * 0.45), Vector3.UP, 0.04, gal)
		StreetKit.beam(mb, Vector3(gx, 0.3, top.z - 3.0), Vector3(gx, top_y - 0.4, top.z + 3.0), 0.1, 0.1, gal, 0.015)
		StreetKit.beam(mb, Vector3(gx, 0.3, top.z + 3.0), Vector3(gx, top_y - 0.4, top.z - 3.0), 0.1, 0.1, gal, 0.015)
	var node := _body("Loop", mb, shape)
	_make_slick(node)
	root.add_child(node)
	var sign := Label3D.new()
	sign.text = "LOOP!\n80+ km/h"
	sign.font_size = 160
	sign.pixel_size = 0.012
	sign.outline_size = 22
	sign.modulate = Color(1.0, 0.85, 0.25)
	sign.outline_modulate = Color(0.08, 0.1, 0.2)
	sign.position = Vector3(LOOP_X - 7.0, 3.0, LOOP_Z - 30.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	root.add_child(sign)


## A static body drawing `mb` (the shared props material) with a collider that
## may be smaller than the drawing (trim and ribs are looks only).
static func _body(node_name: String, mb: MeshBuilder, shape: Shape3D, grip := 1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mb.build_mesh(StreetKit.material())
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.set_meta("surface_grip", grip)
	return body


## Long, low cars scrape their bumpers on tight curves (like real ones would).
## No friction for the bodywork there (the tyres use raycasts, so grip is
## unaffected) and the scraping doesn't count as crashing.
static func _make_slick(body: Node3D) -> void:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.0
	(body as StaticBody3D).physics_material_override = pm
	body.set_meta("no_impact", true)


func _build_bowl(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var segs := 72
	var prof_steps := 12
	var gap := deg_to_rad(30.0)  # half-width of the opening, around north (-Z)
	var top := BOWL_CURVE + 1.5
	var thick := 0.4
	var c3 := Vector3(BOWL_CENTER.x, 0.03, BOWL_CENTER.y)
	var profile: Array[Vector2] = []  # (radius, height)
	var normals: Array[Vector2] = []  # inward/up, in (radius, height)
	for k in prof_steps + 1:
		var phi := PI * 0.5 * k / prof_steps
		profile.append(Vector2(BOWL_FLOOR + BOWL_CURVE * sin(phi), BOWL_CURVE * (1.0 - cos(phi))))
		normals.append(Vector2(-sin(phi), cos(phi)))
	profile.append(Vector2(BOWL_FLOOR + BOWL_CURVE, top))
	normals.append(Vector2(-1, 0))
	# Metres along the profile: the steel deck shader's "across" coordinate.
	var pdist: Array[float] = [0.0]
	for k in profile.size() - 1:
		pdist.append(pdist[k] + profile[k].distance_to(profile[k + 1]))
	for i in segs:
		var a0 := -PI * 0.5 + gap + (TAU - 2.0 * gap) * i / segs
		var a1 := -PI * 0.5 + gap + (TAU - 2.0 * gap) * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		# Painted panels in orange and amber (playful, as the stunt park may be).
		var col := Color(0.88, 0.5, 0.14, StreetKit.STEEL_DECK) if (i / 3) % 2 == 0 else Color(0.9, 0.72, 0.28, StreetKit.STEEL_DECK)
		var along0 := TAU * (BOWL_FLOOR + BOWL_CURVE) * i / segs
		var along1 := TAU * (BOWL_FLOOR + BOWL_CURVE) * (i + 1) / segs
		for k in profile.size() - 1:
			var q0 := profile[k]
			var q1 := profile[k + 1]
			var nk := normals[k]
			var nk1 := normals[k + 1]
			var v00 := c3 + d0 * q0.x + Vector3.UP * q0.y
			var v01 := c3 + d0 * q1.x + Vector3.UP * q1.y
			var v10 := c3 + d1 * q0.x + Vector3.UP * q0.y
			var v11 := c3 + d1 * q1.x + Vector3.UP * q1.y
			var n00 := d0 * nk.x + Vector3.UP * nk.y
			var n01 := d0 * nk1.x + Vector3.UP * nk1.y
			var n10 := d1 * nk.x + Vector3.UP * nk.y
			var n11 := d1 * nk1.x + Vector3.UP * nk1.y
			mb.add_quad_ex(v00, v10, v11, v01, n00, n10, n11, n01, col, col, col, col,
				Vector2(pdist[k], along0), Vector2(pdist[k], along1), Vector2(pdist[k + 1], along1), Vector2(pdist[k + 1], along0))
			# Outside skin: dark steel.
			var o := -(d0 * nk.x + Vector3.UP * nk.y) * thick
			var skin := Color(0.3, 0.32, 0.34, StreetKit.PAINTED)
			_quad(mb, v00 + o, v01 + o, v11 + o, v10 + o, -n00, skin)
		# Coping on top.
		var r := BOWL_FLOOR + BOWL_CURVE
		_quad(mb, c3 + d0 * r + Vector3.UP * top, c3 + d1 * r + Vector3.UP * top,
			c3 + d1 * (r + thick) + Vector3.UP * top, c3 + d0 * (r + thick) + Vector3.UP * top, Vector3.UP, Color(0.62, 0.64, 0.66, StreetKit.METAL))
	# Looks only (not in the collider): a galvanised coping rail round the top and
	# stiffening ribs down the steel skin on the outside.
	var shape := mb.build_collision_shape()
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	var rib := Color(0.34, 0.355, 0.375, StreetKit.PAINTED)
	var rail := PackedVector3Array()
	for i in segs + 1:
		var a := -PI * 0.5 + gap + (TAU - 2.0 * gap) * i / segs
		rail.append(c3 + Vector3(cos(a), 0, sin(a)) * (BOWL_FLOOR + BOWL_CURVE + 0.12) + Vector3.UP * (top + 0.07))
	StreetKit.tube_path(mb, rail, PackedFloat32Array([0.06]), 8, gal, true)
	for i in range(0, segs + 1, 4):
		var a := -PI * 0.5 + gap + (TAU - 2.0 * gap) * i / segs
		var d := Vector3(cos(a), 0, sin(a))
		for k in range(0, profile.size() - 1, 2):
			var k2 := mini(k + 2, profile.size() - 1)
			var pa := c3 + d * profile[k].x + Vector3.UP * profile[k].y - (d * normals[k].x + Vector3.UP * normals[k].y) * (thick + 0.03)
			var pb := c3 + d * profile[k2].x + Vector3.UP * profile[k2].y - (d * normals[k2].x + Vector3.UP * normals[k2].y) * (thick + 0.03)
			StreetKit.beam(mb, pa, pb, 0.08, 0.06, rib, 0.01)
	var node := _body("WallRide", mb, shape)
	node.set_meta("no_impact", true)  # (normal friction: scraping the wall helps you stick)
	root.add_child(node)
	var sign := Label3D.new()
	sign.text = "WALL RIDE"
	sign.font_size = 160
	sign.pixel_size = 0.012
	sign.outline_size = 22
	sign.modulate = Color(1.0, 0.6, 0.15)
	sign.outline_modulate = Color(0.08, 0.1, 0.2)
	sign.position = Vector3(BOWL_CENTER.x, top + 2.0, BOWL_CENTER.y)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	root.add_child(sign)


func _place_ramps() -> void:
	# Entry kickers: small / medium / large, all facing south.
	_ramp(Vector3(-22, 0, 335), PI_ROT, 1, 5.0, 1.2, 6.0)
	_ramp(Vector3(0, 0, 335), PI_ROT, 1, 8.0, 2.2, 7.0)
	_ramp(Vector3(22, 0, 335), PI_ROT, 1, 12.0, 3.6, 8.0)

	# Gap jump over a row of crates (west).
	_ramp(Vector3(-120, 0, 350), PI_ROT, 0, 16.0, 4.0, 9.0, 4.0)
	_ramp(Vector3(-120, 0, 424), 0.0, 0, 20.0, 4.0, 9.0, 4.0, Color(0.35, 0.8, 0.45))

	# Table-top jump (centre).
	_ramp(Vector3(0, 0, 395), PI_ROT, 0, 10.0, 2.5, 10.0, 12.0)
	_ramp(Vector3(0, 0, 427), 0.0, 0, 10.0, 2.5, 10.0)

	# Mega ramp (east): climb, deck, steep drop, then a kicker into the air.
	_ramp(Vector3(125, 0, 322), PI_ROT, 0, 80.0, 14.0, 11.0, 10.0, Color(0.95, 0.45, 0.35))
	_ramp(Vector3(125, 0, 444), 0.0, 0, 32.0, 14.0, 11.0, 0.0, Color(0.95, 0.45, 0.35))
	_ramp(Vector3(125, 0, 458), PI_ROT, 1, 10.0, 3.5, 11.0)

	# Quarter pipes along the south edge.
	for x in [-70.0, -50.0, -30.0]:
		_ramp(Vector3(x, 0, 506), PI_ROT, 2, 6.0, 6.0, 10.0, 3.0, Color(0.4, 0.7, 1.0))

	# Half pipe (west side, runs east-west).
	_ramp(Vector3(-150, 0, 480), PI * 0.5, 2, 6.0, 5.0, 24.0, 2.0, Color(0.4, 0.7, 1.0))
	_ramp(Vector3(-122, 0, 480), -PI * 0.5, 2, 6.0, 5.0, 24.0, 2.0, Color(0.4, 0.7, 1.0))

	# Washboard bumps.
	for k in 12:
		_ramp(Vector3(65, 0, 380 + k * 4.5), PI_ROT, 3, 3.0, 0.35, 9.0, 0.0, Color(0.9, 0.9, 0.3))

	# Side-launch ramps for rolls: tilted kickers.
	var tilt := Basis(Vector3.UP, PI_ROT) * Basis(Vector3.FORWARD, 0.3)
	prop_spawns.append({"scene": "ramp", "xform": Transform3D(tilt, Vector3(-60, -0.6, 355)),
		"shape": 0, "length": 9.0, "height": 2.4, "width": 6.0, "deck": 0.0, "color": Color(0.8, 0.4, 0.95)})


func _place_props() -> void:
	# Crates under the gap jump.
	for k in 6:
		for level in 2:
			var p := Vector3(-124 + (k % 3) * 4.0 + level * 0.6, 0.03 + level * 1.2, 382 + (k / 3) * 8.0)
			prop_spawns.append({"scene": "crate", "xform": Transform3D(Basis.IDENTITY, p)})
	# Crate pyramid.
	var base := Vector3(-60, 0, 430)
	for level in 4:
		for k in 4 - level:
			var p := base + Vector3((k - (3 - level) * 0.5) * 1.25, 0.03 + level * 1.2, 0)
			prop_spawns.append({"scene": "crate", "xform": Transform3D(Basis.IDENTITY, p)})
	# Giant bowling pins.
	var pin_origin := Vector3(40, 0, 470)
	var row := 0
	var count := 0
	while row < 4:
		for k in row + 1:
			var p := pin_origin + Vector3((k - row * 0.5) * 2.2, 0, row * 2.0)
			prop_spawns.append({"scene": "bowling_pin", "xform": Transform3D(Basis.IDENTITY, p)})
			count += 1
		row += 1
	# Barrel wall.
	for k in 10:
		for level in 2:
			prop_spawns.append({"scene": "barrel", "xform": Transform3D(Basis.IDENTITY, Vector3(-10 + k * 1.3 + level * 0.65, 0.03 + level * 0.95, 490))})
	# Cone slalom.
	for k in 10:
		prop_spawns.append({"scene": "cone", "xform": Transform3D(Basis.IDENTITY, Vector3(95 - (k % 2) * 3.0, 0.03, 330 + k * 9.0))})
	# A few parked cars to jump over / crash into.
	for k in 4:
		prop_spawns.append({"scene": "parked_car", "xform": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-6.0 + k * 2.6, 0.03, 452))})
