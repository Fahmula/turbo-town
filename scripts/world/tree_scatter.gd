@tool
class_name TreeScatter
extends RefCounted
## Where the island's trees, shrubs and hedges stand (ART_BIBLE.md §18), and
## the nodes that draw and collide with them: street and park trees at the
## spots CityBuilder gives, woodland on the hills and the mountain flanks
## (conifers up high, broadleaf below), scrub on slopes, palms along the
## coast, hedges round the parks. Called by NatureBuilder.build().
##
## Nothing grows on roads and trails (plus a verge), ramps, the stunt park,
## the dirt fields, the airfield, the beach lot, the harbour quay, beaches
## below 0.5 m or steep rock. Placement is deterministic (fixed seeds).

const GRID := 6.0
const VERGE := 5.0

var _terrain: TerrainBuilder
var _rng := RandomNumberGenerator.new()
var _woods := FastNoiseLite.new()
var _mix := FastNoiseLite.new()
var _groves := FastNoiseLite.new()
var _sets := {}
## Counts of what was placed (printed by the world builder's log via NatureBuilder).
var stats := {}


## One species' instances on their way to TreeLod.
class TreeSet extends RefCounted:
	var xforms: Array[Transform3D] = []
	var variants := PackedInt32Array()
	var customs := PackedColorArray()
	var trunks := PackedVector3Array()  # per tree: radius, height, 0 (for the colliders)


func _init(terrain: TerrainBuilder) -> void:
	_terrain = terrain
	_rng.seed = 99
	_woods.seed = 21
	_woods.frequency = 0.011
	_woods.fractal_octaves = 3
	_mix.seed = 8
	_mix.frequency = 0.02
	_groves.seed = 14
	_groves.frequency = 0.03
	for s: String in TreeKit.SPECIES:
		_sets[s] = TreeSet.new()


## Places everything and adds the "Trees" (TreeLod) and "TreeTrunks"
## (TreeColliders) nodes to `root`.
func build(root: Node3D, city_tree_spots: Array[Vector3]) -> void:
	for p in city_tree_spots:
		var variant := _pick(_rng.randf(), [0.4, 0.25, 0.35])
		# a few flowering trees along the streets and in the parks (ART_BIBLE.md §18)
		_add("broadleaf", variant, p, 0.85, 1.15, false, true, _rng.randf() < 0.07)
	_scatter()
	_tree_lines()
	_islet()
	_add_park_greens(city_tree_spots)
	var lod := TreeLod.new()
	lod.name = "Trees"
	root.add_child(lod)
	var colliders := TreeColliders.new()
	colliders.name = "TreeTrunks"
	root.add_child(colliders)
	for sp: String in _sets:
		var set: TreeSet = _sets[sp]
		stats[sp] = set.xforms.size()
		if set.xforms.is_empty():
			continue
		lod.add_group(sp, set.xforms, set.variants, set.customs)
		# build the meshes now, not on the first frame a tree comes into view
		for v: String in TreeKit.SPECIES[sp]["variants"]:
			TreeKit.mesh(v, 0)
		TreeKit.mesh(sp, 1)
		TreeKit.mesh(sp, 2)
		for i in set.xforms.size():
			var t := set.trunks[i]
			if t.x > 0.0:
				colliders.add(set.xforms[i].origin, t.x, t.y)
	colliders.commit()


func _pick(r: float, weights: Array) -> int:
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			return i
	return weights.size() - 1


## One instance. `trunk`: also gives it a collider.
func _add(species: String, variant: int, p: Vector3, smin: float, smax: float, autumn_ok: bool, trunk := true, flowering := false) -> void:
	var set: TreeSet = _sets[species]
	var s := _rng.randf_range(smin, smax)
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.92, 1.1), s))
	set.xforms.append(Transform3D(b, p))
	set.variants.append(variant)
	var autumn := 0.0
	# a few autumn-tinted broadleaf trees (ART_BIBLE.md §5: accents <= 10%)
	if species == "broadleaf" and _rng.randf() < (0.08 if autumn_ok else 0.05):
		autumn = _rng.randf_range(0.35, 0.9)
	if flowering:
		autumn = 0.0
	set.customs.append(Color(autumn, _rng.randf(), _rng.randf_range(0.2, 0.8), 1.0 if flowering else 0.0))
	var info: Dictionary = TreeKit.VARIANTS[TreeKit.SPECIES[species]["variants"][variant]]
	var tr := float(info.get("trunk_r", TreeKit.SPECIES[species]["trunk_r"]))
	var th := float(TreeKit.SPECIES[species]["trunk_h"])
	set.trunks.append(Vector3(tr * s if trunk and tr > 0.0 else 0.0, th * s, 0.0))


# --------------------------------------------------------------- woodland ---

