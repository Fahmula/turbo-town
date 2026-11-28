class_name PedestrianNetwork
extends RefCounted
## Where pedestrians walk: a graph of the city's sidewalks, its zebra
## crossings, the park paths and a ring round the plaza fountain, worked out
## from MapLayout (the same numbers CityBuilder and RoadBuilder use).
##
## Sidewalks: each block's sidewalk (the outer SIDEWALK_WIDTH of the block,
## raised by CURB_HEIGHT) has a walking line WALK m in from the kerb, clear of
## the street trees (1.6 m in), the lamps (0.5 m) and the shop fronts (4 m);
## walkers keep to the right of it by their own `lane`. At a corner the line
## meets the next side's; the corner's traffic light or lamp stands 1.3 m in
## from the kerb on the diagonal, so the way out to the corner's tip (where
## people wait to cross) goes round it, along either side's line.
##
## Crossings: the junction squares paint their zebras inside the square, along
## each side that has a road (junction.gdshader), so a crossing runs from one
## block's corner tip, over the zebra's middle, to the next block's tip. Every
## city crossing is at a junction with lights; a crossing over the north or
## south arm conflicts with north/south traffic (signal axis 0), one over the
## east or west arm with east/west traffic (axis 1).

enum Kind { SIDEWALK, CORNER, CROSSING, PATH }

## Walking line, from the kerb (m).
const WALK := 2.8
## Corner tip: where people wait to cross, in from the block's corner (m).
const TIP := 0.45
## The way round a corner's pole runs this far in from the kerb (m).
const ROUND := 0.5
## A zebra's middle line, from the junction's centre (m), and how far its
## walking part reaches toward the kerbs (the zebra itself stops at 3.3).
const ZEBRA := 4.5
const ZEBRA_REACH := 4.8
## How far to either side of its line a walker may keep, per kind (m):
## [toward the kerb / left, toward the buildings / right], as fractions of
## their lane (see Pedestrian.lane).
const SPREAD := {Kind.SIDEWALK: 1.0, Kind.CORNER: 0.25, Kind.CROSSING: 0.7, Kind.PATH: 0.6}
## How likely walkers are to take an edge of each kind at a node.
const WEIGHT := {Kind.SIDEWALK: 1.0, Kind.CORNER: 0.35, Kind.CROSSING: 1.0, Kind.PATH: 0.55}


class Edge:
	extends RefCounted
	var id := -1
	var a := -1
	var b := -1
	var kind := 0
	## Polyline from a to b (y = the ground), and the distance to each point.
	var pts := PackedVector3Array()
	var dist := PackedFloat32Array()
	var length := 0.0
	## Crossings: the junction's signal (TrafficNetwork.signals index, -1 =
	## none) and the traffic axis it crosses (0 north/south, 1 east/west).
	var signal_id := -1
	var axis := 0
	var spread := 1.0
	var weight := 1.0


## Node positions (y = the ground).
var points := PackedVector3Array()
## Edge ids at each node.
var adj: Array[PackedInt32Array] = []
var edges: Array[Edge] = []
## The blocks' rectangles (x0, z0, x1, z1): the raised sidewalk level.
var blocks: Array[Rect2] = []


## Builds the city's walking graph. `signal_at` maps a junction's centre
## (x, z) to its traffic signal id (-1 if none).
func build(signal_at: Callable) -> void:
	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	var h := MapLayout.CURB_HEIGHT
	var n := g.size() - 1
	# Per block: its four corner tips, [NW, NE, SE, SW].
	var tips := {}
	for j in n:
		for i in n:
			var x0 := g[i] + hw
			var x1 := g[i + 1] - hw
			var z0 := g[j] + hw
			var z1 := g[j + 1] - hw
			blocks.append(Rect2(x0, z0, x1 - x0, z1 - z0))
			var type: String = MapLayout.BLOCK_TYPES[j][i]
			tips[Vector2i(i, j)] = _add_block(x0, z0, x1, z1, h, type)
	# Crossings at each junction, between neighbouring blocks' tips.
	for l in g.size():
		for k in g.size():
			var c := Vector3(g[k], 0.0, g[l])
			var sig: int = signal_at.call(g[k], g[l])
			var nw := Vector2i(k - 1, l - 1)
			var ne := Vector2i(k, l - 1)
			var sw := Vector2i(k - 1, l)
			var se := Vector2i(k, l)
			# [block a, its corner, block b, its corner, zebra start, zebra end, axis]
			for arm: Array in [
					[nw, 2, ne, 3, Vector3(-ZEBRA_REACH, 0, -ZEBRA), Vector3(ZEBRA_REACH, 0, -ZEBRA), 0],   # north arm
					[sw, 1, se, 0, Vector3(-ZEBRA_REACH, 0, ZEBRA), Vector3(ZEBRA_REACH, 0, ZEBRA), 0],     # south arm
					[nw, 2, sw, 1, Vector3(-ZEBRA, 0, -ZEBRA_REACH), Vector3(-ZEBRA, 0, ZEBRA_REACH), 1],   # west arm
					[ne, 3, se, 0, Vector3(ZEBRA, 0, -ZEBRA_REACH), Vector3(ZEBRA, 0, ZEBRA_REACH), 1]]:    # east arm
				if not tips.has(arm[0]) or not tips.has(arm[2]):
					continue
				var ta: int = tips[arm[0]][arm[1]]
				var tb: int = tips[arm[2]][arm[3]]
				var e := _edge(ta, tb, Kind.CROSSING, PackedVector3Array([
					points[ta], c + arm[4], c + arm[5], points[tb]]))
				e.signal_id = sig
				e.axis = arm[6]


