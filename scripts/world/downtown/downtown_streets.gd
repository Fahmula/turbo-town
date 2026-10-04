@tool
class_name DowntownStreets
extends RefCounted
## Street-level dressing of the Downtown City MegaKit showcase blocks
## (experiment/quaternius-downtown-city): sidewalk furniture and details
## from the kit around DowntownBlock's buildings. Called by CityBuilder once
## all blocks are built.
##
## Per block it makes ONE mesh of kit props (tree pits, box planters, bollards:
## one draw call) and ONE mesh of road markings (lane arrows and words, drawn
## with the markings material), both cut off at VISIBLE_RANGE. Props that can
## be knocked about (hydrants, bins, benches, parked cars) are requested
## through `CityBuilder.prop_spawns` instead, and street trees through
## `CityBuilder.tree_spots` (replacing the city's own trees on these blocks).
##
## Everything stands to the same cross-section of a block side, measured in
## metres from the kerb edge (the slab edge) towards the buildings:
##   0 - 0.5     kerb slope and kerb stone
##   0.6         hydrants, bins (just behind the kerb), bollards (0.45)
##   1.3 - 1.5   tree pits (1.77 m across), so a 4.5 m sidewalk keeps a walking
##               path of 2.3 m beside them (1.8 m on a 4 m one) and 3.5 m between
##   depth - 2   box planters and benches stand against the building front, and
##               never in the middle third of a frontage (where the door is)
##   depth + 0.8 bollards across alley mouths
## and on the road the kerbside strip 1.1 m outside the kerb holds a few parked
## cars (4.9 m from the road centre line, hard against the kerb): traffic drives
## 1.8 m from the centre line and sways up to 0.9 m to the right for oncoming
## cars, and a car parked closer than this ends up in its bumper sensors.

## Props and markings are hidden beyond this distance (m).
const VISIBLE_RANGE := 150.0
const SLAB_Y := MapLayout.CURB_HEIGHT
## Local origin height that puts the kit's markings (modelled at y = -0.13) 2 cm
## over a road at y = 0.
const MARKING_Y := 0.15

## Block sides in DowntownBlock's order (S, E, N, W): the direction along the
## side from its first corner, the direction inwards (towards the buildings)
## and the direction of the traffic lane next to it (right-hand traffic).
const ALONG: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.RIGHT, Vector3.BACK]
const INWARD: Array[Vector3] = [Vector3.FORWARD, Vector3.LEFT, Vector3.BACK, Vector3.RIGHT]
const KERB_HEADING: Array[Vector3] = [Vector3.LEFT, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD]
## From an intersection towards its N, E, S, W road (flag bits 1, 2, 4, 8).
const ARM: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]

# Street trees.
const TREE_CORNER_CLEAR := 8.0    ## no tree within this of a block corner (sight lines)
const TREE_POLE_CLEAR := 3.0      ## nor this close to a lamp or signal
const TREE_DOOR_CLEAR := 2.2      ## nor in front of the middle of a frontage (the door)
const TREE_ALLEY_CLEAR := 2.5     ## nor this close to an alley mouth
const PIT_SOIL := 0.08            ## soil level in a Sidewalk_Planter above its foot
const PIT_HEIGHT := 0.5
# Bollards.
const BOLLARD_KERB := 0.45        ## from the kerb edge
const BOLLARD_HEIGHT := 0.89
# Parked cars.
const PARK_OUT := 1.1             ## car centre outside the kerb edge (4.9 m from the road centre line)
const PARK_JUNCTION_CLEAR := 20.0 ## from the junction centre to the car centre
const PARK_MAX := 12
# Road markings.
const ARROW_DISTANCE := 13.5      ## arrow centre before the junction centre (the stop line is 9.4 m out)
const WORD_DISTANCE := 17.0

const WALL_CORNER_CLEAR := 8.5    ## planters and benches stay this far from a block corner (the bollard rows)
const PROP_GAP := 1.2             ## free space between props, and to lamps and signals
const SPAWN := Vector3(-110.0, 0.6, 3.0)  ## City Center teleport spot

