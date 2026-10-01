@tool
class_name RoadBuilder
extends RefCounted
## Defines the road network (as polylines with heights), cuts it into the
## terrain, and builds road decks, intersections, barriers and bridge pillars.

enum Kind { CITY, HIGHWAY, COUNTRY, TRAIL }

## Deck heights above natural ground beyond this become bridges on pillars
## instead of embankments.
const EMBANKMENT_MAX := 5.0
const DECK_DEPTH := 1.2
## New-style bridge decks (ArtZone): fascia beam depth and deck slab depth.
const FASCIA_DEPTH := 1.3
const SLAB_DEPTH := 0.35


class Road:
	extends RefCounted
	var name := ""
	var kind := Kind.CITY
	var points := PackedVector3Array()
	var width := 12.0
	var closed := false
	var shoulder := 6.0
	var barriers := false
	## Path-distance ranges (x = start, y = end) with no barriers (junctions).
	var barrier_gaps: Array[Vector2] = []
	var elevated := PackedByteArray()
	var dist := PackedFloat32Array()

	func finalize() -> void:
		dist.resize(points.size())
		elevated.resize(points.size())
		elevated.fill(0)
		var d := 0.0
		for i in points.size():
			if i > 0:
				d += points[i].distance_to(points[i - 1])
			dist[i] = d

	func total_length() -> float:
		var l := dist[dist.size() - 1]
		if closed:
			l += points[points.size() - 1].distance_to(points[0])
		return l


var roads: Array[Road] = []
## City intersections: x, z, side flags (1=N, 2=E, 4=S, 8=W).
var intersections: Array[Vector3] = []
## Flattened circular areas: x, z, radius, height.
var flat_areas: Array[Vector4] = []
var summit_height := 0.0
var beach_height := 0.3
var highway: Road

var _terrain: TerrainBuilder
var _mat_city: Material
var _mat_highway: Material
var _mat_country: Material
var _mat_intersection: Material
var _mat_barrier: Material
var _mat_concrete: Material


func _init(terrain: TerrainBuilder) -> void:
	_terrain = terrain


# ============================================================== definition ==

func define_all() -> void:
	_define_city_grid()
	_define_highway()
	_define_hill_roads()
	_define_trails()
	_define_avenues()
	var west := find_road("AvenueWestOuter")
	beach_height = west.points[west.points.size() - 1].y
	flat_areas.append(Vector4(MapLayout.BEACH_LOT.x, MapLayout.BEACH_LOT.y, 24.0, beach_height - 0.15))
	for r in roads:
		r.finalize()
		if r.kind == Kind.HIGHWAY:
			for i in r.points.size():
				var p := r.points[i]
				if p.y - _terrain.base_height(p.x, p.z) > EMBANKMENT_MAX:
					r.elevated[i] = 1


func find_road(road_name: String) -> Road:
	for r in roads:
		if r.name == road_name:
			return r
	return null


func _add_road(road_name: String, kind: Kind, pts: PackedVector3Array, width: float, shoulder: float, closed := false) -> Road:
	var r := Road.new()
	r.name = road_name
	r.kind = kind
	r.points = pts
	r.width = width
	r.shoulder = shoulder
	r.closed = closed
	roads.append(r)
	return r


func _define_city_grid() -> void:
	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	for line in g:
		for i in g.size() - 1:
			var a := g[i] + hw
			var b := g[i + 1] - hw
			_add_road("EW", Kind.CITY, PackedVector3Array([Vector3(a, 0, line), Vector3(b, 0, line)]), MapLayout.CITY_ROAD_WIDTH, 4.0)
			_add_road("NS", Kind.CITY, PackedVector3Array([Vector3(line, 0, a), Vector3(line, 0, b)]), MapLayout.CITY_ROAD_WIDTH, 4.0)
	for gz in g:
		for gx in g:
			var flags := 0
			if gz > g[0] or gx == 0.0:
				flags |= 1
			if gx < g[g.size() - 1] or gz == 0.0:
				flags |= 2
			if gz < g[g.size() - 1] or gx == 0.0:
				flags |= 4
			if gx > g[0] or gz == 0.0:
				flags |= 8
			intersections.append(Vector3(gx, gz, flags))


