@tool
class_name CityBuilder
extends RefCounted
## City blocks (ART_BIBLE.md §15-§17): raised sidewalks with drivable
## kerbs, buildings (BuildingKit), parks, a plaza and car parks, street
## furniture, billboards, plus spawn requests for the physics props (lamps,
## traffic lights, hydrants...).

var _terrain: TerrainBuilder
var _rng := RandomNumberGenerator.new()
## Filled during build; the world builder instantiates these.
var tree_spots: Array[Vector3] = []
var prop_spawns: Array[Dictionary] = []
## Static bollards (one merged mesh with colliders).
var _bollards: Array[Vector3] = []


func _init(terrain: TerrainBuilder) -> void:
	_terrain = terrain
	_rng.seed = 2024


func build(parent: Node3D, intersections: Array[Vector3]) -> void:
	var root := Node3D.new()
	root.name = "City"
	parent.add_child(root)

	# Paved ground with collision; buildings and their clutter in one pair of
	# meshes per block, so blocks cull on their own.
	var ground := MeshBuilder.new()
	var building_body := StaticBody3D.new()
	building_body.name = "Buildings"
	var blocks := Node3D.new()
	blocks.name = "Blocks"

	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	for j in g.size() - 1:
		for i in g.size() - 1:
			var x0 := g[i] + hw
			var x1 := g[i + 1] - hw
			var z0 := g[j] + hw
			var z1 := g[j + 1] - hw
			var type: String = MapLayout.BLOCK_TYPES[j][i]
			var kit := BuildingKit.new(ground, building_body)
			_add_block(ground, kit, building_body, type, x0, z0, x1, z1)
			_add_block_meshes(blocks, kit, "Block_%d_%d" % [i, j])

	_add_street_lamps(intersections)
	_add_billboards(root)

	root.add_child(ground.build_node("Paving", load("res://assets/materials/env/paving.tres"), true, 1.0))
	root.add_child(blocks)
	root.add_child(building_body)
	var bmb := MeshBuilder.new()
	var bbody := StaticBody3D.new()
	bbody.name = "Bollards"
	for p in _bollards:
		StreetKit._bollard(bmb, Transform3D(Basis.IDENTITY, p))
		_add_box_collider(bbody, Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.5), Vector3(0.22, 1.0, 0.22))
	var bm := MeshInstance3D.new()
	bm.mesh = bmb.build_mesh(StreetKit.material())
	bbody.add_child(bm)
	root.add_child(bbody)


## A block's buildings ("Facades") and its clutter ("Clutter": roof
## machinery, awnings, fountains), the clutter dropped beyond 400 m.
func _add_block_meshes(parent: Node3D, kit: BuildingKit, block_name: String) -> void:
	var node := Node3D.new()
	node.name = block_name
	if not kit.facade.is_empty():
		var fmi := MeshInstance3D.new()
		fmi.name = "Facades"
		fmi.mesh = MeshBuilder.with_lods(kit.facade.build_mesh(load("res://assets/materials/env/facade.tres")))
		node.add_child(fmi)
	if not kit.clutter.is_empty():
		var cmi := MeshInstance3D.new()
		cmi.name = "Clutter"
		cmi.mesh = MeshBuilder.with_lods(kit.clutter.build_mesh(StreetKit.material()))
		cmi.visibility_range_end = 400.0
		cmi.visibility_range_end_margin = 40.0
		cmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(cmi)
	parent.add_child(node)


## A block: a raised slab with a drivable kerb (kerb stones, a paving grid)
## and, inside, buildings, a lawn, plaza tiles or car park asphalt
## (paving.gdshader); lamps along each side, street trees, furniture.
func _add_block(ground: MeshBuilder, kit: BuildingKit, body: StaticBody3D,
		type: String, x0: float, z0: float, x1: float, z1: float) -> void:
	var h := MapLayout.CURB_HEIGHT
	var sw := MapLayout.SIDEWALK_WIDTH
	_add_kerbed_slab(ground, x0, z0, x1, z1, h)
	var ix0 := x0 + sw
	var ix1 := x1 - sw
	var iz0 := z0 + sw
	var iz1 := z1 - sw
	var top := h + 0.004
	match type:
		"park":
			_flat_quad(ground, ix0, iz0, ix1, iz1, top, Color(ArtPalette.LAWN, 0.0))
		"plaza":
			_flat_quad(ground, ix0, iz0, ix1, iz1, top, Color(ArtPalette.PLAZA, 0.5))
		"parking":
			_flat_quad(ground, ix0, iz0, ix1, iz1, top, Color(ArtPalette.ASPHALT, 0.25))
	match type:
		"buildings":
			_add_buildings(kit, ix0, iz0, ix1, iz1)
		"park":
			_add_park(ground, kit.clutter, ix0, iz0, ix1, iz1)
		"plaza":
			_add_plaza(kit.clutter, body, ix0, iz0, ix1, iz1)
		"parking":
			_add_parking(ground, ix0, iz0, ix1, iz1)

	var mx := (x0 + x1) * 0.5
	var mz := (z0 + z1) * 0.5
	for lamp: Array in [[Vector3(mx, h, z0 + 0.5), 0.0], [Vector3(mx, h, z1 - 0.5), PI],
			[Vector3(x0 + 0.5, h, mz), PI * 0.5], [Vector3(x1 - 0.5, h, mz), -PI * 0.5]]:
		prop_spawns.append({"scene": "lamp", "xform": Transform3D(Basis(Vector3.UP, lamp[1]), lamp[0])})
	if type != "parking" and _rng.randf() < 0.6:
		var step := 16.0
		var inset := 1.6
		var t := x0 + 8.0
		while t < x1 - 6.0:
			tree_spots.append(Vector3(t, h, z0 + inset))
			tree_spots.append(Vector3(t, h, z1 - inset))
			t += step


