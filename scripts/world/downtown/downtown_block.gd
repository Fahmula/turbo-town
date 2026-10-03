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
var _alleys_all: Array = []
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


## Evaluation switch: every city block in MegaKit buildings instead of just
## the showcase (Project Settings > turbo_town/dev/megakit_whole_city, or
## `--megakit-city` on the command line).
static func whole_city() -> bool:
	return OS.get_cmdline_user_args().has("--megakit-city") \
		or bool(ProjectSettings.get_setting("turbo_town/dev/megakit_whole_city", false))


static func is_showcase(col: int, row: int) -> bool:
	return enabled() and (whole_city() or SHOWCASE.has(Vector2i(col, row)))


## A car park block's built sides: the two facing away from the city centre,
## so the lot sits in the inner corner, open to the streets nearest downtown.
static func car_park_sides(cx: float, cz: float) -> Array[bool]:
	return [cz > 0.0, cx > 0.0, cz <= 0.0, cx <= 0.0]


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
	_alleys_all = _alleys.duplicate()
	_alleys.clear()
	# Shop signs (facade.gdshader's sign boards, lit at night) and the block's
	# clutter (street_props.gdshader: awnings, sign cabinets, roof machinery
	# and water tanks, through BuildingKit's roof clutter).
	var signs := MeshBuilder.new()
	var dressing := BuildingKit.new(MeshBuilder.new(), body)
	dressing.rng.seed = rng.randi()
	# Blocks open on a side (a car park inside): the buildings' inward walls
	# face open ground, so they get windows too.
	var open_inside := sides.has(false)
	for p: Array in parcels:
		footprints.append(p[0])
	# Plan every building first (style, floors, height), so a taller building
	# knows where its party walls show above its neighbours.
	var plans: Array[Dictionary] = []
	var last_style := ""
	for p: Array in parcels:
		var rect: Rect2 = p[0]
		var front: Array[bool] = p[1]
		var corner: bool = p[2]
		var back: Array[bool] = [false, false, false, false]
		if open_inside:
			for k in 4:
				back[k] = not front[k] and _faces_inside(rect, k, x0, z0, x1, z1)
		var style := _pick_style(corner, last_style)
		last_style = style
		var floors := rng.randi_range(3, 6) + int(round(centrality * rng.randf_range(0.0, 4.0)))
		if corner:
			floors += rng.randi_range(0, 2)
		if style == "mansard":
			floors = maxi(floors - 1, 3)
		var top := DowntownBuilding.height_of(floors) + (3.0 if DowntownBuilding.STYLES[style]["roof"] == "mansard" else 1.0)
		plans.append({"rect": rect, "front": front, "back": back, "style": style, "floors": floors, "top": top})
	for plan: Dictionary in plans:
		plan["signs"] = _ghost_signs(plan, plans)

	for plan: Dictionary in plans:
		var rect: Rect2 = plan["rect"]
		var front: Array[bool] = plan["front"]
		var back: Array[bool] = plan["back"]
		var style: String = plan["style"]
		var floors: int = plan["floors"]
		var batch := MegaKit.Batch.new(rng.randi(), true)
		var b := DowntownBuilding.new(batch, rng)
		b.build(rect, base_y, floors, front, style, back)
		for g: Array in plan["signs"]:
			b.ghost_sign(rect, base_y, g[0], g[1], g[2], g[3], g[4], g[5], g[6])
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
		for spot: Array in b.sign_spots:
			_shopfronts(signs, dressing.clutter, spot[0], spot[1], palette)
		dressing._roof_clutter(b.roof_rect.grow(0.6), b.roof_y, b.water_tank, false)
		building_count += 1
		triangles += batch.tris
	if not signs.is_empty():
		var smi := MeshInstance3D.new()
		smi.name = "ShopSigns"
		smi.mesh = signs.build_mesh(load("res://assets/materials/env/facade.tres"))
		smi.visibility_range_end = 220.0
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(smi)
	if not dressing.clutter.is_empty():
		var cmi := MeshInstance3D.new()
		cmi.name = "Clutter"
		cmi.mesh = MeshBuilder.with_lods(dressing.clutter.build_mesh(StreetKit.material()))
		cmi.visibility_range_end = 400.0
		cmi.visibility_range_end_margin = 40.0
		cmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(cmi)
	build_usec += Time.get_ticks_usec() - t0