func _define_avenues() -> void:
	var edge := MapLayout.CITY_GRID[MapLayout.CITY_GRID.size() - 1] + MapLayout.CITY_ROAD_WIDTH * 0.5
	var w := MapLayout.CITY_ROAD_WIDTH
	var hw_h := MapLayout.highway_width() * 0.5
	var ring := MapLayout.HIGHWAY_HALF_EXTENT

	# North avenue ends where it meets the hill loop.
	var loop_y := _nearest_height(find_road("HillLoop"), Vector3(0, 0, -300))
	_add_road("AvenueNorth", Kind.CITY, _line(Vector3(0, 0, -edge), Vector3(0, 0, -ring - hw_h - 2.0), 8.0), w, 6.0)
	_add_road("AvenueNorthHill", Kind.CITY, _line(Vector3(0, 0, -ring - hw_h - 2.0), Vector3(0, loop_y, MapLayout.AVENUE_NORTH_END), 4.0), w, 8.0)
	_add_road("AvenueSouth", Kind.CITY, _line(Vector3(0, 0, edge), Vector3(0, 0, MapLayout.AVENUE_SOUTH_END), 8.0), w, 6.0)

	# East/west avenues stop at the highway edges (at-grade junctions) and continue beyond.
	_add_road("AvenueEast", Kind.CITY, _line(Vector3(edge, 0, 0), Vector3(ring - hw_h, 0, 0), 8.0), w, 6.0)
	var east := _line(Vector3(ring + hw_h, 0, 0), Vector3(MapLayout.AVENUE_EAST_END, 0, 0), 5.0)
	_follow_terrain(east, 4, true, false)
	_add_road("AvenueEastOuter", Kind.CITY, east, w, 10.0)
	_add_road("AvenueWest", Kind.CITY, _line(Vector3(-edge, 0, 0), Vector3(-ring + hw_h, 0, 0), 8.0), w, 6.0)
	var west := _line(Vector3(-ring - hw_h, 0, 0), Vector3(MapLayout.AVENUE_WEST_END, 0, 0), 5.0)
	_follow_terrain(west, 4, true, false)
	_add_road("AvenueWestOuter", Kind.CITY, west, w, 10.0)


func _define_highway() -> void:
	var total := _ring_length()
	var count := int(total / 3.0)
	var pts := PackedVector3Array()
	for i in count:
		var d := total * i / count
		var p := _ring_point(d)
		p.y = _highway_elevation(d, total)
		pts.append(p)
	highway = _add_road("Highway", Kind.HIGHWAY, pts, MapLayout.highway_width(), 12.0, true)
	highway.barriers = true
	# Open the barriers where the east/west avenues cross (turning curves too).
	var gap := MapLayout.CITY_ROAD_WIDTH * 0.5 + 9.0
	for d in [total * 0.25, total * 0.75]:
		highway.barrier_gaps.append(Vector2(d - gap, d + gap))


func _define_hill_roads() -> void:
	var loop := _catmull_rom(MapLayout.HILL_LOOP, true, 3.0)
	_follow_terrain(loop, 10, false, false, true)
	_add_road("HillLoop", Kind.COUNTRY, loop, MapLayout.HILL_ROAD_WIDTH, 10.0, true)

	var summit := _catmull_rom(MapLayout.SUMMIT_ROAD, false, 3.0)
	var start_y := _nearest_height(roads[roads.size() - 1], summit[0])
	_follow_terrain(summit, 8, false, false)
	# Blend the start into the loop's height.
	for i in mini(12, summit.size()):
		var t := float(i) / 12.0
		summit[i].y = lerpf(start_y, summit[i].y, t * t)
	summit_height = summit[summit.size() - 1].y
	_add_road("SummitRoad", Kind.COUNTRY, summit, MapLayout.HILL_ROAD_WIDTH, 10.0)
	var c := MapLayout.MOUNTAIN_CENTER
	flat_areas.append(Vector4(c.x, c.y, MapLayout.SUMMIT_RADIUS, summit_height - 0.15))


## Dirt trails: shaped into the terrain like roads (so no trees grow on them)
## but drawn as bumpy dirt, with no traffic.
func _define_trails() -> void:
	var trail := _fillet_path(MapLayout.MOUNTAIN_TRAIL, 9.0, 3.0)
	_follow_terrain(trail, 5, false, false)
	_add_road("MountainTrail", Kind.TRAIL, trail, MapLayout.TRAIL_WIDTH, 4.0)


# --- geometry helpers ---

## Straight legs between the control points, joined by circular arcs of
## `radius` (proper hairpins on a zig-zag), resampled every `spacing` m.
static func _fillet_path(ctrl: Array, radius: float, spacing: float) -> PackedVector3Array:
	var pts: Array[Vector2] = []
	for p in ctrl:
		pts.append(p)
	var dense: Array[Vector2] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var d0 := (b - a).normalized()
		var d1 := (c - b).normalized()
		var turn := d0.angle_to(d1)
		var trim := minf(radius * tan(absf(turn) * 0.5), minf(a.distance_to(b), b.distance_to(c)) * 0.45)
		var r := trim / maxf(tan(absf(turn) * 0.5), 0.001)
		var t0 := b - d0 * trim
		var nrm := Vector2(-d0.y, d0.x) * signf(turn)
		var center := t0 + nrm * r
		var start_ang := (t0 - center).angle()
		var steps := maxi(int(absf(turn) * r / 1.5), 2)
		for k in steps + 1:
			var ang := start_ang + turn * float(k) / steps
			dense.append(center + Vector2(cos(ang), sin(ang)) * r)
	dense.append(pts[pts.size() - 1])
	var out := PackedVector3Array()
	out.append(Vector3(dense[0].x, 0, dense[0].y))
	var carry := 0.0
	for i in dense.size() - 1:
		var a := dense[i]
		var b := dense[i + 1]
		var seg := a.distance_to(b)
		var pos := spacing - carry
		while pos <= seg:
			var p := a.lerp(b, pos / seg)
			out.append(Vector3(p.x, 0, p.y))
			pos += spacing
		carry = seg - (pos - spacing)
	var last := dense[dense.size() - 1]
	if out[out.size() - 1].distance_to(Vector3(last.x, 0, last.y)) > spacing * 0.4:
		out.append(Vector3(last.x, 0, last.y))
	return out