## Buildings on a block: one to four parcels, taller toward the centre,
## dressed by BuildingKit. The district follows centrality:
## stone and glass towers downtown, brick and stone mid-rise around them,
## stucco low-rise toward the edges (ART_BIBLE.md §15).
func _add_buildings(kit: BuildingKit, x0: float, z0: float, x1: float, z1: float) -> void:
	var rng := kit.rng
	rng.seed = hash(Vector2i(int(x0), int(z0)))
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var centrality := 1.0 - clampf(Vector2(cx, cz).length() / 200.0, 0.0, 1.0)
	var parcels: Array[Rect2] = []
	var w := x1 - x0
	var d := z1 - z0
	var pattern := rng.randi_range(0, 3)
	if centrality > 0.6 and rng.randf() < 0.5:
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
	var last_style := -1
	for p in parcels:
		var fp := p.grow(-rng.randf_range(0.8, 1.6))
		var height := rng.randf_range(9.0, 18.0) + centrality * rng.randf_range(5.0, 30.0)
		if pattern == 0:
			height += 10.0
		var floors := maxi(roundi((height - BuildingKit.GROUND_FLOOR) / BuildingKit.FLOOR), 1)
		height = BuildingKit.GROUND_FLOOR + floors * BuildingKit.FLOOR
		var look := _pick_look(rng, centrality, height, last_style)
		last_style = look["style"]
		kit.add_building(fp, MapLayout.CURB_HEIGHT, height, look)


func _pick_look(rng: RandomNumberGenerator, centrality: float, height: float, avoid: int) -> Dictionary:
	var S := BuildingKit.Style
	var style: int
	for attempt in 2:
		var r := rng.randf()
		if centrality > 0.6:
			if height > 30.0:
				style = S.CURTAIN if r < 0.6 else (S.LIMESTONE if r < 0.85 else S.RIBBON)
			else:
				style = S.LIMESTONE if r < 0.4 else (S.BRICK if r < 0.7 else S.RIBBON)
		elif centrality > 0.35:
			style = S.BRICK if r < 0.35 else (S.LIMESTONE if r < 0.6 else (S.STUCCO if r < 0.85 else S.RIBBON))
		else:
			style = S.STUCCO if r < 0.55 else (S.BRICK if r < 0.85 else S.LIMESTONE)
		if style != avoid:
			break
	var walls: Array = [ArtPalette.STUCCO_WALLS, ArtPalette.LIMESTONE_WALLS, ArtPalette.BRICK_WALLS,
		ArtPalette.MULLIONS, ArtPalette.PANEL_WALLS][style]
	var wall: Color = walls[rng.randi() % walls.size()]
	wall = wall * rng.randf_range(0.96, 1.04)
	var stone: Color = ArtPalette.LIMESTONE_WALLS[rng.randi() % ArtPalette.LIMESTONE_WALLS.size()]
	var trim: Color = ArtPalette.TRIM_WHITE if style != S.LIMESTONE else stone.lightened(0.1)
	if style == S.STUCCO and wall.get_luminance() > 0.8:
		trim = stone
	var accent: Color = ArtPalette.SHOP_ACCENTS[rng.randi() % ArtPalette.SHOP_ACCENTS.size()]
	var look := {
		"style": style, "wall": Color(wall, 1.0), "trim": trim, "stone": stone, "seed": rng.randf(),
		"shops": rng.randf() < (0.85 if centrality > 0.3 else 0.55),
		"fascia": accent.darkened(0.45), "awning": accent,
		"tank": (style == S.BRICK or style == S.STUCCO) and height < 30.0 and rng.randf() < 0.45,
	}
	if style == S.CURTAIN:
		look["podium"] = 2
	var tiers: Array = []
	if height > 24.0 and rng.randf() < 0.7:
		tiers.append([rng.randf_range(3.0, 6.0), BuildingKit.FLOOR * rng.randi_range(2, 5)])
		if height > 40.0 and rng.randf() < 0.6:
			tiers.append([rng.randf_range(2.5, 5.0), BuildingKit.FLOOR * rng.randi_range(2, 4)])
	look["tiers"] = tiers
	return look