## A frontage's shops: the bay run is split into shops 4-8 m wide; each gets
## a sign board on the sign band (facade.gdshader sign style: an invented
## shop name, lit at night) in a painted cabinet, and some get a striped
## fabric awning under the band. `xf` = the wall frame at the middle of the
## run, 3.5 m up (DowntownBuilding.sign_spots).
func _shopfronts(signs: MeshBuilder, clutter: MeshBuilder, xf: Transform3D, run: float, palette: int) -> void:
	var xa := xf.basis.x
	var n := xf.basis.z
	var face := 0.05  # the sign band's front, off the wall plane
	var accent: Color = ArtPalette.SHOP_ACCENTS[(palette + rng.randi()) % ArtPalette.SHOP_ACCENTS.size()]
	var seed := floorf(rng.randf() * 1000.0) / 1000.0
	var x := -run * 0.5
	while run * 0.5 - x > 3.9:
		var w := minf(float(rng.randi_range(2, 4) * 2), run * 0.5 - x)
		if run * 0.5 - x - w < 3.9:
			w = run * 0.5 - x
		var mid := xf.origin + xa * (x + w * 0.5)
		if rng.randf() < 0.85:
			# Sign board: the sign atlas is 8:1, so at most 4.8 x 0.6 m.
			var bw := minf(w - 0.8, 4.8)
			var bh := 0.6
			var cab := Color(accent.darkened(0.55), BuildingKit.PAINTED)
			clutter.add_bevel_box(Transform3D(xf.basis, mid + n * (face + 0.04)), Vector3(bw + 0.12, bh + 0.12, 0.08), 0.015, cab)
			var grp := float(rng.randi_range(0, 60)) * 2.0
			var c := mid + n * (face + 0.085)
			var a := c - xa * bw * 0.5 + Vector3.DOWN * bh * 0.5
			var b := c + xa * bw * 0.5 + Vector3.DOWN * bh * 0.5
			var up := Vector3.UP * bh
			signs.set_uv2(Vector2(seed, BuildingKit.SIGN_STYLE))
			signs.add_quad(a, b, b + up, a + up, Color(1, 1, 1, 0.9),
				Vector2(grp + 0.12, 3.725), Vector2(grp + 1.88, 3.725), Vector2(grp + 1.88, 4.225), Vector2(grp + 0.12, 4.225))
		if rng.randf() < 0.45:
			_awning(clutter, mid - xa * (w * 0.5 - 0.25), mid + xa * (w * 0.5 - 0.25), n, xf.origin.y - 3.5 + 2.92, accent, rng.randf() < 0.5)
		x += w


## A fabric awning from a to b (on the wall), sloping out over the
## sidewalk, with a valance and side cheeks (like BuildingKit._awning).
func _awning(mb: MeshBuilder, a: Vector3, b: Vector3, out: Vector3, y_top: float, col: Color, plain: bool) -> void:
	var depth := 1.25
	var drop := 0.55
	var valance := 0.22
	a.y = y_top
	b.y = y_top
	a += out * 0.06
	b += out * 0.06
	var stripe := Color(0.86, 0.84, 0.78)
	var stripes := maxi(int(a.distance_to(b) / 0.45), 1)
	for s in stripes:
		var p0 := a.lerp(b, float(s) / stripes)
		var p1 := a.lerp(b, float(s + 1) / stripes)
		var c := Color(col if plain or s % 2 == 0 else stripe, BuildingKit.FABRIC)
		var q0 := p0 + out * depth + Vector3.DOWN * drop
		var q1 := p1 + out * depth + Vector3.DOWN * drop
		mb.add_quad(p1, p0, q0, q1, c)
		mb.add_quad(p0, p1, q1, q0, Color(c.darkened(0.25), BuildingKit.FABRIC))
		mb.add_quad(q1, q0, q0 + Vector3.DOWN * valance, q1 + Vector3.DOWN * valance, c)
		mb.add_quad(q0, q1, q1 + Vector3.DOWN * valance, q0 + Vector3.DOWN * valance, Color(c.darkened(0.25), BuildingKit.FABRIC))
	for p: Vector3 in [a, b]:
		var q := p + out * depth + Vector3.DOWN * drop
		var cc := Color(col, BuildingKit.FABRIC)
		mb.add_tri(p, q, q + Vector3.DOWN * valance, cc)
		mb.add_tri(p, q + Vector3.DOWN * valance, q, cc)


