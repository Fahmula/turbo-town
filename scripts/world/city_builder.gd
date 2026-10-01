@tool
class_name CityBuilder
extends RefCounted
## City blocks: raised sidewalks with beveled curbs, stylized buildings,
## parks, a plaza and parking lots, plus spawn requests for street props.

const PALETTE := [
	Color(0.95, 0.56, 0.45), Color(0.97, 0.82, 0.52), Color(0.56, 0.76, 0.92),
	Color(0.70, 0.86, 0.62), Color(0.92, 0.91, 0.86), Color(0.78, 0.46, 0.36),
	Color(0.66, 0.64, 0.78), Color(0.99, 0.70, 0.32), Color(0.95, 0.70, 0.78),
	Color(0.50, 0.80, 0.78),
]
const SIDEWALK_COLOR := Color(0.83, 0.82, 0.79)
const LOT_COLOR := Color(0.74, 0.73, 0.70)
const GRASS_COLOR := Color(0.43, 0.72, 0.33)
const PLAZA_COLOR := Color(0.88, 0.80, 0.68)
const ASPHALT_COLOR := Color(0.33, 0.34, 0.38)

var _terrain: TerrainBuilder
var _rng := RandomNumberGenerator.new()
## Filled during build; the world builder instantiates these.
var tree_spots: Array[Vector3] = []
var prop_spawns: Array[Dictionary] = []


func _init(terrain: TerrainBuilder) -> void:
	_terrain = terrain
	_rng.seed = 2024


func build(parent: Node3D, intersections: Array[Vector3]) -> void:
	var root := Node3D.new()
	root.name = "City"
	parent.add_child(root)

	var slabs := MeshBuilder.new()
	var paint := MeshBuilder.new()
	var buildings := MeshBuilder.new()
	var details := MeshBuilder.new()
	var building_body := StaticBody3D.new()
	building_body.name = "Buildings"

	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	for j in g.size() - 1:
		for i in g.size() - 1:
			var x0 := g[i] + hw
			var x1 := g[i + 1] - hw
			var z0 := g[j] + hw
			var z1 := g[j + 1] - hw
			var type: String = MapLayout.BLOCK_TYPES[j][i]
			_add_block(slabs, paint, buildings, details, building_body, type, x0, z0, x1, z1)

	_add_street_lamps(intersections)
	_add_billboards(root)

	root.add_child(slabs.build_node("Sidewalks", load("res://assets/materials/props.tres"), true, 1.0))
	var paint_node := paint.build_node("Paint", load("res://assets/materials/props.tres"))
	root.add_child(paint_node)
	var bmi := MeshInstance3D.new()
	bmi.name = "Mesh"
	bmi.mesh = buildings.build_mesh(load("res://assets/materials/building.tres"))
	building_body.add_child(bmi)
	root.add_child(building_body)
	root.add_child(details.build_node("Details", load("res://assets/materials/props.tres"), true, 1.0))


func _add_block(slabs: MeshBuilder, paint: MeshBuilder, bmb: MeshBuilder, details: MeshBuilder, body: StaticBody3D,
		type: String, x0: float, z0: float, x1: float, z1: float) -> void:
	var h := MapLayout.CURB_HEIGHT
	var sw := MapLayout.SIDEWALK_WIDTH
	_add_slab(slabs, x0, z0, x1, z1, h, 0.35, SIDEWALK_COLOR)
	var ix0 := x0 + sw
	var ix1 := x1 - sw
	var iz0 := z0 + sw
	var iz1 := z1 - sw
	var top := h + 0.004
	var inner_col := LOT_COLOR
	match type:
		"park":
			inner_col = GRASS_COLOR
		"plaza":
			inner_col = PLAZA_COLOR
		"parking":
			inner_col = ASPHALT_COLOR
	_flat_quad(slabs, ix0, iz0, ix1, iz1, top, inner_col)

	match type:
		"buildings":
			_add_buildings(bmb, details, body, ix0, iz0, ix1, iz1)
		"park":
			_add_park(paint, details, ix0, iz0, ix1, iz1)
		"plaza":
			_add_plaza(paint, details, body, ix0, iz0, ix1, iz1)
		"parking":
			_add_parking(paint, ix0, iz0, ix1, iz1)

	# A street lamp in the middle of each side of the block, arm over the road
	# (between the street trees).
	var mx := (x0 + x1) * 0.5
	var mz := (z0 + z1) * 0.5
	for lamp: Array in [[Vector3(mx, h, z0 + 0.5), 0.0], [Vector3(mx, h, z1 - 0.5), PI],
			[Vector3(x0 + 0.5, h, mz), PI * 0.5], [Vector3(x1 - 0.5, h, mz), -PI * 0.5]]:
		prop_spawns.append({"scene": "lamp", "xform": Transform3D(Basis(Vector3.UP, lamp[1]), lamp[0])})

	# Street trees along the sidewalks of some blocks.
	if type != "parking" and _rng.randf() < 0.6:
		var step := 16.0
		var inset := 1.6
		var t := x0 + 8.0
		while t < x1 - 6.0:
			tree_spots.append(Vector3(t, h, z0 + inset))
			tree_spots.append(Vector3(t, h, z1 - inset))
			t += step


