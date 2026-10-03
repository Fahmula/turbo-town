@tool
class_name LandmarksBuilder
extends RefCounted
## One-off landmarks that make the map easier to read: highway sign
## gantries, a gas station by the east avenue, the airfield, the tunnel on the
## south avenue, the harbour and the lighthouse islet with its bridge.
## ART_BIBLE.md §15-§17: bevelled and smooth parts on the shared
## street props, concrete and paving materials. Colliders are the same boxes
## as before, so the landmarks drive exactly as they did.

var _roads: RoadBuilder
var _props_mat: Material
var _concrete_mat: Material
var _paving_mat: Material

const PAINTED := StreetKit.PAINTED
const METAL := StreetKit.METAL
const CONCRETE := StreetKit.CONCRETE
const RUBBER := StreetKit.RUBBER
const GLASS := StreetKit.GLASS
const SIGN := StreetKit.SIGN
const WOOD := StreetKit.WOOD
const GLOW := 14.0 / 15.0
const LAMP := StreetKit.LAMP
const STEEL := Color(0.62, 0.64, 0.66, METAL)
const WHITE := Color(0.88, 0.87, 0.84, PAINTED)


func _init(roads: RoadBuilder) -> void:
	_roads = roads
	_props_mat = StreetKit.material()
	_concrete_mat = load("res://assets/materials/env/concrete.tres")
	_paving_mat = load("res://assets/materials/env/paving.tres")


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


# ------------------------------------------------------------------ helpers --

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


## A bevelled box that's both drawn and solid.
func _solid(mb: MeshBuilder, body: StaticBody3D, xf: Transform3D, size: Vector3, col: Color, bevel := 0.04, bottom := Color(0, 0, 0, -1)) -> void:
	mb.add_bevel_box(xf, size, bevel, col, bottom, false)
	_collider(body, xf, size)


func _mesh(parent: Node3D, mb: MeshBuilder, mat: Material, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	mi.mesh = mb.build_mesh(mat)
	parent.add_child(mi)
	return mi


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


## A flat quad on the ground (paving.gdshader colour and surface in `col`).
func _ground_quad(mb: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), col)


## A tapered steel strut from a to b (bevelled box turned along the line).
func _strut(mb: MeshBuilder, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mb.add_bevel_box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, a.distance_to(b), w), w * 0.2, col)


# ----------------------------------------------------------------- gantries --

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
	var conc := MeshBuilder.new()
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
		# Galvanised posts on concrete footings.
		for side: float in [-1.0, 1.0]:
			var post: Vector3 = p + right * side * (half + 1.2)
			mb.add_lathe(Transform3D(basis, post), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.06),
				Vector2(0.22, 0.12), Vector2(0.19, 7.7), Vector2(0.0, 7.75)]), 10, PackedColorArray([STEEL]), 40.0)
			conc.add_bevel_box(Transform3D(basis, post + Vector3.UP * 0.1), Vector3(1.3, 0.5, 1.3), 0.05, Color(ArtPalette.CONCRETE, 0.0))
			_collider(body, Transform3D(basis, post + Vector3.UP * 3.8), Vector3(0.5, 7.6, 0.5))
		# Box truss: four chords and zig-zag bracing on the front and back.
		var span := hw.width + 3.0
		var ys := [6.95, 7.6]
		for y: float in ys:
			for zo: float in [-0.32, 0.32]:
				mb.add_bevel_box(Transform3D(basis, p + Vector3.UP * y - dir * zo), Vector3(span, 0.12, 0.12), 0.02, STEEL)
		var bays := int(span / 1.3)
		for k in bays:
			var xa := -span * 0.5 + span * k / bays
			var xb := -span * 0.5 + span * (k + 1) / bays
			var lo: float = ys[0] if k % 2 == 0 else ys[1]
			var hi: float = ys[1] if k % 2 == 0 else ys[0]
			for zo: float in [-0.32, 0.32]:
				_strut(mb, p + right * xa + Vector3.UP * lo - dir * zo, p + right * xb + Vector3.UP * hi - dir * zo, 0.06, STEEL)
		# Sign: green with a white border, facing the traffic that drives towards it.
		var toward_right: bool = s[1]
		var off := right * (1.0 if toward_right else -1.0) * (half * 0.5 + 0.6)
		var face := -dir if toward_right else dir
		var board_basis := Basis(face.cross(Vector3.UP) * -1.0, Vector3.UP, face)
		var board := Transform3D(board_basis, p + off + Vector3.UP * 6.3)
		mb.add_bevel_box(board, Vector3(10.2, 2.8, 0.12), 0.03, Color(0.9, 0.9, 0.88, StreetKit.RETRO))
		mb.add_bevel_box(board * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.03)), Vector3(9.9, 2.5, 0.1), 0.02, Color(0.118, 0.42, 0.235, StreetKit.RETRO))
		mb.add_bevel_box(board * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.09)), Vector3(10.2, 2.8, 0.06), 0.02, Color(0.45, 0.47, 0.48, METAL))
		var label := Label3D.new()
		label.text = s[2]
		label.font_size = 110
		label.pixel_size = 0.01
		label.modulate = Color(0.95, 0.95, 0.93)
		label.outline_size = 0
		label.double_sided = false
		label.transform = Transform3D(board_basis, board.origin + face * 0.1)
		root.add_child(label)
	_mesh(body, mb, _props_mat)
	_mesh(body, conc, _concrete_mat)
	root.add_child(body)


# -------------------------------------------------------------- gas station --

