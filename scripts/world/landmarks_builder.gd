class_name LandmarksBuilder
extends RefCounted
## One-off landmarks that make the map easier to read: highway exit gantries
## and a gas station by the east avenue.

var _roads: RoadBuilder
var _props_mat: Material
var _building_mat: Material


func _init(roads: RoadBuilder) -> void:
	_roads = roads
	_props_mat = load("res://assets/materials/props.tres")
	_building_mat = load("res://assets/materials/building.tres")


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	parent.add_child(root)
	_build_gantries(root)
	_build_gas_station(root, Vector3(198, 0, -32))


func _build_gantries(root: Node3D) -> void:
	var hw := _roads.highway
	var total := hw.total_length()
	# [fraction along the ring, sign above the right (true) or left carriageway, text]
	var signs := [
		[0.19, true, "EXIT  CITY  |  DIRT FIELDS"],
		[0.31, false, "EXIT  CITY  |  DIRT FIELDS"],
		[0.69, true, "EXIT  CITY  |  BEACH"],
		[0.81, false, "EXIT  CITY  |  BEACH"],
	]
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Gantries"
	var half := hw.width * 0.5
	for s in signs:
		var d: float = total * s[0]
		var i := _index_at(hw, d)
		var p := hw.points[i]
		var nxt := hw.points[(i + 1) % hw.points.size()]
		var dir := (nxt - p)
		dir.y = 0.0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP)
		var basis := Basis(right, Vector3.UP, -dir)
		var grey := Color(0.55, 0.57, 0.6)
		for side in [-1.0, 1.0]:
			var post: Vector3 = p + right * side * (half + 1.2)
			var xf := Transform3D(basis, post + Vector3.UP * 3.8)
			mb.add_box(xf, Vector3(0.5, 7.6, 0.5), grey)
			_collider(body, xf, Vector3(0.5, 7.6, 0.5))
		var beam := Transform3D(basis, p + Vector3.UP * 7.3)
		mb.add_box(beam, Vector3(hw.width + 3.0, 0.5, 0.5), grey)
		# Board above one carriageway, facing the traffic that drives towards it.
		var toward_right: bool = s[1]
		var off := right * (1.0 if toward_right else -1.0) * (half * 0.5 + 0.6)
		var face := -dir if toward_right else dir
		var board_basis := Basis(face.cross(Vector3.UP) * -1.0, Vector3.UP, face)
		var board := Transform3D(board_basis, p + off + Vector3.UP * 6.3)
		mb.add_box(board, Vector3(10.0, 2.6, 0.25), Color(0.1, 0.5, 0.3))
		var label := Label3D.new()
		label.text = s[2]
		label.font_size = 110
		label.pixel_size = 0.01
		label.modulate = Color(1, 1, 1)
		label.outline_size = 0
		label.double_sided = false
		label.transform = Transform3D(board_basis, board.origin + face * 0.14)
		root.add_child(label)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(_props_mat)
	body.add_child(mi)
	root.add_child(body)


func _index_at(road: RoadBuilder.Road, d: float) -> int:
	for i in road.dist.size():
		if road.dist[i] >= d:
			return i
	return 0


func _collider(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = xf
	body.add_child(cs)


func _build_gas_station(root: Node3D, c: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "GasStation"
	var mb := MeshBuilder.new()
	var shop := MeshBuilder.new()
	# Forecourt pad.
	var y := 0.02
	mb.add_quad(c + Vector3(-28, y, -16), c + Vector3(-28, y, 16), c + Vector3(28, y, 16), c + Vector3(28, y, -16), Color(0.62, 0.63, 0.66))
	# Canopy on four pillars.
	var red := Color(0.92, 0.25, 0.2)
	for px in [-9.0, 9.0]:
		for pz in [-5.0, 5.0]:
			var xf := Transform3D(Basis.IDENTITY, c + Vector3(px, 2.6, pz))
			mb.add_box(xf, Vector3(0.6, 5.2, 0.6), Color(0.92, 0.92, 0.9))
			_collider(body, xf, Vector3(0.6, 5.2, 0.6))
	var roof := Transform3D(Basis.IDENTITY, c + Vector3(0, 5.6, 0))
	mb.add_box(roof, Vector3(24, 0.8, 14), red, false, false)
	_collider(body, roof, Vector3(24, 0.8, 14))
	mb.add_box(Transform3D(Basis.IDENTITY, c + Vector3(0, 6.1, 0)), Vector3(24.2, 0.2, 14.2), Color(0.97, 0.97, 0.95))
	# Pump islands.
	for px in [-5.0, 5.0]:
		var island := Transform3D(Basis.IDENTITY, c + Vector3(px, 0.1, 0))
		mb.add_box(island, Vector3(1.4, 0.2, 7.0), Color(0.85, 0.85, 0.82))
		for pz in [-2.0, 2.0]:
			var pump := Transform3D(Basis.IDENTITY, c + Vector3(px, 1.0, pz))
			mb.add_box(pump, Vector3(0.9, 1.8, 0.7), Color(0.95, 0.95, 0.93))
			mb.add_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.5, pz)), Vector3(0.95, 0.5, 0.75), red)
			_collider(body, pump, Vector3(0.9, 1.8, 0.7))
	# Little shop behind the canopy.
	var shop_xf := Transform3D(Basis.IDENTITY, c + Vector3(0, 2.2, -13))
	shop.add_box(shop_xf, Vector3(16, 4.4, 5), Color(0.97, 0.9, 0.7), true)
	_collider(body, shop_xf, Vector3(16, 4.4, 5))
	# Tall price sign.
	var pole := Transform3D(Basis.IDENTITY, c + Vector3(24, 5, 12))
	mb.add_box(pole, Vector3(0.5, 10, 0.5), Color(0.5, 0.5, 0.55))
	_collider(body, pole, Vector3(0.5, 10, 0.5))
	mb.add_box(Transform3D(Basis.IDENTITY, c + Vector3(24, 10.5, 12)), Vector3(4.5, 3.0, 0.4), red)
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "GAS\n$1.99"
		label.font_size = 96
		label.pixel_size = 0.01
		label.modulate = Color(1, 1, 1)
		label.outline_size = 0
		label.double_sided = false
		label.position = c + Vector3(24, 10.5, 12 + 0.22 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		root.add_child(label)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(_props_mat)
	body.add_child(mi)
	var smi := MeshInstance3D.new()
	smi.mesh = shop.build_mesh(_building_mat)
	body.add_child(smi)
	root.add_child(body)
