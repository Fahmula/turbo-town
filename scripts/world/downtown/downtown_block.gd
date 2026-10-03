@tool
class_name DowntownBlock
extends RefCounted
## A downtown city block built from the Downtown City MegaKit
## (experiment/quaternius-downtown-city): buildings round the edge of the
## block, flush with the sidewalk like a Boston / New York street wall, a
## corner building at each corner with two frontages, mid-block buildings of
## different widths, heights and styles in between, sometimes a service
## alley through to the courtyard behind.
##
## Each building is ONE MeshInstance3D (one surface, megakit.gdshader) with
## its own palette (instance uniform), so buildings cull and LOD on their own
## and a whole street costs a draw call per building.

## The showcase blocks (column, row) of MapLayout.BLOCK_TYPES: the avenue
## from the City Center spawn east through the middle of downtown.
const SHOWCASE := [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2), Vector2i(0, 2)]
## Buildings switch to their far-LOD proxy (MegaKitLibrary.far) this far
## from the camera (measured to the building's centre), with a hysteresis
## margin so they don't flicker at the boundary.
const FAR_DISTANCE := 90.0
const FAR_MARGIN := 8.0

var parent: Node3D
var body: StaticBody3D
var _alleys: Array = []
var rng := RandomNumberGenerator.new()
## Shop sign spots of every building (see DowntownBuilding.sign_spots).
var sign_spots: Array = []
## Every block built: {"name", "inner" (Rect2 the buildings stand in,
## snapped to the 2 m grid), "slab" (Rect2 of the whole raised block incl.
## sidewalks), "sides" (Array[bool] S, E, N, W built), "alleys" (Array of
## Rect2 gaps between buildings that reach the sidewalk)}.
var blocks: Array[Dictionary] = []
## Every building footprint (Rect2), for street dressing to keep clear of.
var footprints: Array[Rect2] = []
var building_count := 0
var triangles := 0
var far_triangles := 0
var build_usec := 0


## Dev / A-B switch: `--legacy-downtown` builds the old BuildingKit blocks.
static func enabled() -> bool:
	if OS.get_cmdline_user_args().has("--legacy-downtown"):
		return false
	return ResourceLoader.exists(MegaKit.LIBRARY_PATH)


static func is_showcase(col: int, row: int) -> bool:
	return enabled() and SHOWCASE.has(Vector2i(col, row))


func _init(parent_node: Node3D, collision: StaticBody3D) -> void:
	parent = parent_node
	body = collision


