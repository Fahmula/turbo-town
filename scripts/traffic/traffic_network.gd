class_name TrafficNetwork
extends RefCounted
## Lane graph for AI traffic, derived from the RoadBuilder's road polylines.
##
## Every road gets one or more lanes per direction (right-hand traffic).
## Lanes are joined by short "connector" lanes (turn curves) at city
## intersections, T-junctions and highway on/off merges; dead ends get a
## U-turn loop. A link can leave a lane anywhere along it (not just at its end),
## which is how highway exits and junctions on through-roads work.
## City intersections with 3+ roads are signal controlled.

const SPACING := 3.0
const RIGHT_TURN_EXTRA := 3.5
const CITY_OFFSETS := [1.8]
const CITY_SPEEDS := [12.5]
const HIGHWAY_OFFSETS := [3.4, 7.0, 10.6]
const HIGHWAY_SPEEDS := [29.0, 26.0, 22.0]
const COUNTRY_OFFSETS := [2.2]
const COUNTRY_SPEEDS := [15.0]

# Signal timing (seconds).
const GREEN_TIME := 10.0
const AMBER_TIME := 2.5
const ALL_RED_TIME := 1.5
const CYCLE := (GREEN_TIME + AMBER_TIME + ALL_RED_TIME) * 2.0
enum SignalState { RED, AMBER, GREEN }


class Lane:
	extends RefCounted
	var id := -1
	var points := PackedVector3Array()
	var dist := PackedFloat32Array()
	## Unit direction of the segment starting at each point.
	var dirs := PackedVector3Array()
	## Heading change per metre arriving at each point (for curve speeds).
	var curv := PackedFloat32Array()
	var length := 0.0
	var closed := false
	var speed := 12.5
	var connector := false
	var road := -1          ## index of the source road (-1 for connectors)
	var reverse := false    ## runs against the source road's point order
	var index := 0          ## 0 = innermost lane of its direction
	var lane_count := 1
	## Ways off this lane: {"at": float, "to": int, "to_at": float}
	var links: Array[Dictionary] = []
	## Links grouped by position: [{"at": float, "links": Array}], sorted.
	var link_groups: Array[Dictionary] = []
	## Traffic-light stop lines along this lane: {"id": signal, "axis": 0/1, "at": s}.
	var stops: Array[Dictionary] = []
	## Connectors that cross or merge into other traffic check this point.
	var yield_point := Vector3.INF
	var take_chance := 0.35
	## Ends in a tight U-turn loop (long vehicles avoid these roads).
	var dead_end := false
	## Same-direction neighbours on multi-lane roads (-1 if none). Left is
	## towards the median (the faster lanes).
	var left_id := -1
	var right_id := -1
	## Room (m) to move right of the lane centre to pull over, and left of it
	## (into the oncoming lane) to pass something parked. 0 = not allowed.
	var pull_room := 0.0
	var pass_room := 0.0

	func finalize() -> void:
		dist.resize(points.size())
		var d := 0.0
		for i in points.size():
			if i > 0:
				d += points[i].distance_to(points[i - 1])
			dist[i] = d
		length = d
		if closed:
			length += points[points.size() - 1].distance_to(points[0])
		var n := points.size()
		dirs.resize(n)
		curv.resize(n)
		for i in n:
			var j := (i + 1) % n
			if not closed and i == n - 1:
				dirs[i] = dirs[i - 1] if i > 0 else Vector3.FORWARD
			else:
				var dv := points[j] - points[i]
				dirs[i] = dv.normalized() if dv.length_squared() > 1e-8 else (dirs[i - 1] if i > 0 else Vector3.FORWARD)
		for i in n:
			if i == 0 and not closed:
				curv[i] = 0.0
				continue
			var prev := (i - 1 + n) % n
			var seg := maxf(points[i].distance_to(points[prev]), 0.5)
			curv[i] = dirs[prev].angle_to(dirs[i]) / seg

	func wrap_s(s: float) -> float:
		if closed:
			return fposmod(s, length)
		return clampf(s, 0.0, length)

	func _segment(s: float) -> int:
		var i := dist.bsearch(s, false) - 1
		return clampi(i, 0, points.size() - 1)

	func point_at(s: float) -> Vector3:
		s = wrap_s(s)
		var n := points.size()
		var i := _segment(s)
		if i >= n - 1 and not closed:
			return points[n - 1]
		var a := points[i]
		var b := points[(i + 1) % n]
		var seg_end := dist[i + 1] if i + 1 < n else length
		var seg := seg_end - dist[i]
		return a.lerp(b, (s - dist[i]) / seg if seg > 1e-5 else 0.0)

	func dir_at(s: float) -> Vector3:
		s = wrap_s(s)
		var n := points.size()
		var i := _segment(s)
		if i >= n - 1 and not closed:
			i = n - 2
		var d := points[(i + 1) % n] - points[i]
		return d.normalized() if d.length_squared() > 1e-8 else Vector3.FORWARD

	## Distance along the lane of the point closest to `p`, searching around
	## `hint` (+- window). For closed lanes the result stays unwrapped near hint.
	func project(p: Vector3, hint: float, window: float) -> float:
		var n := points.size()
		var best_s := hint
		var best_d := INF
		var s0 := hint - window
		var s1 := hint + window
		if not closed:
			s0 = maxf(s0, 0.0)
			s1 = minf(s1, length)
		var s := s0
		while s <= s1 + 0.001:
			var ws := wrap_s(s)
			var i := _segment(ws)
			var a := points[i]
			var b := points[(i + 1) % n] if (closed or i + 1 < n) else points[i]
			var ab := b - a
			var t := 0.0
			var l2 := ab.length_squared()
			if l2 > 1e-8:
				t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var q := a + ab * t
			var d := q.distance_squared_to(p)
			if d < best_d:
				best_d = d
				var seg_len := sqrt(l2)
				best_s = s + (dist[i] + t * seg_len - ws)
			var seg_end := dist[i + 1] if i + 1 < n else length
			s += maxf(seg_end - ws, 0.05)
		return best_s

	func closest_distance(p: Vector3) -> float:
		return project(p, length * 0.5, length * 0.5 + 1.0)