var city: CityBuilder
var downtown: DowntownBlock

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
## Footprints already claimed on the sidewalks and kerbside: (x, z, radius).
var _taken: Array[Vector3] = []
## Lamp and signal positions (x, z) alone.
var _poles: Array[Vector2] = []
var _batches := {}  # block name -> MegaKit.Batch
var _counts := {}   # what was placed, for the log


## One built (or open) side of a block: its kerb line and what stands behind.
class BlockSide:
	extends RefCounted
	var block: Dictionary
	var index := 0
	## On the kerb edge at the side's first corner, at the slab's top.
	var origin := Vector3.ZERO
	var length := 0.0
	## Kerb edge to the building line.
	var depth := 4.0
	var built := false
	## Along-side ranges (m from the first corner) of building frontages and
	## of alley mouths.
	var frontages: Array[Vector2] = []
	var alleys: Array[Vector2] = []

	## `s` metres along the side, `d` metres in from the kerb edge, at the slab top.
	func point(s: float, d: float) -> Vector3:
		return origin + DowntownStreets.ALONG[index] * s + DowntownStreets.INWARD[index] * d


func _init(city_builder: CityBuilder, blocks: DowntownBlock) -> void:
	city = city_builder
	downtown = blocks


## `root`: the City node; `body`: static collision for solid props;
## `intersections`: RoadBuilder.intersections (x, z, side flags).
func build(root: Node3D, body: StaticBody3D, intersections: Array[Vector3]) -> void:
	if downtown.blocks.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_body = body
	_rng.seed = hash("downtown_streets")
	_remove_city_trees()
	_claim_poles(intersections)

	var node := Node3D.new()
	node.name = "DowntownStreets"
	root.add_child(node)
	var sides: Array[BlockSide] = []
	for info: Dictionary in downtown.blocks:
		_batches[info["name"]] = MegaKit.Batch.new(hash(info["name"]))
		for k in 4:
			sides.append(_make_side(info, k))

	# Hard obstacles first, so the softer furniture works round them.
	for info: Dictionary in downtown.blocks:
		_corner_bollards(info)
	for side in sides:
		if side.built:
			_alley_bollards(side)
	for side in sides:
		if side.built:
			_street_trees(side)
	for side in sides:
		if side.built:
			_planters(side)
			_bench(side)
	for side in sides:
		if side.built:
			_hydrant(side)
			_bins(side)
	_lane_arrows(intersections)
	_parked_cars(sides)

	for info: Dictionary in downtown.blocks:
		var batch: MegaKit.Batch = _batches[info["name"]]
		var mesh := batch.build()
		if mesh:
			var mi := MegaKit.instance(mesh, 0, "Props_" + String(info["name"]))
			mi.visibility_range_end = VISIBLE_RANGE
			mi.visibility_range_end_margin = 15.0
			node.add_child(mi)
		var dm := batch.build_decals()
		if dm:
			var dmi := MeshInstance3D.new()
			dmi.name = "Markings_" + String(info["name"])
			dmi.mesh = dm
			dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dmi.visibility_range_end = VISIBLE_RANGE
			dmi.visibility_range_end_margin = 15.0
			node.add_child(dmi)
	print("Downtown streets: %s, in %d ms" % [_counts, (Time.get_ticks_usec() - t0) / 1000])


# ------------------------------------------------------------- bookkeeping ---

func _count(what: String, n := 1) -> void:
	_counts[what] = int(_counts.get(what, 0)) + n


## CityBuilder's own street trees on the showcase slabs make way for ours.
func _remove_city_trees() -> void:
	var keep: Array[Vector3] = []
	var removed := 0
	for p in city.tree_spots:
		var inside := false
		for info: Dictionary in downtown.blocks:
			if (info["slab"] as Rect2).has_point(Vector2(p.x, p.z)):
				inside = true
				break
		if inside:
			removed += 1
		else:
			keep.append(p)
	city.tree_spots = keep
	_counts["city trees removed"] = removed


