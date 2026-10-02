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
		mb.add_bevel_box(board, Vector3(10.2, 2.8, 0.12), 0.03, Color(0.9, 0.9, 0.88, SIGN))
		mb.add_bevel_box(board * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.03)), Vector3(9.9, 2.5, 0.1), 0.02, Color(0.118, 0.42, 0.235, SIGN))
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
			mb.add_bevel_box(pump, Vector3(0.85, 1.8, 0.65), 0.06, WHITE, Color(0.6, 0.6, 0.58, PAINTED))
			_collider(body, pump, Vector3(0.9, 1.8, 0.7))
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.55, pz)), Vector3(0.88, 0.45, 0.68), 0.03, red)
			for side: float in [-1.0, 1.0]:
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.15, pz + side * 0.33)), Vector3(0.5, 0.3, 0.02), 0.005, Color(0.1, 0.12, 0.13, GLOW))
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(px + side * 0.44, 0.9, pz)), Vector3(0.06, 0.35, 0.12), 0.01, Color(0.15, 0.15, 0.16, RUBBER))
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
	# Hangars along the back of the apron, open to the south: ribbed metal
	# walls on a concrete base, a shallow barrel roof.
	var back := ac.z - asz.y * 0.5
	var cladding := Color(0.7, 0.71, 0.7, PAINTED)
	for hx: float in [ac.x - 28.0, ac.x + 6.0]:
		var c := Vector3(hx, ac.y, back - 10.0)
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(0, 5, -9.5)), Vector3(26, 10, 1), cladding, 0.06, cladding.darkened(0.25))
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(-12.5, 5, 0)), Vector3(1, 10, 20), cladding, 0.06, cladding.darkened(0.25))
		_solid(mb, body, Transform3D(Basis.IDENTITY, c + Vector3(12.5, 5, 0)), Vector3(1, 10, 20), cladding, 0.06, cladding.darkened(0.25))
		_collider(body, Transform3D(Basis.IDENTITY, c + Vector3(0, 10.4, 0)), Vector3(27, 0.8, 21))
		var roof := PackedVector2Array()
		for k in 9:
			var t := -1.0 + 2.0 * k / 8.0
			roof.append(Vector2(t * 13.5, 10.0 + 1.6 * (1.0 - t * t)))
		var roof_path := PackedVector3Array([c + Vector3(0, 0, -10.5), c + Vector3(0, 0, 10.5)])
		var roof_col := Color(0.42, 0.47, 0.52, METAL)
		mb.add_sweep(roof_path, roof, PackedColorArray([roof_col]), 30.0)
		var under := roof.duplicate()
		under.reverse()
		mb.add_sweep(roof_path, under, PackedColorArray([roof_col.darkened(0.5)]), 30.0, false, false)
		for k in 6:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(-12.0 + k * 4.8, 9.4, 0)), Vector3(0.3, 0.5, 20.0), 0.03, STEEL)
		_ground_quad(ground, c.x - 12, c.z - 9, c.x + 12, c.z + 10, ac.y + 0.03, Color(ArtPalette.CONCRETE_STAINED, 0.5))
	_label(root, "TURBO AIRFIELD", Vector3(ac.x - 11.0, ac.y + 12.6, back - 10.0), 220, Color(1.0, 0.85, 0.25), 0.0)
	# Control tower: a concrete shaft, a glazed cab, a red roof band.
	var tw := Vector3(ac.x + asz.x * 0.5 - 6.0, ac.y, back - 6.0)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 9, 0)), Vector3(3.5, 18, 3.5), Color(0.82, 0.81, 0.78, CONCRETE), 0.08)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 18.4, 0)), Vector3(8, 0.8, 8), Color(0.82, 0.81, 0.78, CONCRETE), 0.06)
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 20.4, 0)), Vector3(7, 3.2, 7), Color(0.16, 0.22, 0.27, GLASS), 0.04)
	for cx: float in [-3.5, 3.5]:
		for cz: float in [-3.5, 3.5]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(cx, 20.4, cz)), Vector3(0.2, 3.2, 0.2), 0.02, Color(0.25, 0.26, 0.27, PAINTED))
	_solid(mb, body, Transform3D(Basis.IDENTITY, tw + Vector3(0, 22.3, 0)), Vector3(8.4, 0.6, 8.4), Color(0.7, 0.18, 0.14, PAINTED), 0.06)
	mb.add_lathe(Transform3D(Basis.IDENTITY, tw + Vector3(0, 22.6, 0)), PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.04, 3.0), Vector2(0.0, 3.05)]), 6,
		PackedColorArray([STEEL]))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, tw + Vector3(0, 25.6, 0)), Vector3(0.2, 0.2, 0.2), 0.03, Color(0.9, 0.15, 0.1, GLOW))
	# Windsock: a pole and an orange-and-white sock blowing east.
	var ws := Vector3(b.x - 40.0, a.y, a.z - hw - 12.0)
	_collider(body, Transform3D(Basis.IDENTITY, ws + Vector3(0, 3, 0)), Vector3(0.25, 6, 0.25))
	mb.add_lathe(Transform3D(Basis.IDENTITY, ws), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.07, 6.0), Vector2(0.0, 6.05)]), 8,
		PackedColorArray([Color(0.8, 0.8, 0.78, PAINTED)]))
	var sock := Transform3D(Basis(Vector3.BACK, -PI * 0.5 + 0.12), ws + Vector3(0.1, 5.7, 0))
	var sock_cols := PackedColorArray()
	for k in 6:
		sock_cols.append(Color(0.9, 0.4, 0.1, 12.0 / 15.0) if k % 2 == 0 else Color(0.9, 0.89, 0.86, 12.0 / 15.0))
	mb.add_lathe(sock, PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.34, 0.6), Vector2(0.3, 1.2), Vector2(0.26, 1.8), Vector2(0.22, 2.4), Vector2(0.18, 3.0)]),
		10, sock_cols, 40.0)
	# Parked planes on the apron and one at the runway's west end.
	_plane(mb, body, ac + Vector3(-28.0, 0, 2.0), PI, Color(0.9, 0.9, 0.88), Color(0.7, 0.18, 0.14))
	_plane(mb, body, ac + Vector3(6.0, 0, 3.0), PI * 0.85, Color(0.86, 0.75, 0.32), Color(0.18, 0.32, 0.58))
	_plane(mb, body, Vector3(a.x + 26.0, a.y, a.z + 4.0), -PI * 0.5, Color(0.3, 0.55, 0.38), Color(0.9, 0.9, 0.88))
	_mesh(body, mb, _props_mat)
	_mesh(body, ground, _paving_mat)
	root.add_child(body)