## Raised slab with beveled edges (drivable curb).
func _add_slab(mb: MeshBuilder, x0: float, z0: float, x1: float, z1: float, h: float, b: float, col: Color) -> void:
	var a0 := Vector3(x0, 0, z0)
	var a1 := Vector3(x1, 0, z0)
	var a2 := Vector3(x1, 0, z1)
	var a3 := Vector3(x0, 0, z1)
	var t0 := Vector3(x0 + b, h, z0 + b)
	var t1 := Vector3(x1 - b, h, z0 + b)
	var t2 := Vector3(x1 - b, h, z1 - b)
	var t3 := Vector3(x0 + b, h, z1 - b)
	var curb := col.darkened(0.08)
	mb.add_quad(t0, t3, t2, t1, col)
	mb.add_quad(a1, a0, t0, t1, curb)
	mb.add_quad(a2, a1, t1, t2, curb)
	mb.add_quad(a3, a2, t2, t3, curb)
	mb.add_quad(a0, a3, t3, t0, curb)


func _flat_quad(mb: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), col)


func _add_box_collider(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


# ------------------------------------------------------------- buildings ---

func _add_buildings(bmb: MeshBuilder, details: MeshBuilder, body: StaticBody3D, x0: float, z0: float, x1: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var centrality := 1.0 - clampf(Vector2(cx, cz).length() / 200.0, 0.0, 1.0)
	var parcels: Array[Rect2] = []
	var w := x1 - x0
	var d := z1 - z0
	var pattern := _rng.randi_range(0, 3)
	if centrality > 0.6 and _rng.randf() < 0.5:
		pattern = 0
	match pattern:
		0:
			parcels.append(Rect2(x0, z0, w, d))
		1:
			parcels.append(Rect2(x0, z0, w * 0.5, d))
			parcels.append(Rect2(x0 + w * 0.5, z0, w * 0.5, d))
		2:
			parcels.append(Rect2(x0, z0, w, d * 0.5))
			parcels.append(Rect2(x0, z0 + d * 0.5, w * 0.5, d * 0.5))
			parcels.append(Rect2(x0 + w * 0.5, z0 + d * 0.5, w * 0.5, d * 0.5))
		_:
			for a in 2:
				for b in 2:
					parcels.append(Rect2(x0 + w * 0.5 * a, z0 + d * 0.5 * b, w * 0.5, d * 0.5))
	var base_y := MapLayout.CURB_HEIGHT
	for p in parcels:
		var m := _rng.randf_range(1.0, 2.5)
		var fp := p.grow(-m)
		var height := _rng.randf_range(9.0, 18.0) + centrality * _rng.randf_range(5.0, 30.0)
		if pattern == 0:
			height += 10.0
		height = snappedf(height, 3.4) + 0.6
		var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
		var center := Vector3(fp.get_center().x, base_y + height * 0.5, fp.get_center().y)
		var size := Vector3(fp.size.x, height, fp.size.y)
		var xf := Transform3D(Basis.IDENTITY, center)
		bmb.add_box(xf, size, col, true)
		_add_box_collider(body, xf, size)
		# Roof trim.
		var trim := col.darkened(0.25)
		trim.a = 0.0
		bmb.add_box(Transform3D(Basis.IDENTITY, center + Vector3(0, height * 0.5 + 0.25, 0)), Vector3(size.x + 0.4, 0.5, size.z + 0.4), trim, true)
		var roof_y := base_y + height + 0.5
		# Setback upper section on tall buildings.
		if height > 24.0 and _rng.randf() < 0.7:
			var inset := _rng.randf_range(3.0, 6.0)
			var up_h := snappedf(_rng.randf_range(6.0, 16.0), 3.4)
			var up_size := Vector3(maxf(size.x - inset * 2.0, 6.0), up_h, maxf(size.z - inset * 2.0, 6.0))
			var up_col: Color = col.lightened(0.12) if _rng.randf() < 0.5 else PALETTE[_rng.randi() % PALETTE.size()]
			var up_xf := Transform3D(Basis.IDENTITY, Vector3(center.x, roof_y + up_h * 0.5, center.z))
			bmb.add_box(up_xf, up_size, up_col, true)
			_add_box_collider(body, up_xf, up_size)
			roof_y += up_h
			size = up_size
		# Rooftop clutter.
		for k in _rng.randi_range(1, 3):
			var bx := center.x + _rng.randf_range(-size.x * 0.3, size.x * 0.3)
			var bz := center.z + _rng.randf_range(-size.z * 0.3, size.z * 0.3)
			var bs := Vector3(_rng.randf_range(1.5, 3.5), _rng.randf_range(1.0, 2.0), _rng.randf_range(1.5, 3.0))
			details.add_box(Transform3D(Basis.IDENTITY, Vector3(bx, roof_y + bs.y * 0.5, bz)), bs, Color(0.7, 0.72, 0.75))
		if _rng.randf() < 0.35:
			var tx := center.x + _rng.randf_range(-size.x * 0.25, size.x * 0.25)
			var tz := center.z + _rng.randf_range(-size.z * 0.25, size.z * 0.25)
			details.add_prism(Vector3(tx, roof_y, tz), 1.4, 1.4, 2.6, 8, Color(0.62, 0.45, 0.33))
			details.add_prism(Vector3(tx, roof_y + 2.6, tz), 1.5, 0.1, 1.0, 8, Color(0.5, 0.36, 0.27))
		# Shop awnings on the ground floor.
		if _rng.randf() < 0.6:
			_add_awning(details, fp, base_y)


func _add_awning(details: MeshBuilder, fp: Rect2, base_y: float) -> void:
	var colors := [Color(0.9, 0.2, 0.2), Color(0.2, 0.6, 0.9), Color(0.2, 0.7, 0.4), Color(1.0, 0.6, 0.1)]
	var col: Color = colors[_rng.randi() % colors.size()]
	var side := _rng.randi() % 4
	var y := base_y + 3.0
	var depth := 1.6
	var a: Vector3
	var b: Vector3
	var out: Vector3
	match side:
		0:
			a = Vector3(fp.position.x + 2.0, y, fp.position.y); b = Vector3(fp.end.x - 2.0, y, fp.position.y); out = Vector3(0, 0, -1)
		1:
			a = Vector3(fp.end.x - 2.0, y, fp.end.y); b = Vector3(fp.position.x + 2.0, y, fp.end.y); out = Vector3(0, 0, 1)
		2:
			a = Vector3(fp.end.x, y, fp.position.y + 2.0); b = Vector3(fp.end.x, y, fp.end.y - 2.0); out = Vector3(1, 0, 0)
		_:
			a = Vector3(fp.position.x, y, fp.end.y - 2.0); b = Vector3(fp.position.x, y, fp.position.y + 2.0); out = Vector3(-1, 0, 0)
	var drop := Vector3.DOWN * 0.7
	var stripes := int(a.distance_to(b) / 1.2)
	for s in stripes:
		var p0 := a.lerp(b, float(s) / stripes)
		var p1 := a.lerp(b, float(s + 1) / stripes)
		var c := col if s % 2 == 0 else Color(0.97, 0.97, 0.95)
		details.add_quad(p1, p0, p0 + out * depth + drop, p1 + out * depth + drop, c)
		details.add_quad(p0, p1, p1 + out * depth + drop, p0 + out * depth + drop, c)


# ---------------------------------------------------------------- others ---

func _add_park(paint: MeshBuilder, details: MeshBuilder, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := MapLayout.CURB_HEIGHT + 0.01
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Cross-shaped footpaths.
	_flat_quad(paint, cx - 1.5, z0, cx + 1.5, z1, y, PLAZA_COLOR)
	_flat_quad(paint, x0, cz - 1.5, x1, cz + 1.5, y + 0.002, PLAZA_COLOR)
	# Pond.
	details.add_prism(Vector3(cx + 12, y - 0.05, cz + 12), 6.0, 6.0, 0.08, 10, Color(0.3, 0.65, 0.85))
	for k in 22:
		var p := Vector3(_rng.randf_range(x0 + 3, x1 - 3), MapLayout.CURB_HEIGHT, _rng.randf_range(z0 + 3, z1 - 3))
		if absf(p.x - cx) < 3.5 or absf(p.z - cz) < 3.5:
			continue
		if Vector2(p.x - cx - 12, p.z - cz - 12).length() < 8.0:
			continue
		tree_spots.append(p)


func _add_plaza(paint: MeshBuilder, details: MeshBuilder, body: StaticBody3D, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := MapLayout.CURB_HEIGHT
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Tile pattern.
	var tile := 5.0
	var x := x0
	while x < x1 - 0.1:
		var z := z0
		while z < z1 - 0.1:
			if (int((x - x0) / tile) + int((z - z0) / tile)) % 2 == 0:
				_flat_quad(paint, x, z, minf(x + tile, x1), minf(z + tile, z1), y + 0.01, PLAZA_COLOR.darkened(0.06))
			z += tile
		x += tile
	# Fountain in the middle.
	var c := Vector3(cx, y, cz)
	details.add_prism(c, 7.0, 7.0, 0.7, 16, Color(0.85, 0.84, 0.8))
	details.add_prism(c + Vector3(0, 0.7, 0), 6.3, 6.3, 0.02, 16, Color(0.35, 0.7, 0.9))
	details.add_prism(c, 1.0, 0.8, 3.5, 8, Color(0.85, 0.84, 0.8))
	details.add_prism(c + Vector3(0, 3.5, 0), 2.4, 2.4, 0.3, 12, Color(0.85, 0.84, 0.8))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 7.0
	cyl.height = 0.7
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.35, 0)
	body.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cyl2 := CylinderShape3D.new()
	cyl2.radius = 1.0
	cyl2.height = 3.8
	cs2.shape = cyl2
	cs2.position = c + Vector3(0, 1.9, 0)
	body.add_child(cs2)
	# Fun stuff: a couple of kickers and a cone slalom.
	prop_spawns.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, 0.0), Vector3(cx - 16, y, z1 - 2)), "length": 7.0, "height": 1.6, "width": 5.0, "shape": 1})
	prop_spawns.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, PI), Vector3(cx + 16, y, z0 + 2)), "length": 7.0, "height": 1.6, "width": 5.0, "shape": 1})
	for k in 8:
		prop_spawns.append({"scene": "cone", "xform": Transform3D(Basis.IDENTITY, Vector3(x0 + 5 + k * 6.0, y, cz + 14))})


