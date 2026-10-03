@tool
class_name TerrainBuilder
extends RefCounted
## Island heightfield: procedural hills + mountain, flattened under roads and
## special areas, then turned into chunked meshes and a HeightMapShape3D.
##
## Vertex data for terrain.gdshader (material weights, not a blended colour):
##   COLOR.r = sand, COLOR.g = dirt, COLOR.b = dry grass, COLOR.a = patch noise
##   UV.x    = road influence (worn verge), UV.y = lush grass (1 - the rest)
## Rock comes from the slope, per pixel. The same weights feed the grass
## tufts (grass_field.gd) through `grass_textures()`.

const CHUNK_CELLS := 64

var n: int
var cell: float
var half: float
var heights := PackedFloat32Array()

var _road_w := PackedFloat32Array()
var _road_h := PackedFloat32Array()
var _road_d := PackedFloat32Array()
## Distance (m) from each vertex to the nearest road/flat-area edge (negative
## under it), 99 when nothing is near. Keeps grass tufts off the verges.
var _road_e := PackedFloat32Array()
## Areas where no grass should grow, as Rect2(x, z, w, d) in metres: paved
## sites the road raster doesn't cover (stunt park, city blocks).
var grass_exclusions: Array[Rect2] = []
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
var _height_tex: ImageTexture
var _mask_tex: ImageTexture


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
	# Paved sites that the road raster doesn't cover.
	grass_exclusions.append(Rect2(MapLayout.PARK_MIN, MapLayout.PARK_MAX - MapLayout.PARK_MIN))
	# The bridge to the lighthouse islet (its deck meets the ground at both ends).
	grass_exclusions.append(Rect2(MapLayout.BRIDGE_WEST_X - 3.0, -MapLayout.BRIDGE_WIDTH * 0.5 - 1.5, MapLayout.BRIDGE_EAST_X - MapLayout.BRIDGE_WEST_X + 6.0, MapLayout.BRIDGE_WIDTH + 3.0))
	var ac := MapLayout.APRON_CENTER
	grass_exclusions.append(Rect2(ac.x - 45.0, ac.z - MapLayout.APRON_SIZE.y * 0.5 - 24.0, 100.0, 24.0))


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
	_road_e.resize(n * n)
	_road_w.fill(0.0)
	_road_d.fill(1e9)
	_road_e.fill(99.0)
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
			_road_e[idx] = minf(_road_e[idx], d - half_width)
			# Take the strongest influence; on ties (e.g. both fully flattened)
			# the nearest segment decides the height, so slopes stay accurate.
			var cur := _road_w[idx]
			if w > cur + 0.001 or (w > cur - 0.001 and d < _road_d[idx]):
				_road_w[idx] = maxf(w, cur)
				_road_h[idx] = lerpf(a.y, b.y, t) - 0.15
				_road_d[idx] = d


func raster_circle(center: Vector2, radius: float, height: float, blend: float) -> void:
	# The summit disc is open ground (grass grows on it); the other flat areas are paved.
	var open_ground := center.distance_to(MapLayout.MOUNTAIN_CENTER) < 5.0
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
			if not open_ground:
				_road_e[idx] = minf(_road_e[idx], d - radius)
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

	# Per-vertex normals and material weights, shared by all chunks.
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var mask := PackedByteArray()
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	mask.resize(n * n * 4)
	var park_rects := parks()
	for j in n:
		for i in n:
			var idx := j * n + i
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			var nrm := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			normals[idx] = nrm
			var x := -half + i * cell
			var z := -half + j * cell
			var wgt := _weights_for(x, z, heights[idx], nrm.y, _road_w[idx], _road_e[idx])
			colors[idx] = wgt
			uvs[idx] = Vector2(_road_w[idx], clampf(1.0 - wgt.r - wgt.g - wgt.b * 0.5, 0.0, 1.0))
			var dens := _grass_density(x, z, heights[idx], nrm.y, wgt, _road_e[idx], park_rects)
			mask[idx * 4] = int(dens * 255.0)
			mask[idx * 4 + 1] = int(clampf(maxf(wgt.b, smoothstep(0.1, 0.7, wgt.g) * 0.9), 0.0, 1.0) * 255.0)
			mask[idx * 4 + 2] = int(wgt.a * 255.0)
			mask[idx * 4 + 3] = 255
	# Textures for the grass shader: exact heights (R32F) and the density mask.
	_height_tex = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array()))
	_mask_tex = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, mask))

	var chunks := (n - 1) / CHUNK_CELLS
	for cz in chunks:
		for cx in chunks:
			root.add_child(_build_chunk(cx, cz, normals, colors, uvs, material))

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


func _build_chunk(cx: int, cz: int, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, material: Material) -> MeshInstance3D:
	var size := CHUNK_CELLS + 1
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(size * size)
	nrm.resize(size * size)
	cols.resize(size * size)
	uv.resize(size * size)
	for lj in size:
		for li in size:
			var i := cx * CHUNK_CELLS + li
			var j := cz * CHUNK_CELLS + lj
			var g := j * n + i
			var k := lj * size + li
			verts[k] = Vector3(-half + i * cell, heights[g], -half + j * cell)
			nrm[k] = normals[g]
			cols[k] = colors[g]
			uv[k] = uvs[g]
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
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [cx, cz]
	mi.mesh = mesh
	return mi