## Lamps and signals are keep-out spots. The corner ones are added by
## CityBuilder after this runs: they stand 1.3 m inside each junction corner.
func _claim_poles(intersections: Array[Vector3]) -> void:
	for s: Dictionary in city.prop_spawns:
		if s["scene"] in ["lamp", "traffic_light", "cabinet"]:
			_claim_pole((s["xform"] as Transform3D).origin)
	var off := MapLayout.CITY_ROAD_WIDTH * 0.5 + 1.3
	for it in intersections:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_claim_pole(Vector3(it.x + sx * off, 0.0, it.y + sz * off))


func _claim_pole(p: Vector3) -> void:
	_poles.append(Vector2(p.x, p.z))
	_claim(p, 0.3)


func _claim(p: Vector3, radius: float) -> void:
	_taken.append(Vector3(p.x, p.z, radius))


## Is a footprint of `radius` at `p` clear of everything claimed so far?
func _free(p: Vector3, radius: float) -> bool:
	for t in _taken:
		var need := radius + t.z + PROP_GAP
		if Vector2(p.x - t.x, p.z - t.y).length_squared() < need * need:
			return false
	return true


func _batch_near(p: Vector3) -> MegaKit.Batch:
	var best: MegaKit.Batch
	var best_d := INF
	for info: Dictionary in downtown.blocks:
		var c := (info["slab"] as Rect2).get_center()
		var d := Vector2(p.x - c.x, p.z - c.y).length()
		if d < best_d:
			best_d = d
			best = _batches[info["name"]]
	return best