## A park: paved cross paths, a pond with a stone edge, trees.
func _add_park(ground: MeshBuilder, clutter: MeshBuilder, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := MapLayout.CURB_HEIGHT + 0.01
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var path := Color(ArtPalette.SIDEWALK.darkened(0.04), 1.0)
	_flat_quad(ground, cx - 1.5, z0, cx + 1.5, z1, y, path)
	_flat_quad(ground, x0, cz - 1.5, x1, cz + 1.5, y + 0.002, path)
	_pond(clutter, Vector3(cx + 12, MapLayout.CURB_HEIGHT, cz + 12), 6.0, ArtPalette.POND)
	for k in 22:
		var p := Vector3(_rng.randf_range(x0 + 3, x1 - 3), MapLayout.CURB_HEIGHT, _rng.randf_range(z0 + 3, z1 - 3))
		if absf(p.x - cx) < 3.5 or absf(p.z - cz) < 3.5:
			continue
		if Vector2(p.x - cx - 12, p.z - cz - 12).length() < 8.0:
			continue
		tree_spots.append(p)


## A round pool: a low stone kerb and glossy water a little below its top.
func _pond(clutter: MeshBuilder, c: Vector3, r: float, water: Color) -> void:
	var stone := Color(ArtPalette.LIMESTONE_WALLS[1], StreetKit.CONCRETE)
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c), PackedVector2Array([
		Vector2(r + 0.35, 0.0), Vector2(r + 0.35, 0.22), Vector2(r + 0.3, 0.27), Vector2(r, 0.27), Vector2(r - 0.05, 0.22), Vector2(r - 0.05, 0.1)]),
		40, PackedColorArray([stone.darkened(0.15), stone, stone, stone, stone.darkened(0.2), stone.darkened(0.35)]), 30.0)
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c + Vector3.UP * 0.14), PackedVector2Array([Vector2(r, 0.0), Vector2(0.0, 0.0)]),
		40, PackedColorArray([Color(water.darkened(0.3), StreetKit.GLASS)]))


## The plaza: tiles from paving.gdshader, a stone fountain with basin,
## column and bowl, a couple of kickers and a cone slalom.
func _add_plaza(clutter: MeshBuilder, body: StaticBody3D, x0: float, z0: float, x1: float, z1: float) -> void:
	var y := MapLayout.CURB_HEIGHT
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var c := Vector3(cx, y, cz)
	var stone := Color(ArtPalette.LIMESTONE_WALLS[1], StreetKit.CONCRETE)
	var water := Color(ArtPalette.FOUNTAIN.darkened(0.25), StreetKit.GLASS)
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c), PackedVector2Array([
		Vector2(7.0, 0.0), Vector2(7.05, 0.5), Vector2(7.15, 0.55), Vector2(7.15, 0.68), Vector2(7.05, 0.72),
		Vector2(6.55, 0.72), Vector2(6.45, 0.66), Vector2(6.45, 0.3)]), 48,
		PackedColorArray([stone.darkened(0.2), stone, stone, stone, stone, stone, stone.darkened(0.2), stone.darkened(0.4)]), 30.0)
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c + Vector3.UP * 0.55), PackedVector2Array([Vector2(6.45, 0.0), Vector2(0.0, 0.0)]), 48,
		PackedColorArray([water]))
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c), PackedVector2Array([
		Vector2(1.1, 0.0), Vector2(1.1, 0.7), Vector2(0.75, 0.9), Vector2(0.55, 1.2), Vector2(0.45, 2.9), Vector2(0.6, 3.2),
		Vector2(2.4, 3.45), Vector2(2.5, 3.7), Vector2(2.3, 3.72), Vector2(0.3, 3.6), Vector2(0.25, 4.3), Vector2(0.4, 4.5), Vector2(0.0, 4.75)]), 24,
		PackedColorArray([stone.darkened(0.2), stone, stone, stone, stone, stone, stone.darkened(0.25), stone, stone.darkened(0.1), stone, stone, stone]), 35.0)
	clutter.add_lathe(Transform3D(Basis.IDENTITY, c + Vector3.UP * 3.68), PackedVector2Array([Vector2(2.3, 0.0), Vector2(0.3, 0.0)]), 24, PackedColorArray([water]))
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
	prop_spawns.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, 0.0), Vector3(cx - 16, y, z1 - 2)), "length": 7.0, "height": 1.6, "width": 5.0, "shape": 1})
	prop_spawns.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, PI), Vector3(cx + 16, y, z0 + 2)), "length": 7.0, "height": 1.6, "width": 5.0, "shape": 1})
	for k in 8:
		prop_spawns.append({"scene": "cone", "xform": Transform3D(Basis.IDENTITY, Vector3(x0 + 5 + k * 6.0, y, cz + 14))})