var lanes: Array[Lane] = []
## Per city intersection (same order as RoadBuilder.intersections):
## {"pos": Vector3, "offset": float, "signalized": bool}
var signals: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()


# ================================================================== build ==

func build(roads: RoadBuilder) -> void:
	_rng.seed = 777
	var t0 := Time.get_ticks_msec()
	for ri in roads.roads.size():
		var r := roads.roads[ri]
		if r.kind == RoadBuilder.Kind.TRAIL:
			continue  # dirt trails: no traffic
		var offsets: Array = CITY_OFFSETS
		var speeds: Array = CITY_SPEEDS
		if r.kind == RoadBuilder.Kind.HIGHWAY:
			offsets = HIGHWAY_OFFSETS
			speeds = HIGHWAY_SPEEDS
		elif r.kind == RoadBuilder.Kind.COUNTRY:
			offsets = COUNTRY_OFFSETS
			speeds = COUNTRY_SPEEDS
		var rights := MeshBuilder._path_rights(r.points, r.closed)
		for k in offsets.size():
			for rev in [false, true]:
				var pts := PackedVector3Array()
				for i in r.points.size():
					var side := -1.0 if rev else 1.0
					pts.append(r.points[i] + rights[i] * offsets[k] * side)
				if rev:
					pts.reverse()
				var lane := _add_lane(_resample(pts, r.closed), r.closed)
				lane.road = ri
				lane.reverse = rev
				lane.index = k
				lane.lane_count = offsets.size()
				lane.speed = speeds[k]
				# Room between a ~2 m wide car and the road edge.
				if k == offsets.size() - 1:
					lane.pull_room = clampf(r.width * 0.5 - offsets[k] - 1.3, 0.0, 2.0)
					if r.kind == RoadBuilder.Kind.HIGHWAY:
						lane.pull_room = 1.2
				if offsets.size() == 1:
					lane.pass_room = offsets[k] * 2.0 + 1.0
		_link_neighbours(ri)

	_connect_city_intersections(roads)

	# North avenue: continuation, then T-junction with the hill loop.
	var hw := MapLayout.highway_width() * 0.5
	var ring := MapLayout.HIGHWAY_HALF_EXTENT
	_connect_junction(Vector3(0, 0, -ring - hw - 2.0), 4.0, 0.0, 0.0, false, false, 0.0)
	var loop_start: Vector2 = MapLayout.HILL_LOOP[0]
	_connect_junction(Vector3(loop_start.x, 0, loop_start.y), 10.0, 8.0, 8.0, false, false, 13.0)
	var summit_start: Vector2 = MapLayout.SUMMIT_ROAD[0]
	_connect_junction(Vector3(summit_start.x, 0, summit_start.y), 7.0, 10.0, 10.0, false, false, 13.0)
	# Highway junctions with the east/west avenues (signal ids follow the city
	# intersections: east first, then west — WorldBuilder places their lights).
	for x in [ring, -ring]:
		_connect_highway_junction(Vector3(x, 0, 0))

	_connect_dead_ends()
	for lane in lanes:
		_group_links(lane)
	print("Traffic network: %d lanes in %d ms" % [lanes.size(), Time.get_ticks_msec() - t0])


