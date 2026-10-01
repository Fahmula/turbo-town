class_name RaceCatalog
extends RefCounted
## The races: start spot, checkpoints (the last one is the finish) and medal
## times. Built from the generated world so the gates follow the real roads.
## Medal times come from the autopilot in the `--races` dev test (gold is a
## bit slower than the autopilot, which drives cleanly but cautiously).

## Medal time = reference time * these factors (gold, silver, bronze).
const MEDAL_FACTORS := [1.05, 1.25, 1.5]
const MEDAL_NAMES := ["GOLD", "SILVER", "BRONZE"]
const MEDAL_COLORS := [Color(1.0, 0.82, 0.2), Color(0.82, 0.86, 0.92), Color(0.86, 0.55, 0.3)]

## id -> reference time (s) measured with the dev-test autopilot.
const REFERENCE_TIMES := {
	"city": 51.5,
	"highway": 56.7,
	"mountain": 26.3,
	"dirt": 36.4,
	"beach": 13.0,
	"trail": 32.1,
}


static func build(world: WorldBuilder) -> Array[Dictionary]:
	var t := world.terrain
	var ground := func(x: float, z: float) -> Vector3: return Vector3(x, t.height_at(x, z), z)
	var races: Array[Dictionary] = []

	# City Sprint: a lap around the edge of the city.
	var city: Array[Vector3] = []
	for p in [Vector2(-40, 0), Vector2(37, 0), Vector2(75, 37), Vector2(75, 112), Vector2(37, 150),
			Vector2(-37, 150), Vector2(-112, 150), Vector2(-150, 112), Vector2(-150, 37), Vector2(-110, 0)]:
		city.append(ground.call(p.x, p.y))
	var city_path: Array[Vector3] = []
	for p in [Vector2(-110, 0), Vector2(75, 0), Vector2(75, 150), Vector2(-150, 150), Vector2(-150, 0), Vector2(-110, 0)]:
		city_path.append(ground.call(p.x, p.y))
	# Starts sit a little behind the teleport spots so you don't spawn in them.
	races.append(_race("city", "City Sprint", "A lap around the city. Watch out for traffic!",
		_behind(world.spawn_points[0]["xform"], 22.0), city, 13.0, city_path))

	# Highway Loop: one lap of the ring, inner carriageway.
	var hwy := world.roads.highway
	var hstart := _behind(world.spawn_points[1]["xform"], 30.0)
	var start_i := _nearest_index(hwy.points, hstart.origin)
	var loop := _sample_road(hwy, start_i, 1, hwy.points.size(), 180.0, 7.0)
	loop.append(_offset_point(hwy, start_i, 7.0))
	races.append(_race("highway", "Highway Loop", "Full speed around the ring highway.",
		hstart, loop, 14.0, _sample_road(hwy, start_i, 1, hwy.points.size(), 6.0, 7.0)))

	# Mountain Climb: up the hill loop and the summit road to the top.
	var hill := world.roads.find_road("HillLoop")
	var summit := world.roads.find_road("SummitRoad")
	var hi := _nearest_index(hill.points, Vector3(0, 0, -300))
	var west := _nearest_index(hill.points, Vector3(-60, 0, -310))
	var dir := 1 if (west - hi + hill.points.size()) % hill.points.size() < hill.points.size() / 2 else -1
	var junction := _nearest_index(hill.points, Vector3(-147, 0, -440))
	var steps := (junction - hi) * dir
	if steps < 0:
		steps += hill.points.size()
	var climb := _sample_road(hill, hi, dir, steps, 70.0, 0.0)
	climb.append_array(_sample_road(summit, 0, 1, summit.points.size() - 1, 60.0, 0.0))
	climb.append(summit.points[summit.points.size() - 1])
	var mstart := ground.call(0.0, -268.0) as Vector3
	var climb_path: Array[Vector3] = [mstart]
	climb_path.append_array(_sample_road(hill, hi, dir, steps, 6.0, 0.0))
	climb_path.append_array(_sample_road(summit, 0, 1, summit.points.size() - 1, 6.0, 0.0))
	races.append(_race("mountain", "Mountain Climb", "Race up the mountain road to the summit.",
		Transform3D(Basis.looking_at(Vector3.FORWARD), mstart + Vector3.UP * 0.6), climb, 11.0, climb_path))

	# Dirt Rally: a loop over the dirt fields (and some of the mounds).
	var dirt: Array[Vector3] = []
	for p in [Vector2(400, 4), Vector2(465, 22), Vector2(510, -30), Vector2(495, -120),
			Vector2(420, -140), Vector2(355, -100), Vector2(345, 4)]:
		dirt.append(ground.call(p.x, p.y))
	var dstart := _behind(world.spawn_points[4]["xform"], 22.0)
	dstart.origin.y = t.height_at(dstart.origin.x, dstart.origin.z) + 0.6
	races.append(_race("dirt", "Dirt Rally", "Bumps, jumps and dust on the dirt fields.",
		dstart, dirt, 16.0))

	# Trail Climb: up the dirt switchbacks to the summit.
	var trail := world.roads.find_road("MountainTrail")
	var tcps: Array[Vector3] = []
	for i in range(20, trail.points.size(), 20):
		tcps.append(trail.points[i])
	tcps.append(trail.points[trail.points.size() - 1])
	var tdir := trail.points[3] - trail.points[0]
	tdir.y = 0.0
	var tpath: Array[Vector3] = []
	for p in trail.points:
		tpath.append(p)
	races.append(_race("trail", "Trail Climb", "Dirt switchbacks all the way up. Try the buggy!",
		Transform3D(Basis.looking_at(tdir.normalized()), trail.points[0] + Vector3.UP * 0.6), tcps, 10.0, tpath))

	# Beach Dash: from the middle of the city west to the beach.
	var beach: Array[Vector3] = []
	for p in [Vector2(-112, 0), Vector2(-190, 0), Vector2(-250, 0), Vector2(-300, 0), Vector2(-345, 0)]:
		beach.append(ground.call(p.x, p.y))
	var bstart := ground.call(-37.0, -1.8) as Vector3
	races.append(_race("beach", "Beach Dash", "Straight through the highway lights to the sea!",
		Transform3D(Basis.looking_at(Vector3.LEFT), bstart + Vector3.UP * 0.6), beach, 14.0))
	return races