func _ring_length() -> float:
	var s := MapLayout.HIGHWAY_HALF_EXTENT - MapLayout.HIGHWAY_CORNER_RADIUS
	return 8.0 * s + TAU * MapLayout.HIGHWAY_CORNER_RADIUS


## Point on the rounded-rectangle ring, starting at the north crossing
## (0, -A) heading east, going clockwise seen from above.
func _ring_point(d: float) -> Vector3:
	var a := MapLayout.HIGHWAY_HALF_EXTENT
	var r := MapLayout.HIGHWAY_CORNER_RADIUS
	var s := a - r
	var arc := PI * 0.5 * r
	# Segments: half straight, then 4 x (corner, full straight), then half straight.
	if d < s:
		return Vector3(d, 0, -a)
	d -= s
	var corners := [Vector2(s, -s), Vector2(s, s), Vector2(-s, s), Vector2(-s, -s)]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var straight_dirs := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for k in 4:
		var c: Vector2 = corners[k]
		if d < arc:
			var th: float = start_angles[k] + d / r
			return Vector3(c.x + cos(th) * r, 0, c.y + sin(th) * r)
		d -= arc
		var end_th: float = start_angles[k] + PI * 0.5
		var start := c + Vector2(cos(end_th), sin(end_th)) * r
		var seg_len := 2.0 * s if k < 3 else s
		if d < seg_len or k == 3:
			var p: Vector2 = start + straight_dirs[k] * minf(d, seg_len)
			return Vector3(p.x, 0, p.y)
		d -= seg_len
	return Vector3(0, 0, -a)


func _highway_elevation(d: float, total: float) -> float:
	var h := 0.0
	for center in [0.0, total * 0.5]:
		var dd := absf(d - center)
		dd = minf(dd, total - dd)
		h += 1.0 - smoothstep(MapLayout.HIGHWAY_BRIDGE_FLAT, MapLayout.HIGHWAY_BRIDGE_FLAT + MapLayout.HIGHWAY_BRIDGE_RAMP, dd)
	return h * MapLayout.HIGHWAY_BRIDGE_HEIGHT


func _line(a: Vector3, b: Vector3, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := maxi(int(a.distance_to(b) / spacing), 1)
	for i in count + 1:
		out.append(a.lerp(b, float(i) / count))
	return out


static func _catmull_rom(ctrl: Array, closed: bool, spacing: float) -> PackedVector3Array:
	var pts: Array[Vector2] = []
	for p in ctrl:
		pts.append(p)
	var n := pts.size()
	var dense: Array[Vector2] = []
	var seg_count := n if closed else n - 1
	for i in seg_count:
		var p0: Vector2 = pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n] if (closed or i + 2 < n) else pts[n - 1]
		for k in 24:
			var t := k / 24.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	if not closed:
		dense.append(pts[n - 1])
	# Resample at even spacing.
	var out := PackedVector3Array()
	out.append(Vector3(dense[0].x, 0, dense[0].y))
	var carry := 0.0
	var count := dense.size() if closed else dense.size() - 1
	for i in count:
		var a: Vector2 = dense[i]
		var b: Vector2 = dense[(i + 1) % dense.size()]
		var seg := a.distance_to(b)
		var pos := spacing - carry
		while pos <= seg:
			var p := a.lerp(b, pos / seg)
			out.append(Vector3(p.x, 0, p.y))
			pos += spacing
		carry = seg - (pos - spacing)
	if closed and out[out.size() - 1].distance_to(out[0]) < spacing * 0.5:
		out.remove_at(out.size() - 1)
	return out


## Sets point heights from smoothed natural terrain.
func _follow_terrain(pts: PackedVector3Array, window: int, pin_start: bool, pin_end: bool, closed := false) -> void:
	var n := pts.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = _terrain.base_height(pts[i].x, pts[i].z)
	for pass_i in 2:
		var sm := PackedFloat32Array()
		sm.resize(n)
		for i in n:
			var sum := 0.0
			var cnt := 0
			for k in range(-window, window + 1):
				var j := i + k
				if closed:
					j = (j + n) % n
				elif j < 0 or j >= n:
					continue
				sum += raw[j]
				cnt += 1
			sm[i] = sum / cnt
		raw = sm
	var y0 := pts[0].y
	var y1 := pts[n - 1].y
	for i in n:
		var y := raw[i]
		if pin_start:
			y = lerpf(y0, y, smoothstep(0.0, 8.0, float(i)))
		if pin_end:
			y = lerpf(y1, y, smoothstep(0.0, 8.0, float(n - 1 - i)))
		pts[i].y = y