func _link_neighbours(road_index: int) -> void:
	var by_key := {}
	for lane in lanes:
		if lane.road == road_index:
			by_key["%s%d" % [lane.reverse, lane.index]] = lane
	for lane in lanes:
		if lane.road != road_index:
			continue
		var left: Lane = by_key.get("%s%d" % [lane.reverse, lane.index - 1])
		var right: Lane = by_key.get("%s%d" % [lane.reverse, lane.index + 1])
		lane.left_id = left.id if left else -1
		lane.right_id = right.id if right else -1


func _add_lane(pts: PackedVector3Array, closed: bool) -> Lane:
	var lane := Lane.new()
	lane.id = lanes.size()
	lane.points = pts
	lane.closed = closed
	lane.finalize()
	lanes.append(lane)
	return lane


static func _resample(pts: PackedVector3Array, closed: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(pts[0])
	var n := pts.size()
	var seg_count := n if closed else n - 1
	var carry := 0.0
	for i in seg_count:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var seg := a.distance_to(b)
		var pos := SPACING - carry
		while pos < seg:
			out.append(a.lerp(b, pos / seg))
			pos += SPACING
		carry = seg - (pos - SPACING)
	if closed:
		if out[out.size() - 1].distance_to(out[0]) < SPACING * 0.4:
			out.remove_at(out.size() - 1)
	elif out[out.size() - 1].distance_to(pts[n - 1]) > 0.05:
		if out[out.size() - 1].distance_to(pts[n - 1]) < SPACING * 0.4:
			out[out.size() - 1] = pts[n - 1]
		else:
			out.append(pts[n - 1])
	return out


func _connector(a: Lane, at: float, b: Lane, to_at: float, yield_pt := Vector3.INF) -> void:
	var p0 := a.point_at(at)
	var p3 := b.point_at(to_at)
	var chord := p0.distance_to(p3)
	if chord < 1.0:
		a.links.append({"at": at, "to": b.id, "to_at": to_at})
		return
	var d0 := a.dir_at(at)
	var d3 := b.dir_at(to_at)
	var turn := 1.0 - absf(d0.dot(d3))
	var h := chord * lerpf(0.36, 0.5, turn)
	var p1 := p0 + d0 * h
	var p2 := p3 - d3 * h
	var pts := PackedVector3Array()
	var steps := maxi(int(chord / 1.5), 4)
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	var c := _add_lane(pts, false)
	c.connector = true
	c.speed = minf(a.speed, b.speed)
	c.yield_point = yield_pt
	a.links.append({"at": at, "to": c.id, "to_at": 0.0})
	c.links.append({"at": c.length, "to": b.id, "to_at": to_at})


static func _turn_kind(d0: Vector3, d1: Vector3) -> int:
	## 0 straight, 1 right, 2 left, 3 U-turn
	var dot := d0.dot(d1)
	if dot < -0.7:
		return 3
	if dot > 0.7:
		return 0
	return 1 if d0.cross(d1).y < 0.0 else 2


## Signal axis of a travel direction: 0 = north/south, 1 = east/west.
static func _axis(dir: Vector3) -> int:
	return 0 if absf(dir.z) > absf(dir.x) else 1


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _connect_city_intersections(roads: RoadBuilder) -> void:
	for idx in roads.intersections.size():
		var it := roads.intersections[idx]
		var p := Vector3(it.x, 0, it.y)
		var flags := int(it.z)
		var count := 0
		for b in 4:
			if flags & (1 << b):
				count += 1
		var signalized := count >= 3
		signals.append({"pos": p, "offset": _rng.randf() * CYCLE, "signalized": signalized})
		var incoming: Array[Lane] = []
		var outgoing: Array[Lane] = []
		for lane in lanes:
			if lane.connector or lane.closed:
				continue
			if _flat_dist(lane.points[lane.points.size() - 1], p) < 7.5:
				incoming.append(lane)
			if _flat_dist(lane.points[0], p) < 7.5:
				outgoing.append(lane)
		for a in incoming:
			var da := a.dir_at(a.length)
			if signalized:
				a.stops.append({"id": idx, "axis": _axis(da), "at": a.length - RIGHT_TURN_EXTRA - 0.5})
			for b in outgoing:
				var kind := _turn_kind(da, b.dir_at(0.0))
				if kind == 3:
					continue
				# Right turns start earlier and end later so the curve is wide
				# enough for a car's turning circle.
				var extra := RIGHT_TURN_EXTRA if kind == 1 else 0.0
				_connector(a, a.length - extra, b, extra, p if kind == 2 else Vector3.INF)


## Distances (m) along the highway / avenue for the signalized highway junctions.
const HJ_STOP := 12.5        ## highway stop line before the junction centre
const HJ_RIGHT_OFF := 11.0   ## right turns leave the highway this far before the centre
const HJ_LEFT_OFF := 8.0     ## left turns leave the highway this far before the centre
const HJ_ON := 13.0          ## turns join the highway this far after the centre
const HJ_AVE_STOP := 9.0     ## avenue stop line before the highway edge
const HJ_AVE_RIGHT := 8.0    ## avenue right turns start this far before the highway edge


## Full signalized junction where an avenue crosses the highway at grade:
## straight across, plus left and right turns on and off in both directions
## (right turns use the outer lane, left turns the lane next to the median).
func _connect_highway_junction(p: Vector3) -> void:
	var sig := signals.size()
	signals.append({"pos": p, "offset": 0.0, "signalized": true, "highway": true})
	var ave_in: Array[Lane] = []
	var ave_out: Array[Lane] = []
	var hwy: Array[Lane] = []
	for lane in lanes:
		if lane.connector:
			continue
		if lane.closed:
			if lane.lane_count > 1 and _flat_dist(lane.point_at(lane.closest_distance(p)), p) < 16.0:
				hwy.append(lane)
			continue
		if _flat_dist(lane.points[lane.points.size() - 1], p) < 16.0:
			ave_in.append(lane)
		if _flat_dist(lane.points[0], p) < 16.0:
			ave_out.append(lane)
	for h in hwy:
		var sc := h.closest_distance(p)
		h.stops.append({"id": sig, "axis": _axis(h.dir_at(sc)), "at": h.wrap_s(sc - HJ_STOP)})
	for a in ave_in:
		var da := a.dir_at(a.length)
		a.stops.append({"id": sig, "axis": _axis(da), "at": a.length - HJ_AVE_STOP})
		for b in ave_out:
			if b.road != a.road and _turn_kind(da, b.dir_at(0.0)) == 0:
				_connector(a, a.length, b, 0.0)
		for h in hwy:
			var sc := h.closest_distance(p)
			var kind := _turn_kind(da, h.dir_at(sc))
			if kind == 1 and h.index == h.lane_count - 1:
				_connector(a, a.length - HJ_AVE_RIGHT, h, h.wrap_s(sc + HJ_ON))
			elif kind == 2 and h.index == 0:
				_connector(a, a.length, h, h.wrap_s(sc + HJ_ON), p)
	for h in hwy:
		var sc := h.closest_distance(p)
		var dh := h.dir_at(sc)
		for b in ave_out:
			var kind := _turn_kind(dh, b.dir_at(0.0))
			if kind == 1 and h.index == h.lane_count - 1:
				_connector(h, h.wrap_s(sc - HJ_RIGHT_OFF), b, minf(6.0, b.length))
			elif kind == 2 and h.index == 0:
				_connector(h, h.wrap_s(sc - HJ_LEFT_OFF), b, minf(2.0, b.length), p)


## Joins lanes that end/start near `p`, and lanes passing by it.
## end_back / start_fwd: how far before a lane end / after a lane start the
## turn curve attaches. through_gap: same for lanes passing through.
func _connect_junction(p: Vector3, radius: float, end_back: float, start_fwd: float,
		right_only: bool, outer_only: bool, through_gap: float) -> void:
	var entries: Array = []  # [lane, at, is_through]
	var exits: Array = []    # [lane, to_at, is_through]
	for lane in lanes:
		if lane.connector:
			continue
		var n := lane.points.size()
		var ends_here := not lane.closed and _flat_dist(lane.points[n - 1], p) < radius
		var starts_here := not lane.closed and _flat_dist(lane.points[0], p) < radius
		if ends_here:
			entries.append([lane, maxf(lane.length - end_back, 0.0), false])
		if starts_here:
			exits.append([lane, minf(start_fwd, lane.length), false])
		if ends_here or starts_here or through_gap <= 0.0:
			continue
		if outer_only and lane.index != lane.lane_count - 1:
			continue
		var s := lane.closest_distance(p)
		if _flat_dist(lane.point_at(s), p) > radius:
			continue
		if not lane.closed and (s < through_gap + 2.0 or s > lane.length - through_gap - 2.0):
			continue
		entries.append([lane, lane.wrap_s(s - through_gap), true])
		exits.append([lane, lane.wrap_s(s + through_gap), true])
	for e in entries:
		var a: Lane = e[0]
		for x in exits:
			var b: Lane = x[0]
			if a == b or (a.road == b.road and a.road >= 0 and (e[2] or x[2])):
				continue
			var kind := _turn_kind(a.dir_at(e[1]), b.dir_at(x[1]))
			if kind == 3 or (right_only and kind != 1):
				continue
			var yield_pt := Vector3.INF
			if x[2]:
				yield_pt = b.point_at(x[1])  # merging into a through road
			elif kind == 2:
				yield_pt = p
			_connector(a, e[1], b, x[1], yield_pt)


func _connect_dead_ends() -> void:
	var count := lanes.size()
	for li in count:
		var a := lanes[li]
		if a.connector or a.closed:
			continue
		var has_end := false
		for l in a.links:
			if l["at"] >= a.length - 15.0:
				has_end = true
		if has_end:
			continue
		var rev: Lane = null
		for b in lanes:
			if b.road == a.road and b.reverse != a.reverse and b.index == a.index:
				rev = b
		if rev == null:
			continue
		a.dead_end = true
		_u_turn(a, rev)


## U-turn loop at a dead end, using the full road width.
func _u_turn(a: Lane, b: Lane) -> void:
	var back := minf(10.0, a.length * 0.4)
	var start_s := a.length - back
	var end_p := a.point_at(a.length)
	var f := a.dir_at(a.length)
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP)
	var half := _flat_dist(end_p, b.point_at(0.0)) * 0.5
	var center := end_p - r * half
	var radius := 4.5
	var local: Array[Vector2] = [Vector2(-back, half), Vector2(-6.5, half + 1.2), Vector2(-4.0, radius - 0.2)]
	for k in range(1, 12):
		var phi := PI * 0.5 - PI * k / 12.0
		local.append(Vector2(-3.0 + cos(phi) * radius, sin(phi) * radius))
	local.append(Vector2(-4.0, -radius + 0.2))
	local.append(Vector2(-6.5, -half - 1.2))
	local.append(Vector2(-back, -half))
	var pts := PackedVector3Array()
	for v in local:
		pts.append(center + f * v.x + r * v.y)
	var c := _add_lane(pts, false)
	c.connector = true
	c.speed = 2.5
	a.links.append({"at": start_s, "to": c.id, "to_at": 0.0})
	c.links.append({"at": c.length, "to": b.id, "to_at": minf(back, b.length)})