func _add_parking(paint: MeshBuilder, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := MapLayout.CURB_HEIGHT + 0.012
	var white := Color(0.95, 0.95, 0.92)
	var stall_w := 2.9
	var stall_d := 5.5
	# Rows of stalls facing each other, with aisles between.
	var rows := [z0 + 1.0, z0 + 1.0 + stall_d * 2.0 + 7.0, z0 + 1.0 + stall_d * 4.0 + 14.0]
	for row_z in rows:
		if row_z + stall_d * 2.0 > z1:
			break
		var x := x0 + 3.0
		while x + stall_w < x1 - 3.0:
			for side in 2:
				var sz: float = row_z + side * stall_d
				_flat_quad(paint, x - 0.06, sz, x + 0.06, sz + stall_d, y, white)
				if _rng.randf() < 0.35:
					var rot := 0.0 if side == 0 else PI
					var pos := Vector3(x + stall_w * 0.5, MapLayout.CURB_HEIGHT, sz + stall_d * 0.5)
					prop_spawns.append({"scene": "parked_car", "xform": Transform3D(Basis(Vector3.UP, rot + PI * 0.5 * 0.0 + _rng.randf_range(-0.05, 0.05)), pos)})
			x += stall_w
		_flat_quad(paint, x0 + 3.0, row_z + stall_d - 0.06, x - 0.0, row_z + stall_d + 0.06, y, white)


## Street lamps on block corners, and at every intersection with 3+ roads a
## traffic light for each approach, standing on the approach's near-right
## corner with its arm over the lane. Light axis 0 = north/south traffic.
func _add_street_lamps(intersections: Array[Vector3]) -> void:
	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	var off := hw + 1.3
	# corner (sx, sz) -> [flag of the approach it serves, travel dir, axis]
	var corners := [
		[1.0, 1.0, 4, Vector3(0, 0, -1), 0],   # SE corner: northbound from the south
		[-1.0, 1.0, 8, Vector3(1, 0, 0), 1],   # SW corner: eastbound from the west
		[-1.0, -1.0, 1, Vector3(0, 0, 1), 0],  # NW corner: southbound from the north
		[1.0, -1.0, 2, Vector3(-1, 0, 0), 1],  # NE corner: westbound from the east
	]
	for idx in intersections.size():
		var it := intersections[idx]
		var gx := it.x
		var gz := it.y
		var flags := int(it.z)
		var count := 0
		for b in 4:
			if flags & (1 << b):
				count += 1
		for c in corners:
			var px: float = gx + c[0] * off
			var pz: float = gz + c[1] * off
			var on_block := px > g[0] and px < g[g.size() - 1] and pz > g[0] and pz < g[g.size() - 1]
			var y := MapLayout.CURB_HEIGHT if on_block else 0.0
			if count >= 3 and flags & c[2]:
				var t: Vector3 = c[3]
				var r := t.cross(Vector3.UP)
				prop_spawns.append({"scene": "traffic_light", "xform": Transform3D(Basis(r, Vector3.UP, -t), Vector3(px, y, pz)),
					"signal": [idx, c[4]]})
			elif on_block:
				var yaw := atan2(c[0], c[1])  # arm points at the intersection
				prop_spawns.append({"scene": "lamp", "xform": Transform3D(Basis(Vector3.UP, yaw), Vector3(px, y, pz))})


func _add_billboards(root: Node3D) -> void:
	var boards := [
		["TURBO TOWN", Vector3(-150 + 10, 0.15, -150 + 10), 0.8, Color(0.95, 0.3, 0.5)],
		["JUMP PARK ->", Vector3(12, 0.15, 170), PI, Color(1.0, 0.65, 0.1)],
		["HOT PIZZA", Vector3(160, 0.15, -120), -PI * 0.5, Color(0.2, 0.7, 0.95)],
		["MOUNTAIN ROAD", Vector3(-12, 0.15, -170), 0.0, Color(0.3, 0.75, 0.35)],
	]
	for b in boards:
		var node := Node3D.new()
		node.position = b[1]
		node.rotation.y = b[2]
		var mb := MeshBuilder.new()
		mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(0.4, 8.0, 0.4), Color(0.5, 0.5, 0.55))
		mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 9.5, 0)), Vector3(9.0, 3.6, 0.3), b[3])
		mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 9.5, 0.05)), Vector3(8.4, 3.0, 0.3), Color(0.98, 0.97, 0.94))
		node.add_child(mb.build_node("Board", load("res://assets/materials/props.tres"), true))
		for side in [1.0, -1.0]:
			var label := Label3D.new()
			label.text = b[0]
			label.font_size = 160
			label.outline_size = 0
			label.modulate = b[3].darkened(0.2)
			label.pixel_size = 0.012
			label.position = Vector3(0, 9.5, 0.23 * side)
			label.rotation.y = 0.0 if side > 0 else PI
			label.double_sided = false
			node.add_child(label)
		root.add_child(node)
