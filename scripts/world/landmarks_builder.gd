class_name LandmarksBuilder
extends RefCounted
## One-off landmarks that make the map easier to read: highway exit gantries,
## a gas station by the east avenue, the airfield, the tunnel on the south
## avenue, the harbour and the lighthouse islet with its bridge.

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
	_build_airport(root)
	_build_tunnel(root)
	_build_harbor(root)
	_build_islet(root)


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


# ------------------------------------------------------------------ helpers --

func _label(root: Node3D, text: String, pos: Vector3, font_size: int, col: Color, yaw := 0.0, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.012
	l.outline_size = font_size / 7
	l.modulate = col
	l.outline_modulate = Color(0.08, 0.1, 0.18)
	l.position = pos
	l.rotation.y = yaw
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	root.add_child(l)
	return l


## A box that's both drawn and solid.
func _solid_box(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, size: Vector3, col: Color) -> void:
	mb.add_box(xf, size, col, false, false)
	_collider(body, xf, size)


func _finish(root: Node3D, body: StaticBody3D, mb: MeshBuilder, body_name: String) -> void:
	body.name = body_name
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(_props_mat)
	body.add_child(mi)
	root.add_child(body)


func _glow_material(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ airport --

func _build_airport(root: Node3D) -> void:
	var body := StaticBody3D.new()
	var mb := MeshBuilder.new()
	var a := MapLayout.RUNWAY_A
	var b := MapLayout.RUNWAY_B
	var hw := MapLayout.RUNWAY_WIDTH * 0.5
	var y := a.y + 0.02
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var asphalt := Color(0.24, 0.25, 0.28)
	var white := Color(0.95, 0.95, 0.93)
	# Runway (runs east-west).
	mb.add_quad(Vector3(a.x, y, a.z - hw), Vector3(a.x, y, a.z + hw), Vector3(b.x, y, b.z + hw), Vector3(b.x, y, b.z - hw), asphalt)
	_collider(body, Transform3D(Basis.IDENTITY, Vector3(mid.x, a.y - 0.5, mid.z)), Vector3(length, 1.0, hw * 2.0))
	var lift := Vector3.UP * 0.01
	for side in [-1.0, 1.0]:
		var z: float = a.z + side * (hw - 1.0)
		mb.add_quad(Vector3(a.x, y, z - 0.4) + lift, Vector3(a.x, y, z + 0.4) + lift, Vector3(b.x, y, z + 0.4) + lift, Vector3(b.x, y, z - 0.4) + lift, white)
	var x := a.x + 30.0
	while x < b.x - 40.0:
		mb.add_quad(Vector3(x, y, a.z - 0.5) + lift, Vector3(x, y, a.z + 0.5) + lift, Vector3(x + 12.0, y, a.z + 0.5) + lift, Vector3(x + 12.0, y, a.z - 0.5) + lift, white)
		x += 22.0
	for end in [a.x + 4.0, b.x - 22.0]:
		for k in 8:
			var z0: float = a.z - hw + 2.5 + k * (hw * 2.0 - 5.0) / 8.0
			mb.add_quad(Vector3(end, y, z0) + lift, Vector3(end, y, z0 + 1.6) + lift, Vector3(end + 18.0, y, z0 + 1.6) + lift, Vector3(end + 18.0, y, z0) + lift, white)
	for e in [[a.x + 30.0, -PI * 0.5, "09"], [b.x - 30.0, PI * 0.5, "27"]]:
		var num := _label(root, e[2], Vector3(e[0], y + 0.05, a.z), 600, white, e[1])
		num.rotation.x = -PI * 0.5
		num.outline_size = 0
	# Apron, taxiway.
	var ac := MapLayout.APRON_CENTER
	var asz := MapLayout.APRON_SIZE
	var concrete := Color(0.62, 0.63, 0.66)
	mb.add_quad(ac + Vector3(-asz.x * 0.5, 0.02, -asz.y * 0.5), ac + Vector3(-asz.x * 0.5, 0.02, asz.y * 0.5),
		ac + Vector3(asz.x * 0.5, 0.02, asz.y * 0.5), ac + Vector3(asz.x * 0.5, 0.02, -asz.y * 0.5), concrete)
	_collider(body, Transform3D(Basis.IDENTITY, ac + Vector3(0, -0.5, 0)), Vector3(asz.x, 1.0, asz.y))
	var tz0 := ac.z + asz.y * 0.5
	var tz1 := a.z - hw
	mb.add_quad(Vector3(ac.x - 10, y, tz0), Vector3(ac.x - 10, y, tz1), Vector3(ac.x + 10, y, tz1), Vector3(ac.x + 10, y, tz0), asphalt)
	_collider(body, Transform3D(Basis.IDENTITY, Vector3(ac.x, a.y - 0.5, (tz0 + tz1) * 0.5)), Vector3(20, 1.0, tz1 - tz0))
	mb.add_quad(Vector3(ac.x - 0.3, y + 0.01, tz0), Vector3(ac.x - 0.3, y + 0.01, tz1), Vector3(ac.x + 0.3, y + 0.01, tz1), Vector3(ac.x + 0.3, y + 0.01, tz0), Color(1.0, 0.8, 0.15))
	# Hangars along the back of the apron, open to the south.
	var back := ac.z - asz.y * 0.5
	for hx in [ac.x - 28.0, ac.x + 6.0]:
		var c := Vector3(hx, ac.y, back - 10.0)
		var wall := Color(0.82, 0.84, 0.88)
		_solid_box(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(0, 5, -9.5)), Vector3(26, 10, 1), wall)
		_solid_box(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(-12.5, 5, 0)), Vector3(1, 10, 20), wall)
		_solid_box(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(12.5, 5, 0)), Vector3(1, 10, 20), wall)
		_solid_box(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(0, 10.4, 0)), Vector3(27, 0.8, 21), Color(0.3, 0.5, 0.85))
		mb.add_quad(c + Vector3(-12, 0.03, -9), c + Vector3(-12, 0.03, 10), c + Vector3(12, 0.03, 10), c + Vector3(12, 0.03, -9), Color(0.5, 0.52, 0.56))
	_label(root, "TURBO AIRFIELD", Vector3(ac.x - 11.0, ac.y + 12.6, back - 10.0), 220, Color(1.0, 0.85, 0.25), 0.0)
	# Control tower at the east end of the apron.
	var tw := Vector3(ac.x + asz.x * 0.5 - 6.0, ac.y, back - 6.0)
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 9, 0)), Vector3(3.5, 18, 3.5), Color(0.9, 0.9, 0.88))
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 18.4, 0)), Vector3(8, 0.8, 8), Color(0.9, 0.9, 0.88))
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 20.4, 0)), Vector3(7, 3.2, 7), Color(0.18, 0.28, 0.4))
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 22.3, 0)), Vector3(8.4, 0.6, 8.4), Color(0.92, 0.3, 0.25))
	# Windsock.
	var ws := Vector3(b.x - 40.0, a.y, a.z - hw - 12.0)
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, ws + Vector3(0, 3, 0)), Vector3(0.25, 6, 0.25), Color(0.8, 0.8, 0.8))
	mb.add_prism(ws + Vector3(0.3, 5.7, 0), 0.0, 0.0, 0.0, 6, Color.WHITE, false)
	mb.add_box(Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, 0.0), ws + Vector3(1.6, 5.7, 0)), Vector3(0.7, 2.6, 0.7), Color(1.0, 0.45, 0.1))
	# Parked planes on the apron and one at the runway's west end.
	_plane(mb, body, ac + Vector3(-28.0, 0, 2.0), PI, Color(0.95, 0.95, 0.97), Color(0.9, 0.25, 0.2))
	_plane(mb, body, ac + Vector3(6.0, 0, 3.0), PI * 0.85, Color(0.95, 0.85, 0.3), Color(0.2, 0.4, 0.85))
	_plane(mb, body, Vector3(a.x + 26.0, a.y, a.z + 4.0), -PI * 0.5, Color(0.3, 0.75, 0.45), Color(0.97, 0.97, 0.95))
	_finish(root, body, mb, "Airport")