func _build_gas_station(root: Node3D, c: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "GasStation"
	var mb := MeshBuilder.new()
	var ground := MeshBuilder.new()
	var y := 0.02
	# Concrete forecourt with an asphalt apron toward the road.
	_ground_quad(ground, c.x - 28, c.z - 16, c.x + 28, c.z + 16, y, Color(ArtPalette.PAVING, 0.5))
	var red := Color(0.72, 0.16, 0.12, PAINTED)
	# Canopy: slim white columns, a deep fascia with a red band, lights underneath.
	for px: float in [-9.0, 9.0]:
		for pz: float in [-5.0, 5.0]:
			var xf := Transform3D(Basis.IDENTITY, c + Vector3(px, 2.6, pz))
			mb.add_bevel_box(xf, Vector3(0.5, 5.2, 0.5), 0.05, WHITE, Color(0.6, 0.6, 0.6, PAINTED))
			_collider(body, xf, Vector3(0.6, 5.2, 0.6))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 0.25, pz)), Vector3(0.8, 0.5, 0.8), 0.04, Color(ArtPalette.CONCRETE, CONCRETE))
	var roof := Transform3D(Basis.IDENTITY, c + Vector3(0, 5.6, 0))
	mb.add_bevel_box(roof, Vector3(24, 0.8, 14), 0.08, WHITE, Color(0.55, 0.55, 0.55, PAINTED), false)
	_collider(body, roof, Vector3(24, 0.8, 14))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(0, 5.55, 0)), Vector3(24.1, 0.3, 14.1), 0.03, red)
	for px: float in [-6.0, -2.0, 2.0, 6.0]:
		for pz: float in [-3.5, 0.0, 3.5]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 5.19, pz)), Vector3(1.2, 0.03, 0.6), 0.01, Color(0.95, 0.95, 0.92, LAMP))
	_label(root, "TURBO FUEL", c + Vector3(0, 5.6, 7.07), 130, Color(0.95, 0.95, 0.93))
	# Pump islands.
	for px: float in [-5.0, 5.0]:
		var island := Transform3D(Basis.IDENTITY, c + Vector3(px, 0.1, 0))
		mb.add_bevel_box(island, Vector3(1.4, 0.2, 7.0), 0.04, Color(ArtPalette.CONCRETE, CONCRETE))
		for pz: float in [-2.0, 2.0]:
			var pump := Transform3D(Basis.IDENTITY, c + Vector3(px, 1.0, pz))
			var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
			mb.add_bevel_box(pump, Vector3(0.85, 1.8, 0.65), 0.1, Color(WHITE, StreetKit.GLOSS), Color(0.6, 0.6, 0.58, StreetKit.GLOSS))
			_collider(body, pump, Vector3(0.9, 1.8, 0.7))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.55, pz)), Vector3(0.88, 0.45, 0.68), 0.08, Color(red, StreetKit.GLOSS))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 0.14, pz)), Vector3(0.9, 0.18, 0.7), 0.03, Color(0.2, 0.2, 0.21, StreetKit.PAINTED))
			for side: float in [-1.0, 1.0]:
				# Display window (dark glass with a lit readout) and a grade label.
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.28, pz + side * 0.33)), Vector3(0.5, 0.26, 0.02), 0.005, Color(0.08, 0.1, 0.12, GLASS), Color(0, 0, 0, -1), false)
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.3, pz + side * 0.336)), Vector3(0.34, 0.1, 0.006), 0.002, Color(0.5, 0.75, 0.35, GLOW), Color(0, 0, 0, -1), false)
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px - 0.2, 0.85, pz + side * 0.33)), Vector3(0.14, 0.2, 0.02), 0.004, Color(0.2, 0.4, 0.7, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px + 0.2, 0.85, pz + side * 0.33)), Vector3(0.14, 0.2, 0.02), 0.004, Color(0.72, 0.16, 0.12, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
				# Nozzle holster on the end, a hose sagging to a nozzle.
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px + side * 0.45, 0.9, pz)), Vector3(0.08, 0.3, 0.2), 0.012, Color(0.15, 0.15, 0.16, RUBBER))
				var hose := PackedVector3Array([c + Vector3(px + side * 0.3, 1.15, pz - 0.2), c + Vector3(px + side * 0.55, 1.0, pz - 0.18), c + Vector3(px + side * 0.62, 0.7, pz - 0.1),
					c + Vector3(px + side * 0.52, 0.45, pz), c + Vector3(px + side * 0.5, 0.78, pz)])
				StreetKit.tube_path(mb, hose, PackedFloat32Array([0.025]), 6, Color(0.08, 0.08, 0.09, StreetKit.RUBBER), false)
				StreetKit.rod(mb, c + Vector3(px + side * 0.5, 0.78, pz), c + Vector3(px + side * 0.5, 1.0, pz + 0.04), 0.022, 0.016, 6, gal)
	# Shop: a single-storey building from the building kit.
	var kit := BuildingKit.new(ground, body)
	kit.rng.seed = 77
	kit.add_building(Rect2(c.x - 8, c.z - 15.5, 16, 5), y, BuildingKit.GROUND_FLOOR,
		{"style": BuildingKit.Style.STUCCO, "wall": ArtPalette.STUCCO_WALLS[4], "trim": ArtPalette.TRIM_WHITE,
		"stone": ArtPalette.LIMESTONE_WALLS[2], "seed": 0.37, "shops": true, "fascia": Color(0.62, 0.15, 0.12)})
	# Price sign on a pole.
	var pole := Transform3D(Basis.IDENTITY, c + Vector3(24, 5, 12))
	mb.add_lathe(Transform3D(Basis.IDENTITY, c + Vector3(24, 0, 12)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.0),
		Vector2(0.4, 0.3), Vector2(0.22, 0.4), Vector2(0.2, 10.0), Vector2(0.0, 10.0)]), 10, PackedColorArray([STEEL]), 40.0)
	_collider(body, pole, Vector3(0.5, 10, 0.5))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(24, 10.5, 12)), Vector3(4.5, 3.0, 0.4), 0.06, red)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(24, 10.15, 12)), Vector3(4.0, 1.6, 0.44), 0.02, Color(0.12, 0.13, 0.14, SIGN))
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "GAS\n$1.99"
		label.font_size = 96
		label.pixel_size = 0.01
		label.modulate = Color(1, 1, 1)
		label.outline_size = 0
		label.double_sided = false
		label.position = c + Vector3(24, 10.5, 12 + 0.23 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		root.add_child(label)
	_mesh(body, mb, _props_mat)
	_mesh(body, kit.clutter, _props_mat)
	_mesh(body, kit.facade, load("res://assets/materials/env/facade.tres"))
	_mesh(body, ground, _paving_mat)
	root.add_child(body)


# ------------------------------------------------------------------ airport --

func _build_airport(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Airport"
	var mb := MeshBuilder.new()
	var ground := MeshBuilder.new()
	var a := MapLayout.RUNWAY_A
	var b := MapLayout.RUNWAY_B
	var hw := MapLayout.RUNWAY_WIDTH * 0.5
	var y := a.y + 0.02
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var asphalt := Color(ArtPalette.ASPHALT_DARK, 0.25)
	var white := Color(ArtPalette.ROAD_WHITE, 0.0)
	# Runway (runs east-west).
	_ground_quad(ground, a.x, a.z - hw, b.x, a.z + hw, y, asphalt)
	_collider(body, Transform3D(Basis.IDENTITY, Vector3(mid.x, a.y - 0.5, mid.z)), Vector3(length, 1.0, hw * 2.0))
	var ly := y + 0.01
	for side: float in [-1.0, 1.0]:
		var z: float = a.z + side * (hw - 1.0)
		_ground_quad(ground, a.x, z - 0.4, b.x, z + 0.4, ly, white)
	var x := a.x + 30.0
	while x < b.x - 40.0:
		_ground_quad(ground, x, a.z - 0.5, x + 12.0, a.z + 0.5, ly, white)
		x += 22.0
	for end: float in [a.x + 4.0, b.x - 22.0]:
		for k in 8:
			var z0: float = a.z - hw + 2.5 + k * (hw * 2.0 - 5.0) / 8.0
			_ground_quad(ground, end, z0, end + 18.0, z0 + 1.6, ly, white)
	for e in [[a.x + 30.0, -PI * 0.5, "09"], [b.x - 30.0, PI * 0.5, "27"]]:
		var num := _label(root, e[2], Vector3(e[0], y + 0.05, a.z), 600, ArtPalette.ROAD_WHITE, e[1])
		num.rotation.x = -PI * 0.5
		num.outline_size = 0
	# Apron (concrete), taxiway (asphalt with a yellow centre line).
	var ac := MapLayout.APRON_CENTER
	var asz := MapLayout.APRON_SIZE
	_ground_quad(ground, ac.x - asz.x * 0.5, ac.z - asz.y * 0.5, ac.x + asz.x * 0.5, ac.z + asz.y * 0.5, ac.y + 0.02, Color(ArtPalette.PAVING, 0.5))
	_collider(body, Transform3D(Basis.IDENTITY, ac + Vector3(0, -0.5, 0)), Vector3(asz.x, 1.0, asz.y))
	var tz0 := ac.z + asz.y * 0.5
	var tz1 := a.z - hw
	_ground_quad(ground, ac.x - 10, tz0, ac.x + 10, tz1, y, asphalt)
	_collider(body, Transform3D(Basis.IDENTITY, Vector3(ac.x, a.y - 0.5, (tz0 + tz1) * 0.5)), Vector3(20, 1.0, tz1 - tz0))
	_ground_quad(ground, ac.x - 0.3, tz0, ac.x + 0.3, tz1, ly, Color(ArtPalette.ROAD_YELLOW, 0.0))
	# Edge lights along the runway: frangible yellow stems with a lens that glows white at night.
	var rlx := a.x + 15.0
	while rlx < b.x - 10.0:
		for side: float in [-1.0, 1.0]:
			var lp := Vector3(rlx, a.y, a.z + side * (hw + 0.6))
			StreetKit.rod(mb, lp, lp + Vector3.UP * 0.32, 0.07, 0.06, 8, Color(0.85, 0.7, 0.15, StreetKit.PLASTIC))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, lp + Vector3(0, 0.36, 0)), Vector3(0.14, 0.08, 0.14), 0.015, Color(0.95, 0.96, 1.0, StreetKit.LAMP_COOL), Color(0, 0, 0, -1), false)
		rlx += 30.0
	# Hangars along the back of the apron, open to the south: box-profile steel
	# cladding on a concrete plinth, a barrel roof on arched trusses with
	# strip lights, a lintel and door tracks across the front.
	var back := ac.z - asz.y * 0.5
	var cladding := Color(0.74, 0.75, 0.73, StreetKit.CORRUGATED_B)
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for hx: float in [ac.x - 28.0, ac.x + 6.0]:
		var c := Vector3(hx, ac.y, back - 10.0)
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(0, 5, -9.5)), Vector3(26, 10, 1), cladding, 0.06, cladding.darkened(0.25))
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(-12.5, 5, 0)), Vector3(1, 10, 20), cladding, 0.06, cladding.darkened(0.25))
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(12.5, 5, 0)), Vector3(1, 10, 20), cladding, 0.06, cladding.darkened(0.25))
		_collider(body, Transform3D(Basis.IDENTITY, c + Vector3(0, 10.4, 0)), Vector3(27, 0.8, 21))
		# Concrete plinth round the three walls.
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.3, -9.5)), Vector3(26.2, 0.6, 1.14), 0.03, Color(ArtPalette.CONCRETE, CONCRETE))
		for sx: float in [-12.5, 12.5]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(sx, 0.3, 0)), Vector3(1.14, 0.6, 20.2), 0.03, Color(ArtPalette.CONCRETE, CONCRETE))
		# Barrel roof (ribs run down the slope), a lip along the front and eaves.
		var roof := PackedVector2Array()
		var lip := PackedVector3Array()
		for k in 9:
			var t := -1.0 + 2.0 * k / 8.0
			roof.append(Vector2(t * 13.5, 10.0 + 1.6 * (1.0 - t * t)))
		for k in 17:
			var t := -1.0 + 2.0 * k / 16.0
			lip.append(c + Vector3(t * 13.5, 10.04 + 1.6 * (1.0 - t * t), 10.55))
		var roof_path := PackedVector3Array([c + Vector3(0, 0, -10.5), c + Vector3(0, 0, 10.5)])
		var roof_col := Color(0.66, 0.7, 0.74, StreetKit.CORRUGATED_B)
		mb.add_sweep(roof_path, roof, PackedColorArray([roof_col]), 30.0)
		var under := roof.duplicate()
		under.reverse()
		mb.add_sweep(roof_path, under, PackedColorArray([roof_col.darkened(0.45)]), 30.0, false, false)
		StreetKit.tube_path(mb, lip, PackedFloat32Array([0.11]), 8, gal, true)
		for sx: float in [-1.0, 1.0]:
			StreetKit.beam(mb, c + Vector3(sx * 13.6, 9.9, -10.4), c + Vector3(sx * 13.6, 9.9, 10.4), 0.22, 0.16, gal, 0.02)
		for k in 6:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(-12.0 + k * 4.8, 9.4, 0)), Vector3(0.3, 0.5, 20.0), 0.03, STEEL)
		# Arched trusses under the roof with a pair of strip lights between them.
		for zz: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			var arc := PackedVector3Array()
			for k in 13:
				var t := -1.0 + 2.0 * k / 12.0
				arc.append(c + Vector3(t * 12.9, 9.55 + 1.55 * (1.0 - t * t), zz))
			StreetKit.tube_path(mb, arc, PackedFloat32Array([0.09]), 6, gal, true)
		for zz: float in [-6.0, 2.0, 6.0]:
			for lx: float in [-5.0, 5.0]:
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(lx, 9.9 + 1.55 * (1.0 - pow(lx / 13.0, 2.0)) - 0.55, zz)), Vector3(0.2, 0.1, 2.6), 0.02, Color(0.95, 0.96, 1.0, StreetKit.LAMP_COOL), Color(0, 0, 0, -1), false)
		# Door tracks and a lintel across the opening.
		StreetKit.beam(mb, c + Vector3(-13.0, 0.04, 10.3), c + Vector3(13.0, 0.04, 10.3), 0.1, 0.08, gal, 0.01)
		StreetKit.beam(mb, c + Vector3(-13.0, 9.65, 10.35), c + Vector3(13.0, 9.65, 10.35), 0.3, 0.5, Color(0.5, 0.52, 0.54, StreetKit.PAINTED), 0.03)
		_ground_quad(ground, c.x - 12, c.z - 9, c.x + 12, c.z + 10, ac.y + 0.03, Color(ArtPalette.CONCRETE_STAINED, 0.5))
	_label(root, "TURBO AIRFIELD", Vector3(ac.x - 11.0, ac.y + 12.6, back - 10.0), 220, Color(1.0, 0.85, 0.25), 0.0)
	# Control tower: a concrete shaft with windows and painted bands, a balcony
	# with railings, a glazed cab with mullions, a red roof, antennas and a radar.
	var tw := Vector3(ac.x + asz.x * 0.5 - 6.0, ac.y, back - 6.0)
	var tower_white := Color(0.84, 0.83, 0.8)
	var dark_glass := Color(0.1, 0.14, 0.18, GLASS)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 9, 0)), Vector3(3.5, 18, 3.5), Color(tower_white, CONCRETE), 0.08)
	for by: float in [14.2, 16.6]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, by, 0)), Vector3(3.58, 1.0, 3.58), 0.05, Color(0.72, 0.17, 0.13, StreetKit.WORN), Color(0, 0, 0, -1), false)
	for wy: float in [3.0, 6.0, 9.0, 12.0]:
		for s: float in [-1.0, 1.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, wy, s * 1.76)), Vector3(0.9, 1.3, 0.05), 0.01, dark_glass, Color(0, 0, 0, -1), false)
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, wy, s * 1.745)), Vector3(1.1, 1.5, 0.02), 0.01, Color(0.55, 0.55, 0.55, PAINTED), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, 1.1, 1.77)), Vector3(1.1, 2.2, 0.06), 0.02, Color(0.16, 0.28, 0.45, StreetKit.WORN), Color(0, 0, 0, -1), false)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 18.4, 0)), Vector3(8, 0.8, 8), Color(tower_white, CONCRETE), 0.06)
	# Balcony railing: posts every metre, a top rail and a mid rail.
	for side in 4:
		var d := Vector3(1, 0, 0) if side % 2 == 0 else Vector3(0, 0, 1)
		var n := Vector3(0, 0, 1) if side % 2 == 0 else Vector3(1, 0, 0)
		var sgn := 3.85 if side < 2 else -3.85
		var o := tw + n * sgn + Vector3(0, 18.8, 0)
		StreetKit.beam(mb, o - d * 3.85, o + d * 3.85, 0.05, 0.05, gal, 0.008)
		StreetKit.beam(mb, o - d * 3.85 + Vector3(0, 0.55, 0), o + d * 3.85 + Vector3(0, 0.55, 0), 0.05, 0.05, gal, 0.008)
		StreetKit.beam(mb, o - d * 3.85 + Vector3(0, 1.1, 0), o + d * 3.85 + Vector3(0, 1.1, 0), 0.06, 0.06, gal, 0.008)
		for pi in 8:
			var p := o + d * (-3.85 + 7.7 * pi / 7.0)
			StreetKit.rod(mb, p + Vector3(0, -0.3, 0), p + Vector3(0, 1.1, 0), 0.025, 0.025, 6, gal)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 20.4, 0)), Vector3(7, 3.2, 7), Color(0.16, 0.22, 0.27, GLASS), 0.04)
	for cx: float in [-3.5, 3.5]:
		for cz: float in [-3.5, 3.5]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(cx, 20.4, cz)), Vector3(0.2, 3.2, 0.2), 0.02, Color(0.25, 0.26, 0.27, PAINTED))
	for mx: float in [-1.75, 0.0, 1.75]:
		for s: float in [-1.0, 1.0]:
			StreetKit.rod(mb, tw + Vector3(mx, 18.8, s * 3.5), tw + Vector3(mx, 22.0, s * 3.5), 0.04, 0.04, 6, Color(0.25, 0.26, 0.27, PAINTED))
			StreetKit.rod(mb, tw + Vector3(s * 3.5, 18.8, mx), tw + Vector3(s * 3.5, 22.0, mx), 0.04, 0.04, 6, Color(0.25, 0.26, 0.27, PAINTED))
	for s: float in [-1.0, 1.0]:
		StreetKit.beam(mb, tw + Vector3(-3.5, 20.4, s * 3.5), tw + Vector3(3.5, 20.4, s * 3.5), 0.06, 0.06, Color(0.25, 0.26, 0.27, PAINTED), 0.008)
		StreetKit.beam(mb, tw + Vector3(s * 3.5, 20.4, -3.5), tw + Vector3(s * 3.5, 20.4, 3.5), 0.06, 0.06, Color(0.25, 0.26, 0.27, PAINTED), 0.008)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 22.3, 0)), Vector3(8.4, 0.6, 8.4), Color(0.7, 0.18, 0.14, PAINTED), 0.06)
	mb.add_lathe(Transform3D(Basis.IDENTITY, tw + Vector3(0, 22.6, 0)), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.04, 3.0), Vector2(0.0, 3.05)]), 6,
		PackedColorArray([STEEL]))
	StreetKit.rod(mb, tw + Vector3(2.4, 22.6, 2.2), tw + Vector3(2.4, 24.0, 2.2), 0.05, 0.04, 8, gal)
	mb.add_bevel_box(Transform3D(Basis(Vector3.UP, 0.4), tw + Vector3(2.4, 24.2, 2.2)), Vector3(2.2, 0.55, 0.08), 0.03, Color(0.85, 0.85, 0.83, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
	StreetKit.rod(mb, tw + Vector3(-2.6, 22.6, -2.4), tw + Vector3(-2.6, 26.0, -2.4), 0.02, 0.012, 5, gal)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, 25.6, 0)), Vector3(0.2, 0.2, 0.2), 0.03, Color(0.9, 0.15, 0.1, GLOW))
	# Windsock: a pole and an orange-and-white sock blowing east.
	var ws := Vector3(b.x - 40.0, a.y, a.z - hw - 12.0)
	_collider(body, Transform3D(Basis.IDENTITY, ws + Vector3(0, 3, 0)), Vector3(0.25, 6, 0.25))
	mb.add_lathe(Transform3D(Basis.IDENTITY, ws), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.07, 6.0), Vector2(0.0, 6.05)]), 8,
		PackedColorArray([Color(0.8, 0.8, 0.78, PAINTED)]))
	var sock := Transform3D(Basis(Vector3.BACK, -PI * 0.5 + 0.12), ws + Vector3(0.1, 5.7, 0))
	var sock_pts := PackedVector2Array()
	var sock_cols := PackedColorArray()
	for k in 5:
		var cc := Color(0.9, 0.4, 0.1, StreetKit.FABRIC) if k % 2 == 0 else Color(0.9, 0.89, 0.86, StreetKit.FABRIC)
		for hh: float in [0.6 * k + 0.003, 0.6 * (k + 1)]:
			sock_pts.append(Vector2(lerpf(0.38, 0.16, hh / 3.0), hh))
			sock_cols.append(cc)
	mb.add_lathe(sock, sock_pts, 12, sock_cols, 40.0)
	mb.add_lathe(Transform3D(Basis.IDENTITY, ws), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(0.4, 0.25), Vector2(0.0, 0.25)]), 10,
		PackedColorArray([Color(ArtPalette.CONCRETE, CONCRETE)]), 40.0)
	mb.add_lathe(Transform3D(Basis.IDENTITY, ws + Vector3(0, 5.6, 0)), PackedVector2Array([Vector2(0.19, 0.0), Vector2(0.19, 0.06), Vector2(0.14, 0.06), Vector2(0.14, 0.0)]), 12,
		PackedColorArray([Color(StreetKit.GALV, StreetKit.METAL)]), 40.0)
	# Parked planes on the apron and one at the runway's west end.
	_plane(mb, body, ac + Vector3(-28.0, 0, 2.0), PI, Color(0.9, 0.9, 0.88), Color(0.7, 0.18, 0.14))
	_plane(mb, body, ac + Vector3(6.0, 0, 3.0), PI * 0.85, Color(0.86, 0.75, 0.32), Color(0.18, 0.32, 0.58))
	_plane(mb, body, Vector3(a.x + 26.0, a.y, a.z + 4.0), -PI * 0.5, Color(0.3, 0.55, 0.38), Color(0.9, 0.9, 0.88))
	_mesh(body, mb, _props_mat)
	_mesh(body, ground, _paving_mat)
	root.add_child(body)