## Fills the block interior (x0..x1, z0..z1: inside the sidewalks) with
## buildings. `centrality` 0..1 makes the middle of downtown taller.
## `sides` = which edges to build on (south, east, north, west); the
## others stay open (a car park behind, say).
func build(block_name: String, x0: float, z0: float, x1: float, z1: float, base_y: float,
		centrality: float, sides: Array[bool] = [true, true, true, true]) -> void:
	var t0 := Time.get_ticks_usec()
	rng.seed = hash(block_name)
	var slab := Rect2(x0, z0, x1 - x0, z1 - z0).grow(MapLayout.SIDEWALK_WIDTH)
	# Snap to the kit's 2 m grid, centred in the block.
	var w := floorf((x1 - x0) / 2.0) * 2.0
	var d := floorf((z1 - z0) / 2.0) * 2.0
	x0 = (x0 + x1 - w) * 0.5
	z0 = (z0 + z1 - d) * 0.5
	x1 = x0 + w
	z1 = z0 + d
	var node := Node3D.new()
	node.name = block_name
	parent.add_child(node)
	var info := {"name": block_name, "inner": Rect2(x0, z0, w, d), "slab": slab, "sides": sides, "alleys": []}
	blocks.append(info)

	var parcels: Array = []  # [Rect2, front flags, is_corner]
	# Corners first: square-ish buildings with two frontages.
	var cs := {}  # corner index (0 SW, 1 SE, 2 NE, 3 NW) -> Vector2 size (x, z)
	for k in 4:
		var s := Vector2(_even(16.0, 22.0), _even(16.0, 22.0))
		cs[k] = s
	var sw: Vector2 = cs[0]
	var se: Vector2 = cs[1]
	var ne: Vector2 = cs[2]
	var nw: Vector2 = cs[3]
	# Corner flags in S, E, N, W order.
	if sides[0] and sides[3]:
		parcels.append([Rect2(x0, z1 - sw.y, sw.x, sw.y), _f(true, false, false, true), true])
	if sides[0] and sides[1]:
		parcels.append([Rect2(x1 - se.x, z1 - se.y, se.x, se.y), _f(true, true, false, false), true])
	if sides[2] and sides[1]:
		parcels.append([Rect2(x1 - ne.x, z0, ne.x, ne.y), _f(false, true, true, false), true])
	if sides[2] and sides[3]:
		parcels.append([Rect2(x0, z0, nw.x, nw.y), _f(false, false, true, true), true])
	# Mid-block runs along each side between its corner buildings.
	if sides[0]:  # south: x from SW to SE corner
		_run(parcels, x0 + (sw.x if sides[3] else 0.0), x1 - (se.x if sides[1] else 0.0), func(a: float, b: float, dep: float) -> Rect2:
			return Rect2(a, z1 - dep, b - a, dep), 0)
	if sides[2]:  # north
		_run(parcels, x0 + (nw.x if sides[3] else 0.0), x1 - (ne.x if sides[1] else 0.0), func(a: float, b: float, dep: float) -> Rect2:
			return Rect2(a, z0, b - a, dep), 2)
	if sides[1]:  # east: z from NE to SE corner
		_run(parcels, z0 + (ne.y if sides[2] else 0.0), z1 - (se.y if sides[0] else 0.0), func(a: float, b: float, dep: float) -> Rect2:
			return Rect2(x1 - dep, a, dep, b - a), 1)
	if sides[3]:  # west
		_run(parcels, z0 + (nw.y if sides[2] else 0.0), z1 - (sw.y if sides[0] else 0.0), func(a: float, b: float, dep: float) -> Rect2:
			return Rect2(x0, a, dep, b - a), 3)

	(info["alleys"] as Array).append_array(_alleys)
	_alleys.clear()
	var last_style := ""
	for p: Array in parcels:
		var rect: Rect2 = p[0]
		var front: Array[bool] = p[1]
		var corner: bool = p[2]
		footprints.append(rect)
		var style := _pick_style(corner, last_style)
		last_style = style
		var floors := rng.randi_range(3, 6) + int(round(centrality * rng.randf_range(0.0, 4.0)))
		if corner:
			floors += rng.randi_range(0, 2)
		if style == "mansard":
			floors = maxi(floors - 1, 3)
		var batch := MegaKit.Batch.new(rng.randi(), true)
		var b := DowntownBuilding.new(batch, rng)
		b.build(rect, base_y, floors, front, style)
		var pals: Array = DowntownBuilding.STYLES[style]["palettes"]
		var palette: int = pals[rng.randi() % pals.size()]
		var mesh := batch.build()
		if mesh == null:
			continue
		var mi := MegaKit.instance(mesh, palette, "Building_%d" % building_count)
		mi.visibility_range_end = FAR_DISTANCE
		mi.visibility_range_end_margin = FAR_MARGIN
		node.add_child(mi)
		var far_mesh := batch.far.build()
		var fmi := MegaKit.instance(far_mesh, palette, "Building_%d_Far" % building_count)
		fmi.visibility_range_begin = FAR_DISTANCE
		fmi.visibility_range_begin_margin = FAR_MARGIN
		node.add_child(fmi)
		# Buildings hide whatever is behind them (occlusion culling).
		var occ := OccluderInstance3D.new()
		var box_occ := BoxOccluder3D.new()
		box_occ.size = Vector3(rect.size.x - 0.6, b.top_height - 1.2, rect.size.y - 0.6)
		occ.occluder = box_occ
		occ.position = Vector3(rect.get_center().x, base_y + (b.top_height - 1.2) * 0.5, rect.get_center().y)
		node.add_child(occ)
		far_triangles += batch.far.tris
		var dm := batch.build_decals()
		if dm:
			var dmi := MeshInstance3D.new()
			dmi.mesh = dm
			dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(dmi)
		for c: Array in b.colliders:
			var cs3 := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = c[1]
			cs3.shape = box
			cs3.transform = c[0]
			body.add_child(cs3)
		sign_spots.append_array(b.sign_spots)
		building_count += 1
		triangles += batch.tris
	build_usec += Time.get_ticks_usec() - t0


## Splits a block side from a to b (metres along it) into mid-block parcels
## of 8-20 m frontage, sometimes leaving a 4 m alley. `side` = 0 S, 1 E, 2 N, 3 W.
func _run(parcels: Array, a: float, b: float, rect_of: Callable, side: int) -> void:
	var length := b - a
	if length < 3.9:
		return
	var alley := -1.0
	if length > 26.0 and rng.randf() < 0.45:
		alley = a + _even(8.0, length - 12.0)
	var x := a
	while b - x > 0.1:
		if alley > 0.0 and absf(x - alley) < 0.1:
			_alleys.append(rect_of.call(x, x + 4.0, 16.0))
			x += 4.0
			continue
		var rest := b - x
		var stop := alley if alley > x else b
		var w := minf(_even(8.0, 20.0), stop - x)
		if stop - x - w < 6.0 and stop - x - w > 0.1:
			w = stop - x  # don't leave a sliver
		var dep := _even(12.0, 16.0)  # never deeper than a corner building (>= 16 m)
		var front := _f(side == 0, side == 1, side == 2, side == 3)
		parcels.append([rect_of.call(x, x + w, dep), front, false])
		x += w
		if rest <= 0.0:
			break


func _pick_style(corner: bool, avoid: String) -> String:
	var options: Array = ["hotel", "mansard", "commercial", "loft"] if corner else ["loft", "tenement", "warehouse", "commercial", "hotel", "tenement"]
	for attempt in 4:
		var s: String = options[rng.randi() % options.size()]
		if s != avoid:
			return s
	return options[0]


## A random even number of metres in [lo, hi].
func _even(lo: float, hi: float) -> float:
	return float(rng.randi_range(int(ceilf(lo / 2.0)), int(floorf(hi / 2.0))) * 2)


static func _f(s: bool, e: bool, n: bool, w: bool) -> Array[bool]:
	return [s, e, n, w]