func _nearest_height(road: Road, p: Vector3) -> float:
	var best := INF
	var y := 0.0
	for q in road.points:
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < best:
			best = d
			y = q.y
	return y


# ================================================================== raster ==

func raster_into_terrain() -> void:
	for r in roads:
		var hw := r.width * 0.5
		var n := r.points.size()
		var seg_count := n if r.closed else n - 1
		for i in seg_count:
			var i1 := (i + 1) % n
			if r.elevated[i] or r.elevated[i1]:
				continue
			_terrain.raster_segment(r.points[i], r.points[i1], hw, r.shoulder)
	for f in flat_areas:
		_terrain.raster_circle(Vector2(f.x, f.y), f.z, f.w, 14.0)
	# Landmark ground: airport runway + apron, harbour quay.
	_terrain.raster_segment(MapLayout.RUNWAY_A, MapLayout.RUNWAY_B, MapLayout.RUNWAY_WIDTH * 0.5 + 4.0, 16.0)
	var ac := MapLayout.APRON_CENTER
	var asz := MapLayout.APRON_SIZE
	_terrain.raster_segment(ac - Vector3(asz.x * 0.5, 0, 0), ac + Vector3(asz.x * 0.5, 0, 0), asz.y * 0.5 + 3.0, 12.0)
	_terrain.raster_segment(MapLayout.HARBOR_QUAY_A, MapLayout.HARBOR_QUAY_B, 18.0, 8.0)


# =================================================================== build ==

func build(parent: Node3D) -> void:
	_mat_city = load("res://assets/materials/road_city.tres")
	_mat_highway = load("res://assets/materials/road_highway.tres")
	_mat_country = load("res://assets/materials/road_country.tres")
	_mat_intersection = load("res://assets/materials/road_intersection.tres")
	_mat_barrier = load("res://assets/materials/barrier.tres")
	_mat_concrete = load("res://assets/materials/concrete.tres")

	var root := Node3D.new()
	root.name = "Roads"
	parent.add_child(root)

	var decks := {Kind.CITY: MeshBuilder.new(), Kind.HIGHWAY: MeshBuilder.new(), Kind.COUNTRY: MeshBuilder.new()}
	# New style (ArtZone preview): decks, and the overpass undersides (no collision).
	var env_decks := {Kind.CITY: MeshBuilder.new(), Kind.HIGHWAY: MeshBuilder.new(), Kind.COUNTRY: MeshBuilder.new()}
	var structure := MeshBuilder.new()
	var trails := MeshBuilder.new()
	var markers := MeshBuilder.new()
	for r in roads:
		if r.kind == Kind.TRAIL:
			_add_trail(trails, markers, r)
		else:
			_add_deck(decks[r.kind], env_decks[r.kind], structure, r)
	root.add_child(trails.build_node("Trails", load("res://assets/materials/props.tres"), true, 0.85))
	root.add_child(markers.build_node("TrailMarkers", load("res://assets/materials/props.tres"), false))
	for r in roads:
		if r.kind == Kind.TRAIL:
			var sign := Label3D.new()
			sign.text = "MOUNTAIN TRAIL"
			sign.font_size = 120
			sign.pixel_size = 0.012
			sign.outline_size = 18
			sign.modulate = Color(1.0, 0.6, 0.2)
			sign.outline_modulate = Color(0.1, 0.08, 0.05)
			sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sign.position = r.points[0] + Vector3(-5.0, 3.5, 0.0)
			root.add_child(sign)
	root.add_child(decks[Kind.CITY].build_node("CityRoads", _mat_city, true, 1.0))
	root.add_child(decks[Kind.HIGHWAY].build_node("Highway", _mat_highway, true, 1.0))
	root.add_child(decks[Kind.COUNTRY].build_node("CountryRoads", _mat_country, true, 1.0))
	var env_mats := {
		Kind.CITY: load("res://assets/materials/env/road_city.tres"),
		Kind.HIGHWAY: load("res://assets/materials/env/road_highway.tres"),
		Kind.COUNTRY: load("res://assets/materials/env/road_country.tres"),
	}
	var env_names := {Kind.CITY: "CityRoadsEnv", Kind.HIGHWAY: "HighwayEnv", Kind.COUNTRY: "CountryRoadsEnv"}
	for kind: Kind in env_decks:
		if not (env_decks[kind] as MeshBuilder).is_empty():
			root.add_child((env_decks[kind] as MeshBuilder).build_node(env_names[kind], env_mats[kind], true, 1.0))
	if not structure.is_empty():
		var smi := MeshInstance3D.new()
		smi.name = "OverpassStructure"
		smi.mesh = structure.build_mesh(load("res://assets/materials/env/concrete.tres"))
		root.add_child(smi)

	var inter := MeshBuilder.new()
	var env_inter := MeshBuilder.new()
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	for it in intersections:
		var c := Vector3(it.x, 0, it.y)
		var flags := int(it.z)
		var col := Color(float(flags & 1), float((flags >> 1) & 1), float((flags >> 2) & 1), float((flags >> 3) & 1))
		var target := env_inter if ArtZone.has_point(c) else inter
		target.add_quad(c + Vector3(-hw, 0, hw), c + Vector3(hw, 0, hw), c + Vector3(hw, 0, -hw), c + Vector3(-hw, 0, -hw), col,
			Vector2(-hw, hw), Vector2(hw, hw), Vector2(hw, -hw), Vector2(-hw, -hw))
	root.add_child(inter.build_node("Intersections", _mat_intersection, true, 1.0))
	if not env_inter.is_empty():
		root.add_child(env_inter.build_node("IntersectionsEnv", load("res://assets/materials/env/junction.tres"), true, 1.0))

	_build_barriers(root)
	_build_pillars(root)