## A light high-wing aeroplane facing `yaw` (0 = nose to -Z): a lofted two-tone
## fuselage, airfoil wings with struts, a tail, a glazed cabin, a spinner and
## propeller, fixed gear. Colliders are the same boxes as before.
func _plane(mb: MeshBuilder, body: StaticBody3D, at: Vector3, yaw: float, col: Color, stripe: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := func(p: Vector3) -> Transform3D: return Transform3D(b, at + b * p)
	var wp := func(p: Vector3) -> Vector3: return at + b * p
	var paint := Color(col, StreetKit.GLOSS)
	var accent := Color(stripe, StreetKit.GLOSS)
	var glass := Color(0.1, 0.14, 0.18, GLASS)
	var alu := Color(0.75, 0.76, 0.78, StreetKit.ALUMINIUM)
	# Fuselage: oval rings (half width, top, bottom, centre height) from nose to tail.
	var rings_up: Array = []
	var rings_low: Array = []
	for s: Array in [[-4.0, 0.3, 0.28, 0.26, 1.42], [-3.7, 0.52, 0.48, 0.46, 1.5], [-3.0, 0.7, 0.62, 0.6, 1.55], [-2.2, 0.76, 0.78, 0.62, 1.62],
			[-1.0, 0.76, 0.84, 0.6, 1.66], [0.4, 0.68, 0.76, 0.52, 1.7], [1.8, 0.5, 0.55, 0.4, 1.8], [3.0, 0.3, 0.32, 0.25, 1.92], [4.0, 0.1, 0.12, 0.1, 2.0]]:
		var ring := StreetKit._oval(s[1], s[2], s[3], s[0], Vector3(0, s[4], 0), 16, 0.7)
		var up := PackedVector3Array()
		var low := PackedVector3Array()
		for j in 9:
			up.append(wp.call(ring[j]))
		for j in 9:
			low.append(wp.call(ring[(j + 8) % 16]))
		rings_up.append(up)
		rings_low.append(low)
	StreetKit.loft(mb, rings_up, paint, false, false, false)
	StreetKit.loft(mb, rings_low, accent, false, false, false)
	_collider(body, xf.call(Vector3(0, 1.6, 0)), Vector3(1.6, 1.6, 8.0))
	# Cabin glazing: side windows, a windscreen and a rear window.
	for sx: float in [-1.0, 1.0]:
		mb.add_bevel_box(xf.call(Vector3(sx * 0.775, 2.05, -1.3)), Vector3(0.03, 0.5, 1.7), 0.01, glass, Color(0, 0, 0, -1), false)
		mb.add_bevel_box(xf.call(Vector3(sx * 0.67, 2.1, 0.55)), Vector3(0.03, 0.34, 0.5), 0.01, glass, Color(0, 0, 0, -1), false)
	var wind := Transform3D(b * Basis(Vector3.RIGHT, -0.62), at + b * Vector3(0, 2.3, -2.45))
	mb.add_bevel_box(wind, Vector3(1.15, 0.6, 0.03), 0.01, glass, Color(0, 0, 0, -1), false)
	# Wings: NACA-style airfoil sections, tapering to the tip, painted tips.
	var xs := [-5.4, -4.5, -3.2, -1.8, -0.8, 0.8, 1.8, 3.2, 4.5, 5.4]
	var wing: Array = []
	for x: float in xs:
		var f := clampf((absf(x) - 0.8) / 4.6, 0.0, 1.0)
		var chord := lerpf(1.8, 1.1, f)
		var ring := _foil_ring(Vector3(x, 2.66 + absf(x) * 0.012, -1.55 + f * 0.2), chord, 0.13, false)
		var w := PackedVector3Array()
		for p in ring:
			w.append(wp.call(p))
		wing.append(w)
	StreetKit.loft(mb, wing.slice(1, wing.size() - 1), paint, true, false, false)
	StreetKit.loft(mb, wing.slice(0, 2), accent, true, true, false)
	StreetKit.loft(mb, wing.slice(wing.size() - 2), accent, true, true, false)
	_collider(body, xf.call(Vector3(0, 2.7, -0.6)), Vector3(11.0, 0.22, 1.7))
	# Struts from the lower fuselage to the wings.
	for sx: float in [-1.0, 1.0]:
		StreetKit.beam(mb, wp.call(Vector3(sx * 0.72, 1.25, -0.5)), wp.call(Vector3(sx * 3.1, 2.6, -0.95)), 0.1, 0.045, paint, 0.01)
		StreetKit.beam(mb, wp.call(Vector3(sx * 1.9, 1.95, -0.7)), wp.call(Vector3(sx * 1.9, 2.62, -1.0)), 0.04, 0.03, paint, 0.005)
	# Tail: stabiliser and a swept fin (airfoil lofts), painted with the accent.
	var stab: Array = []
	for x: float in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		var chord := lerpf(0.95, 0.6, absf(x) / 2.0)
		var ring := _foil_ring(Vector3(x, 2.0, 3.0 + absf(x) * 0.08), chord, 0.09, false)
		var w := PackedVector3Array()
		for p in ring:
			w.append(wp.call(p))
		stab.append(w)
	StreetKit.loft(mb, stab, paint, true, true, false)
	_collider(body, xf.call(Vector3(0, 1.9, 3.6)), Vector3(4.0, 0.18, 1.0))
	var fin: Array = []
	for yy: float in [1.95, 2.5, 3.0, 3.5]:
		var f := (yy - 1.95) / 1.55
		var ring := _foil_ring(Vector3(0, yy, 2.6 + f * 1.1), lerpf(1.5, 0.75, f), 0.08, true)
		var w := PackedVector3Array()
		for p in ring:
			w.append(wp.call(p))
		fin.append(w)
	StreetKit.loft(mb, fin, accent, true, true, false)
	_collider(body, xf.call(Vector3(0, 2.9, 3.7)), Vector3(0.2, 1.8, 1.2))
	# Spinner and a two-blade propeller.
	var along := b * Basis(Vector3.RIGHT, PI * 0.5)
	mb.add_lathe(Transform3D(along, at + b * Vector3(0, 1.42, -4.25)), PackedVector2Array([Vector2(0.0, -0.4), Vector2(0.14, -0.3), Vector2(0.24, -0.1), Vector2(0.28, 0.1), Vector2(0.0, 0.12)]), 14,
		PackedColorArray([accent]), 40.0)
	for s: float in [-1.0, 1.0]:
		StreetKit.beam(mb, wp.call(Vector3(0, 1.42 + s * 0.2, -4.4)), wp.call(Vector3(0.0, 1.42 + s * 1.38, -4.36)), 0.16, 0.025, Color(0.1, 0.1, 0.11, PAINTED), 0.008)
		StreetKit.beam(mb, wp.call(Vector3(0, 1.42 + s * 1.2, -4.36)), wp.call(Vector3(0.0, 1.42 + s * 1.38, -4.36)), 0.15, 0.028, Color(0.9, 0.75, 0.15, StreetKit.RETRO), 0.006)
	# Exhaust pipe and an oil-cooler intake under the nose.
	StreetKit.rod(mb, wp.call(Vector3(0.28, 1.0, -3.4)), wp.call(Vector3(0.3, 0.95, -2.2)), 0.04, 0.035, 8, Color(0.3, 0.3, 0.32, StreetKit.RUST))
	mb.add_bevel_box(xf.call(Vector3(0, 1.45, -3.88)), Vector3(0.7, 0.2, 0.05), 0.02, Color(0.06, 0.06, 0.07, PAINTED), Color(0, 0, 0, -1), false)
	# Fixed gear: struts, tyres, hubs, wheel fairings.
	var tyre := PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.28, -0.1), Vector2(0.36, -0.06), Vector2(0.38, 0.0), Vector2(0.36, 0.06), Vector2(0.28, 0.1), Vector2(0.0, 0.1)])
	for g: Vector3 in [Vector3(-1.35, 0.4, -0.7), Vector3(1.35, 0.4, -0.7), Vector3(0, 0.38, -3.1)]:
		_collider(body, xf.call(g), Vector3(0.25, 0.7, 0.7))
		var wheel := b * Basis(Vector3.BACK, PI * 0.5)
		mb.add_lathe(Transform3D(wheel, at + b * g), tyre, 14, PackedColorArray([Color(0.1, 0.1, 0.11, StreetKit.RUBBER)]), 40.0)
		mb.add_lathe(Transform3D(wheel, at + b * (g + Vector3(0.0, 0.0, 0.0))), PackedVector2Array([Vector2(0.0, -0.12), Vector2(0.14, -0.12), Vector2(0.14, 0.12), Vector2(0.0, 0.12)]), 10,
			PackedColorArray([Color(0.7, 0.7, 0.72, StreetKit.METAL)]), 40.0)
		var top := Vector3(g.x * 0.45, 1.25, g.z + 0.2) if absf(g.x) > 0.1 else Vector3(0, 1.3, g.z)
		StreetKit.beam(mb, wp.call(top), wp.call(g + Vector3(0, 0.1, 0)), 0.09, 0.07, Color(0.16, 0.16, 0.17, StreetKit.PAINTED), 0.01)
		if absf(g.x) > 0.1:
			mb.add_bevel_box(xf.call(g + Vector3(0, 0.1, 0.0)), Vector3(0.28, 0.5, 0.9), 0.1, accent, Color(0, 0, 0, -1), false)
	StreetKit.rod(mb, wp.call(Vector3(0, 2.4, 1.2)), wp.call(Vector3(0.0, 2.95, 1.5)), 0.012, 0.008, 5, alu)