## One block's sidewalk ring, its corners and paths; returns its corner tips.
func _add_block(x0: float, z0: float, x1: float, z1: float, h: float, type: String) -> Array:
	var corner := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	var inward := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var ring: Array[int] = []
	var tip: Array[int] = []
	for k in 4:
		var c: Vector2 = corner[k]
		var d: Vector2 = inward[k]
		ring.append(_node(c + d * WALK, h))
		tip.append(_node(c + d * TIP, h))
	for k in 4:
		var c: Vector2 = corner[k]
		var d: Vector2 = inward[k]
		# Round the pole: along the north/south side's line, or the east/west one's.
		var along_z := Vector2(c.x + d.x * ROUND, c.y + d.y * WALK)
		var along_x := Vector2(c.x + d.x * WALK, c.y + d.y * ROUND)
		for via: Vector2 in [along_z, along_x]:
			_edge(ring[k], tip[k], Kind.CORNER, PackedVector3Array([points[ring[k]], _p(via, h), points[tip[k]]]))
	# The sides: north (0-1), east (1-2), south (2-3), west (3-0). Parks and
	# the plaza get a node halfway along each side for their paths.
	var mids: Array[int] = []
	for k in 4:
		var a := ring[k]
		var b := ring[(k + 1) % 4]
		var pa := points[a]
		var pb := points[b]
		if type == "park" or type == "plaza":
			var m := _node(Vector2((pa.x + pb.x) * 0.5, (pa.z + pb.z) * 0.5), h)
			mids.append(m)
			_side(a, m, type, x0, z0, x1, z1, h)
			_side(m, b, type, x0, z0, x1, z1, h)
		else:
			_edge(a, b, Kind.SIDEWALK, PackedVector3Array([pa, pb]))
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	if type == "park":
		# The paved cross paths (CityBuilder._add_park) meet in the middle.
		var c := _node(Vector2(cx, cz), h + 0.01)
		for m in mids:
			_edge(m, c, Kind.PATH, PackedVector3Array([points[m], points[c]]))
	elif type == "plaza":
		# A ring round the fountain (7.15 m), the sides' paths joining it.
		var r := 10.0
		var ring_nodes: Array[int] = []
		for k in 8:
			var a := TAU * k / 8.0 - PI * 0.5      # k = 0: north
			ring_nodes.append(_node(Vector2(cx + cos(a) * r, cz + sin(a) * r), h))
		for k in 8:
			var a := TAU * k / 8.0 - PI * 0.5
			var arc := PackedVector3Array()
			for t in 4:
				var aa := a + (TAU / 8.0) * t / 3.0
				arc.append(_p(Vector2(cx + cos(aa) * r, cz + sin(aa) * r), h))
			_edge(ring_nodes[k], ring_nodes[(k + 1) % 8], Kind.PATH, arc)
		# mids are north, east, south, west; ring nodes 0, 2, 4, 6 face them.
		for k in 4:
			_edge(mids[k], ring_nodes[k * 2], Kind.PATH, PackedVector3Array([points[mids[k]], points[ring_nodes[k * 2]]]))
	return tip


