@tool
class_name TerrainBuilder
extends RefCounted
## Island heightfield: procedural hills + mountain, flattened under roads and
## special areas, then turned into chunked meshes and a HeightMapShape3D.

const CHUNK_CELLS := 64

var n: int
var cell: float
var half: float
var heights := PackedFloat32Array()

var _road_w := PackedFloat32Array()
var _road_h := PackedFloat32Array()
var _road_d := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()


func _init() -> void:
	half = MapLayout.TERRAIN_HALF_SIZE
	cell = MapLayout.TERRAIN_CELL
	n = int(round(2.0 * half / cell)) + 1
	_noise.seed = 7
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 4
	_detail.seed = 13
	_detail.frequency = 0.018
	_detail.fractal_octaves = 3
	_color_noise.seed = 3
	_color_noise.frequency = 0.035


# ---------------------------------------------------------------- heights ---

## Natural terrain height before roads are cut in.
func base_height(x: float, z: float) -> float:
	var core := maxf(absf(x), absf(z))
	var outside := smoothstep(290.0, 350.0, core)
	var h := MapLayout.CORE_FLAT_HEIGHT
	h += outside * (_noise.get_noise_2d(x, z) * 7.0 + 2.5)

	# Mountain to the north.
	var north := smoothstep(-300.0, -390.0, z)
	if north > 0.0:
		var dm := Vector2(x, z).distance_to(MapLayout.MOUNTAIN_CENTER)
		var r := MapLayout.MOUNTAIN_RADIUS
		var m := MapLayout.MOUNTAIN_HEIGHT * exp(-dm * dm / (2.0 * r * r))
		m += absf(_detail.get_noise_2d(x, z)) * 9.0 * smoothstep(40.0, 160.0, dm)
		h += north * m

	# Dirt jumps in the east fields.
	if x > 320.0:
		for mv: Vector4 in MapLayout.DIRT_MOUNDS:
			var dx := x - mv.x
			var dz := z - mv.y
			var d2 := dx * dx + dz * dz
			if d2 < mv.z * mv.z * 6.0:
				h += mv.w * exp(-d2 / (2.0 * mv.z * mv.z * 0.45))

	# Gentle, low beach area to the west.
	var west_flat := smoothstep(-290.0, -350.0, x) * (1.0 - smoothstep(70.0, 150.0, absf(z)))
	h = lerpf(h, 0.6, west_flat * 0.85)

	# Stunt park stays flat.
	var park := _rect_mask(x, z, MapLayout.PARK_MIN - Vector2(20, 20), MapLayout.PARK_MAX + Vector2(20, 20), 45.0)
	h = lerpf(h, MapLayout.CORE_FLAT_HEIGHT, park)

	# Island shoreline.
	h = lerpf(h, -6.5, shore_factor(x, z))

	# Lighthouse islet out in the sea to the west.
	var di := Vector2(x, z).distance_to(MapLayout.ISLET_CENTER)
	if di < MapLayout.ISLET_RADIUS + 25.0:
		var top := MapLayout.ISLET_HEIGHT + _detail.get_noise_2d(x, z) * 0.6
		h = maxf(h, lerpf(-6.5, top, smoothstep(MapLayout.ISLET_RADIUS + 20.0, MapLayout.ISLET_RADIUS - 6.0, di)))
	return h


func shore_factor(x: float, z: float) -> float:
	var sx := x * (MapLayout.SHORE_DISTANCE / MapLayout.SHORE_DISTANCE_WEST) if x < 0.0 else x
	var d := pow(pow(absf(sx), 4.0) + pow(absf(z), 4.0), 0.25)
	return smoothstep(MapLayout.SHORE_DISTANCE - 60.0, MapLayout.SHORE_DISTANCE + 60.0, d)


func _rect_mask(x: float, z: float, mn: Vector2, mx: Vector2, blend: float) -> float:
	var dx := maxf(mn.x - x, x - mx.x)
	var dz := maxf(mn.y - z, z - mx.y)
	var d := maxf(dx, dz)
	return 1.0 - smoothstep(0.0, blend, d)


func generate_base() -> void:
	heights.resize(n * n)
	_road_w.resize(n * n)
	_road_h.resize(n * n)
	_road_d.resize(n * n)
	_road_w.fill(0.0)
	_road_d.fill(1e9)
	for j in n:
		var z := -half + j * cell
		for i in n:
			heights[j * n + i] = base_height(-half + i * cell, z)


# ----------------------------------------------------------------- raster ---

## Flattens terrain along a road segment (a->b are road surface points).
func raster_segment(a: Vector3, b: Vector3, half_width: float, shoulder: float) -> void:
	var inner := half_width + cell
	var r := inner + shoulder
	var i0 := maxi(int(floor((minf(a.x, b.x) - r + half) / cell)), 0)
	var i1 := mini(int(ceil((maxf(a.x, b.x) + r + half) / cell)), n - 1)
	var j0 := maxi(int(floor((minf(a.z, b.z) - r + half) / cell)), 0)
	var j1 := mini(int(ceil((maxf(a.z, b.z) + r + half) / cell)), n - 1)
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	for j in range(j0, j1 + 1):
		var z := -half + j * cell
		for i in range(i0, i1 + 1):
			var x := -half + i * cell
			var apx := x - a.x
			var apz := z - a.z
			var t := 0.0
			if len2 > 0.0:
				t = clampf((apx * abx + apz * abz) / len2, 0.0, 1.0)
			var dx := apx - abx * t
			var dz := apz - abz * t
			var d := sqrt(dx * dx + dz * dz)
			if d >= r:
				continue
			var w := 1.0 - smoothstep(inner, r, d)
			var idx := j * n + i
			# Take the strongest influence; on ties (e.g. both fully flattened)
			# the nearest segment decides the height, so slopes stay accurate.
			var cur := _road_w[idx]
			if w > cur + 0.001 or (w > cur - 0.001 and d < _road_d[idx]):
				_road_w[idx] = maxf(w, cur)
				_road_h[idx] = lerpf(a.y, b.y, t) - 0.15
				_road_d[idx] = d