## Groups a lane's links into decision points. All the turns at the end of
## a lane (right turns start a few metres before the others) form one choice.
func _group_links(lane: Lane) -> void:
	lane.link_groups.clear()
	var sorted := lane.links.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["at"] < y["at"])
	var end_zone := lane.length - 12.0
	for l in sorted:
		var last: Dictionary = lane.link_groups.back() if not lane.link_groups.is_empty() else {}
		var same: bool = not last.is_empty() and (absf(last["at"] - l["at"]) <= 0.5
			or (not lane.closed and last["at"] >= end_zone and l["at"] >= end_zone))
		if not same:
			lane.link_groups.append({"at": l["at"], "links": []})
		lane.link_groups.back()["links"].append(l)
	if lane.road >= 0 and not lane.closed:
		lane.take_chance = 1.0
	elif lane.closed:
		lane.take_chance = 0.3


## True if `link` starts a left turn (connector curving left).
func is_left_turn(link: Dictionary) -> bool:
	var lane := lanes[link["to"]]
	return lane.connector and lane.length > 4.0 and _turn_kind(lane.dir_at(0.0), lane.dir_at(lane.length)) == 2


## True if following `link` puts a vehicle onto a road that dead-ends.
func leads_to_dead_end(link: Dictionary) -> bool:
	var lane := lanes[link["to"]]
	if lane.connector and not lane.links.is_empty():
		lane = lanes[lane.links[0]["to"]]
	return lane.dead_end