func _add_box(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


## A knock-over prop (hydrant, bin, bench, parked car) for the world builder.
func _spawn(scene: String, xf: Transform3D) -> void:
	city.prop_spawns.append({"scene": scene, "xform": xf})


# ------------------------------------------------------------------- sides ---

func _make_side(info: Dictionary, k: int) -> BlockSide:
	var slab: Rect2 = info["slab"]
	var inner: Rect2 = info["inner"]
	var side := BlockSide.new()
	side.block = info
	side.index = k
	side.built = (info["sides"] as Array)[k]
	match k:
		0:
			side.origin = Vector3(slab.position.x, SLAB_Y, slab.end.y)
			side.length = slab.size.x
			side.depth = slab.end.y - inner.end.y
		1:
			side.origin = Vector3(slab.end.x, SLAB_Y, slab.position.y)
			side.length = slab.size.y
			side.depth = slab.end.x - inner.end.x
		2:
			side.origin = Vector3(slab.position.x, SLAB_Y, slab.position.y)
			side.length = slab.size.x
			side.depth = inner.position.y - slab.position.y
		_:
			side.origin = Vector3(slab.position.x, SLAB_Y, slab.position.y)
			side.length = slab.size.y
			side.depth = inner.position.x - slab.position.x
	var start := slab.position.x if k % 2 == 0 else slab.position.y
	for rect in downtown.footprints:
		if slab.encloses(rect) and _on_edge(rect, inner, k):
			side.frontages.append(_span(rect, k) - Vector2(start, start))
	for rect: Rect2 in info["alleys"]:
		if _on_edge(rect, inner, k):
			side.alleys.append(_span(rect, k) - Vector2(start, start))
	return side


## Does `rect` touch the building line of side `k` of the block interior `inner`?
static func _on_edge(rect: Rect2, inner: Rect2, k: int) -> bool:
	match k:
		0:
			return absf(rect.end.y - inner.end.y) < 0.05
		1:
			return absf(rect.end.x - inner.end.x) < 0.05
		2:
			return absf(rect.position.y - inner.position.y) < 0.05
	return absf(rect.position.x - inner.position.x) < 0.05


## The range of `rect` along side `k` (world x for S / N, z for E / W).
static func _span(rect: Rect2, k: int) -> Vector2:
	if k % 2 == 0:
		return Vector2(rect.position.x, rect.end.x)
	return Vector2(rect.position.y, rect.end.y)


## The side's own basis: x along the side, z towards the street.
func _side_basis(side: BlockSide) -> Basis:
	return Basis.looking_at(INWARD[side.index], Vector3.UP)


func _near_alley(side: BlockSide, s: float, margin: float) -> bool:
	for a in side.alleys:
		if s > a.x - margin and s < a.y + margin:
			return true
	return false


## Within `margin` of the middle of a building frontage (the door).
func _near_door(side: BlockSide, s: float, margin: float) -> bool:
	for f in side.frontages:
		if absf(s - (f.x + f.y) * 0.5) < margin:
			return true
	return false


# ---------------------------------------------------------------- bollards ---

func _bollard(p: Vector3) -> void:
	var batch := _batch_near(p)
	batch.add("Prop_Bollard", Transform3D(Basis.IDENTITY, Vector3(p.x, SLAB_Y, p.z)), false)
	_add_box(Transform3D(Basis.IDENTITY, Vector3(p.x, SLAB_Y + BOLLARD_HEIGHT * 0.5, p.z)), Vector3(0.22, BOLLARD_HEIGHT, 0.23))
	_claim(p, 0.12)
	_count("bollards")


## A short row of three along each of the two kerbs at every block corner,
## 1.8 m apart (1.6 m between them) and clear of the corner's lamp or signal.
func _corner_bollards(info: Dictionary) -> void:
	var slab: Rect2 = info["slab"]
	for cx in [0, 1]:
		for cz in [0, 1]:
			var corner := Vector3(slab.position.x if cx == 0 else slab.end.x, SLAB_Y, slab.position.y if cz == 0 else slab.end.y)
			var ix := 1.0 if cx == 0 else -1.0  # inwards along x, z
			var iz := 1.0 if cz == 0 else -1.0
			for k in 3:
				var a := 2.7 + 1.8 * k
				for p: Vector3 in [corner + Vector3(ix * a, 0, iz * BOLLARD_KERB), corner + Vector3(ix * BOLLARD_KERB, 0, iz * a)]:
					if _free(p, 0.12):
						_bollard(p)


## Three bollards across each alley mouth, just inside it.
func _alley_bollards(side: BlockSide) -> void:
	for a in side.alleys:
		for off in [0.35, 0.5 * (a.y - a.x), a.y - a.x - 0.35]:
			_bollard(side.point(a.x + off, side.depth + 0.8))


# ------------------------------------------------------------------- trees ---

## Kit tree pits along the side every 12-15 m, with a real tree in each.
func _street_trees(side: BlockSide) -> void:
	var s := _rng.randf_range(TREE_CORNER_CLEAR, TREE_CORNER_CLEAR + 2.0)
	while s <= side.length - TREE_CORNER_CLEAR:
		var d := _rng.randf_range(1.28, 1.45)
		# A spot that is taken (lamp, alley, door): slide along to the next free one.
		for nudge: float in [0.0, 2.5, -2.5, 4.5, -4.5]:
			var at := s + nudge
			if at < TREE_CORNER_CLEAR or at > side.length - TREE_CORNER_CLEAR:
				continue
			var p := side.point(at, d)
			if _near_alley(side, at, TREE_ALLEY_CLEAR) or _near_door(side, at, TREE_DOOR_CLEAR):
				continue
			if not _free(p, 1.2) or not _clear_of_poles(p, TREE_POLE_CLEAR):
				continue
			_tree_pit(side, p)
			s = at
			break
		s += _rng.randf_range(12.0, 15.0)


func _clear_of_poles(p: Vector3, distance: float) -> bool:
	for q in _poles:
		if Vector2(p.x - q.x, p.z - q.y).length() < distance:
			return false
	return true


func _tree_pit(side: BlockSide, p: Vector3) -> void:
	var yaw := 0.0 if side.index % 2 == 0 else PI * 0.5
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, SLAB_Y, p.z))
	_batch_near(p).add("Sidewalk_Planter", xf, false)
	var size := Vector3(1.97, PIT_HEIGHT, 1.77)
	if side.index % 2 == 1:
		size = Vector3(size.z, size.y, size.x)
	_add_box(Transform3D(Basis.IDENTITY, Vector3(p.x, SLAB_Y + PIT_HEIGHT * 0.5, p.z)), size)
	city.tree_spots.append(Vector3(p.x, SLAB_Y + PIT_SOIL, p.z))
	_claim(p, 1.2)
	_count("tree pits")