## A closed airfoil ring (NACA 00xx thickness) of `chord` starting at `le`
## (leading edge): wings lie along X (thickness up), a fin along Y (thickness sideways).
static func _foil_ring(le: Vector3, chord: float, thick: float, vertical: bool) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var n := 7
	var pts: Array = []
	for i in n + 1:
		pts.append([0.5 - 0.5 * cos(PI * i / n), 1.0])
	for i in range(n - 1, 0, -1):
		pts.append([0.5 - 0.5 * cos(PI * i / n), -1.0])
	for p: Array in pts:
		var xc: float = p[0]
		var yt := 5.0 * thick * (0.2969 * sqrt(xc) - 0.126 * xc - 0.3516 * xc * xc + 0.2843 * pow(xc, 3.0) - 0.1015 * pow(xc, 4.0)) * chord * float(p[1])
		if vertical:
			ring.append(Vector3(le.x + yt, le.y, le.z + xc * chord))
		else:
			ring.append(Vector3(le.x, le.y + yt, le.z + xc * chord))
	return ring


# ------------------------------------------------------------------- tunnel --

func _build_tunnel(root: Node3D) -> void:
	var z0 := MapLayout.TUNNEL_Z0
	var z1 := MapLayout.TUNNEL_Z1
	var hw := MapLayout.TUNNEL_HALF_WIDTH
	var hill := MapLayout.TUNNEL_HILL_HALF_WIDTH
	var wall_h := 4.8
	var arch := 2.0
	var inside := MeshBuilder.new()
	var grass := MeshBuilder.new()
	# Inside: cast concrete walls and arch, a pale painted lower band.
	var inner: Array[Vector2] = [Vector2(-hw, -0.6), Vector2(-hw, 1.2), Vector2(-hw, wall_h)]
	for k in range(1, 10):
		var ang := PI - PI * k / 10.0
		inner.append(Vector2(cos(ang) * hw, wall_h + sin(ang) * arch))
	inner.append(Vector2(hw, wall_h))
	inner.append(Vector2(hw, 1.2))
	inner.append(Vector2(hw, -0.6))
	for k in inner.size() - 1:
		var p0 := inner[k]
		var p1 := inner[k + 1]
		var m := (p0 + p1) * 0.5
		var col := Color(0.72, 0.71, 0.68, 0.0) if m.y > 1.2 else Color(0.86, 0.84, 0.76, 0.0)
		var facing := Vector3(-m.x, 3.0 - m.y, 0)
		StuntParkBuilder._quad(inside, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), facing, col)
	# Outside: a grassy hill over the tube, smooth shaded, with concrete
	# retaining walls round the mouths.
	var outer := func(x: float) -> float:
		var t := clampf(absf(x) / hill, 0.0, 1.0)
		return maxf(11.0 * pow(1.0 - t * t, 1.3), (wall_h + arch + 1.5) * (1.0 - smoothstep(hw + 1.0, hw + 6.0, absf(x))))
	var steps := 32
	var slope := func(x: float) -> Vector3:
		var dy: float = outer.call(x + 0.25) - outer.call(x - 0.25)
		return Vector3(-dy / 0.5, 1.0, 0.0).normalized()
	for k in steps:
		var x0 := -hill + 2.0 * hill * k / steps
		var x1 := -hill + 2.0 * hill * (k + 1) / steps
		var y0: float = outer.call(x0)
		var y1: float = outer.call(x1)
		var na: Vector3 = slope.call(x0)
		var nb: Vector3 = slope.call(x1)
		var g := Color(ArtPalette.GRASS_DARK.lerp(ArtPalette.GRASS_LIGHT, 0.4), 0.0)
		grass.add_quad_ex(Vector3(x0, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y0, z1), na, nb, nb, na, g, g, g, g)
		var b0 := _tunnel_floor(x0, hw, wall_h, arch)
		var b1 := _tunnel_floor(x1, hw, wall_h, arch)
		for e: Array in [[z0, -1.0], [z1, 1.0]]:
			var z: float = e[0]
			StuntParkBuilder._quad(inside, Vector3(x0, b0, z), Vector3(x1, b1, z), Vector3(x1, y1, z), Vector3(x0, y0, z),
				Vector3(0, 0, e[1]), Color(0.6, 0.58, 0.55, 0.0))
	var node := inside.build_node("Tunnel", _concrete_mat, true, 1.0)
	root.add_child(node)
	root.add_child(grass.build_node("TunnelHill", _paving_mat, true, 1.0))
	# Concrete portals and signs.
	var frame := MeshBuilder.new()
	var portal := Color(0.78, 0.77, 0.73, 1.0)
	for z: float in [z0, z1]:
		var s := -1.0 if z == z0 else 1.0
		frame.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(-hw - 0.6, 3.6, z + s * 0.3)), Vector3(1.2, 7.2, 0.6), 0.06, portal, portal.darkened(0.2))
		frame.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(hw + 0.6, 3.6, z + s * 0.3)), Vector3(1.2, 7.2, 0.6), 0.06, portal, portal.darkened(0.2))
		frame.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_h + arch + 0.8, z + s * 0.3)), Vector3(hw * 2.0 + 2.4, 1.6, 0.6), 0.06, portal)
		_label(root, "TURBO TUNNEL", Vector3(0, wall_h + arch + 0.8, z + s * 0.62), 110, Color(1.0, 0.85, 0.25), 0.0 if s > 0.0 else PI)
	_mesh(root, frame, _concrete_mat)
	# Strip lights along the ceiling (always on).
	var lights := MeshBuilder.new()
	var z := z0 + 3.0
	while z < z1 - 2.0:
		lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_h + arch - 0.08, z)), Vector3(0.5, 0.12, 2.2), 0.02, Color(0.3, 0.3, 0.32, PAINTED))
		lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_h + arch - 0.15, z)), Vector3(0.42, 0.02, 2.1), 0.005, Color(1.0, 0.92, 0.75, GLOW))
		z += 6.0
	# Cable trays and conduit along both walls, amber wall reflectors, emergency
	# phones and extinguisher boxes in recesses, green exit signs.
	var tgal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for sx: float in [-1.0, 1.0]:
		var wx := sx * (hw - 0.14)
		StreetKit.beam(lights, Vector3(wx, 3.9, z0 + 0.3), Vector3(wx, 3.9, z1 - 0.3), 0.32, 0.04, tgal, 0.006)
		StreetKit.rod(lights, Vector3(wx, 4.0, z0 + 0.3), Vector3(wx, 4.0, z1 - 0.3), 0.035, 0.035, 8, Color(0.12, 0.12, 0.13, StreetKit.PLASTIC))
		StreetKit.rod(lights, Vector3(wx - sx * 0.1, 4.0, z0 + 0.3), Vector3(wx - sx * 0.1, 4.0, z1 - 0.3), 0.025, 0.025, 8, Color(0.8, 0.25, 0.15, StreetKit.PLASTIC))
		var zb := z0 + 2.0
		while zb < z1 - 1.0:
			StreetKit.beam(lights, Vector3(wx, 3.6, zb), Vector3(wx, 3.92, zb), 0.05, 0.04, tgal, 0.006)
			zb += 4.0
		var zr := z0 + 4.0
		while zr < z1 - 2.0:
			lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.03), 1.1, zr)), Vector3(0.05, 0.16, 0.16), 0.01, Color(0.95, 0.65, 0.1, StreetKit.RETRO), Color(0, 0, 0, -1), false)
			zr += 6.0
		for pz: float in [z0 + 14.0, z1 - 14.0]:
			lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.1), 1.5, pz)), Vector3(0.2, 0.7, 0.5), 0.02, Color(0.9, 0.45, 0.1, StreetKit.PLASTIC))
			lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.21), 1.65, pz)), Vector3(0.02, 0.28, 0.34), 0.004, Color(0.1, 0.12, 0.14, GLASS), Color(0, 0, 0, -1), false)
			lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.1), 1.5, pz + 3.0)), Vector3(0.2, 0.5, 0.4), 0.02, Color(0.75, 0.15, 0.1, StreetKit.PLASTIC))
			lights.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.12), 2.6, pz + 1.5)), Vector3(0.06, 0.26, 0.6), 0.01, Color(0.15, 0.7, 0.35, GLOW), Color(0, 0, 0, -1), false)
	_mesh(root, lights, _props_mat)
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
	body.name = "Harbor"
	var mb := MeshBuilder.new()
	var ground := MeshBuilder.new()
	var conc := MeshBuilder.new()
	var qa := MapLayout.HARBOR_QUAY_A
	var qb := MapLayout.HARBOR_QUAY_B
	var y := qa.y
	var edge := qa.x - 18.0
	var inner := qa.x + 18.0
	_ground_quad(ground, edge, qb.z, inner, qa.z, y, Color(ArtPalette.PAVING, 0.5))
	_collider(body, Transform3D(Basis.IDENTITY, Vector3((edge + inner) * 0.5, y - 0.5, (qa.z + qb.z) * 0.5)), Vector3(inner - edge, 1.0, absf(qb.z - qa.z)))
	# Quay wall down into the water, with a yellow edge and bollards.
	var wall := Transform3D(Basis.IDENTITY, Vector3(edge - 0.6, y - 2.4, (qa.z + qb.z) * 0.5))
	conc.add_bevel_box(wall, Vector3(1.2, 5.0, absf(qb.z - qa.z)), 0.06, Color(0.6, 0.58, 0.55, 1.0), Color(0.36, 0.38, 0.36, 1.0))
	_collider(body, wall, Vector3(1.2, 5.0, absf(qb.z - qa.z)))
	_ground_quad(ground, edge, qb.z, edge + 0.6, qa.z, y + 0.01, Color(0.86, 0.66, 0.16, 0.0))
	var bz := qb.z + 4.0
	while bz < qa.z - 2.0:
		_mooring_bollard(mb, Vector3(edge + 0.5, y, bz))
		bz += 10.0
	# CC0 Poly Haven models (assets/models/props, see SOURCES.md there): channel
	# buoys bobbing off the piers and lifebuoy stations on the quay and pier roots.
	var buoy_scene := load("res://assets/models/props/ocean_buoy.glb") as PackedScene
	for bp: Vector3 in [Vector3(edge - 72.0, MapLayout.SEA_LEVEL, qa.z - 6.0), Vector3(edge - 80.0, MapLayout.SEA_LEVEL, (qa.z + qb.z) * 0.5),
			Vector3(edge - 72.0, MapLayout.SEA_LEVEL, qb.z + 6.0)]:
		var buoy := buoy_scene.instantiate() as Node3D
		buoy.position = bp
		buoy.rotation.y = bp.z * 0.37
		root.add_child(buoy)
	var ring_scene := load("res://assets/models/props/lifebuoy.glb") as PackedScene
	var gal_post := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	for lp: Vector3 in [Vector3(edge + 0.5, y, qb.z + 22.0), Vector3(edge + 0.5, y, qa.z - 22.0), Vector3(edge - 2.0, y, qa.z - 11.8), Vector3(edge - 2.0, y, qb.z + 11.8)]:
		StreetKit.rod(mb, lp, lp + Vector3.UP * 1.6, 0.045, 0.04, 8, Color(0.85, 0.85, 0.82, StreetKit.WORN))
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, lp + Vector3(0.0, 0.04, 0.0)), Vector3(0.4, 0.08, 0.4), 0.01, gal_post)
		StreetKit.beam(mb, lp + Vector3(0.0, 1.35, 0.0), lp + Vector3(-0.2, 1.35, 0.0), 0.05, 0.03, gal_post, 0.005)
		var ring := ring_scene.instantiate() as Node3D
		ring.position = lp + Vector3(-0.27, 1.25, 0.0)
		ring.rotation.y = PI * 0.5
		root.add_child(ring)
	# Quay ladders down to the water.
	bz = qb.z + 9.0
	while bz < qa.z - 5.0:
		var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
		for lz: float in [-0.22, 0.22]:
			StreetKit.beam(mb, Vector3(edge - 1.26, y + 0.1, bz + lz), Vector3(edge - 1.26, y - 3.6, bz + lz), 0.04, 0.03, gal, 0.006)
		for ly in 12:
			StreetKit.rod(mb, Vector3(edge - 1.26, y - ly * 0.3, bz - 0.22), Vector3(edge - 1.26, y - ly * 0.3, bz + 0.22), 0.014, 0.014, 6, gal)
		bz += 20.0
	# Timber piers on piles with plank decking, tyre fenders, cast-iron
	# bollards and moored boats.
	var wood := Color(0.55, 0.45, 0.35)
	var rope := Color(0.62, 0.56, 0.44)
	var boat_cols := [[Color(0.7, 0.18, 0.14), Color(0.9, 0.89, 0.86)], [Color(0.18, 0.34, 0.6), Color(0.9, 0.89, 0.86)], [Color(0.9, 0.89, 0.86), Color(0.85, 0.52, 0.16)]]
	var k := 0
	for pz: float in [qa.z - 15.0, (qa.z + qb.z) * 0.5, qb.z + 15.0]:
		var x0 := edge - 46.0
		var deck := Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y - 0.2, pz))
		_collider(body, deck, Vector3(edge - x0, 0.4, 6.0))
		# Decking in 6 m panels (the shader draws the 152 mm boards).
		var px := x0
		while px < edge - 0.01:
			var len := minf(6.0, edge - px)
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(px + len * 0.5, y - 0.08, pz)), Vector3(len, 0.16, 6.0), 0.01, Color(wood, StreetKit.DECKING))
			px += len
		# Stringers along both sides, an edge log, cross beams under the deck.
		for side: float in [-1.0, 1.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y - 0.34, pz + side * 2.7)), Vector3(edge - x0, 0.3, 0.22), 0.02, Color(wood.darkened(0.25), StreetKit.TIMBER))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y + 0.04, pz + side * 3.04)), Vector3(edge - x0, 0.2, 0.14), 0.02, Color(wood.darkened(0.15), StreetKit.TIMBER))
		px = x0 + 2.0
		while px < edge:
			for side: float in [-2.6, 2.6]:
				var pile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.22, 0.4), Vector2(0.2, 1.8), Vector2(0.185, 5.5), Vector2(0.0, 5.55)])
				var pc := PackedColorArray([Color(0.12, 0.13, 0.1, StreetKit.TIMBER), Color(0.12, 0.13, 0.1, StreetKit.TIMBER), Color(0.2, 0.2, 0.16, StreetKit.TIMBER),
					Color(wood.darkened(0.2), StreetKit.TIMBER), Color(wood.darkened(0.1), StreetKit.TIMBER), Color(wood, StreetKit.TIMBER)])
				mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(px, y - 5.8, pz + side)), pile, 10, pc, 40.0)
			# Cross beam and a diagonal brace between a pair of piles.
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(px, y - 0.62, pz)), Vector3(0.2, 0.26, 6.0), 0.02, Color(wood.darkened(0.3), StreetKit.TIMBER))
			StreetKit.beam(mb, Vector3(px, y - 3.2, pz - 2.6), Vector3(px + 2.8, y - 1.0, pz - 2.6), 0.14, 0.1, Color(wood.darkened(0.35), StreetKit.TIMBER), 0.01)
			StreetKit.beam(mb, Vector3(px, y - 3.2, pz + 2.6), Vector3(px + 2.8, y - 1.0, pz + 2.6), 0.14, 0.1, Color(wood.darkened(0.35), StreetKit.TIMBER), 0.01)
			px += 6.0
		# Mooring bollards and tyre fenders along both edges.
		px = x0 + 3.0
		while px < edge:
			for side: float in [-1.0, 1.0]:
				var bp := Vector3(px, y + 0.0, pz + side * 2.82)
				_mooring_bollard(mb, bp)
				_tyre_fender(mb, Vector3(px + 3.0, y - 0.6, pz + side * 3.14), side)
			px += 6.0
		_boat(mb, body, Vector3(x0 + 14.0, MapLayout.SEA_LEVEL, pz + 6.5), boat_cols[k][0], boat_cols[k][1], 9.0, k)
		_boat(mb, body, Vector3(x0 + 30.0, MapLayout.SEA_LEVEL, pz - 6.5), boat_cols[(k + 1) % 3][0], boat_cols[(k + 1) % 3][1], 7.0, k + 1)
		k += 1
	_crane(mb, body, Vector3(qa.x - 10.0, y, (qa.z + qb.z) * 0.5 - 10.0))
	# Container stacks: ribbed steel boxes in muted shipping colours.
	var cols := [Color(0.6, 0.24, 0.18), Color(0.2, 0.34, 0.52), Color(0.26, 0.44, 0.3), Color(0.74, 0.52, 0.2), Color(0.42, 0.3, 0.44), Color(0.7, 0.7, 0.68)]
	var ci := 0
	for row in 3:
		for col in 4:
			var height := 1 + (row + col) % 3
			for level in height:
				var c := Vector3(inner - 6.0 - row * 3.2, y + 1.3 + level * 2.6, qa.z - 12.0 - col * 7.0)
				_container(mb, body, c, cols[ci % cols.size()], ci)
				ci += 1
	_label(root, "TURBO HARBOUR", Vector3(inner - 2.0, y + 9.0, (qa.z + qb.z) * 0.5 + 18.0), 200, Color(1.0, 0.85, 0.25), PI * 0.5, true)
	_mesh(body, mb, _props_mat)
	_mesh(body, conc, _concrete_mat)
	_mesh(body, ground, _paving_mat)
	root.add_child(body)