## A small propeller plane facing `yaw` (0 = nose to -Z): a smooth fuselage,
## tapered wings and tail, a glazed cockpit, a spinner and fixed gear.
func _plane(mb: MeshBuilder, body: StaticBody3D, at: Vector3, yaw: float, col: Color, stripe: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := func(p: Vector3) -> Transform3D: return Transform3D(b, at + b * p)
	var paint := Color(col, PAINTED)
	var accent := Color(stripe, PAINTED)
	var along := b * Basis(Vector3.RIGHT, PI * 0.5)  # lathe axis (Y) -> local +Z (toward the tail)
	var cols := PackedColorArray([paint, paint, paint, accent, paint, paint, paint, paint])
	mb.add_lathe(Transform3D(along, at + b * Vector3(0, 1.6, 0)), PackedVector2Array([
		Vector2(0.0, -4.3), Vector2(0.42, -4.15), Vector2(0.78, -3.5), Vector2(0.82, -2.3), Vector2(0.8, -0.2),
		Vector2(0.6, 1.8), Vector2(0.3, 3.7), Vector2(0.0, 3.95)]), 12, cols, 35.0)
	_collider(body, xf.call(Vector3(0, 1.6, 0)), Vector3(1.6, 1.6, 8.0))
	# Cockpit glazing.
	mb.add_lathe(Transform3D(along, at + b * Vector3(0, 2.05, -1.5)), PackedVector2Array([
		Vector2(0.0, -0.9), Vector2(0.45, -0.6), Vector2(0.55, 0.2), Vector2(0.35, 0.9), Vector2(0.0, 1.0)]), 10,
		PackedColorArray([Color(0.14, 0.19, 0.24, GLASS)]), 40.0)
	# Wings, tailplane, fin.
	mb.add_bevel_box(xf.call(Vector3(0, 1.9, -0.6)), Vector3(11.0, 0.18, 1.7), 0.07, paint)
	_collider(body, xf.call(Vector3(0, 1.9, -0.6)), Vector3(11.0, 0.22, 1.7))
	for s: float in [-1.0, 1.0]:
		mb.add_bevel_box(xf.call(Vector3(s * 5.3, 1.9, -0.6)), Vector3(0.4, 0.2, 1.72), 0.05, accent)
	mb.add_bevel_box(xf.call(Vector3(0, 1.95, 3.6)), Vector3(4.0, 0.14, 1.0), 0.05, paint)
	_collider(body, xf.call(Vector3(0, 1.9, 3.6)), Vector3(4.0, 0.18, 1.0))
	mb.add_bevel_box(xf.call(Vector3(0, 2.8, 3.65)), Vector3(0.16, 1.7, 1.1), 0.05, accent)
	_collider(body, xf.call(Vector3(0, 2.9, 3.7)), Vector3(0.2, 1.8, 1.2))
	# Spinner and propeller.
	mb.add_lathe(Transform3D(along, at + b * Vector3(0, 1.6, -4.25)), PackedVector2Array([Vector2(0.0, -0.4), Vector2(0.2, -0.15), Vector2(0.25, 0.1), Vector2(0.0, 0.12)]), 10,
		PackedColorArray([Color(0.8, 0.8, 0.78, METAL)]), 40.0)
	mb.add_bevel_box(xf.call(Vector3(0, 1.6, -4.45)), Vector3(3.0, 0.22, 0.05), 0.02, Color(0.14, 0.14, 0.15, PAINTED))
	# Fixed gear: struts and wheels.
	for p: Vector3 in [Vector3(-1.4, 0.4, -0.8), Vector3(1.4, 0.4, -0.8), Vector3(0, 0.35, 3.2)]:
		_collider(body, xf.call(p), Vector3(0.25, 0.7, 0.7))
		var wheel := b * Basis(Vector3.BACK, PI * 0.5)
		mb.add_lathe(Transform3D(wheel, at + b * (p + Vector3(-0.1, 0, 0))), PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.35, 0.05), Vector2(0.35, 0.15), Vector2(0.3, 0.2), Vector2(0.0, 0.2)]), 12,
			PackedColorArray([Color(0.12, 0.12, 0.13, RUBBER)]), 40.0)
		_strut(mb, at + b * (p + Vector3(0, 0.1, 0)), at + b * (p + Vector3(0, 1.3, 0)), 0.1, Color(0.5, 0.5, 0.52, METAL))


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
		mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(edge + 0.5, y, bz)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.22, 0.0),
			Vector2(0.18, 0.35), Vector2(0.28, 0.42), Vector2(0.28, 0.5), Vector2(0.0, 0.52)]), 10, PackedColorArray([Color(0.14, 0.14, 0.15, PAINTED)]), 40.0)
		bz += 10.0
	# Timber piers on piles, with moored boats.
	var wood := Color(0.5, 0.38, 0.26, WOOD)
	var boat_cols := [[Color(0.7, 0.18, 0.14), Color(0.9, 0.89, 0.86)], [Color(0.18, 0.34, 0.6), Color(0.9, 0.89, 0.86)], [Color(0.9, 0.89, 0.86), Color(0.85, 0.52, 0.16)]]
	var k := 0
	for pz: float in [qa.z - 15.0, (qa.z + qb.z) * 0.5, qb.z + 15.0]:
		var x0 := edge - 46.0
		var deck := Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y - 0.2, pz))
		_collider(body, deck, Vector3(edge - x0, 0.4, 6.0))
		var px := x0 + 0.5
		while px < edge:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(px + 0.6, y - 0.08, pz)), Vector3(1.15, 0.16, 6.0), 0.02, wood)
			px += 1.2
		for side: float in [-1.0, 1.0]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3((x0 + edge) * 0.5, y - 0.32, pz + side * 2.7)), Vector3(edge - x0, 0.3, 0.25), 0.03, wood.darkened(0.2))
		px = x0 + 2.0
		while px < edge:
			for side: float in [-2.6, 2.6]:
				mb.add_lathe(Transform3D(Basis.IDENTITY, Vector3(px, y - 5.8, pz + side)), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.2, 5.8), Vector2(0.0, 5.85)]),
					8, PackedColorArray([Color(0.2, 0.22, 0.2, WOOD), wood.darkened(0.3)]), 40.0)
			px += 6.0
		_boat(mb, body, Vector3(x0 + 14.0, MapLayout.SEA_LEVEL, pz + 6.5), boat_cols[k][0], boat_cols[k][1], 9.0)
		_boat(mb, body, Vector3(x0 + 30.0, MapLayout.SEA_LEVEL, pz - 6.5), boat_cols[(k + 1) % 3][0], boat_cols[(k + 1) % 3][1], 7.0)
		k += 1
	# Crane: a hazard-yellow tower and jib, a cab, the hook.
	var cr := Vector3(qa.x - 10.0, y, (qa.z + qb.z) * 0.5 - 10.0)
	var yellow := Color(StreetKit.HAZARD_YELLOW.darkened(0.05), PAINTED)
	_solid(mb, body, Transform3D(Basis.IDENTITY, cr + Vector3(0, 12, 0)), Vector3(2.2, 24, 2.2), yellow, 0.08, yellow.darkened(0.3))
	for lv in 8:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(0, 1.5 + lv * 3.0, 0)), Vector3(2.3, 0.12, 2.3), 0.02, yellow.darkened(0.15))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(-12, 24.6, 0)), Vector3(34, 1.4, 1.6), 0.08, yellow)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(5, 24.0, 0)), Vector3(4, 3, 2.4), 0.08, Color(0.36, 0.38, 0.4, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(1.5, 26.2, 0)), Vector3(2.4, 2.2, 2.4), 0.06, Color(0.9, 0.89, 0.86, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(1.5, 26.3, 0)), Vector3(2.45, 0.9, 2.2), 0.02, Color(0.14, 0.19, 0.24, GLASS))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(-24, 17.0, 0)), Vector3(0.08, 14, 0.08), 0.01, Color(0.18, 0.18, 0.19, METAL))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, cr + Vector3(-24, 9.6, 0)), Vector3(1.2, 0.8, 1.2), 0.08, Color(0.72, 0.18, 0.13, PAINTED))
	# Container stacks: ribbed steel boxes in muted shipping colours.
	var cols := [Color(0.6, 0.24, 0.18), Color(0.2, 0.34, 0.52), Color(0.26, 0.44, 0.3), Color(0.74, 0.52, 0.2), Color(0.42, 0.3, 0.44), Color(0.7, 0.7, 0.68)]
	var ci := 0
	for row in 3:
		for col in 4:
			var height := 1 + (row + col) % 3
			for level in height:
				var c := Vector3(inner - 6.0 - row * 3.2, y + 1.3 + level * 2.6, qa.z - 12.0 - col * 7.0)
				_container(mb, body, c, cols[ci % cols.size()])
				ci += 1
	_label(root, "TURBO HARBOUR", Vector3(inner - 2.0, y + 9.0, (qa.z + qb.z) * 0.5 + 18.0), 200, Color(1.0, 0.85, 0.25), PI * 0.5, true)
	_mesh(body, mb, _props_mat)
	_mesh(body, conc, _concrete_mat)
	_mesh(body, ground, _paving_mat)
	root.add_child(body)