## Painted wall signs for a planned building: on a plain side whose upper
## part shows above a neighbour at least 6 m lower (or faces an alley), a
## faded advertisement in the exposed band. Returns [side, s0, s1, y0, y1,
## atlas row, paint scheme] entries for DowntownBuilding.ghost_sign.
func _ghost_signs(plan: Dictionary, plans: Array[Dictionary]) -> Array:
	var out := []
	var rect: Rect2 = plan["rect"]
	var top: float = plan["top"]
	var wall_top := DowntownBuilding.height_of(plan["floors"])
	for k in 4:
		if plan["front"][k] or plan["back"][k]:
			continue
		var length := rect.size.x if k % 2 == 0 else rect.size.y
		if length < 8.0:
			continue
		var probe := rect
		match k:
			0: probe = Rect2(rect.position.x + 0.5, rect.end.y + 0.1, rect.size.x - 1.0, 0.6)
			1: probe = Rect2(rect.end.x + 0.1, rect.position.y + 0.5, 0.6, rect.size.y - 1.0)
			2: probe = Rect2(rect.position.x + 0.5, rect.position.y - 0.7, rect.size.x - 1.0, 0.6)
			3: probe = Rect2(rect.position.x - 0.7, rect.position.y + 0.5, 0.6, rect.size.y - 1.0)
		var neighbour_top := -1.0
		for other: Dictionary in plans:
			if other != plan and (other["rect"] as Rect2).intersects(probe):
				neighbour_top = maxf(neighbour_top, other["top"])
		var y0 := neighbour_top + 1.5 if neighbour_top > 0.0 else 7.0
		if neighbour_top < 0.0 and not _near_alley(probe):
			continue  # courtyard side: nobody sees it
		var y1 := wall_top - 1.2
		if y1 - y0 < 4.0 or rng.randf() > 0.7:
			continue
		var h := minf(y1 - y0, rng.randf_range(4.0, 6.5))
		var w := minf(length - 2.0, h * rng.randf_range(1.6, 2.4))
		var s0 := (length - w) * rng.randf_range(0.3, 0.7)
		var yb := y0 + (y1 - y0 - h) * rng.randf_range(0.2, 0.9)
		out.append([k, s0, s0 + w, yb, yb + h, rng.randi_range(0, 15), rng.randi_range(0, 3)])
	return out


func _near_alley(probe: Rect2) -> bool:
	for a: Rect2 in _alleys_all:
		if a.grow(0.5).intersects(probe):
			return true
	return false


## Whether side k (S, E, N, W) of `rect` faces into the block rather than
## onto a neighbour: nothing else stands within 1 m in that direction.
func _faces_inside(rect: Rect2, k: int, x0: float, z0: float, x1: float, z1: float) -> bool:
	var probe := rect
	match k:
		0: probe = Rect2(rect.position.x + 0.5, rect.end.y + 0.2, rect.size.x - 1.0, 1.0)
		1: probe = Rect2(rect.end.x + 0.2, rect.position.y + 0.5, 1.0, rect.size.y - 1.0)
		2: probe = Rect2(rect.position.x + 0.5, rect.position.y - 1.2, rect.size.x - 1.0, 1.0)
		3: probe = Rect2(rect.position.x - 1.2, rect.position.y + 0.5, 1.0, rect.size.y - 1.0)
	if not Rect2(x0, z0, x1 - x0, z1 - z0).encloses(probe):
		return false  # that side is the block edge
	for f: Rect2 in footprints:
		if f != rect and f.intersects(probe):
			return false
	return true


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