# ================================================================ signals ==

func signal_state(id: int, axis: int, time: float) -> int:
	if id < 0 or id >= signals.size() or not signals[id]["signalized"]:
		return SignalState.GREEN
	var t := fposmod(time + signals[id]["offset"], CYCLE)
	var half := CYCLE * 0.5
	var active := 0 if t < half else 1
	var tt := t if t < half else t - half
	if axis != active:
		return SignalState.RED
	if tt < GREEN_TIME:
		return SignalState.GREEN
	if tt < GREEN_TIME + AMBER_TIME:
		return SignalState.AMBER
	return SignalState.RED


# ================================================================ helpers ==

## A random point on a non-connector lane, weighted by length.
func random_spawn(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for lane in lanes:
		if not lane.connector:
			total += lane.length * _spawn_weight(lane)
	var pick := rng.randf() * total
	for lane in lanes:
		if lane.connector:
			continue
		pick -= lane.length * _spawn_weight(lane)
		if pick <= 0.0:
			var margin := 15.0 if not lane.closed else 0.0
			if lane.length < margin * 2.0 + 5.0:
				return {}
			return {"lane": lane, "s": rng.randf_range(margin, lane.length - margin)}
	return {}


func _spawn_weight(lane: Lane) -> float:
	return 0.6 if lane.speed > 20.0 else 1.0


## Sanity report for debugging the lane graph.
func debug_report(roads: RoadBuilder) -> String:
	var road_lanes := 0
	var connectors := 0
	var stuck: Array[String] = []
	for lane in lanes:
		if lane.connector:
			connectors += 1
		else:
			road_lanes += 1
		if not lane.closed and lane.link_groups.is_empty():
			stuck.append("%s lane %d (road '%s', rev=%s) len=%.0f" % ["connector" if lane.connector else "road", lane.id,
				roads.roads[lane.road].name if lane.road >= 0 else "-", lane.reverse, lane.length])
	# Reachability from lane 0 following links.
	var seen := {0: true}
	var queue := [0]
	while not queue.is_empty():
		var id: int = queue.pop_back()
		for l in lanes[id].links:
			if not seen.has(l["to"]):
				seen[l["to"]] = true
				queue.append(l["to"])
	var unreachable := 0
	var names: Array[String] = []
	for lane in lanes:
		if not seen.has(lane.id) and not lane.connector:
			unreachable += 1
			names.append("%s#%d%s" % [roads.roads[lane.road].name, lane.index, "r" if lane.reverse else ""])
	var per_junction := {}
	for lane in lanes:
		if lane.connector and lane.yield_point != Vector3.INF:
			per_junction["yield"] = per_junction.get("yield", 0) + 1
	return "road lanes %d, connectors %d (%d yield), no-exit lanes %d %s, unreachable road lanes %d %s" % [
		road_lanes, connectors, per_junction.get("yield", 0), stuck.size(), str(stuck), unreachable, str(names)]