## Road deck: the top surface plus side walls. Segments inside the ArtZone go
## to `env` (new style, with stop lines, bridge-deck joints and fascias) and
## the undersides of their bridge sections to `structure`.
func _add_deck(mb: MeshBuilder, env: MeshBuilder, structure: MeshBuilder, r: Road) -> void:
	var hw := r.width * 0.5
	var n := r.points.size()
	var rights := MeshBuilder._path_rights(r.points, r.closed)
	var top := Color(1, 1, 1, 1)
	var side := Color(1, 1, 1, 0)
	var seg_count := n if r.closed else n - 1
	var total := r.total_length()
	env.set_uv2(_stop_lines(r))
	for i in seg_count:
		var i1 := (i + 1) % n
		var p0 := r.points[i]
		var p1 := r.points[i1]
		var d0 := r.dist[i]
		var d1 := r.dist[i1] if i1 != 0 else total
		var l0 := p0 - rights[i] * hw
		var r0 := p0 + rights[i] * hw
		var l1 := p1 - rights[i1] * hw
		var r1 := p1 + rights[i1] * hw
		var bridge := r.elevated[i] or r.elevated[i1]
		if ArtZone.has_point((p0 + p1) * 0.5):
			var depth := FASCIA_DEPTH if bridge else 0.6
			var down := Vector3.DOWN * depth
			env.add_quad(l0, r0, r1, l1, Color(1, 1, 0, 1) if bridge else top,
				Vector2(-hw, d0), Vector2(hw, d0), Vector2(hw, d1), Vector2(-hw, d1))
			env.add_quad(r0 + down, r1 + down, r1, r0, side, Vector2(d0, depth), Vector2(d1, depth), Vector2(d1, 0), Vector2(d0, 0))
			env.add_quad(l1 + down, l0 + down, l0, l1, side, Vector2(d1, depth), Vector2(d0, depth), Vector2(d0, 0), Vector2(d1, 0))
			if bridge:
				_add_deck_underside(structure, p0, p1, rights[i], rights[i1], hw)
			else:
				env.add_quad(l0 + down, l1 + down, r1 + down, r0 + down, side)
			continue
		var depth := DECK_DEPTH if bridge else 0.6
		var down := Vector3.DOWN * depth
		mb.add_quad(l0, r0, r1, l1, top, Vector2(-hw, d0), Vector2(hw, d0), Vector2(hw, d1), Vector2(-hw, d1))
		mb.add_quad(r0 + down, r1 + down, r1, r0, side)
		mb.add_quad(l1 + down, l0 + down, l0, l1, side)
		mb.add_quad(l0 + down, l1 + down, r1 + down, r0 + down, side)
	if not r.closed:
		for end in [0, n - 1]:
			var p := r.points[end]
			var l := p - rights[end] * hw
			var rr := p + rights[end] * hw
			var down := Vector3.DOWN * 0.6
			var target := env if ArtZone.has_point(p) else mb
			if end == 0:
				target.add_quad(rr + down, rr, l, l + down, side, Vector2(0, 0.6), Vector2(0, 0), Vector2(r.width, 0), Vector2(r.width, 0.6))
			else:
				target.add_quad(l + down, l, rr, rr + down, side, Vector2(0, 0.6), Vector2(0, 0), Vector2(r.width, 0), Vector2(r.width, 0.6))


## Where the stop lines go on a road (UV2 for road_surface.gdshader): x for
## traffic leaving the road at its start, y for traffic leaving at its end,
## as distances from the start (0 = no line). They sit just ahead of where
## TrafficNetwork makes cars stop at red lights.
func _stop_lines(r: Road) -> Vector2:
	if r.kind != Kind.CITY or r.closed:
		return Vector2.ZERO
	var total := r.total_length()
	var s := 0.0
	var e := 0.0
	if _signalized_at(r.points[0]):
		s = 3.4
	if _signalized_at(r.points[r.points.size() - 1]):
		e = total - 3.4
	# Avenues stopping at the highway junctions.
	if r.name == "AvenueEast" or r.name == "AvenueWest":
		e = total - TrafficNetwork.HJ_AVE_STOP + 0.6
	elif r.name == "AvenueEastOuter" or r.name == "AvenueWestOuter":
		s = TrafficNetwork.HJ_AVE_STOP - 0.6
	return Vector2(s, e)


func _signalized_at(p: Vector3) -> bool:
	for it in intersections:
		if Vector2(it.x - p.x, it.y - p.z).length() < 7.5:
			var flags := int(it.z)
			var count := 0
			for b in 4:
				if flags & (1 << b):
					count += 1
			return count >= 3
	return false