## A 6 m shipping container: corrugated sides (raised ribs), corner posts, doors.
func _container(mb: MeshBuilder, body: StaticBody3D, c: Vector3, col: Color) -> void:
	var paint := Color(col, PAINTED)
	_solid(mb, body, Transform3D(Basis.IDENTITY, c), Vector3(2.5, 2.6, 6.2), paint, 0.04, paint.darkened(0.2))
	for s: float in [-1.0, 1.0]:
		var rz := -2.8
		while rz < 2.9:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(s * 1.27, 0, rz)), Vector3(0.04, 2.3, 0.12), 0.01, paint.darkened(0.08))
			rz += 0.4
	for cx: float in [-1.2, 1.2]:
		for cz: float in [-3.05, 3.05]:
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, c + Vector3(cx, 0, cz)), Vector3(0.14, 2.62, 0.14), 0.02, paint.darkened(0.25))


## A moored boat (rounded hull, deck, cabin) floating at `at` (water line).
func _boat(mb: MeshBuilder, body: StaticBody3D, at: Vector3, hull: Color, cabin: Color, length: float) -> void:
	var w := length * 0.36
	var h := Color(hull, PAINTED)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)), Vector3(length * 0.8, 1.4, w), w * 0.3, h, Color(0.16, 0.17, 0.18, PAINTED))
	var bow := Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 1.0)), at + Vector3(-length * 0.38, 0.3, 0))
	mb.add_bevel_box(bow, Vector3(w * 0.72, 1.2, w * 0.72), w * 0.2, h, Color(0.16, 0.17, 0.18, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.92, 0)), Vector3(length * 0.82, 0.08, w * 1.02), 0.03, Color(0.86, 0.85, 0.82, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(length * 0.1, 1.6, 0)), Vector3(length * 0.32, 1.3, w * 0.7), 0.08, Color(cabin, PAINTED))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, at + Vector3(length * 0.1, 1.78, 0)), Vector3(length * 0.33, 0.42, w * 0.72), 0.03, Color(0.14, 0.19, 0.24, GLASS))
	mb.add_lathe(Transform3D(Basis.IDENTITY, at + Vector3(length * 0.15, 2.25, 0)), PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.03, 2.2), Vector2(0.0, 2.25)]), 6,
		PackedColorArray([Color(0.75, 0.76, 0.77, METAL)]))
	_collider(body, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), Vector3(length, 2.2, w))


