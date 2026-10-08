@tool
class_name TreeLod
extends Node3D
## Draws the island's trees, shrubs and hedges (ART_BIBLE.md §18, §26).
##
## Every instance lives in a quadtree of square cells (40 m up to the whole
## island). A cell is drawn as one MultiMesh per level of detail it needs, so
## a view costs a handful of draw calls however many trees stand in it:
##   * tier 0 (full detail, TreeKit LOD 0): 40 m cells whose centre is within
##     the species' r0 of the camera;
##   * tier 1 (mid detail): cells beyond r0, as 40 / 80 / 160 m units;
##   * tier 2 (a solid canopy blob, one mesh per species): whole 160 m to 1.3 km
##     cells that lie entirely beyond r1.
## The quadtree is re-walked from the camera position a few times a second
## (a few hundred cell tests); MultiMeshes are built the first time a cell needs
## them. Tier 0 has one MultiMesh per variant (broadleaf_a/b/c...), tiers 1 and
## 2 one per species. Instances never overlap between tiers, so nothing is
## drawn twice and nothing falls in a gap, unlike distance-range LOD on fixed
## chunks. Distances are measured to the cell's box (cells are big, trees small).
##
## Instances are stored in Z-order (Morton order of their 40 m cell, then by
## variant), so every cell at every level owns one contiguous run of the
## instance buffer: building a MultiMesh is a single slice of it.
##
## Foliage doesn't occlude GI (gi_mode disabled): alpha-tested cards voxelised
## into SDFGI would blotch the canopy.

const LEAF := 40.0
const LEVELS := 6  # cell sizes 40, 80, 160, 320, 640, 1280
const ORIGIN := -640.0
## Tier 2 is allowed from this level up (160 m cells).
const FAR_LEVEL := 2
## Tier 1 units are at most this level (160 m cells).
const MID_LEVEL := 2
const STRIDE := 16  # floats per instance: 12 transform + 4 custom data
## Mid-detail units farther than this don't cast shadows.
const SHADOW_MID_RANGE := 120.0
const MAX_VARIANTS := 8

var _groups: Array[Group] = []
var _visible := {}
var _last_cam := Vector3(1e9, 0.0, 0.0)
var _last_cam2 := Vector3(1e9, 0.0, 0.0)
var _since := 0.0
## Every camera the detail is chosen for (split-screen: one per player).
var _cams := PackedVector3Array()
## Scales the LOD distances: 0.7 on Low (the viewport renders at 0.75 scale
## then, see GraphicsQuality), 1 otherwise.
var _k := 1.0
## How long the last update took (microseconds), for the dev tools.
var update_usec := 0
## Stats of the last update, for the dev tools.
var drawn := {"t0": 0, "t1": 0, "t2": 0}


class Group extends RefCounted:
	var species := ""
	var variants: Array = []
	var r0 := 70.0
	var r1 := 260.0
	var cull := 3000.0
	var buf := PackedFloat32Array()  # STRIDE floats per instance, in Z-order
	var cells := {}  # Vector3i(level, ix, iz) -> Cell
	var count := 0


class Cell extends RefCounted:
	var a := 0  # first instance
	var b := 0  # one past the last
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var vstart := PackedInt32Array()  # leaf cells: first instance of each variant (+ the end)
	var mmis := {}  # tier * MAX_VARIANTS + variant -> MultiMeshInstance3D
	var last_tier := -1