## `path`: dense points along the intended route (for the test autopilot);
## defaults to the checkpoints themselves.
static func _race(id: String, race_name: String, blurb: String, start: Transform3D, cps: Array[Vector3], width: float,
		path: Array[Vector3] = []) -> Dictionary:
	if path.is_empty():
		path = cps.duplicate()
	# Fill in long straight legs so the autopilot aims at each gate.
	var dense: Array[Vector3] = []
	for i in path.size():
		if i > 0:
			var a: Vector3 = path[i - 1]
			var n := int(a.distance_to(path[i]) / 10.0)
			for k in range(1, n):
				dense.append(a.lerp(path[i], float(k) / n))
		dense.append(path[i])
	path = dense
	# Drop gates that ended up right next to the one before (or the finish).
	var kept: Array[Vector3] = []
	for i in cps.size():
		var last := i == cps.size() - 1
		if not kept.is_empty() and cps[i].distance_to(kept.back()) < 30.0:
			if last:
				kept[kept.size() - 1] = cps[i]
			continue
		kept.append(cps[i])
	cps = kept
	var ref: float = REFERENCE_TIMES.get(id, 60.0)
	var medals: Array[float] = []
	for f: float in MEDAL_FACTORS:
		medals.append(snappedf(ref * f, 0.5))
	return {"id": id, "name": race_name, "blurb": blurb, "start": start, "checkpoints": cps,
		"width": width, "medals": medals, "path": path}


## 0 gold, 1 silver, 2 bronze, -1 none.
static func medal_for(race: Dictionary, time: float) -> int:
	var medals: Array = race["medals"]
	for i in medals.size():
		if time <= float(medals[i]):
			return i
	return -1


static func format_time(t: float) -> String:
	var m := int(t / 60.0)
	return "%d:%05.2f" % [m, t - m * 60.0]


static func _behind(xform: Transform3D, metres: float) -> Transform3D:
	var back := xform.basis.z
	back.y = 0.0
	return Transform3D(xform.basis, xform.origin + back.normalized() * metres)


static func _nearest_index(pts: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


static func _offset_point(road: RoadBuilder.Road, i: int, right_offset: float) -> Vector3:
	if right_offset == 0.0:
		return road.points[i]
	var rights := MeshBuilder._path_rights(road.points, road.closed)
	return road.points[i] + rights[i] * right_offset


## Points every `spacing` m along a road, walking `count` points from index
## `from` in direction `dir`, shifted `right_offset` m to the right of travel.
static func _sample_road(road: RoadBuilder.Road, from: int, dir: int, count: int, spacing: float, right_offset: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := road.points.size()
	var rights := MeshBuilder._path_rights(road.points, road.closed)
	var acc := 0.0
	var i := from
	for k in count:
		var j := (i + dir + n) % n if road.closed else clampi(i + dir, 0, n - 1)
		acc += road.points[i].distance_to(road.points[j])
		i = j
		if acc >= spacing:
			acc = 0.0
			out.append(road.points[i] + rights[i] * right_offset * float(dir))
	return out