# ------------------------------------------------------- islet and bridge --

func _build_islet(root: Node3D) -> void:
	var t: TerrainBuilder = _roads._terrain
	var body := StaticBody3D.new()
	body.name = "Lighthouse"
	var mb := MeshBuilder.new()
	# Lighthouse: a smooth tapered tower in red and white bands, a gallery
	# with railings, the lamp room, a domed roof.
	var c := MapLayout.ISLET_CENTER
	var base := Vector3(c.x, t.height_at(c.x, c.y), c.y)
	var bands := 6
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 0.5), Vector2(2.7, 0.6)])
	var cols := PackedColorArray([Color(0.6, 0.58, 0.55, CONCRETE), Color(0.6, 0.58, 0.55, CONCRETE), Color(0.6, 0.58, 0.55, CONCRETE), Color(0.6, 0.58, 0.55, CONCRETE)])
	for k in bands + 1:
		var y := 0.6 + k * (16.2 / bands)
		prof.append(Vector2(lerpf(2.6, 1.8, float(k) / bands), y))
		cols.append(Color(0.74, 0.17, 0.13, PAINTED) if k % 2 == 0 else Color(0.9, 0.89, 0.86, PAINTED))
	mb.add_lathe(Transform3D(Basis.IDENTITY, base), prof, 16, cols, 20.0)
	_collider(body, Transform3D(Basis.IDENTITY, base + Vector3.UP * 8.4), Vector3(4.4, 16.8, 4.4))
	var dark := Color(0.2, 0.21, 0.22, PAINTED)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 16.8), PackedVector2Array([Vector2(1.8, 0.0), Vector2(2.9, 0.15), Vector2(2.9, 0.4), Vector2(0.0, 0.4)]), 16,
		PackedColorArray([dark]), 30.0)
	for k in 16:
		var a := TAU * k / 16.0
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, base + Vector3(cos(a) * 2.75, 17.65, sin(a) * 2.75)), Vector3(0.06, 0.9, 0.06), 0.01, dark)
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 18.05), PackedVector2Array([Vector2(2.78, 0.0), Vector2(2.78, 0.06), Vector2(0.0, 0.06)]), 16,
		PackedColorArray([dark]))
	mb.add_lathe(Transform3D(Basis.IDENTITY, base + Vector3.UP * 19.6), PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.95, 0.0), Vector2(1.7, 0.6),
		Vector2(1.0, 1.4), Vector2(0.25, 1.9), Vector2(0.2, 2.3), Vector2(0.0, 2.35)]), 16, PackedColorArray([Color(0.7, 0.17, 0.13, PAINTED)]), 40.0)
	for k in 8:
		var a := TAU * k / 8.0
		mb.add_bevel_box(Transform3D(Basis(Vector3.UP, -a), base + Vector3(cos(a) * 1.5, 18.4, sin(a) * 1.5)), Vector3(0.06, 2.4, 0.06), 0.01, dark)
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
	# Keeper's cottage: whitewashed walls, a slate roof, a door and windows.
	var hx := base + Vector3(10.0, 0, 7.0)
	_solid(mb, body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 1.6, 0)), Vector3(7, 3.2, 5), Color(0.9, 0.88, 0.82, PAINTED), 0.05, Color(0.66, 0.65, 0.6, PAINTED))
	_collider(body, Transform3D(Basis.IDENTITY, hx + Vector3(0, 3.5, 0)), Vector3(7.6, 0.6, 5.6))
	var slate := Color(0.3, 0.33, 0.36, PAINTED)
	for s: float in [-1.0, 1.0]:
		mb.add_bevel_box(Transform3D(Basis(Vector3.RIGHT, s * 0.6), hx + Vector3(0, 4.0, s * 1.35)), Vector3(7.6, 0.14, 3.3), 0.03, slate)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(-1.5, 1.05, 2.51)), Vector3(0.95, 2.1, 0.06), 0.02, Color(0.18, 0.3, 0.46, PAINTED))
	for wx: float in [0.8, 2.4]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(wx, 1.7, 2.51)), Vector3(0.9, 1.0, 0.05), 0.02, Color(0.14, 0.19, 0.24, GLASS))
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, hx + Vector3(2.5, 4.4, 0)), Vector3(0.6, 1.4, 0.6), 0.04, Color(0.6, 0.58, 0.55, CONCRETE))
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


func _glow_material(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m