## A quayside tower crane: a lattice tower (its collider is the 2.2 m box), a
## turntable with a machinery house and counterweight, a lattice jib with a
## trolley and hook block, an A-frame with tie rods, a cab.
func _crane(mb: MeshBuilder, body: StaticBody3D, cr: Vector3) -> void:
	var yellow := Color(StreetKit.HAZARD_YELLOW.darkened(0.05), StreetKit.WORN)
	var steel := Color(0.4, 0.42, 0.44, PAINTED)
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	var b := StreetKit.beam
	_collider(body, Transform3D(Basis.IDENTITY, cr + Vector3(0, 12, 0)), Vector3(2.2, 24, 2.2))
	# Footing, base plate and bolts.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(0, 0.2, 0)), Vector3(3.6, 0.4, 3.6), 0.04, Color(ArtPalette.CONCRETE, CONCRETE))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(0, 0.45, 0)), Vector3(2.8, 0.1, 2.8), 0.015, gal)
	for bx: float in [-1.1, 1.1]:
		for bz: float in [-1.1, 1.1]:
			StreetKit.bolt(mb, cr + Vector3(bx, 0.5, bz), Vector3.UP, 0.06, gal)
	# Tower: four legs, a ring of ties and an X brace in every bay.
	var h := 24.0
	var cs := [Vector2(-0.95, -0.95), Vector2(0.95, -0.95), Vector2(0.95, 0.95), Vector2(-0.95, 0.95)]
	for c: Vector2 in cs:
		b.call(mb, cr + Vector3(c.x, 0.5, c.y), cr + Vector3(c.x, h, c.y), 0.2, 0.2, yellow, 0.02)
	var bays := 8
	for lv in bays:
		var y0 := 0.5 + (h - 0.5) * lv / bays
		var y1 := 0.5 + (h - 0.5) * (lv + 1) / bays
		for f in 4:
			var ca: Vector2 = cs[f]
			var cb: Vector2 = cs[(f + 1) % 4]
			b.call(mb, cr + Vector3(ca.x, y1, ca.y), cr + Vector3(cb.x, y1, cb.y), 0.1, 0.1, yellow, 0.01)
			var d0 := Vector3(ca.x, y0, ca.y) if lv % 2 == 0 else Vector3(cb.x, y0, cb.y)
			var d1 := Vector3(cb.x, y1, cb.y) if lv % 2 == 0 else Vector3(ca.x, y1, ca.y)
			b.call(mb, cr + d0, cr + d1, 0.08, 0.08, yellow, 0.008)
	# A ladder up the front with a safety cage hoop at the top.
	for lz: float in [-0.25, 0.25]:
		b.call(mb, cr + Vector3(0.0 + lz, 0.6, 1.08), cr + Vector3(0.0 + lz, h - 0.5, 1.08), 0.05, 0.04, gal, 0.006)
	var ry := 0.9
	while ry < h - 0.6:
		StreetKit.rod(mb, cr + Vector3(-0.25, ry, 1.08), cr + Vector3(0.25, ry, 1.08), 0.014, 0.014, 6, gal)
		ry += 0.8
	# Turntable, machinery house, counterweight, counter-jib.
	mb.add_lathe(Transform3D(Basis.IDENTITY, cr + Vector3(0, h, 0)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.6, 0.0), Vector2(1.6, 0.4), Vector2(0.0, 0.4)]), 16,
		PackedColorArray([Color(steel, PAINTED)]), 40.0)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(3.3, h + 0.35, 0)), Vector3(7.6, 0.2, 2.6), 0.03, yellow)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(4.0, h + 1.65, 0)), Vector3(4.2, 2.4, 2.4), 0.12, Color(0.4, 0.42, 0.44, StreetKit.WORN), Color(0, 0, 0, -1), false)
	for vx in 4:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(2.6 + vx * 0.3, h + 1.7, 1.21)), Vector3(0.05, 1.2, 0.02), 0.005, Color(0.12, 0.12, 0.13, PAINTED), Color(0, 0, 0, -1), false)
	for cw in 3:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(6.9 + cw * 0.72, h + 1.0, 0)), Vector3(0.7, 1.7, 2.2), 0.03, Color(ArtPalette.CONCRETE, CONCRETE))
	# Cab on the side of the jib: white with a dark glass band all round and a roof overhang.
	var cab := cr + Vector3(-1.9, h + 1.4, 1.9)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cab), Vector3(2.0, 2.0, 1.8), 0.1, Color(0.92, 0.92, 0.9, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cab + Vector3(0, 0.25, 0)), Vector3(2.04, 0.9, 1.84), 0.03, Color(0.1, 0.14, 0.18, GLASS), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cab + Vector3(0, 1.08, 0)), Vector3(2.3, 0.1, 2.1), 0.03, Color(0.92, 0.92, 0.9, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
	# Lattice jib (triangular section) along -X and the A-frame with tie rods.
	var jx0 := -0.8
	var jx1 := -30.0
	var jb := h + 0.8
	var jt := h + 2.4
	for z: float in [-0.7, 0.7]:
		b.call(mb, cr + Vector3(jx0, jb, z), cr + Vector3(jx1, jb, z), 0.14, 0.14, yellow, 0.015)
	b.call(mb, cr + Vector3(jx0, jt, 0), cr + Vector3(jx1, jt, 0), 0.14, 0.14, yellow, 0.015)
	var nb := 15
	for i in nb:
		var xa := lerpf(jx0, jx1, float(i) / nb)
		var xb := lerpf(jx0, jx1, float(i + 1) / nb)
		var up := i % 2 == 0
		for z: float in [-0.7, 0.7]:
			b.call(mb, cr + Vector3(xa if up else xb, jb, z), cr + Vector3(xb if up else xa, jt, 0), 0.07, 0.07, yellow, 0.007)
		b.call(mb, cr + Vector3(xa, jb, -0.7), cr + Vector3(xb, jb, 0.7), 0.06, 0.06, yellow, 0.006)
		b.call(mb, cr + Vector3(xb, jb, -0.7), cr + Vector3(xb, jb, 0.7), 0.07, 0.07, yellow, 0.007)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(jx1 - 0.2, h + 1.5, 0)), Vector3(0.5, 2.8, 1.8), 0.05, yellow)
	var apex := cr + Vector3(0.6, h + 7.5, 0)
	for z: float in [-0.9, 0.9]:
		b.call(mb, cr + Vector3(-0.5, h + 0.4, z), apex, 0.18, 0.14, yellow, 0.02)
		b.call(mb, cr + Vector3(1.5, h + 0.4, z), apex, 0.18, 0.14, yellow, 0.02)
	for tx: float in [-11.0, -23.0]:
		StreetKit.rod(mb, apex, cr + Vector3(tx, jt, 0), 0.035, 0.035, 6, Color(0.15, 0.15, 0.16, StreetKit.METAL))
	StreetKit.rod(mb, apex, cr + Vector3(7.5, h + 0.9, 0), 0.035, 0.035, 6, Color(0.15, 0.15, 0.16, StreetKit.METAL))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, apex + Vector3(0, 0.15, 0)), Vector3(0.2, 0.2, 0.2), 0.03, Color(0.95, 0.15, 0.1, GLOW), Color(0, 0, 0, -1), false)
	# Trolley, hoist cable, hook block and hook.
	var tx2 := -24.0
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(tx2, jb - 0.5, 0)), Vector3(1.4, 0.5, 1.7), 0.05, Color(0.4, 0.42, 0.44, StreetKit.WORN))
	StreetKit.rod(mb, cr + Vector3(tx2 - 0.3, jb - 0.7, 0), cr + Vector3(tx2 - 0.3, 10.4, 0), 0.03, 0.03, 6, Color(0.14, 0.14, 0.15, StreetKit.METAL))
	StreetKit.rod(mb, cr + Vector3(tx2 + 0.3, jb - 0.7, 0), cr + Vector3(tx2 + 0.3, 10.4, 0), 0.03, 0.03, 6, Color(0.14, 0.14, 0.15, StreetKit.METAL))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(tx2, 10.1, 0)), Vector3(1.0, 0.7, 0.5), 0.06, Color(0.72, 0.18, 0.13, StreetKit.WORN))
	var hook := PackedVector3Array([Vector3(0, -0.35, 0), Vector3(0, -0.8, 0), Vector3(0.12, -1.05, 0), Vector3(0.3, -1.05, 0), Vector3(0.36, -0.85, 0), Vector3(0.28, -0.7, 0)])
	var hook_world := PackedVector3Array()
	for p in hook:
		hook_world.append(cr + Vector3(tx2, 10.1, 0) + p)
	StreetKit.tube_path(mb, hook_world, PackedFloat32Array([0.06, 0.06, 0.055, 0.05, 0.045, 0.035]), 8, Color(0.16, 0.16, 0.17, StreetKit.METAL), true)