## Under a bridge deck: the fascia beams' inner faces and bottoms, the soffit
## and five girders, visual only (concrete, no collision).
func _add_deck_underside(mb: MeshBuilder, p0: Vector3, p1: Vector3, rt0: Vector3, rt1: Vector3, hw: float) -> void:
	var soffit := Vector3.DOWN * SLAB_DEPTH
	var bottom := Vector3.DOWN * FASCIA_DEPTH
	var fascia_w := 0.4
	var shade := ArtPalette.CONCRETE_STAINED
	shade.a = 0.0
	var col := ArtPalette.CONCRETE.darkened(0.08)
	col.a = 0.0
	var pt := func(p: Vector3, rt: Vector3, x: float, dn: Vector3) -> Vector3: return p + rt * x + dn
	# Soffit between the fascia beams, facing down.
	var si := hw - fascia_w
	mb.add_quad(pt.call(p0, rt0, -si, soffit), pt.call(p1, rt1, -si, soffit), pt.call(p1, rt1, si, soffit), pt.call(p0, rt0, si, soffit), shade)
	for s: float in [-1.0, 1.0]:
		# Fascia beam bottom and inner face.
		var xo := s * hw
		var xi := s * si
		var a := pt.call(p0, rt0, xo, bottom) as Vector3
		var b := pt.call(p1, rt1, xo, bottom) as Vector3
		var c := pt.call(p1, rt1, xi, bottom) as Vector3
		var d := pt.call(p0, rt0, xi, bottom) as Vector3
		if s > 0.0:
			mb.add_quad(a, d, c, b, col)
			mb.add_quad(d, pt.call(p0, rt0, xi, soffit), pt.call(p1, rt1, xi, soffit), c, shade)
		else:
			mb.add_quad(a, b, c, d, col)
			mb.add_quad(c, pt.call(p1, rt1, xi, soffit), pt.call(p0, rt0, xi, soffit), d, shade)
	# Girders.
	var gw := 0.25
	var gd := Vector3.DOWN * (FASCIA_DEPTH - 0.15)
	for k in 5:
		var x := lerpf(-si + 2.6, si - 2.6, k / 4.0)
		var l0 := pt.call(p0, rt0, x - gw, soffit) as Vector3
		var r0 := pt.call(p0, rt0, x + gw, soffit) as Vector3
		var l1 := pt.call(p1, rt1, x - gw, soffit) as Vector3
		var r1 := pt.call(p1, rt1, x + gw, soffit) as Vector3
		var lb0 := pt.call(p0, rt0, x - gw, gd) as Vector3
		var rb0 := pt.call(p0, rt0, x + gw, gd) as Vector3
		var lb1 := pt.call(p1, rt1, x - gw, gd) as Vector3
		var rb1 := pt.call(p1, rt1, x + gw, gd) as Vector3
		mb.add_quad(rb0, rb1, r1, r0, shade)  # right face
		mb.add_quad(lb1, lb0, l0, l1, shade)  # left face
		mb.add_quad(lb0, lb1, rb1, rb0, col)  # bottom


## A dirt ribbon a few cm above the shaped terrain, with darker wheel ruts,
## and marker posts every 24 m on alternating sides.
func _add_trail(mb: MeshBuilder, markers: MeshBuilder, r: Road) -> void:
	var hw := r.width * 0.5
	var n := r.points.size()
	var rights := MeshBuilder._path_rights(r.points, r.closed)
	var lift := Vector3.UP * 0.04
	# Across the trail: verge, rut, middle, rut, verge.
	var cuts := [-1.0, -0.62, -0.38, 0.38, 0.62, 1.0]
	var cols := [ArtPalette.DIRT, ArtPalette.DIRT_RUT, ArtPalette.DIRT.lightened(0.04), ArtPalette.DIRT_RUT, ArtPalette.DIRT]
	for i in n - 1:
		var p0 := r.points[i] + lift
		var p1 := r.points[i + 1] + lift
		for k in cols.size():
			var a0: Vector3 = p0 + rights[i] * hw * cuts[k]
			var b0: Vector3 = p0 + rights[i] * hw * cuts[k + 1]
			var a1: Vector3 = p1 + rights[i + 1] * hw * cuts[k]
			var b1: Vector3 = p1 + rights[i + 1] * hw * cuts[k + 1]
			mb.add_quad(a0, b0, b1, a1, cols[k])
	var next := 12.0
	var side := 1.0
	for i in n:
		if r.dist[i] < next:
			continue
		next += 24.0
		side = -side
		var base := r.points[i] + rights[i] * (hw + 0.8) * side
		markers.add_box(Transform3D(Basis.IDENTITY, base + Vector3.UP * 0.5), Vector3(0.18, 1.0, 0.18), Color(0.95, 0.95, 0.9))
		markers.add_box(Transform3D(Basis.IDENTITY, base + Vector3.UP * 1.1), Vector3(0.22, 0.25, 0.22), Color(1.0, 0.5, 0.1))