## Registers the trees of one species: `xforms[i]`, `variants[i]` (index into
## the species' variants) and `customs[i]` (autumn amount, random seed,
## brightness variation, flowering: see foliage.gdshader).
func add_group(species: String, xforms: Array[Transform3D], variants: PackedInt32Array, customs: PackedColorArray) -> void:
	var info: Dictionary = TreeKit.SPECIES[species]
	var g := Group.new()
	g.species = species
	g.variants = info["variants"]
	g.r0 = info["r0"]
	g.r1 = info["r1"]
	g.cull = info["cull"]
	var n := xforms.size()
	g.count = n
	# Counting sort by (Z-order of the 40 m cell, variant).
	var nv := MAX_VARIANTS
	var key := PackedInt32Array()
	key.resize(n)
	var counts := PackedInt32Array()
	counts.resize(4096 * nv + 1)
	for i in n:
		var o := xforms[i].origin
		var ix := clampi(int(floor((o.x - ORIGIN) / LEAF)), 0, 63)
		var iz := clampi(int(floor((o.z - ORIGIN) / LEAF)), 0, 63)
		var k := _morton(ix, iz) * nv + mini(variants[i], nv - 1)
		key[i] = k
		counts[k + 1] += 1
	for k in range(1, counts.size()):
		counts[k] += counts[k - 1]
	var pref := counts.duplicate()  # pref[k] = number of instances with a smaller key
	var order := PackedInt32Array()
	order.resize(n)
	var fill := counts  # reused as the running write position
	for i in n:
		var k := key[i]
		order[fill[k]] = i
		fill[k] += 1
	g.buf.resize(n * STRIDE)
	var pos_pad := Vector3(6.0, 0.0, 6.0)
	var leaf_cells := {}
	for j in n:
		var i := order[j]
		var xf := xforms[i]
		var o := j * STRIDE
		var bs := xf.basis
		g.buf[o + 0] = bs.x.x
		g.buf[o + 1] = bs.y.x
		g.buf[o + 2] = bs.z.x
		g.buf[o + 3] = xf.origin.x
		g.buf[o + 4] = bs.x.y
		g.buf[o + 5] = bs.y.y
		g.buf[o + 6] = bs.z.y
		g.buf[o + 7] = xf.origin.y
		g.buf[o + 8] = bs.x.z
		g.buf[o + 9] = bs.y.z
		g.buf[o + 10] = bs.z.z
		g.buf[o + 11] = xf.origin.z
		var c := customs[i]
		g.buf[o + 12] = c.r
		g.buf[o + 13] = c.g
		g.buf[o + 14] = c.b
		g.buf[o + 15] = c.a
		var ix := clampi(int(floor((xf.origin.x - ORIGIN) / LEAF)), 0, 63)
		var iz := clampi(int(floor((xf.origin.z - ORIGIN) / LEAF)), 0, 63)
		var ck := Vector3i(0, ix, iz)
		var cell: Cell = leaf_cells.get(ck)
		if cell == null:
			cell = Cell.new()
			cell.a = j
			leaf_cells[ck] = cell
		cell.b = j + 1
		var top := xf.origin + Vector3(0.0, 16.0 * bs.get_scale().y, 0.0)
		cell.mn = cell.mn.min(xf.origin - pos_pad)
		cell.mx = cell.mx.max(top + pos_pad)
	# Variant runs inside each leaf cell, then the parents (their runs are the union).
	for ck: Vector3i in leaf_cells:
		var cell: Cell = leaf_cells[ck]
		var m := _morton(ck.y, ck.z)
		cell.vstart.resize(nv + 1)
		for v in nv + 1:
			cell.vstart[v] = pref[m * nv + v]
		g.cells[ck] = cell
	for lvl in range(1, LEVELS):
		var parents := {}
		for ck: Vector3i in g.cells:
			if ck.x != lvl - 1:
				continue
			var pk := Vector3i(lvl, ck.y >> 1, ck.z >> 1)
			var child: Cell = g.cells[ck]
			var par: Cell = parents.get(pk)
			if par == null:
				par = Cell.new()
				par.a = child.a
				par.b = child.b
				parents[pk] = par
			par.a = mini(par.a, child.a)
			par.b = maxi(par.b, child.b)
			par.mn = par.mn.min(child.mn)
			par.mx = par.mx.max(child.mx)
		for pk: Vector3i in parents:
			g.cells[pk] = parents[pk]
	_groups.append(g)


## Z-order (Morton) code of a 64 x 64 grid cell.
static func _morton(ix: int, iz: int) -> int:
	var m := 0
	for b in 6:
		m |= ((ix >> b) & 1) << (2 * b)
		m |= ((iz >> b) & 1) << (2 * b + 1)
	return m


func _process(delta: float) -> void:
	_since += delta
	var cams := Views.cameras(self) if is_inside_tree() else ([] as Array[Camera3D])
	var pos := cams[0].global_position if not cams.is_empty() else Vector3(0.0, 80.0, 0.0)
	# Split-screen: near detail around the second player's camera too.
	var extra := PackedVector3Array()
	for i in range(1, cams.size()):
		extra.append(cams[i].global_position)
	var moved := pos.distance_to(_last_cam)
	if not extra.is_empty():
		moved = maxf(moved, extra[0].distance_to(_last_cam2))
	if moved < 4.0 and _since < 0.5:
		return
	if _since < 0.06 and _last_cam.x < 1e8:
		return
	_since = 0.0
	_last_cam = pos
	if not extra.is_empty():
		_last_cam2 = extra[0]
	update(pos, extra)


## Re-chooses what is drawn for a camera at `cam` (and in split-screen the
## other player's camera at `extra`: each tree gets the detail its nearest
## camera needs).
func update(cam: Vector3, extra := PackedVector3Array()) -> void:
	_cams = PackedVector3Array([cam])
	_cams.append_array(extra)
	var t0 := Time.get_ticks_usec()
	# Low renders at 0.75 scale with FSR (GraphicsQuality.apply): shorter LOD distances there.
	var vp := get_viewport()
	_k = 0.7 if vp and vp.scaling_3d_scale < 0.99 else 1.0
	var want := {}
	drawn = {"t0": 0, "t1": 0, "t2": 0}
	for g in _groups:
		var top_level := LEVELS - 1
		var root: Cell = g.cells.get(Vector3i(top_level, 0, 0))
		if root:
			_visit(g, Vector3i(top_level, 0, 0), root, cam, want)
	for m: MultiMeshInstance3D in _visible:
		if not want.has(m):
			m.visible = false
	for m: MultiMeshInstance3D in want:
		if not _visible.has(m):
			m.visible = true
	_visible = want
	update_usec = Time.get_ticks_usec() - t0
	if OS.get_environment("TT_TREE_DEBUG") != "":
		print(debug_summary())