## A 6 m shipping container: corrugated panels (the shader draws the ribs and the
## dents), steel corner posts and castings, rails, doors with locking bars.
func _container(mb: MeshBuilder, body: StaticBody3D, c: Vector3, col: Color, idx := 0) -> void:
	var paint := Color(col, StreetKit.CORRUGATED)
	var frame := Color(col.darkened(0.3), StreetKit.WORN)
	var steel := Color(0.26, 0.26, 0.27, StreetKit.WORN)
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	mb.set_uv2(Vector2(fmod(idx * 0.37, 1.0), fmod(idx * 0.61, 1.0)))
	_solid(mb, body, Transform3D(Basis.IDENTITY, c), Vector3(2.44, 2.5, 6.06), paint, 0.02, paint.darkened(0.15))
	mb.set_uv2(Vector2.ZERO)
	for cx: float in [-1.2, 1.2]:
		for cz: float in [-3.04, 3.04]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(cx, 0, cz)), Vector3(0.14, 2.6, 0.14), 0.02, frame)
			for cy: float in [-1.3, 1.3]:
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(cx, cy, cz)), Vector3(0.18, 0.15, 0.2), 0.02, steel)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.3, 1.3]:
			StreetKit.beam(mb, c + Vector3(sx * 1.2, sy, -2.9), c + Vector3(sx * 1.2, sy, 2.9), 0.1, 0.1, frame, 0.015)
	# Doors at one end (which end alternates): two leaves, four locking rods with cams.
	var dir := 1.0 if idx % 2 == 0 else -1.0
	var ze := dir * 3.08
	for dx: float in [-0.58, 0.58]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(dx, 0, ze)), Vector3(1.1, 2.34, 0.05), 0.01, paint)
	for rx: float in [-0.9, -0.28, 0.28, 0.9]:
		StreetKit.rod(mb, c + Vector3(rx, -1.12, ze + dir * 0.045), c + Vector3(rx, 1.12, ze + dir * 0.045), 0.016, 0.016, 6, gal)
		for ry: float in [-0.9, 0.0, 0.9]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(rx, ry, ze + dir * 0.05)), Vector3(0.07, 0.05, 0.03), 0.005, gal)
	for ry: float in [-0.1, 0.1]:
		StreetKit.beam(mb, c + Vector3(-0.3, ry, ze + dir * 0.06), c + Vector3(0.3, ry, ze + dir * 0.06), 0.03, 0.02, steel, 0.005)


## A cast-iron mooring bollard with four anchor nuts.
func _mooring_bollard(mb: MeshBuilder, p: Vector3) -> void:
	var iron := Color(0.2, 0.19, 0.18)
	mb.add_lathe(Transform3D(Basis.IDENTITY, p), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.24, 0.03), Vector2(0.16, 0.06), Vector2(0.13, 0.12),
		Vector2(0.12, 0.3), Vector2(0.15, 0.33), Vector2(0.2, 0.38), Vector2(0.2, 0.43), Vector2(0.12, 0.465), Vector2(0.0, 0.47)]), 12, PackedColorArray([Color(iron, StreetKit.RUST)]), 40.0)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		StreetKit.bolt(mb, p + Vector3(cos(a) * 0.2, 0.03, sin(a) * 0.2), Vector3.UP, 0.025, Color(0.3, 0.28, 0.26, StreetKit.RUST))


## A tyre hung over a pier edge as a fender (axis along Z, face toward the water).
func _tyre_fender(mb: MeshBuilder, p: Vector3, side: float) -> void:
	var prof := PackedVector2Array()
	for i in 9:
		var a := TAU * i / 8.0
		prof.append(Vector2(0.23 + cos(a) * 0.1, 0.075 + sin(a) * 0.075))
	mb.add_lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), prof, 16, PackedColorArray([Color(0.1, 0.1, 0.105, StreetKit.RUBBER)]), 40.0)
	StreetKit.beam(mb, p + Vector3(0, 0.3, 0.0), p + Vector3(0, 0.55, -side * 0.18), 0.03, 0.03, Color(0.62, 0.56, 0.44, StreetKit.FABRIC), 0.005)