func _build_barriers(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var env := MeshBuilder.new()
	# Jersey barrier cross-section (across, up), left to right over the top.
	var profile := PackedVector2Array([
		Vector2(-0.32, 0.0), Vector2(-0.24, 0.22), Vector2(-0.12, 0.72), Vector2(-0.1, 0.85),
		Vector2(0.1, 0.85), Vector2(0.12, 0.72), Vector2(0.24, 0.22), Vector2(0.32, 0.0),
	])
	var profile_colors := PackedColorArray([
		ArtPalette.CONCRETE_STAINED, ArtPalette.CONCRETE, ArtPalette.CONCRETE, ArtPalette.CONCRETE_TOP,
		ArtPalette.CONCRETE, ArtPalette.CONCRETE, ArtPalette.CONCRETE_STAINED,
	])
	# New style (ArtZone): the real New Jersey shape, 0.81 m tall: a short
	# toe, a 55° lower slope and an 84° upper face, softened top edges and a
	# stained base. Alpha 0.5 = barrier joints in concrete.gdshader.
	var jersey := PackedVector2Array([
		Vector2(-0.305, 0.0), Vector2(-0.305, 0.075), Vector2(-0.126, 0.33), Vector2(-0.078, 0.78),
		Vector2(-0.05, 0.81), Vector2(0.05, 0.81), Vector2(0.078, 0.78), Vector2(0.126, 0.33),
		Vector2(0.305, 0.075), Vector2(0.305, 0.0),
	])
	var stained := Color(ArtPalette.CONCRETE_STAINED, 0.5)
	var conc := Color(ArtPalette.CONCRETE, 0.5)
	var top := Color(ArtPalette.CONCRETE_TOP, 0.5)
	var jersey_colors := PackedColorArray([
		stained, stained.lerp(conc, 0.4), conc, conc, top, top, conc, conc, stained.lerp(conc, 0.4), stained,
	])
	for r in roads:
		if not r.barriers:
			continue
		var hw := r.width * 0.5
		var rights := MeshBuilder._path_rights(r.points, r.closed)
		for offset in [-(hw - 0.35), 0.0, hw - 0.35]:
			for run in _split_runs(r, offset, rights):
				for part in _split_by_zone(run):
					if ArtZone.has_point(part[part.size() / 2]):
						env.add_sweep(part, jersey, jersey_colors, 32.0)
					else:
						_add_colored_extrusion(mb, part, profile, profile_colors)
	root.add_child(mb.build_node("Barriers", _mat_barrier, true, 0.6))
	if not env.is_empty():
		root.add_child(env.build_node("BarriersEnv", load("res://assets/materials/env/concrete.tres"), true, 0.6))


## Splits a polyline where it crosses the ArtZone edge (the parts share the
## crossing point, so they join up).
static func _split_by_zone(run: PackedVector3Array) -> Array[PackedVector3Array]:
	var parts: Array[PackedVector3Array] = []
	var cur := PackedVector3Array()
	var inside := ArtZone.has_point(run[0])
	for p in run:
		var now := ArtZone.has_point(p)
		if now != inside and cur.size() > 0:
			cur.append(p)
			if cur.size() > 1:
				parts.append(cur)
			cur = PackedVector3Array()
			inside = now
		cur.append(p)
	if cur.size() > 1:
		parts.append(cur)
	return parts


## Splits a road edge line into runs, skipping barrier gaps. Closed roads
## produce runs that wrap around the start.
func _split_runs(r: Road, offset: float, rights: PackedVector3Array) -> Array[PackedVector3Array]:
	var runs: Array[PackedVector3Array] = []
	var cur := PackedVector3Array()
	var n := r.points.size()
	var start := 0
	if r.closed:
		# Start inside a gap if there is one, so runs never wrap mid-barrier.
		for i in n:
			if _in_gap(r, r.dist[i]):
				start = i
				break
	var count := n + 1 if r.closed else n
	for k in count:
		var i := (start + k) % n
		if _in_gap(r, r.dist[i]):
			if cur.size() > 1:
				runs.append(cur)
			cur = PackedVector3Array()
			continue
		cur.append(r.points[i] + rights[i] * offset)
	if cur.size() > 1:
		runs.append(cur)
	return runs


func _in_gap(r: Road, d: float) -> bool:
	for g in r.barrier_gaps:
		if d >= g.x and d <= g.y:
			return true
	return false


func _add_colored_extrusion(mb: MeshBuilder, path: PackedVector3Array, profile: PackedVector2Array, cols: PackedColorArray) -> void:
	var n := path.size()
	var rights := MeshBuilder._path_rights(path, false)
	for i in n - 1:
		for k in profile.size() - 1:
			var pa := profile[k]
			var pb := profile[k + 1]
			mb.add_quad(
				path[i] + rights[i] * pa.x + Vector3.UP * pa.y,
				path[i] + rights[i] * pb.x + Vector3.UP * pb.y,
				path[i + 1] + rights[i + 1] * pb.x + Vector3.UP * pb.y,
				path[i + 1] + rights[i + 1] * pa.x + Vector3.UP * pa.y,
				cols[k])
	var cap_col := cols[cols.size() / 2]
	for end in [0, n - 1]:
		var pts: Array[Vector3] = []
		for pv in profile:
			pts.append(path[end] + rights[end] * pv.x + Vector3.UP * pv.y)
		for k in range(1, pts.size() - 1):
			if end == 0:
				mb.add_tri(pts[0], pts[k + 1], pts[k], cap_col)
			else:
				mb.add_tri(pts[0], pts[k], pts[k + 1], cap_col)


func _build_pillars(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var env := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "BridgePillars"
	var col := ArtPalette.CONCRETE
	var keep_clear: Array[Road] = []
	for r in roads:
		if r.kind != Kind.HIGHWAY:
			keep_clear.append(r)
	var r := highway
	var rights := MeshBuilder._path_rights(r.points, r.closed)
	var next_d := 0.0
	for i in r.points.size():
		if r.dist[i] < next_d or not r.elevated[i]:
			continue
		var p := r.points[i]
		var ground := _terrain.height_at(p.x, p.z)
		var top := p.y - DECK_DEPTH
		if top - ground < 2.0:
			continue
		var blocked := false
		for off in [-7.0, 7.0]:
			var q: Vector3 = p + rights[i] * off
			if _near_road(keep_clear, q, 3.0):
				blocked = true
		if blocked:
			continue
		next_d = r.dist[i] + 24.0
		var basis := Basis.looking_at(rights[i].cross(Vector3.UP), Vector3.UP)
		if ArtZone.has_point(p):
			_add_pier(env, body, p, basis, ground)
			continue
		for off in [-7.0, 7.0]:
			var q: Vector3 = p + rights[i] * off
			var h := top - ground + 0.5
			var xf := Transform3D(basis, Vector3(q.x, ground - 0.5 + h * 0.5, q.z))
			mb.add_box(xf, Vector3(1.6, h, 1.6), col)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.6, h, 1.6)
			cs.shape = shape
			cs.transform = xf
			body.add_child(cs)
		# Cross beam under the deck.
		var beam := Transform3D(basis, Vector3(p.x, top - 0.4, p.z))
		mb.add_box(beam, Vector3(r.width - 3.0, 0.8, 1.8), col)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mb.build_mesh(_mat_concrete)
	body.add_child(mi)
	if not env.is_empty():
		var emi := MeshInstance3D.new()
		emi.name = "MeshEnv"
		emi.mesh = env.build_mesh(load("res://assets/materials/env/concrete.tres"))
		body.add_child(emi)
	root.add_child(body)


## New-style pier (ArtZone): two bevelled columns on footings under a cap
## beam that carries the deck girders. Local X = across the deck.
func _add_pier(mb: MeshBuilder, body: StaticBody3D, p: Vector3, basis: Basis, ground: float) -> void:
	var cast := Color(ArtPalette.CONCRETE, 1.0)
	var stained := Color(ArtPalette.CONCRETE_STAINED, 1.0)
	var cap_top := p.y - (FASCIA_DEPTH - 0.15)
	var cap_h := 1.3
	var cap := Transform3D(basis, Vector3(p.x, cap_top - cap_h * 0.5, p.z))
	mb.add_bevel_box(cap, Vector3(highway.width - 4.0, cap_h, 2.0), 0.12, cast, cast.darkened(0.12), false)
	var col_top := cap_top - cap_h
	for off: float in [-7.0, 7.0]:
		var q := p + basis.x * off
		var base := ground - 0.4
		var h := col_top - base
		var size := Vector3(1.9, h, 1.5)
		var xf := Transform3D(basis, Vector3(q.x, base + h * 0.5, q.z))
		mb.add_bevel_box(xf, size, 0.1, cast, stained)
		mb.add_bevel_box(Transform3D(basis, Vector3(q.x, ground - 0.15, q.z)), Vector3(3.4, 0.5, 3.0), 0.06, stained)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = xf
		body.add_child(cs)


func _near_road(list: Array[Road], q: Vector3, margin: float) -> bool:
	for rd in list:
		var hw := rd.width * 0.5 + margin
		for i in rd.points.size() - 1:
			var a := Vector2(rd.points[i].x, rd.points[i].z)
			var b := Vector2(rd.points[i + 1].x, rd.points[i + 1].z)
			var p := Vector2(q.x, q.z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if p.distance_to(a + ab * t) < hw:
				return true
	return false


## Distance from a point to the nearest road centreline, and that road's half width.
func distance_to_roads(p: Vector2) -> Vector2:
	var best := INF
	var best_hw := 0.0
	for rd in roads:
		var n := rd.points.size()
		var seg_count := n if rd.closed else n - 1
		for i in seg_count:
			var a := Vector2(rd.points[i].x, rd.points[i].z)
			var q := rd.points[(i + 1) % n]
			var b := Vector2(q.x, q.z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t) - rd.width * 0.5
			if d < best:
				best = d
				best_hw = rd.width * 0.5
	return Vector2(best, best_hw)
