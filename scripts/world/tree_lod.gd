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
## 2 one per species. Instances never overlap between tiers, so nothing is drawn twice and
## nothing falls in a gap, unlike distance-range LOD on fixed chunks.
## Distances are measured to the cell's box (cells are big, trees small).
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

var _groups: Array[Group] = []
var _visible := {}
var _last_cam := Vector3(1e9, 0.0, 0.0)
var _since := 0.0
## Scales the LOD distances: 0.7 on Low, 0.85 on Medium, 1 on High (see
## GraphicsQuality; read from the global `quality` shader parameter).
var _k := 1.0
## Stats of the last update, for the dev tools.
var drawn := {"t0": 0, "t1": 0, "t2": 0}


class Group extends RefCounted:
	var species := ""
	var variants: Array = []
	var r0 := 70.0
	var r1 := 260.0
	var cull := 3000.0
	var buf := PackedFloat32Array()
	var variant := PackedInt32Array()
	var cells := {}  # Vector3i(level, ix, iz) -> Cell
	var count := 0


class Cell extends RefCounted:
	var trees := PackedInt32Array()
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var mmis := {}  # tier * 16 + variant -> MultiMeshInstance3D
	var last_tier := -1


## Registers the trees of one species: `xforms[i]`, `variants[i]` (index into
## the species' variants) and `customs[i]` (autumn amount, random seed,
## brightness variation, unused: see foliage.gdshader).
func add_group(species: String, xforms: Array[Transform3D], variants: PackedInt32Array, customs: PackedColorArray) -> void:
	var info: Dictionary = TreeKit.SPECIES[species]
	var g := Group.new()
	g.species = species
	g.variants = info["variants"]
	g.r0 = info["r0"]
	g.r1 = info["r1"]
	g.cull = info["cull"]
	g.count = xforms.size()
	g.buf.resize(g.count * STRIDE)
	g.variant = variants
	var pos_pad := Vector3(6.0, 0.0, 6.0)
	for i in g.count:
		var xf := xforms[i]
		var o := i * STRIDE
		var b := xf.basis
		g.buf[o + 0] = b.x.x
		g.buf[o + 1] = b.y.x
		g.buf[o + 2] = b.z.x
		g.buf[o + 3] = xf.origin.x
		g.buf[o + 4] = b.x.y
		g.buf[o + 5] = b.y.y
		g.buf[o + 6] = b.z.y
		g.buf[o + 7] = xf.origin.y
		g.buf[o + 8] = b.x.z
		g.buf[o + 9] = b.y.z
		g.buf[o + 10] = b.z.z
		g.buf[o + 11] = xf.origin.z
		var c := customs[i]
		g.buf[o + 12] = c.r
		g.buf[o + 13] = c.g
		g.buf[o + 14] = c.b
		g.buf[o + 15] = c.a
		var ix := int(floor((xf.origin.x - ORIGIN) / LEAF))
		var iz := int(floor((xf.origin.z - ORIGIN) / LEAF))
		var top := xf.origin + Vector3(0.0, 16.0 * b.get_scale().y, 0.0)
		for lvl in LEVELS:
			var key := Vector3i(lvl, ix >> lvl, iz >> lvl)
			var cell: Cell = g.cells.get(key)
			if cell == null:
				cell = Cell.new()
				g.cells[key] = cell
			cell.trees.append(i)
			cell.mn = cell.mn.min(xf.origin - pos_pad)
			cell.mx = cell.mx.max(top + pos_pad)
	_groups.append(g)


func _process(delta: float) -> void:
	_since += delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var pos := cam.global_position if cam else Vector3(0.0, 80.0, 0.0)
	if pos.distance_to(_last_cam) < 4.0 and _since < 0.5:
		return
	if _since < 0.06 and _last_cam.x < 1e8:
		return
	_since = 0.0
	_last_cam = pos
	update(pos)


## Re-chooses what is drawn for a camera at `cam`.
func update(cam: Vector3) -> void:
	var q: Variant = RenderingServer.global_shader_parameter_get("quality")
	_k = [0.7, 0.85, 1.0][clampi(int(q) if q != null else 2, 0, 2)]
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
	return "TreeLod: t0 %d mm %d trees %dk tris | t1 %d mm %d trees %dk tris | t2 %d mm %d trees %dk tris (before frustum culling)" % [
		mm_n[0], inst[0], tris[0] / 1000, mm_n[1], inst[1], tris[1] / 1000, mm_n[2], inst[2], tris[2] / 1000]


func _visit(g: Group, key: Vector3i, cell: Cell, cam: Vector3, want: Dictionary) -> void:
	var dmin := _dist_min(cell, cam)
	if dmin > g.cull * _k:
		return
	var r0 := g.r0 * _k
	var r1 := g.r1 * _k
	var lvl := key.x
	var size := LEAF * float(1 << lvl)
	if lvl >= FAR_LEVEL and dmin >= r1:
		cell.last_tier = 2
		_show(g, cell, key, 2, want, dmin)
		return
	if lvl == 0:
		var c := Vector3((key.y + 0.5) * LEAF + ORIGIN, (cell.mn.y + cell.mx.y) * 0.5, (key.z + 0.5) * LEAF + ORIGIN)
		var dc := Vector2(c.x - cam.x, c.z - cam.z).length()
		var tier := 0 if dc < r0 * (1.15 if cell.last_tier == 0 else 1.0) else 1
		# beyond the cull distance of the whole cell's near corner, the blob is enough
		cell.last_tier = tier
		_show(g, cell, key, tier, want, dmin)
		return
	if lvl <= MID_LEVEL and dmin >= r0 * 1.15 and _dist_max(cell, cam) <= r1 * 1.6:
		cell.last_tier = 1
		_show(g, cell, key, 1, want, dmin)
		return
	for dz in 2:
		for dx in 2:
			var ck := Vector3i(lvl - 1, key.y * 2 + dx, key.z * 2 + dz)
			var child: Cell = g.cells.get(ck)
			if child:
				_visit(g, ck, child, cam, want)


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


## The MultiMeshInstance3D of a cell at a tier (variant `vi` for tiers 0 and 1),
## built on first use; null if the cell has no tree of that variant.
func _mmi(g: Group, cell: Cell, key: Vector3i, tier: int, vi: int) -> MultiMeshInstance3D:
	var mk := tier * 16 + vi
	if cell.mmis.has(mk):
		return cell.mmis[mk]
	var out := PackedFloat32Array()
	var n := 0
	for t in cell.trees:
		if tier >= 1 or g.variant[t] == vi:
			out.append_array(g.buf.slice(t * STRIDE, t * STRIDE + STRIDE))
			n += 1
	if n == 0:
		cell.mmis[mk] = null
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = TreeKit.mesh(g.variants[vi] if tier == 0 else g.species, tier)
	mm.instance_count = n
	mm.buffer = out
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_L%d_%d_%d_t%d_%d" % [g.species, key.x, key.y, key.z, tier, vi]
	mmi.multimesh = mm
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tier == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visible = false
	add_child(mmi)
	cell.mmis[mk] = mmi
	return mmi