## A small propeller plane facing `yaw` (0 = nose to -Z).
func _plane(mb: MeshBuilder, body: StaticBody3D, at: Vector3, yaw: float, col: Color, stripe: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := func(p: Vector3) -> Transform3D: return Transform3D(b, at + b * p)
	_solid_box(mb, body, xf.call(Vector3(0, 1.6, 0)), Vector3(1.6, 1.6, 8.0), col)
	mb.add_box(xf.call(Vector3(0, 2.15, -1.6)), Vector3(1.4, 0.6, 1.8), Color(0.2, 0.3, 0.45))
	mb.add_box(xf.call(Vector3(0, 1.6, 0.2)), Vector3(1.65, 0.3, 7.0), stripe)
	_solid_box(mb, body, xf.call(Vector3(0, 1.9, -0.6)), Vector3(11.0, 0.22, 1.7), col)
	_solid_box(mb, body, xf.call(Vector3(0, 1.9, 3.6)), Vector3(4.0, 0.18, 1.0), col)
	_solid_box(mb, body, xf.call(Vector3(0, 2.9, 3.7)), Vector3(0.2, 1.8, 1.2), stripe)
	mb.add_box(xf.call(Vector3(0, 1.6, -4.15)), Vector3(0.5, 0.5, 0.3), Color(0.15, 0.15, 0.17))
	mb.add_box(xf.call(Vector3(0, 1.6, -4.35)), Vector3(3.0, 0.25, 0.08), Color(0.15, 0.15, 0.17))
	for p in [Vector3(-1.4, 0.4, -0.8), Vector3(1.4, 0.4, -0.8), Vector3(0, 0.35, 3.2)]:
		mb.add_box(xf.call(p), Vector3(0.25, 0.7, 0.7), Color(0.1, 0.1, 0.11))
		mb.add_box(xf.call(p + Vector3(0, 0.6, 0)), Vector3(0.12, 0.8, 0.12), Color(0.5, 0.5, 0.52))


# ------------------------------------------------------------------- tunnel --

func _build_tunnel(root: Node3D) -> void:
	var z0 := MapLayout.TUNNEL_Z0
	var z1 := MapLayout.TUNNEL_Z1
	var hw := MapLayout.TUNNEL_HALF_WIDTH
	var hill := MapLayout.TUNNEL_HILL_HALF_WIDTH
	var wall_h := 4.8
	var arch := 2.0
	var mb := MeshBuilder.new()
	# Inside: walls and an arched ceiling, facing the tunnel's axis.
	var inner: Array[Vector2] = [Vector2(-hw, -0.6), Vector2(-hw, wall_h)]
	for k in range(1, 10):
		var ang := PI - PI * k / 10.0
		inner.append(Vector2(cos(ang) * hw, wall_h + sin(ang) * arch))
	inner.append(Vector2(hw, wall_h))
	inner.append(Vector2(hw, -0.6))
	for k in inner.size() - 1:
		var p0 := inner[k]
		var p1 := inner[k + 1]
		var m := (p0 + p1) * 0.5
		var col := Color(0.78, 0.78, 0.75) if m.y > 1.2 else Color(0.95, 0.75, 0.2)
		StuntParkBuilder._quad(mb, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1),
			Vector3(-m.x, 3.0 - m.y, 0), col)
	# Outside: a grassy hill over the tube.
	var outer := func(x: float) -> float:
		var t := clampf(absf(x) / hill, 0.0, 1.0)
		return maxf(11.0 * pow(1.0 - t * t, 1.3), (wall_h + arch + 1.5) * (1.0 - smoothstep(hw + 1.0, hw + 6.0, absf(x))))
	var steps := 32
	for k in steps:
		var x0 := -hill + 2.0 * hill * k / steps
		var x1 := -hill + 2.0 * hill * (k + 1) / steps
		var y0: float = outer.call(x0)
		var y1: float = outer.call(x1)
		var g := Color(0.38, 0.64, 0.3) if (k / 3) % 2 == 0 else Color(0.42, 0.68, 0.32)
		StuntParkBuilder._quad(mb, Vector3(x0, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y0, z1),
			Vector3((x0 + x1) * 0.5, 6.0, 0), g)
		# The hill's ends, around the tunnel mouth.
		var b0 := _tunnel_floor(x0, hw, wall_h, arch)
		var b1 := _tunnel_floor(x1, hw, wall_h, arch)
		for e: Array in [[z0, -1.0], [z1, 1.0]]:
			var z: float = e[0]
			StuntParkBuilder._quad(mb, Vector3(x0, b0, z), Vector3(x1, b1, z), Vector3(x1, y1, z), Vector3(x0, y0, z),
				Vector3(0, 0, e[1]), Color(0.58, 0.56, 0.52))
	var node := mb.build_node("Tunnel", _props_mat, true, 1.0)
	root.add_child(node)
	# Concrete portals and signs.
	var frame := MeshBuilder.new()
	for z in [z0, z1]:
		var s := -1.0 if z == z0 else 1.0
		frame.add_box(Transform3D(Basis.IDENTITY, Vector3(-hw - 0.6, 3.6, z + s * 0.3)), Vector3(1.2, 7.2, 0.6), Color(0.85, 0.85, 0.82))
		frame.add_box(Transform3D(Basis.IDENTITY, Vector3(hw + 0.6, 3.6, z + s * 0.3)), Vector3(1.2, 7.2, 0.6), Color(0.85, 0.85, 0.82))
		frame.add_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_h + arch + 0.8, z + s * 0.3)), Vector3(hw * 2.0 + 2.4, 1.6, 0.6), Color(0.85, 0.85, 0.82))
		_label(root, "TURBO TUNNEL", Vector3(0, wall_h + arch + 0.8, z + s * 0.62), 110, Color(1.0, 0.85, 0.25), 0.0 if s > 0.0 else PI)
	var fmi := MeshInstance3D.new()
	fmi.mesh = frame.build_mesh(_props_mat)
	root.add_child(fmi)
	# Strip lights along the ceiling.
	var lights := MeshBuilder.new()
	var z := z0 + 3.0
	while z < z1 - 2.0:
		lights.add_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_h + arch - 0.12, z)), Vector3(0.5, 0.12, 2.2), Color.WHITE)
		z += 6.0
	var lmi := MeshInstance3D.new()
	lmi.mesh = lights.build_mesh(_glow_material(Color(1.0, 0.92, 0.75), 3.0))
	root.add_child(lmi)
	# A few real lights so the inside isn't dark (on day and night).
	for k in 3:
		var light := OmniLight3D.new()
		light.position = Vector3(0, wall_h + arch - 0.8, lerpf(z0 + 8.0, z1 - 8.0, k / 2.0))
		light.omni_range = 16.0
		light.light_energy = 1.6
		light.light_color = Color(1.0, 0.9, 0.72)
		root.add_child(light)