func raster_circle(center: Vector2, radius: float, height: float, blend: float) -> void:
	var r := radius + blend
	var i0 := maxi(int(floor((center.x - r + half) / cell)), 0)
	var i1 := mini(int(ceil((center.x + r + half) / cell)), n - 1)
	var j0 := maxi(int(floor((center.y - r + half) / cell)), 0)
	var j1 := mini(int(ceil((center.y + r + half) / cell)), n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(-half + i * cell, -half + j * cell).distance_to(center)
			if d >= r:
				continue
			var w := 1.0 - smoothstep(radius, r, d)
			var idx := j * n + i
			if w > _road_w[idx] + 0.001:
				_road_w[idx] = w
				_road_h[idx] = height
				_road_d[idx] = 0.0


func apply_raster() -> void:
	for idx in n * n:
		var w := _road_w[idx]
		if w > 0.0:
			heights[idx] = lerpf(heights[idx], _road_h[idx], w)


# --------------------------------------------------------------- sampling ---

func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / cell, 0.0, n - 1.001)
	var fz := clampf((z + half) / cell, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * n + i]
	var h10 := heights[j * n + i + 1]
	var h01 := heights[(j + 1) * n + i]
	var h11 := heights[(j + 1) * n + i + 1]
	# Match the mesh triangulation (split along v00-v11).
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	return Vector2(dx, dz).length() * 0.5


## How strongly a road/flat area shaped the terrain near (x, z): 0 = untouched.
func road_weight_at(x: float, z: float) -> float:
	var i := clampi(int(round((x + half) / cell)), 0, n - 1)
	var j := clampi(int(round((z + half) / cell)), 0, n - 1)
	return _road_w[j * n + i]


# ------------------------------------------------------------------ build ---

func build(parent: Node3D, material: Material) -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)

	# Per-vertex normals and colours, shared by all chunks.
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	normals.resize(n * n)
	colors.resize(n * n)
	for j in n:
		for i in n:
			var idx := j * n + i
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			var nrm := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			normals[idx] = nrm
			colors[idx] = _color_for(-half + i * cell, -half + j * cell, heights[idx], nrm.y, _road_w[idx])

	var chunks := (n - 1) / CHUNK_CELLS
	for cz in chunks:
		for cx in chunks:
			root.add_child(_build_chunk(cx, cz, normals, colors, material))

	# Collision: one heightmap, scaled to the cell size.
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface_grip", 0.85)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell, 1.0, cell)
	body.add_child(cs)
	root.add_child(body)


func _build_chunk(cx: int, cz: int, normals: PackedVector3Array, colors: PackedColorArray, material: Material) -> MeshInstance3D:
	var size := CHUNK_CELLS + 1
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(size * size)
	nrm.resize(size * size)
	cols.resize(size * size)
	for lj in size:
		for li in size:
			var i := cx * CHUNK_CELLS + li
			var j := cz * CHUNK_CELLS + lj
			var g := j * n + i
			var k := lj * size + li
			verts[k] = Vector3(-half + i * cell, heights[g], -half + j * cell)
			nrm[k] = normals[g]
			cols[k] = colors[g]
	idx.resize(CHUNK_CELLS * CHUNK_CELLS * 6)
	var w := 0
	for lj in CHUNK_CELLS:
		for li in CHUNK_CELLS:
			var v00 := lj * size + li
			var v10 := v00 + 1
			var v01 := v00 + size
			var v11 := v01 + 1
			idx[w] = v00; idx[w + 1] = v10; idx[w + 2] = v11
			idx[w + 3] = v00; idx[w + 4] = v11; idx[w + 5] = v01
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [cx, cz]
	mi.mesh = mesh
	return mi


func _color_for(x: float, z: float, h: float, up: float, road_w: float) -> Color:
	var cn := _color_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var grass := Color(0.38, 0.66, 0.27).lerp(Color(0.56, 0.76, 0.30), cn)
	var c := grass
	# Dry, yellowish grass high on the mountain.
	c = c.lerp(Color(0.66, 0.70, 0.36), smoothstep(22.0, 40.0, h) * 0.7)
	# Dirt fields to the east.
	var fields := smoothstep(330.0, 360.0, x) * (1.0 - smoothstep(170.0, 200.0, absf(z)))
	c = c.lerp(Color(0.72, 0.52, 0.34).lerp(Color(0.64, 0.45, 0.30), cn), fields * 0.9)
	# Rock on steep slopes.
	var steep := 1.0 - smoothstep(0.72, 0.9, up)
	c = c.lerp(Color(0.55, 0.52, 0.50).lerp(Color(0.62, 0.60, 0.58), cn), steep)
	# Road verges slightly worn.
	c = c.lerp(c.darkened(0.12), road_w * 0.6)
	# Beach and sea floor.
	var shore := shore_factor(x, z)
	if shore > 0.02:
		var sand := Color(0.95, 0.86, 0.62).lerp(Color(0.90, 0.80, 0.56), cn)
		c = c.lerp(sand, smoothstep(2.2, 0.8, h) * smoothstep(0.02, 0.12, shore))
	return c