func _scatter() -> void:
	var half := MapLayout.TERRAIN_HALF_SIZE - 16.0
	var n := int(2.0 * half / GRID)
	var mc := MapLayout.MOUNTAIN_CENTER
	for j in n:
		var z0 := -half + j * GRID
		for i in n:
			var x := -half + i * GRID + _rng.randf() * GRID
			var z := z0 + _rng.randf() * GRID
			if absf(x) < 165.0 and absf(z) < 165.0:
				continue
			var pat := _woods.get_noise_2d(x, z) * 0.5 + 0.5
			var mountain := smoothstep(-300.0, -400.0, z)
			pat += mountain * 0.2
			var forest := smoothstep(0.4, 0.56, pat)
			var chance := 0.02 + forest * 0.85
			var edge := smoothstep(0.34, 0.46, pat) * (1.0 - forest)
			if _rng.randf() > chance + edge * 0.1:
				continue
			if _blocked(x, z):
				continue
			var h := _h(x, z)
			if h < 0.5:
				continue
			var slope := _slope(x, z)
			if slope > 0.62:
				continue
			if _near_road(x, z):
				continue
			var p := Vector3(x, h - 0.1, z)
			# high ground thins out
			if h > 38.0 and _rng.randf() < smoothstep(38.0, 50.0, h) * 0.85:
				continue
			# Palms on the low coast (sand), groves clumped by noise.
			if h < 5.5 and (x < -300.0 or _terrain.shore_factor(x, z) > 0.0005):
				var grove := _groves.get_noise_2d(x, z) * 0.5 + 0.5
				if _rng.randf() < smoothstep(0.35, 0.6, grove) * 0.5 and not _beach_clear(x, z):
					_add("palm", 0, p, 0.85, 1.2, false)
				elif h > 1.2 and _rng.randf() < 0.25:
					_add("shrub", 0, p, 0.9, 1.5, false, false)
				continue
			if h < 1.4:
				continue
			# Scrub on slopes and at the forest's edge.
			if forest < 0.15 and (slope > 0.2 or edge > 0.2):
				if _rng.randf() < 0.5:
					_add("shrub", 0, p, 1.1, 2.1, false, false)
				continue
			var cf := smoothstep(7.0, 15.0, h + _mix.get_noise_2d(x, z) * 6.0 + mountain * 10.0)
			if _rng.randf() < cf:
				_add("conifer", _pick(_rng.randf(), [0.5, 0.3, 0.2]), p, 0.75, 1.3, false)
			else:
				_add("broadleaf", _pick(_rng.randf(), [0.45, 0.3, 0.25]), p, 0.8, 1.25, true)
			# understory
			if _rng.randf() < 0.14:
				var q := Vector3(x + _rng.randf_range(-3.0, 3.0), 0.0, z + _rng.randf_range(-3.0, 3.0))
				q.y = _h(q.x, q.z) - 0.05
				if not _blocked(q.x, q.z) and not _near_road(q.x, q.z) and q.y > 1.4:
					_add("shrub", 0, q, 1.0, 1.9, false, false)


## Rows of trees along the edges of the cleared areas (dirt fields, stunt park,
## airfield), like windbreaks and field hedgerows.
func _tree_lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pm := MapLayout.PARK_MIN
	var px := MapLayout.PARK_MAX
	# [start, end] of each row, just outside the cleared rectangles
	var rows := [
		[Vector2(322, -213), Vector2(322, 213)],       # dirt fields, west edge
		[Vector2(332, -222), Vector2(555, -222)],      # dirt fields, north edge
		[Vector2(240, 214), Vector2(240, 346)],        # airfield, west edge
		[Vector2(245, 352), Vector2(565, 352)],        # airfield, south edge
		[Vector2(pm.x - 20, pm.y - 22), Vector2(px.x + 20, pm.y - 22)],  # stunt park, north edge
		[Vector2(pm.x - 22, pm.y - 18), Vector2(pm.x - 22, px.y + 20)],  # stunt park, west edge
		[Vector2(px.x + 22, pm.y - 18), Vector2(px.x + 22, px.y + 20)],  # stunt park, east edge
	]
	for r: Array in rows:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var len := a.distance_to(b)
		var d := rng.randf_range(0.0, 8.0)
		while d < len:
			var q := a.lerp(b, d / len) + Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8))
			d += rng.randf_range(7.0, 11.5)
			if rng.randf() < 0.12:
				continue
			if _blocked(q.x, q.y) or absf(q.x) > 620.0 or absf(q.y) > 620.0:
				continue
			var h := _h(q.x, q.y)
			if h < 1.4 or _near_road(q.x, q.y) or _slope(q.x, q.y) > 0.5:
				continue
			var p := Vector3(q.x, h - 0.1, q.y)
			if rng.randf() < 0.22:
				_add("conifer", _pick(rng.randf(), [0.5, 0.3, 0.2]), p, 0.8, 1.15, false)
			else:
				_add("broadleaf", _pick(rng.randf(), [0.45, 0.1, 0.45]), p, 0.85, 1.2, true)


## Palms and scrub round the lighthouse on its islet.
func _islet() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var c := MapLayout.ISLET_CENTER
	for k in 9:
		var ang := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(18.0, 25.0)
		var x := c.x + cos(ang) * dist
		var z := c.y + sin(ang) * dist
		if absf(z) < 8.0 and x > c.x:  # the bridge side
			continue
		var h := _h(x, z)
		if h < 1.3 or _blocked(x, z):
			continue
		var p := Vector3(x, h - 0.1, z)
		if k % 3 == 2:
			_add("shrub", 0, p, 1.0, 1.6, false, false)
		else:
			_add("palm", 0, p, 0.8, 1.1, false)