## A side of the plaza or a park, in two halves. The plaza has a kicker ramp
## on its north and south sidewalks (CityBuilder._add_plaza: 16 m either side
## of the middle, 2 m in, 5 m wide, 7 m long), so its walkers step round them
## on the plaza side.
func _side(a: int, b: int, type: String, x0: float, z0: float, x1: float, z1: float, h: float) -> void:
	var pa := points[a]
	var pb := points[b]
	var line := PackedVector3Array([pa, pb])
	if type == "plaza" and absf(pa.z - pb.z) < 0.01:
		var cx := (x0 + x1) * 0.5
		var north := absf(pa.z - (z0 + WALK)) < 0.01
		var ramp_x := cx + 16.0 if north else cx - 16.0
		var lo := minf(pa.x, pb.x)
		var hi := maxf(pa.x, pb.x)
		if ramp_x > lo and ramp_x < hi:
			var inner := (z0 + 7.8) if north else (z1 - 7.8)
			var dir := signf(pb.x - pa.x)
			line = PackedVector3Array([pa,
				_p(Vector2(ramp_x - dir * 5.0, pa.z), h), _p(Vector2(ramp_x - dir * 3.5, inner), h),
				_p(Vector2(ramp_x + dir * 3.5, inner), h), _p(Vector2(ramp_x + dir * 5.0, pa.z), h), pb])
	_edge(a, b, Kind.SIDEWALK, line)


func _p(v: Vector2, y: float) -> Vector3:
	return Vector3(v.x, y, v.y)


func _node(v: Vector2, y: float) -> int:
	points.append(Vector3(v.x, y, v.y))
	adj.append(PackedInt32Array())
	return points.size() - 1


func _edge(a: int, b: int, kind: int, pts: PackedVector3Array) -> Edge:
	var e := Edge.new()
	e.id = edges.size()
	e.a = a
	e.b = b
	e.kind = kind
	e.pts = pts
	e.spread = SPREAD[kind]
	e.weight = WEIGHT[kind]
	var d := 0.0
	e.dist.append(0.0)
	for i in range(1, pts.size()):
		d += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		e.dist.append(d)
	e.length = d
	edges.append(e)
	adj[a].append(e.id)
	adj[b].append(e.id)
	return e


# ================================================================= queries ==

## The point `s` m along edge `e` walking from `from_a` (true: from its a),
## and the direction of travel there: [position, direction].
func point_on(e: Edge, s: float, from_a: bool) -> Array:
	var d := clampf(s if from_a else e.length - s, 0.0, e.length)
	var i := e.dist.bsearch(d, true) - 1
	i = clampi(i, 0, e.pts.size() - 2)
	var seg := e.dist[i + 1] - e.dist[i]
	var t := (d - e.dist[i]) / seg if seg > 0.0001 else 0.0
	var p := e.pts[i].lerp(e.pts[i + 1], t)
	var dir := e.pts[i + 1] - e.pts[i]
	dir.y = 0.0
	dir = dir.normalized()
	return [p, dir if from_a else -dir]


## The node a walker arrives at when walking edge `e` from `from_a`.
func end_node(e: Edge, from_a: bool) -> int:
	return e.b if from_a else e.a


## Ground height at (x, z): the raised sidewalks inside the blocks, the road
## (0) between them.
func ground_y(x: float, z: float) -> float:
	for r in blocks:
		if r.has_point(Vector2(x, z)):
			return MapLayout.CURB_HEIGHT
	return 0.0


## The nearest point on any edge to `p` (flat): [edge, distance along it from a].
func nearest(p: Vector3, kinds := [Kind.SIDEWALK, Kind.CORNER, Kind.PATH]) -> Array:
	var best := INF
	var best_e: Edge = null
	var best_s := 0.0
	var q := Vector2(p.x, p.z)
	for e in edges:
		if not kinds.has(e.kind):
			continue
		for i in e.pts.size() - 1:
			var a := Vector2(e.pts[i].x, e.pts[i].z)
			var b := Vector2(e.pts[i + 1].x, e.pts[i + 1].z)
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := q.distance_squared_to(a + ab * t)
			if d < best:
				best = d
				best_e = e
				best_s = e.dist[i] + (e.dist[i + 1] - e.dist[i]) * t
	return [best_e, best_s]


## Total walking length (m) and counts, for the dev test.
func report() -> String:
	var counts := {}
	var total := 0.0
	for e in edges:
		counts[e.kind] = counts.get(e.kind, 0) + 1
		total += e.length
	return "%d nodes, %d edges (sidewalk %d, corner %d, crossing %d, path %d), %.1f km" % [
		points.size(), edges.size(), counts.get(Kind.SIDEWALK, 0), counts.get(Kind.CORNER, 0),
		counts.get(Kind.CROSSING, 0), counts.get(Kind.PATH, 0), total / 1000.0]