## Kerb slope (drivable: rises 0.15 m over 0.35 m), a kerb-stone top band
## and the sidewalk paving over the whole block top.
func _add_kerbed_slab(mb: MeshBuilder, x0: float, z0: float, x1: float, z1: float, h: float) -> void:
	var b := 0.35
	var kt := b + 0.16
	var kerb := Color(ArtPalette.CURB, 0.75)
	var walk := Color(ArtPalette.SIDEWALK, 1.0)
	var ring := func(inset: float, y: float) -> Array[Vector3]:
		return [Vector3(x0 + inset, y, z0 + inset), Vector3(x1 - inset, y, z0 + inset),
			Vector3(x1 - inset, y, z1 - inset), Vector3(x0 + inset, y, z1 - inset)]
	var outer: Array[Vector3] = ring.call(0.0, 0.0)
	var slope_top: Array[Vector3] = ring.call(b, h)
	var band_in: Array[Vector3] = ring.call(kt, h)
	# Side k runs from corner k to corner k+1; UV.x = metres along it.
	for k in 4:
		var k1 := (k + 1) % 4
		var along_x := k % 2 == 0
		var u0: float = outer[k].x if along_x else outer[k].z
		var u1: float = outer[k1].x if along_x else outer[k1].z
		mb.add_quad(outer[k1], outer[k], slope_top[k], slope_top[k1], kerb,
			Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, 0), Vector2(u1, 0))
		mb.add_quad(slope_top[k1], slope_top[k], band_in[k], band_in[k1], kerb,
			Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, 0), Vector2(u1, 0))
	mb.add_quad(band_in[0], band_in[3], band_in[2], band_in[1], walk)


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

## Car park stall lines (plain paint in paving.gdshader) and parked cars.
func _add_parking(paint: MeshBuilder, x0: float, z0: float, x1: float, z1: float) -> void:
	var white := Color(ArtPalette.ROAD_WHITE, 0.0)
	var y := MapLayout.CURB_HEIGHT + 0.012
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
		_add_billboard(root, b[0], b[1], b[2], b[3])


## A billboard: a steel monopole, a framed board with a catwalk, printed
## both sides (the words are Label3D).
func _add_billboard(root: Node3D, text: String, pos: Vector3, yaw: float, accent: Color) -> void:
	var node := StaticBody3D.new()
	node.position = pos
	node.rotation.y = yaw
	var mb := MeshBuilder.new()
	var steel := Color(0.42, 0.43, 0.44, StreetKit.METAL)
	mb.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.55, 0.0), Vector2(0.55, 0.3),
		Vector2(0.32, 0.4), Vector2(0.24, 7.6), Vector2(0.0, 7.7)]), 12, PackedColorArray([steel.darkened(0.2), steel]), 40.0)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 7.65, 0)), Vector3(2.2, 0.25, 0.5), 0.03, steel)
	var frame := Color(0.22, 0.23, 0.24, StreetKit.PAINTED)
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 9.5, 0)), Vector3(9.2, 3.7, 0.36), 0.05, frame)
	for side: float in [1.0, -1.0]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 9.5, 0.17 * side)), Vector3(8.8, 3.3, 0.04), 0.01,
			Color(0.93, 0.92, 0.88, StreetKit.SIGN))
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.1, 0.18 * side)), Vector3(8.8, 0.3, 0.04), 0.01,
			Color(accent.darkened(0.1), StreetKit.SIGN))
	# Catwalk and lamp arms on the front.
	mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(0, 7.55, 0.75)), Vector3(9.0, 0.06, 0.8), 0.01, Color(0.35, 0.36, 0.37, StreetKit.METAL))
	for x: float in [-3.0, 0.0, 3.0]:
		mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(x, 7.62, 1.05)), Vector3(0.3, 0.1, 0.18), 0.02, Color(0.2, 0.2, 0.21, StreetKit.PAINTED))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(StreetKit.material())
	node.add_child(mi)
	_add_box_collider(node, Transform3D(Basis.IDENTITY, Vector3(0, 3.85, 0)), Vector3(0.5, 7.7, 0.5))
	_add_box_collider(node, Transform3D(Basis.IDENTITY, Vector3(0, 9.5, 0)), Vector3(9.2, 3.7, 0.4))
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = 160
		label.outline_size = 0
		label.modulate = accent.darkened(0.25)
		label.pixel_size = 0.012
		label.position = Vector3(0, 9.6, 0.2 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		label.double_sided = false
		node.add_child(label)
	root.add_child(node)