## A moored boat (lofted hull, teak deck, cabin, rails, mast) floating at `at`
## (water line), bow toward -X.
func _boat(mb: MeshBuilder, body: StaticBody3D, at: Vector3, hull: Color, cabin: Color, length: float, style := 0) -> void:
	var w := length * 0.36
	var L := length * 0.9
	var white := Color(0.93, 0.93, 0.9)
	var stations := 13
	var rings: Array = []
	var edge_l := PackedVector3Array()
	var edge_r := PackedVector3Array()
	var sheer_at := func(t: float) -> float: return 0.95 + 0.5 * pow(1.0 - t, 2.4) - 0.06 * t
	for i in stations:
		var t := float(i) / (stations - 1)
		var x := (t - 0.5) * L
		var half := w * 0.5 * pow(sin(minf(t / 0.5, 1.0) * PI * 0.5), 0.7) if t < 0.5 else w * 0.5 * (1.0 - 0.1 * pow((t - 0.5) / 0.5, 2.0))
		half = maxf(half, 0.03)
		var sheer: float = sheer_at.call(t)
		var keel := 0.5 * (0.3 + 0.7 * smoothstep(0.0, 0.5, t))
		var ring := PackedVector3Array()
		for j in 11:
			var u := -1.0 + 2.0 * j / 10.0
			ring.append(at + Vector3(x, sheer - (sheer + keel) * (1.0 - pow(absf(u), 1.9)), u * half))
		rings.append(ring)
		edge_l.append(at + Vector3(x, sheer, -half))
		edge_r.append(at + Vector3(x, sheer, half))
	StreetKit.loft(mb, rings, Color(hull, StreetKit.GLOSS), false, false, false)
	# Transom (flat stern) and a teak deck laid along the boat.
	var stern: PackedVector3Array = rings[stations - 1]
	for j in range(1, 10):
		mb._tri_out(stern[0], stern[j], stern[j + 1], Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Color(hull.darkened(0.05), StreetKit.GLOSS), Color(hull.darkened(0.05), StreetKit.GLOSS),
			Color(hull.darkened(0.05), StreetKit.GLOSS), Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), Vector3.RIGHT)
	var teak := Color(0.6, 0.45, 0.3, StreetKit.DECKING)
	var up := Vector3.UP
	var u0 := 0.0
	for i in stations - 1:
		var a := edge_l[i] + up * -0.03
		var b := edge_r[i] + up * -0.03
		var c := edge_r[i + 1] + up * -0.03
		var d := edge_l[i + 1] + up * -0.03
		var seg := a.distance_to(d)
		# UV: x across the boards, y along the boat.
		mb.add_quad_ex(a, b, c, d, up, up, up, up, teak, teak, teak, teak,
			Vector2(-a.z + at.z, u0), Vector2(-b.z + at.z, u0), Vector2(-c.z + at.z, u0 + seg), Vector2(-d.z + at.z, u0 + seg))
		u0 += seg
	# Gunwale: a white rail round the deck edge, and bow rails on stanchions.
	var gun := PackedVector3Array()
	for i in range(stations - 1, -1, -1):
		gun.append(edge_l[i] + Vector3(0, 0.02, 0.03))
	for i in stations:
		gun.append(edge_r[i] + Vector3(0, 0.02, -0.03))
	StreetKit.tube_path(mb, gun, PackedFloat32Array([0.035]), 8, Color(white, StreetKit.GLOSS), true)
	var rail := PackedVector3Array()
	for i in range(6, -1, -1):
		rail.append(edge_l[i] + Vector3(0, 0.62, 0.05))
	for i in range(1, 7):
		rail.append(edge_r[i] + Vector3(0, 0.62, -0.05))
	StreetKit.tube_path(mb, rail, PackedFloat32Array([0.022]), 6, Color(0.75, 0.76, 0.77, StreetKit.ALUMINIUM), true)
	for i in [1, 3, 5, 6]:
		for e: PackedVector3Array in [edge_l, edge_r]:
			StreetKit.rod(mb, e[i] + Vector3(0, 0.0, 0.0), e[i] + Vector3(0, 0.62, 0), 0.018, 0.018, 6, Color(0.75, 0.76, 0.77, StreetKit.ALUMINIUM))
	# Cabin with side windows, a windscreen and a roof overhang.
	var deck_y: float = sheer_at.call(0.55) - 0.03
	var cx := at.x + L * 0.1
	var cl := L * 0.34
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(cx, at.y + deck_y + 0.5, at.z)), Vector3(cl, 1.0, w * 0.64), 0.1, Color(cabin, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
	var glass := Color(0.1, 0.14, 0.18, StreetKit.GLASS)
	for s: float in [-1.0, 1.0]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(cx + cl * 0.05, at.y + deck_y + 0.62, at.z + s * w * 0.322)), Vector3(cl * 0.7, 0.36, 0.02), 0.01, glass, Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis(Vector3.BACK, -0.45), Vector3(cx - cl * 0.5, at.y + deck_y + 0.62, at.z)), Vector3(0.03, 0.4, w * 0.55), 0.01, glass, Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(cx - 0.02, at.y + deck_y + 1.04, at.z)), Vector3(cl * 1.12, 0.07, w * 0.72), 0.03, Color(white, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
	# Mast with a spreader, a radar dome and a navigation light.
	var mx := cx + cl * 0.25
	var my := at.y + deck_y + 1.08
	StreetKit.rod(mb, Vector3(mx, my, at.z), Vector3(mx, my + 2.0, at.z), 0.045, 0.03, 8, Color(0.75, 0.76, 0.77, StreetKit.ALUMINIUM))
	StreetKit.beam(mb, Vector3(mx, my + 1.45, at.z - 0.45), Vector3(mx, my + 1.45, at.z + 0.45), 0.03, 0.03, Color(0.75, 0.76, 0.77, StreetKit.ALUMINIUM), 0.005)
	mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(mx - 0.4, my, at.z)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.2, 0.06), Vector2(0.14, 0.2), Vector2(0.0, 0.25)]), 12,
		PackedColorArray([Color(white, StreetKit.GLOSS)]), 40.0)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(mx, my + 2.05, at.z)), Vector3(0.08, 0.08, 0.08), 0.01, Color(0.95, 0.2, 0.15, StreetKit.GLOW), Color(0, 0, 0, -1), false)
	# Fenders hanging on the side, a life ring on the cabin and an outboard for the smaller one.
	for s: float in [-1.0, 1.0]:
		for ft: float in [0.32, 0.62]:
			# Lying on the hull from the gunwale down, with a lanyard to the rail.
			var fi := int(round(ft * (stations - 1)))
			var ring: PackedVector3Array = rings[fi]
			var top: Vector3 = (edge_l[fi] if s < 0.0 else edge_r[fi]) + Vector3(0, -0.12, s * 0.1)
			var low := ring[0]
			for j in 6:
				var q: Vector3 = ring[j] if s < 0.0 else ring[10 - j]
				if absf(q.y - (top.y - 0.45)) < absf(low.y - (top.y - 0.45)) or j == 0:
					low = q
			low += Vector3(0, 0, s * 0.1)
			StreetKit.rod(mb, top, low, 0.09, 0.09, 10, Color(0.88, 0.88, 0.85, StreetKit.PLASTIC))
			StreetKit.beam(mb, top + Vector3(0, 0.1, 0), top + Vector3(0, 0.7, -s * 0.1), 0.02, 0.02, Color(0.62, 0.56, 0.44, StreetKit.FABRIC), 0.004)
	mb.add_lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx + cl * 0.52, at.y + deck_y + 0.62, at.z + w * 0.33)), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.2, 0.03), Vector2(0.25, 0.03), Vector2(0.27, 0.0),
		Vector2(0.25, -0.03), Vector2(0.2, -0.03)]), 16, PackedColorArray([Color(0.9, 0.4, 0.12, StreetKit.GLOSS)]), 40.0)
	if style % 2 == 1:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(at.x + L * 0.5 + 0.18, at.y + 0.5, at.z)), Vector3(0.3, 0.7, 0.35), 0.05, Color(0.2, 0.22, 0.24, StreetKit.GLOSS), Color(0, 0, 0, -1), false)
		StreetKit.rod(mb, Vector3(at.x + L * 0.5 + 0.18, at.y + 0.2, at.z), Vector3(at.x + L * 0.5 + 0.2, at.y - 0.5, at.z), 0.05, 0.04, 8, Color(0.2, 0.22, 0.24, StreetKit.PAINTED))
	_collider(body, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), Vector3(length, 2.2, w))


# ------------------------------------------------------- islet and bridge --