## Bottom of the hill's end wall at x: the top of the tunnel mouth, or the ground.
func _tunnel_floor(x: float, hw: float, wall_h: float, arch: float) -> float:
	if absf(x) >= hw:
		return -0.6
	return wall_h + sqrt(maxf(1.0 - (x / hw) * (x / hw), 0.0)) * arch


# ------------------------------------------------------------------ harbour --

func _build_harbor(root: Node3D) -> void:
	var body := StaticBody3D.new()
	var mb := MeshBuilder.new()
	var qa := MapLayout.HARBOR_QUAY_A
	var qb := MapLayout.HARBOR_QUAY_B
	var y := qa.y
	var edge := qa.x - 18.0
	var inner := qa.x + 18.0
	var concrete := Color(0.66, 0.67, 0.68)
	mb.add_quad(Vector3(edge, y, qa.z), Vector3(edge, y, qb.z), Vector3(inner, y, qb.z), Vector3(inner, y, qa.z), concrete)
	_collider(body, Transform3D(Basis.IDENTITY, Vector3((edge + inner) * 0.5, y - 0.5, (qa.z + qb.z) * 0.5)), Vector3(inner - edge, 1.0, absf(qb.z - qa.z)))
	# Quay wall down into the water, with a yellow edge.
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, Vector3(edge - 0.6, y - 2.4, (qa.z + qb.z) * 0.5)), Vector3(1.2, 5.0, absf(qb.z - qa.z)), Color(0.55, 0.55, 0.56))
	mb.add_box(Transform3D(Basis.IDENTITY, Vector3(edge + 0.3, y + 0.06, (qa.z + qb.z) * 0.5)), Vector3(0.6, 0.12, absf(qb.z - qa.z)), Color(1.0, 0.8, 0.15))
	# Wooden piers with moored boats.
	var wood := Color(0.55, 0.4, 0.26)
	var boat_cols := [[Color(0.9, 0.25, 0.2), Color(0.97, 0.97, 0.95)], [Color(0.2, 0.45, 0.85), Color(0.97, 0.97, 0.95)], [Color(0.97, 0.97, 0.95), Color(0.95, 0.6, 0.15)]]
	var k := 0
	for pz in [qa.z - 15.0, (qa.z + qb.z) * 0.5, qb.z + 15.0]:
		var x0 := edge - 46.0
		_solid_box(mb, body, Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y - 0.2, pz)), Vector3(edge - x0, 0.4, 6.0), wood)
		var px := x0 + 2.0
		while px < edge:
			for side in [-2.6, 2.6]:
				mb.add_box(Transform3D(Basis.IDENTITY, Vector3(px, y - 3.0, pz + side)), Vector3(0.4, 5.6, 0.4), wood.darkened(0.25))
			px += 6.0
		_boat(mb, body, Vector3(x0 + 14.0, MapLayout.SEA_LEVEL, pz + 6.5), boat_cols[k][0], boat_cols[k][1], 9.0)
		_boat(mb, body, Vector3(x0 + 30.0, MapLayout.SEA_LEVEL, pz - 6.5), boat_cols[(k + 1) % 3][0], boat_cols[(k + 1) % 3][1], 7.0)
		k += 1
	# Crane.
	var cr := Vector3(qa.x - 10.0, y, (qa.z + qb.z) * 0.5 - 10.0)
	var yellow := Color(1.0, 0.75, 0.1)
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, cr + Vector3(0, 12, 0)), Vector3(2.2, 24, 2.2), yellow)
	mb.add_box(Transform3D(Basis.IDENTITY, cr + Vector3(-12, 24.6, 0)), Vector3(34, 1.4, 1.6), yellow)
	mb.add_box(Transform3D(Basis.IDENTITY, cr + Vector3(5, 24.0, 0)), Vector3(4, 3, 2.4), Color(0.4, 0.42, 0.45))
	mb.add_box(Transform3D(Basis.IDENTITY, cr + Vector3(1.5, 26.2, 0)), Vector3(2.4, 2.2, 2.4), Color(0.25, 0.35, 0.5))
	mb.add_box(Transform3D(Basis.IDENTITY, cr + Vector3(-24, 17.0, 0)), Vector3(0.12, 14, 0.12), Color(0.2, 0.2, 0.22))
	mb.add_box(Transform3D(Basis.IDENTITY, cr + Vector3(-24, 9.6, 0)), Vector3(1.4, 0.8, 1.4), Color(0.9, 0.3, 0.2))
	# Container stacks.
	var cols := [Color(0.85, 0.25, 0.2), Color(0.2, 0.5, 0.85), Color(0.3, 0.7, 0.35), Color(0.95, 0.65, 0.15), Color(0.6, 0.35, 0.7)]
	var ci := 0
	for row in 3:
		for col in 4:
			var height := 1 + (row + col) % 3
			for level in height:
				var c := Vector3(inner - 6.0 - row * 3.2, y + 1.3 + level * 2.6, qa.z - 12.0 - col * 7.0)
				_solid_box(mb, body, Transform3D(Basis.IDENTITY, c), Vector3(2.5, 2.6, 6.2), cols[ci % cols.size()])
				ci += 1
	_label(root, "TURBO HARBOUR", Vector3(inner - 2.0, y + 9.0, (qa.z + qb.z) * 0.5 + 18.0), 200, Color(1.0, 0.85, 0.25), PI * 0.5, true)
	_finish(root, body, mb, "Harbor")