# ------------------------------------------------------- planters, benches ---

## Up to three kit box planters per side, flush against a building front in
## one of the outer thirds of a frontage.
func _planters(side: BlockSide) -> void:
	var placed := 0
	var fronts := side.frontages.duplicate()
	_shuffle(fronts)
	for f: Vector2 in fronts:
		var length := f.y - f.x
		if placed >= 3 or length < 10.0 or _rng.randf() > 0.55:
			continue
		var c := _rng.randf_range(f.x + 1.5, f.x + length / 3.0 - 1.0)
		if _rng.randf() < 0.5:
			c = f.x + f.y - c
		var p := side.point(c, side.depth - 1.12)
		if c < WALL_CORNER_CLEAR or c > side.length - WALL_CORNER_CLEAR or not _free(p, 1.3):
			continue
		_batch_near(p).add("Prop_Planter_Single", Transform3D(Basis.IDENTITY, Vector3(p.x, SLAB_Y, p.z)), false)
		_add_box(Transform3D(Basis.IDENTITY, Vector3(p.x, SLAB_Y + 0.3, p.z)), Vector3(2.0, 0.6, 2.0))
		_claim(p, 1.3)
		placed += 1
		_count("box planters")


## One bench against a wide frontage, in an outer third, facing the street.
func _bench(side: BlockSide) -> void:
	if _rng.randf() > 0.85:
		return
	var fronts := side.frontages.duplicate()
	_shuffle(fronts)
	for f: Vector2 in fronts:
		var length := f.y - f.x
		if length < 14.0:
			continue
		var c := _rng.randf_range(f.x + 1.5, f.x + length / 3.0 - 0.95)
		if _rng.randf() < 0.5:
			c = f.x + f.y - c
		var p := side.point(c, side.depth - 0.42)
		if c < WALL_CORNER_CLEAR or c > side.length - WALL_CORNER_CLEAR or not _free(p, 1.05):
			continue
		# The seat faces +Z in the bench's own frame.
		_spawn("bench", Transform3D(_side_basis(side), Vector3(p.x, SLAB_Y, p.z)))
		_claim(p, 1.05)
		_count("benches")
		return


# ------------------------------------------------------ hydrants and bins ---

func _hydrant(side: BlockSide) -> void:
	for attempt in 10:
		var s := _rng.randf_range(10.0, side.length - 10.0)
		var p := side.point(s, 0.6)
		if _near_alley(side, s, 3.0) or not _free(p, 0.25):
			continue
		# Its pumper outlet (+Z) faces the street.
		_spawn("hydrant", Transform3D(_side_basis(side), Vector3(p.x, SLAB_Y, p.z)))
		_claim(p, 0.25)
		_count("hydrants")
		return


func _bins(side: BlockSide) -> void:
	var want := 1 + int(_rng.randf() < 0.45)
	for attempt in 14:
		if want == 0:
			return
		var s := _rng.randf_range(10.0, side.length - 10.0)
		var p := side.point(s, 0.8)
		if _near_alley(side, s, 3.0) or not _free(p, 0.32):
			continue
		_spawn("bin", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, SLAB_Y, p.z)))
		_claim(p, 0.32)
		_count("bins")
		want -= 1


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp


# ----------------------------------------------------------- lane arrows ---