func _build_islet(root: Node3D) -> void:
	var t: TerrainBuilder = _roads._terrain
	var body := StaticBody3D.new()
	body.name = "Lighthouse"
	var mb := MeshBuilder.new()
	# Lighthouse: a tapered tower in painted red and white bands on a stone
	# plinth, with a door, stair windows, a gallery with railings, the lantern
	# room and a domed roof.
	var c := MapLayout.ISLET_CENTER
	var base := Vector3(c.x, t.height_at(c.x, c.y), c.y)
	var gal := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	var stone := Color(0.56, 0.55, 0.52, CONCRETE)
	var red := Color(0.74, 0.17, 0.13, StreetKit.WORN)
	var white := Color(0.92, 0.91, 0.88, StreetKit.WORN)
	var r_at := func(y: float) -> float: return lerpf(2.6, 1.8, (y - 0.6) / 16.2)
	# Stone plinth with a stepped top.
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3(0, -0.4, 0)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.6, 0.0), Vector2(3.5, 0.5), Vector2(3.2, 0.9), Vector2(3.0, 1.0),
		Vector2(2.85, 1.0), Vector2(2.7, 1.0), Vector2(0.0, 1.0)]), 20, PackedColorArray([stone]), 30.0)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.9, 0.0), Vector2(2.7, 0.6)])
	var cols := PackedColorArray([white, white, white])
	var bands := 6
	for k in bands:
		var y0 := 0.6 + k * (16.2 / bands)
		var y1 := 0.6 + (k + 1) * (16.2 / bands)
		var cc := red if k % 2 == 0 else white
		prof.append(Vector2(r_at.call(y0 + 0.01), y0 + 0.01))
		cols.append(cc)
		prof.append(Vector2(r_at.call(y1), y1))
		cols.append(cc)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base), prof, 24, cols, 20.0)
	_collider(body, Transform3D(Basis.IDENTITY, base + Vector3.UP * 8.4), Vector3(4.4, 16.8, 4.4))
	var dark := Color(0.2, 0.21, 0.22, PAINTED)
	# Door facing the bridge (+X) with a stone lintel and steps, and stair windows.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, base + Vector3(2.62, 2.0, 0)), Vector3(0.3, 2.5, 1.5), 0.04, Color(stone, CONCRETE), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, base + Vector3(2.7, 1.9, 0)), Vector3(0.14, 2.0, 1.0), 0.02, Color(0.14, 0.26, 0.42, StreetKit.WORN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, base + Vector3(3.0, 0.7, 0)), Vector3(0.9, 0.3, 1.8), 0.03, Color(stone, CONCRETE))
	StreetKit.rod(mb, base + Vector3(2.8, 1.9, 0.35), base + Vector3(2.8, 1.9, 0.5), 0.03, 0.03, 8, gal)
	for k in 6:
		var y := 4.0 + k * 2.4
		var a := k * 1.9
		var rr: float = r_at.call(y)
		mb.add_bevel_box(Transform3D(Basis(Vector3.UP, PI * 0.5 - a), base + Vector3(cos(a) * rr, y, sin(a) * rr)), Vector3(0.38, 0.9, 0.26), 0.03, Color(0.1, 0.14, 0.18, GLASS), Color(0, 0, 0, -1), false)
		mb.add_bevel_box(Transform3D(Basis(Vector3.UP, PI * 0.5 - a), base + Vector3(cos(a) * (rr + 0.03), y, sin(a) * (rr + 0.03))), Vector3(0.5, 1.05, 0.1), 0.02, Color(stone, CONCRETE), Color(0, 0, 0, -1), false)
	# Gallery: a steel deck on brackets, posts and two rails all round.
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 16.8), PackedVector2Array([Vector2(1.8, 0.0), Vector2(2.9, 0.15), Vector2(2.9, 0.4), Vector2(0.0, 0.4)]), 24,
		PackedColorArray([dark]), 30.0)
	for k in 16:
		var a := TAU * k / 16.0
		StreetKit.rod(mb, base + Vector3(cos(a) * 2.78, 17.2, sin(a) * 2.78), base + Vector3(cos(a) * 2.78, 18.25, sin(a) * 2.78), 0.028, 0.028, 6, gal)
		StreetKit.beam(mb, base + Vector3(cos(a) * 1.9, 16.7, sin(a) * 1.9), base + Vector3(cos(a) * 2.7, 17.15, sin(a) * 2.7), 0.1, 0.05, dark, 0.008)
	for ry: float in [17.7, 18.25]:
		var ring := PackedVector3Array()
		for k in 33:
			var a := TAU * k / 32.0
			ring.append(base + Vector3(cos(a) * 2.78, ry, sin(a) * 2.78))
		StreetKit.tube_path(mb, ring, PackedFloat32Array([0.03]), 6, gal, false)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 18.05), PackedVector2Array([Vector2(2.78, 0.0), Vector2(2.78, 0.06), Vector2(0.0, 0.06)]), 24,
		PackedColorArray([dark]))
	# Lantern room: a base ring, eight mullions and a transom, a domed roof with a vent ball and rod.
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 18.05), PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.75, 0.0), Vector2(1.75, 0.35), Vector2(0.0, 0.35)]), 16,
		PackedColorArray([Color(0.16, 0.17, 0.18, PAINTED)]), 30.0)
	for k in 8:
		var a := TAU * k / 8.0
		StreetKit.rod(mb, base + Vector3(cos(a) * 1.56, 18.4, sin(a) * 1.56), base + Vector3(cos(a) * 1.56, 20.0, sin(a) * 1.56), 0.045, 0.045, 6, Color(dark, StreetKit.PAINTED))
	var ring2 := PackedVector3Array()
	for k in 25:
		var a := TAU * k / 24.0
		ring2.append(base + Vector3(cos(a) * 1.56, 19.2, sin(a) * 1.56))
	StreetKit.tube_path(mb, ring2, PackedFloat32Array([0.03]), 6, Color(dark, StreetKit.PAINTED), false)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 19.6), PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.95, 0.0), Vector2(1.9, 0.12), Vector2(1.7, 0.6),
		Vector2(1.0, 1.4), Vector2(0.4, 1.85), Vector2(0.25, 1.9), Vector2(0.2, 2.15), Vector2(0.0, 2.35)]), 20, PackedColorArray([red]), 40.0)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 21.8), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.18, 0.1), Vector2(0.2, 0.25), Vector2(0.14, 0.4), Vector2(0.0, 0.45)]), 12,
		PackedColorArray([gal]), 40.0)
	StreetKit.rod(mb, base + Vector3.UP * 22.2, base + Vector3.UP * 23.6, 0.025, 0.012, 6, gal)
	var lamp := MeshInstance3D.new()
	var lm := MeshBuilder.new()
	lm.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 17.2), PackedVector2Array([Vector2(1.5, 0.0), Vector2(1.5, 2.4), Vector2(0.0, 2.4)]), 16,
		PackedColorArray([Color.WHITE]))
	lamp.mesh = lm.build_mesh(_glow_material(Color(1.0, 0.9, 0.5), 2.5))
	lamp.name = "LighthouseLamp"
	root.add_child(lamp)
	var beam := LighthouseBeam.new()
	beam.name = "LighthouseBeam"
	beam.position = base + Vector3.UP * 18.4
	root.add_child(beam)
	# Keeper's cottage: whitewashed walls on a stone plinth, a slate gable roof
	# with rake boards and a ridge, a brick chimney, a door and trimmed windows.
	var hx := base + Vector3(10.0, 0, 7.0)
	var wall := Color(0.9, 0.88, 0.82, CONCRETE)
	var trim := Color(0.94, 0.93, 0.9, StreetKit.WORN)
	_solid(mb, body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 1.6, 0)), Vector3(7, 3.2, 5), wall, 0.05, Color(0.66, 0.65, 0.6, CONCRETE))
	_collider(body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 3.5, 0)), Vector3(7.6, 0.6, 5.6))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(0, 0.25, 0)), Vector3(7.14, 0.5, 5.14), 0.03, Color(0.52, 0.51, 0.48, CONCRETE))
	var slate := Color(0.32, 0.35, 0.38, StreetKit.SLATE)
	var path := PackedVector3Array([hx + Vector3(-3.95, 0, 0), hx + Vector3(3.95, 0, 0)])
	mb.add_sweep(path, PackedVector2Array([Vector2(-2.95, 3.1), Vector2(0.0, 5.1), Vector2(2.95, 3.1)]), PackedColorArray([slate]), 30.0, false, false)
	var under := PackedVector2Array([Vector2(2.95, 2.98), Vector2(0.0, 4.98), Vector2(-2.95, 2.98)])
	mb.add_sweep(path, under, PackedColorArray([Color(0.2, 0.2, 0.2, StreetKit.PAINTED)]), 30.0, false, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			StreetKit.beam(mb, hx + Vector3(sx * 3.95, 3.04, sz * 2.95), hx + Vector3(sx * 3.95, 5.04, 0.0), 0.12, 0.16, trim, 0.012)
		mb._tri_out(hx + Vector3(sx * 3.5, 3.2, -2.5), hx + Vector3(sx * 3.5, 3.2, 2.5), hx + Vector3(sx * 3.5, 4.96, 0.0), Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0),
			wall, wall, wall, Vector2(0, 0), Vector2(5.0, 0), Vector2(2.5, 1.8), Vector3(sx, 0, 0))
	StreetKit.beam(mb, hx + Vector3(-3.97, 5.1, 0), hx + Vector3(3.97, 5.1, 0), 0.2, 0.12, Color(0.22, 0.24, 0.27, StreetKit.SLATE), 0.02)
	# Chimney with a cap.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(2.4, 4.6, -0.9)), Vector3(0.7, 2.2, 0.7), 0.03, Color(0.6, 0.28, 0.2, CONCRETE))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(2.4, 5.75, -0.9)), Vector3(0.9, 0.14, 0.9), 0.02, Color(0.55, 0.54, 0.5, CONCRETE))
	# Door with frame, step and a porch lamp; windows with frames, sills and shutters.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(-1.5, 1.05, 2.51)), Vector3(0.95, 2.1, 0.06), 0.02, Color(0.18, 0.3, 0.46, StreetKit.WORN), Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(-1.5, 1.1, 2.49)), Vector3(1.15, 2.2, 0.03), 0.01, trim, Color(0, 0, 0, -1), false)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(-1.5, 0.08, 2.9)), Vector3(1.3, 0.16, 0.7), 0.02, Color(0.55, 0.54, 0.5, CONCRETE))
	StreetKit.rod(mb, hx + Vector3(-1.15, 1.0, 2.54), hx + Vector3(-1.15, 1.0, 2.62), 0.03, 0.03, 8, gal)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(-0.2, 2.5, 2.58)), Vector3(0.14, 0.2, 0.14), 0.02, Color(1.0, 0.9, 0.7, StreetKit.LAMP))
	for wx: float in [0.8, 2.4]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.7, 2.49)), Vector3(1.1, 1.2, 0.03), 0.01, trim, Color(0, 0, 0, -1), false)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.7, 2.51)), Vector3(0.9, 1.0, 0.05), 0.02, Color(0.14, 0.19, 0.24, GLASS), Color(0, 0, 0, -1), false)
		StreetKit.beam(mb, hx + Vector3(wx, 1.2, 2.54), hx + Vector3(wx, 2.2, 2.54), 0.04, 0.03, trim, 0.005)
		StreetKit.beam(mb, hx + Vector3(wx - 0.45, 1.7, 2.54), hx + Vector3(wx + 0.45, 1.7, 2.54), 0.04, 0.03, trim, 0.005)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.08, 2.62)), Vector3(1.2, 0.08, 0.2), 0.015, Color(0.55, 0.54, 0.5, CONCRETE))
		for s: float in [-1.0, 1.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx + s * 0.78, 1.7, 2.52)), Vector3(0.5, 1.2, 0.04), 0.01, Color(0.18, 0.3, 0.46, StreetKit.WORN), Color(0, 0, 0, -1), false)
	for wx: float in [-1.5, 1.5]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.7, -2.51)), Vector3(0.9, 1.0, 0.05), 0.02, Color(0.14, 0.19, 0.24, GLASS), Color(0, 0, 0, -1), false)
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.7, -2.49)), Vector3(1.1, 1.2, 0.03), 0.01, trim, Color(0, 0, 0, -1), false)
	_mesh(body, mb, _props_mat)
	root.add_child(body)
	_label(root, "LIGHTHOUSE ISLAND", base + Vector3(0, 24.0, 0), 160, Color(1.0, 0.85, 0.25), 0.0, true)

	# The bridge from the beach: an arched concrete deck with solid parapets
	# (cars bounce off them) on pillars.
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
	var deck := Color(0.6, 0.59, 0.56, 0.0)
	var side := Color(0.7, 0.69, 0.66, 0.0)
	var rail := Color(0.8, 0.79, 0.76, 0.0)
	for k in segs:
		var x0 := lerpf(xe, xw, float(k) / segs)
		var x1 := lerpf(xe, xw, float(k + 1) / segs)
		var y0: float = deck_y.call(x0)
		var y1: float = deck_y.call(x1)
		StuntParkBuilder._quad(bmb, Vector3(x0, y0, -hw), Vector3(x0, y0, hw), Vector3(x1, y1, hw), Vector3(x1, y1, -hw), Vector3.UP, deck)
		StuntParkBuilder._quad(bmb, Vector3(x0, y0 - 0.7, -hw), Vector3(x1, y1 - 0.7, -hw), Vector3(x1, y1 - 0.7, hw), Vector3(x0, y0 - 0.7, hw), Vector3.DOWN, side.darkened(0.3))
		for sd: float in [-1.0, 1.0]:
			var z: float = sd * hw
			StuntParkBuilder._quad(bmb, Vector3(x0, y0 - 0.7, z), Vector3(x1, y1 - 0.7, z), Vector3(x1, y1, z), Vector3(x0, y0, z), Vector3(0, 0, sd), side)
			var zi: float = z - sd * 0.2
			StuntParkBuilder._quad(bmb, Vector3(x0, y0, zi), Vector3(x1, y1, zi), Vector3(x1, y1 + 1.0, zi), Vector3(x0, y0 + 1.0, zi), Vector3(0, 0, -sd), rail)
			StuntParkBuilder._quad(bmb, Vector3(x0, y0, z), Vector3(x0, y0 + 1.0, z), Vector3(x1, y1 + 1.0, z), Vector3(x1, y1, z), Vector3(0, 0, sd), side)
			StuntParkBuilder._quad(bmb, Vector3(x0, y0 + 1.0, zi), Vector3(x1, y1 + 1.0, zi), Vector3(x1, y1 + 1.0, z), Vector3(x0, y0 + 1.0, z), Vector3.UP, rail)
	var bridge := bmb.build_node("IsletBridge", _concrete_mat, true, 1.0)
	root.add_child(bridge)
	var pillars := MeshBuilder.new()
	var px := xe - 14.0
	while px > xw + 8.0:
		var py: float = deck_y.call(px)
		pillars.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(px, (py - 0.7 - 7.0) * 0.5, 0)), Vector3(1.6, py - 0.7 + 7.0, MapLayout.BRIDGE_WIDTH * 0.7), 0.08,
			Color(0.7, 0.69, 0.66, 1.0), Color(0.38, 0.4, 0.38, 1.0))
		px -= 16.0
	_mesh(root, pillars, _concrete_mat)
	# Bridge lamps (the same knock-over lamps as in town) on alternating parapets,
	# and amber reflector posts between them.
	var lamp_scene := load("res://scenes/props/street_lamp.tscn") as PackedScene
	var lamp_x := xe - 10.0
	var lamp_side := 1.0
	while lamp_x > xw + 8.0:
		var bl := lamp_scene.instantiate() as Node3D
		bl.position = Vector3(lamp_x, deck_y.call(lamp_x) + 1.0, lamp_side * (hw - 0.1))
		bl.rotation.y = 0.0 if lamp_side > 0.0 else PI
		root.add_child(bl)
		lamp_side = -lamp_side
		lamp_x -= 16.0


func _glow_material(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m
