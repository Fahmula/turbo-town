class_name StuntParkBuilder
extends RefCounted
## The stunt park south of the city: a big concrete pad full of ramps, a gap
## jump, a mega ramp, quarter/half pipes, bumps and things to knock over.
## Everything here is placed as spawn requests so it can later be moved into
## a hand-edited scene if wanted.

const PI_ROT := PI  # rotate a ramp 180° so it faces south (+Z)

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
	_place_ramps()
	_place_props()


func _ramp(pos: Vector3, yaw: float, shape: int, length: float, height: float, width: float, deck := 0.0, color := Color(1.0, 0.74, 0.22)) -> void:
	prop_spawns.append({
		"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, yaw), pos),
		"shape": shape, "length": length, "height": height, "width": width, "deck": deck, "color": color,
	})


func _build_pad(root: Node3D) -> void:
	var mn := MapLayout.PARK_MIN
	var mx := MapLayout.PARK_MAX
	var mb := MeshBuilder.new()
	var tile := 10.0
	var y := 0.03
	var x := mn.x
	while x < mx.x - 0.01:
		var z := mn.y
		while z < mx.y - 0.01:
			var dark := (int((x - mn.x) / tile) + int((z - mn.y) / tile)) % 2 == 0
			var col := Color(0.52, 0.54, 0.60) if dark else Color(0.58, 0.60, 0.66)
			var x1 := minf(x + tile, mx.x)
			var z1 := minf(z + tile, mx.y)
			mb.add_quad(Vector3(x, y, z), Vector3(x, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z), col)
			z += tile
		x += tile
	# Orange edge band.
	var band := 1.2
	var o := Color(1.0, 0.55, 0.15)
	mb.add_quad(Vector3(mn.x, y + 0.005, mn.y), Vector3(mn.x, y + 0.005, mn.y + band), Vector3(mx.x, y + 0.005, mn.y + band), Vector3(mx.x, y + 0.005, mn.y), o)
	mb.add_quad(Vector3(mn.x, y + 0.005, mx.y - band), Vector3(mn.x, y + 0.005, mx.y), Vector3(mx.x, y + 0.005, mx.y), Vector3(mx.x, y + 0.005, mx.y - band), o)
	var body := StaticBody3D.new()
	body.name = "Pad"
	body.set_meta("surface_grip", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(load("res://assets/materials/props.tres"))
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
	for sx in [-1.0, 1.0]:
		var xf := Transform3D(Basis.IDENTITY, Vector3(sx * 9.0, 4.0, z))
		mb.add_box(xf, Vector3(1.2, 8.0, 1.2), Color(0.95, 0.3, 0.25))
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.2, 8.0, 1.2)
		cs.shape = sh
		cs.transform = xf
		body.add_child(cs)
	mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.6, z)), Vector3(20.0, 2.4, 1.0), Color(0.2, 0.55, 0.95))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(load("res://assets/materials/props.tres"))
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