## Arrows (and ONLY for turn lanes) in the traffic lane 13-17 m before every
## signalized junction next to a showcase block.
func _lane_arrows(intersections: Array[Vector3]) -> void:
	for it in intersections:
		var flags := int(it.z)
		var arms := 0
		for b in 4:
			arms += (flags >> b) & 1
		if arms < 3:
			continue
		var centre := Vector3(it.x, 0.0, it.y)
		for b in 4:
			if not flags & (1 << b):
				continue
			# Traffic arriving from arm b.
			var t: Vector3 = -ARM[b]
			var right := t.cross(Vector3.UP)
			if not _beside_block(centre + ARM[b] * 30.0, right):
				continue
			var straight := (flags & _arm_flag(t)) != 0
			var go_right := (flags & _arm_flag(right)) != 0
			var go_left := (flags & _arm_flag(-right)) != 0
			var coin := hash(Vector3i(int(it.x), int(it.y), b)) % 100
			var module := "Decal_ArrowStraight"
			var lateral := 1.6
			var word := false
			if straight:
				if go_right and go_left:
					if coin < 45:
						module = "Decal_ArrowForwardRight"
						lateral = 1.4
				elif go_right:
					module = "Decal_ArrowForwardRight"
					lateral = 1.4
				elif go_left:
					module = "Decal_ArrowForwardLeft"
					lateral = 1.8
			else:
				word = true
				if go_right and (coin < 50 or not go_left):
					module = "Decal_ArrowTurnRight"
					lateral = 1.55
				else:
					module = "Decal_ArrowTurnLeft"
					lateral = 1.65
			_marking(module, centre - t * ARROW_DISTANCE + right * lateral, t)
			_count("arrows")
			if word:
				_marking("Decal_Only", centre - t * WORD_DISTANCE + right * 1.6, t)
				_count("ONLY words")


## The flag bit of the arm that points along `v`.
static func _arm_flag(v: Vector3) -> int:
	if v.z < -0.5:
		return 1
	if v.x > 0.5:
		return 2
	if v.z > 0.5:
		return 4
	return 8


## Is the road at `p` (a point on its centre line) next to a block of ours?
func _beside_block(p: Vector3, across: Vector3) -> bool:
	for info: Dictionary in downtown.blocks:
		var slab: Rect2 = info["slab"]
		for sign_ in [-1.0, 1.0]:
			var q: Vector3 = p + across * 9.0 * sign_
			if slab.has_point(Vector2(q.x, q.z)):
				return true
	return false


## A road marking lying in the road, its top (the kit's -Z) towards `heading`.
func _marking(module: String, p: Vector3, heading: Vector3) -> void:
	var xf := Transform3D(Basis.looking_at(heading, Vector3.UP), Vector3(p.x, MARKING_Y, p.z))
	_batch_near(p).add(module, xf)


# ------------------------------------------------------------ parked cars ---

## 0-2 parked cars per block side in the kerbside strip, facing the way
## traffic goes there, 20 m+ from any junction. Never on the City Center spawn
## avenue (z = 0, x -150..-75) or within 30 m of the spawn point.
func _parked_cars(sides: Array[BlockSide]) -> void:
	var order := sides.duplicate()
	_shuffle(order)
	var total := 0
	for side: BlockSide in order:
		var r := _rng.randf()
		var n := 0 if r < 0.4 else (1 if r < 0.85 else 2)
		var s_at: Array[float] = []
		if n == 1:
			s_at.append(_rng.randf_range(14.0, side.length - 14.0))
		elif n == 2:
			s_at.append(_rng.randf_range(14.0, 24.0))
			s_at.append(_rng.randf_range(side.length - 24.0, side.length - 14.0))
		for s in s_at:
			if total >= PARK_MAX:
				return
			var p := side.point(s, -PARK_OUT)
			p.y = 0.02
			if Vector2(p.x - SPAWN.x, p.z - SPAWN.z).length() < 30.0:
				continue
			if absf(p.z) < 8.0 and p.x > -156.0 and p.x < -69.0:
				continue
			if _junction_distance(p) < PARK_JUNCTION_CLEAR:
				continue
			var heading := KERB_HEADING[side.index].rotated(Vector3.UP, _rng.randf_range(-0.015, 0.015))
			_spawn("parked_car", Transform3D(Basis.looking_at(heading, Vector3.UP), p))
			total += 1
			_count("parked cars")


func _junction_distance(p: Vector3) -> float:
	var g := MapLayout.CITY_GRID
	var best := INF
	for gx in g:
		for gz in g:
			best = minf(best, Vector2(p.x - gx, p.z - gz).length())
	return best