## Material weights for one vertex (see the class comment): the shader turns
## them into ground using real texture scans.
func _weights_for(x: float, z: float, h: float, _up: float, _road_weight: float, road_e: float) -> Color:
	var cn := _color_noise.get_noise_2d(x, z) * 0.5 + 0.5
	# Dry grass high on the mountain (the shader adds dry patches lower down).
	var dry := smoothstep(30.0, 46.0, h) * 0.4
	# Dirt fields to the east.
	var fields := smoothstep(330.0, 360.0, x) * (1.0 - smoothstep(170.0, 200.0, absf(z)))
	var dirt := fields * 0.9
	# Road verges: a worn, gravelly strip along country roads.
	dirt = maxf(dirt, smoothstep(-0.5, 0.5, road_e) * (1.0 - smoothstep(0.5, 3.5, road_e)) * 0.35 * (1.0 - fields))
	# Beach and sea floor.
	var sand := 0.0
	var shore := shore_factor(x, z)
	if shore > 0.02:
		sand = smoothstep(2.2, 0.8, h) * smoothstep(0.02, 0.12, shore)
	return Color(sand, dirt, dry, cn)


## A flat approximate ground colour (the world map still draws with it):
## the old palette blend, driven by the same weights as the shader.
func _color_for(x: float, z: float, h: float, up: float, road_w: float) -> Color:
	var w := _weights_for(x, z, h, up, road_w, 99.0)
	var c := ArtPalette.GRASS_DARK.lerp(ArtPalette.GRASS_LIGHT, w.a)
	c = c.lerp(ArtPalette.GRASS_DRY, w.b)
	c = c.lerp(ArtPalette.DIRT.lerp(ArtPalette.DIRT_DARK, w.a), w.g)
	c = c.lerp(ArtPalette.ROCK_DARK.lerp(ArtPalette.ROCK_LIGHT, w.a), 1.0 - smoothstep(0.72, 0.9, up))
	c = c.lerp(c.darkened(0.12), road_w * 0.6)
	return c.lerp(ArtPalette.SAND_LIGHT.lerp(ArtPalette.SAND_DARK, w.a), w.r)


## 0..1 where grass tufts may grow: not on sand, dirt, steep rock, under
## water, on or at the edge of roads, paved sites or the city blocks.
func _grass_density(x: float, z: float, h: float, up: float, wgt: Color, road_e: float, _park_rects: Array[Rect2]) -> float:
	var d := (1.0 - smoothstep(0.25, 0.7, wgt.r)) * (1.0 - smoothstep(0.1, 0.8, wgt.g))
	if d <= 0.0:
		return 0.0
	d *= smoothstep(0.62, 0.82, up) * smoothstep(-1.0, -0.4, h) * smoothstep(1.0, 2.6, road_e)
	if d <= 0.0:
		return 0.0
	# The city: blocks are paved; the parks' lawns get tufts in the shader.
	if absf(x) < 161.0 and absf(z) < 161.0:
		d *= smoothstep(0.5, 4.0, _outside(Rect2(-156.0, -156.0, 312.0, 312.0), x, z))
	for r: Rect2 in grass_exclusions:
		if x > r.position.x - 4.0 and x < r.end.x + 4.0 and z > r.position.y - 4.0 and z < r.end.y + 4.0:
			d *= smoothstep(0.5, 4.0, _outside(r, x, z))
	return d


## Distance from (x, z) to the outside of `r` (negative inside).
func _outside(r: Rect2, x: float, z: float) -> float:
	var dx := maxf(r.position.x - x, x - r.end.x)
	var dz := maxf(r.position.y - z, z - r.end.y)
	return maxf(dx, dz)


## Lawn rectangles of the city's parks (inner lawn of each "park" block,
## after the kerb and sidewalk), as Rect2(x, z, w, d).
static func parks() -> Array[Rect2]:
	var list: Array[Rect2] = []
	var g := MapLayout.CITY_GRID
	var inset := MapLayout.CITY_ROAD_WIDTH * 0.5 + MapLayout.SIDEWALK_WIDTH
	for j in g.size() - 1:
		for i in g.size() - 1:
			if MapLayout.BLOCK_TYPES[j][i] == "park":
				list.append(Rect2(g[i] + inset, g[j] + inset, g[i + 1] - g[i] - 2.0 * inset, g[j + 1] - g[j] - 2.0 * inset))
	return list


## Textures for grass_field.gd: "heights" (R32F, one texel per vertex) and
## "mask" (RGBA8: R grass density, G dry grass, B patch noise). Valid after build().
func grass_textures() -> Dictionary:
	return {"heights": _height_tex, "mask": _mask_tex}