## What is drawn right now: MultiMeshes, trees and triangles per tier.
func debug_summary() -> String:
	var mm_n := [0, 0, 0]
	var inst := [0, 0, 0]
	var tris := [0, 0, 0]
	for m: MultiMeshInstance3D in _visible:
		var tier := int(String(m.name).split("_t")[-1].split("_")[0])
		mm_n[tier] += 1
		inst[tier] += m.multimesh.instance_count
		tris[tier] += m.multimesh.instance_count * (m.multimesh.mesh as ArrayMesh).surface_get_array_index_len(0) / 3
	return "TreeLod (%.2f ms): t0 %d mm %d trees %dk tris | t1 %d mm %d trees %dk tris | t2 %d mm %d trees %dk tris (before frustum culling)" % [
		update_usec / 1000.0, mm_n[0], inst[0], tris[0] / 1000, mm_n[1], inst[1], tris[1] / 1000, mm_n[2], inst[2], tris[2] / 1000]


func _visit(g: Group, key: Vector3i, cell: Cell, cam: Vector3, want: Dictionary) -> void:
	var dmin := _dist_min_all(cell)
	if dmin > g.cull * _k:
		return
	var r0 := g.r0 * _k
	var r1 := g.r1 * _k
	var lvl := key.x
	if lvl >= FAR_LEVEL and dmin >= r1:
		cell.last_tier = 2
		_show(g, cell, key, 2, want, dmin)
		return
	if lvl == 0:
		var c := Vector3((key.y + 0.5) * LEAF + ORIGIN, (cell.mn.y + cell.mx.y) * 0.5, (key.z + 0.5) * LEAF + ORIGIN)
		var dc := INF
		for p in _cams:
			dc = minf(dc, Vector2(c.x - p.x, c.z - p.z).length())
		var tier := 0 if dc < r0 * (1.15 if cell.last_tier == 0 else 1.0) else 1
		cell.last_tier = tier
		_show(g, cell, key, tier, want, dmin)
		return
	if lvl <= MID_LEVEL and dmin >= r0 * 1.15 and _dist_max_all(cell) <= r1 * 1.6:
		cell.last_tier = 1
		_show(g, cell, key, 1, want, dmin)
		return
	for dz in 2:
		for dx in 2:
			var ck := Vector3i(lvl - 1, key.y * 2 + dx, key.z * 2 + dz)
			var child: Cell = g.cells.get(ck)
			if child:
				_visit(g, ck, child, cam, want)


## Distance from the cell to the nearest camera.
func _dist_min_all(cell: Cell) -> float:
	var d := INF
	for p in _cams:
		d = minf(d, _dist_min(cell, p))
	return d


## The cell's far corner from the nearest camera (by that measure).
func _dist_max_all(cell: Cell) -> float:
	var d := INF
	for p in _cams:
		d = minf(d, _dist_max(cell, p))
	return d


func _dist_min(cell: Cell, p: Vector3) -> float:
	var d := Vector3.ZERO.max(cell.mn - p).max(p - cell.mx)
	return d.length()


func _dist_max(cell: Cell, p: Vector3) -> float:
	var d := (cell.mn - p).abs().max((cell.mx - p).abs())
	return d.length()


func _show(g: Group, cell: Cell, key: Vector3i, tier: int, want: Dictionary, dmin: float) -> void:
	drawn["t%d" % tier] += 1
	if tier >= 1:
		# mid and far detail share one mesh per species
		var m1 := _mmi(g, cell, key, tier, 0)
		if m1:
			want[m1] = true
			_set_shadows(m1, tier == 1 and dmin < SHADOW_MID_RANGE * _k)
		return
	for vi in g.variants.size():
		var m := _mmi(g, cell, key, tier, vi)
		if m:
			want[m] = true


## Mid-detail trees cast shadows only while the unit is near (the far
## cascades' resolution can't show them, and they cost as much as lit trees).
func _set_shadows(m: MultiMeshInstance3D, on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m.cast_shadow != mode:
		m.cast_shadow = mode


## The MultiMeshInstance3D of a cell at a tier (variant `vi` for tier 0),
## built on first use (one slice of the group's instance buffer); null if the
## cell has no tree of that variant.
func _mmi(g: Group, cell: Cell, key: Vector3i, tier: int, vi: int) -> MultiMeshInstance3D:
	var mk := tier * MAX_VARIANTS + vi
	if cell.mmis.has(mk):
		return cell.mmis[mk]
	var a := cell.a
	var b := cell.b
	if tier == 0:
		a = cell.vstart[vi]
		b = cell.vstart[vi + 1]
	var n := b - a
	if n <= 0:
		cell.mmis[mk] = null
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = TreeKit.mesh(g.variants[vi] if tier == 0 else g.species, tier)
	mm.instance_count = n
	mm.buffer = g.buf.slice(a * STRIDE, b * STRIDE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_L%d_%d_%d_t%d_%d" % [g.species, key.x, key.y, key.z, tier, vi]
	mmi.multimesh = mm
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tier == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visible = false
	add_child(mmi)
	cell.mmis[mk] = mmi
	return mmi