## A simple moored boat (hull + cabin) floating at `at` (water line).
func _boat(mb: MeshBuilder, body: StaticBody3D, at: Vector3, hull: Color, cabin: Color, length: float) -> void:
	var w := length * 0.36
	mb.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)), Vector3(length * 0.8, 1.4, w), hull)
	mb.add_box(Transform3D(Basis.IDENTITY, at + Vector3(-length * 0.45, 0.35, 0)), Vector3(length * 0.2, 1.1, w * 0.6), hull)
	mb.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.92, 0)), Vector3(length * 0.82, 0.06, w * 1.02), Color(0.9, 0.9, 0.88))
	mb.add_box(Transform3D(Basis.IDENTITY, at + Vector3(length * 0.1, 1.6, 0)), Vector3(length * 0.32, 1.3, w * 0.7), cabin)
	mb.add_box(Transform3D(Basis.IDENTITY, at + Vector3(length * 0.1, 1.75, 0)), Vector3(length * 0.33, 0.45, w * 0.72), Color(0.2, 0.3, 0.45))
	_collider(body, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), Vector3(length, 2.2, w))


# ------------------------------------------------------- islet and bridge --

func _build_islet(root: Node3D) -> void:
	var t: TerrainBuilder = _roads._terrain
	var body := StaticBody3D.new()
	var mb := MeshBuilder.new()
	# Lighthouse: banded tower, gallery, lamp room, roof.
	var c := MapLayout.ISLET_CENTER
	var base := Vector3(c.x, t.height_at(c.x, c.y), c.y)
	var bands := 6
	for k in bands:
		var r0 := lerpf(2.6, 1.8, float(k) / bands)
		var r1 := lerpf(2.6, 1.8, float(k + 1) / bands)
		mb.add_prism(base + Vector3.UP * (k * 2.8), r0, r1, 2.8, 12, Color(0.95, 0.25, 0.2) if k % 2 == 0 else Color(0.97, 0.97, 0.95), false)
	_collider(body, Transform3D(Basis.IDENTITY, base + Vector3.UP * 8.4), Vector3(4.4, 16.8, 4.4))
	mb.add_prism(base + Vector3.UP * 16.8, 2.8, 2.8, 0.4, 12, Color(0.25, 0.27, 0.3))
	mb.add_prism(base + Vector3.UP * 19.6, 1.9, 0.2, 2.0, 12, Color(0.9, 0.25, 0.2))
	var lamp := MeshInstance3D.new()
	var lm := MeshBuilder.new()
	lm.add_prism(base + Vector3.UP * 17.2, 1.5, 1.5, 2.4, 12, Color.WHITE)
	lamp.mesh = lm.build_mesh(_glow_material(Color(1.0, 0.9, 0.5), 2.5))
	lamp.name = "LighthouseLamp"
	root.add_child(lamp)
	var beam := LighthouseBeam.new()
	beam.name = "LighthouseBeam"
	beam.position = base + Vector3.UP * 18.4
	root.add_child(beam)
	# Keeper's cottage.
	var hx := base + Vector3(10.0, 0, 7.0)
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 1.6, 0)), Vector3(7, 3.2, 5), Color(0.97, 0.93, 0.85))
	_solid_box(mb, body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 3.5, 0)), Vector3(7.6, 0.6, 5.6), Color(0.3, 0.45, 0.7))
	_finish(root, body, mb, "Lighthouse")
	_label(root, "LIGHTHOUSE ISLAND", base + Vector3(0, 24.0, 0), 160, Color(1.0, 0.85, 0.25), 0.0, true)

	# The bridge from the beach: an arched deck on pillars with railings.
	var bmb := MeshBuilder.new()
	var hw := MapLayout.BRIDGE_WIDTH * 0.5
	var xe := MapLayout.BRIDGE_EAST_X
	var xw := MapLayout.BRIDGE_WEST_X
	var ye := t.height_at(xe, 0.0) + 0.05
	var yw := t.height_at(xw, 0.0) + 0.05
	var deck_y := func(x: float) -> float:
		var u := (x - xe) / (xw - xe)
		return lerpf(ye, yw, u) + 3.2 * sin(PI * u)
	var segs := 40
	var deck := Color(0.5, 0.52, 0.56)
	var rail := Color(0.95, 0.95, 0.95)
	for k in segs:
		var x0 := lerpf(xe, xw, float(k) / segs)
		var x1 := lerpf(xe, xw, float(k + 1) / segs)
		var y0: float = deck_y.call(x0)
		var y1: float = deck_y.call(x1)
		StuntParkBuilder._quad(bmb, Vector3(x0, y0, -hw), Vector3(x0, y0, hw), Vector3(x1, y1, hw), Vector3(x1, y1, -hw), Vector3.UP, deck)
		StuntParkBuilder._quad(bmb, Vector3(x0, y0 - 0.7, -hw), Vector3(x1, y1 - 0.7, -hw), Vector3(x1, y1 - 0.7, hw), Vector3(x0, y0 - 0.7, hw), Vector3.DOWN, deck.darkened(0.3))
		for side in [-1.0, 1.0]:
			var z: float = side * hw
			StuntParkBuilder._quad(bmb, Vector3(x0, y0 - 0.7, z), Vector3(x1, y1 - 0.7, z), Vector3(x1, y1, z), Vector3(x0, y0, z), Vector3(0, 0, side), deck.darkened(0.15))
			# Solid railing (both faces) so cars bounce off instead of falling in.
			var zi: float = z - side * 0.2
			StuntParkBuilder._quad(bmb, Vector3(x0, y0, zi), Vector3(x1, y1, zi), Vector3(x1, y1 + 1.0, zi), Vector3(x0, y0 + 1.0, zi), Vector3(0, 0, -side), rail)
			StuntParkBuilder._quad(bmb, Vector3(x0, y0, z), Vector3(x0, y0 + 1.0, z), Vector3(x1, y1 + 1.0, z), Vector3(x1, y1, z), Vector3(0, 0, side), rail)
			StuntParkBuilder._quad(bmb, Vector3(x0, y0 + 1.0, zi), Vector3(x1, y1 + 1.0, zi), Vector3(x1, y1 + 1.0, z), Vector3(x0, y0 + 1.0, z), Vector3.UP, rail)
	var bridge := bmb.build_node("IsletBridge", _props_mat, true, 1.0)
	root.add_child(bridge)
	var pillars := MeshBuilder.new()
	var px := xe - 14.0
	while px > xw + 8.0:
		var py: float = deck_y.call(px)
		pillars.add_box(Transform3D(Basis.IDENTITY, Vector3(px, (py - 0.7 - 7.0) * 0.5, 0)), Vector3(1.6, py - 0.7 + 7.0, MapLayout.BRIDGE_WIDTH * 0.7), Color(0.7, 0.7, 0.68))
		px -= 16.0
	var pmi := MeshInstance3D.new()
	pmi.mesh = pillars.build_mesh(_props_mat)
	root.add_child(pmi)