func _h(x: float, z: float) -> float:
	return _terrain.height_at(x, z)


func _slope(x: float, z: float) -> float:
	return _terrain.slope_at(x, z)


func _near_road(x: float, z: float) -> bool:
	if _terrain.road_weight_at(x, z) > 0.01:
		return true
	return _terrain.road_weight_at(x + VERGE, z) > 0.01 or _terrain.road_weight_at(x - VERGE, z) > 0.01 \
		or _terrain.road_weight_at(x, z + VERGE) > 0.01 or _terrain.road_weight_at(x, z - VERGE) > 0.01


## Gameplay and landmark areas that stay clear: the stunt park, the dirt
## fields (and their kickers), the airfield, the jumps, the harbour quay.
func _blocked(x: float, z: float) -> bool:
	if x > MapLayout.PARK_MIN.x - 15.0 and x < MapLayout.PARK_MAX.x + 15.0 and z > MapLayout.PARK_MIN.y - 15.0 and z < MapLayout.PARK_MAX.y + 15.0:
		return true
	if x > 330.0 and absf(z) < 215.0:
		return true
	if x > 250.0 and x < 560.0 and z > 215.0 and z < 345.0:
		return true
	if x < -360.0 and z > -312.0 and z < -165.0:
		return true
	var mc := MapLayout.MOUNTAIN_CENTER
	if Vector2(x - mc.x, z - (mc.y - 8.0)).length() < 32.0:
		return true
	for j: Vector2 in [Vector2(-185, 60), Vector2(185, -60), Vector2(-60, 195)]:
		if Vector2(x - j.x, z - j.y).length() < 22.0:
			return true
	return NatureBuilder._keep_clear(x, z)


## The beach lot, the lighthouse bridge and the beach race route.
func _beach_clear(x: float, z: float) -> bool:
	return x < -300.0 and absf(z) < 30.0


# ------------------------------------------------------------------ parks ---

## Clipped hedges round each park's lawn (gaps for the paths) and a few shrubs
## under the trees.
func _add_park_greens(city_tree_spots: Array[Vector3]) -> void:
	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	var sw := MapLayout.SIDEWALK_WIDTH
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	for j in g.size() - 1:
		for i in g.size() - 1:
			if MapLayout.BLOCK_TYPES[j][i] != "park":
				continue
			var x0: float = g[i] + hw + sw
			var x1: float = g[i + 1] - hw - sw
			var z0: float = g[j] + hw + sw
			var z1: float = g[j + 1] - hw - sw
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var y := MapLayout.CURB_HEIGHT
			var inset := 1.0
			var seg := 2.0
			# along x on the north and south edges, along z on the east and west
			for side in 4:
				var horizontal := side < 2
				var len := (x1 - x0) if horizontal else (z1 - z0)
				var count := int((len - 4.0) / seg)
				for k in count:
					var t := 2.0 + (k + 0.5) * seg
					var px := x0 + t if horizontal else (x0 + inset if side == 2 else x1 - inset)
					var pz := (z0 + inset if side == 0 else z1 - inset) if horizontal else z0 + t
					# leave the paths open (the cross paths are 3 m wide)
					if absf(px - cx) < 3.2 and horizontal:
						continue
					if absf(pz - cz) < 3.2 and not horizontal:
						continue
					var yaw := 0.0 if horizontal else PI * 0.5
					var set: TreeSet = _sets["hedge"]
					var b := Basis(Vector3.UP, yaw).scaled(Vector3(1.0, rng.randf_range(0.9, 1.1), 1.0))
					set.xforms.append(Transform3D(b, Vector3(px, y, pz)))
					set.variants.append(0)
					set.customs.append(Color(0.0, rng.randf(), rng.randf_range(0.3, 0.7), 0.0))
					set.trunks.append(Vector3.ZERO)
			# a few shrubs on the lawn
			for k in 22:
				var p := Vector3(rng.randf_range(x0 + 4.0, x1 - 4.0), y, rng.randf_range(z0 + 4.0, z1 - 4.0))
				if absf(p.x - cx) < 4.5 or absf(p.z - cz) < 4.5:
					continue
				if Vector2(p.x - cx - 12.0, p.z - cz - 12.0).length() < 9.0:
					continue
				var near_tree := false
				for tp in city_tree_spots:
					if absf(tp.x - p.x) < 1.8 and absf(tp.z - p.z) < 1.8:
						near_tree = true
						break
				if near_tree:
					continue
				var set: TreeSet = _sets["shrub"]
				var s := rng.randf_range(0.8, 1.3)
				set.xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
				set.variants.append(0)
				set.customs.append(Color(0.0, rng.randf(), rng.randf_range(0.3, 0.7), 0.0))
				set.trunks.append(Vector3.ZERO)
