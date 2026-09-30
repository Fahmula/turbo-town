class_name TrafficDriver
extends Node
## AI controller for a traffic car (add as a child of a Vehicle).
##
## Follows a randomly chosen route through the TrafficNetwork lane graph,
## steers with pure pursuit and sets its speed with the Intelligent Driver
## Model (IDM): cars ahead, red lights and give-way points are all treated as
## "leaders" to keep a safe gap to. Curves and speed limits set the free-road
## speed. If it gets knocked off course or flipped it gives up ("LOST") and the
## TrafficManager removes it once nobody is looking.

enum State { DRIVING, STUNNED, LOST }

const COMFORT_DECEL := 3.0
const HEADWAY := 1.3
const MIN_GAP := 2.5
const LAT_ACCEL := 3.2

var vehicle: Vehicle
var manager: TrafficManager
var state := State.DRIVING
var state_time := 0.0
var lost_reason := ""
var cruise_factor := 1.0
## Taken from the vehicle so buses and trucks keep proper gaps and turn wide.
var _front := 2.2
var _half_width := 0.95
var _wheelbase := 2.7
var _max_accel := 2.2
var _mass_scale := 1.0
var _avoid_dead_ends := false

var _net: TrafficNetwork
## Route legs: {"lane": Lane, "from": float, "to": float, "link": Dictionary}
var _plan: Array[Dictionary] = []
var _s := 0.0
var _rng := RandomNumberGenerator.new()
var _tick := 0
var _accel_cmd := 0.0
var _stuck_time := 0.0
var _wait_time := 0.0
var _hold := false
var _ray := PhysicsRayQueryParameters3D.new()
var _samples_p := PackedVector3Array()
var _samples_d := PackedFloat32Array()
var _samples_dir := PackedVector3Array()
var _yield_to := ""
var _nudge := 0.0
var _engine_audio: AudioStreamPlayer3D
var _horn_audio: AudioStreamPlayer3D
var _crash_audio: AudioStreamPlayer3D
var _honk_cooldown := 0.0
var _blocked_by_player := 0.0
## What is currently limiting our speed (for debugging).
var blocker := ""
## The vehicle we're currently waiting for, if any.
var blocker_vehicle: Vehicle = null


func setup(mgr: TrafficManager, lane: TrafficNetwork.Lane, s: float) -> void:
	manager = mgr
	_net = mgr.network
	vehicle = get_parent() as Vehicle
	_rng.randomize()
	_tick = _rng.randi() % 3
	cruise_factor = _rng.randf_range(0.85, 1.05) * vehicle.ai_speed_factor
	_front = vehicle.body_front
	_half_width = vehicle.body_half_width
	_wheelbase = vehicle.wheelbase
	_max_accel = vehicle.ai_max_accel
	_mass_scale = maxf(vehicle.mass / 1300.0, 1.0)
	_avoid_dead_ends = _wheelbase > 3.2
	vehicle.auto_reverse = false
	vehicle.impact.connect(_on_impact)
	_ray.exclude = [vehicle.get_rid()]
	_ray.collision_mask = 0b111
	_s = s
	_plan = [_make_leg(lane, s)]
	_extend_plan()
	_setup_audio()
	# Run before the vehicle so it sees this tick's inputs.
	process_physics_priority = -10


func _setup_audio() -> void:
	_engine_audio = _make_player(TrafficAudio.engine_loop(), 7.0, 80.0)
	_engine_audio.volume_db = -10.0
	_engine_audio.play(_rng.randf() * 0.4)
	_horn_audio = _make_player(TrafficAudio.horn(), 14.0, 160.0)
	_crash_audio = _make_player(TrafficAudio.crash(), 14.0, 150.0)


func _make_player(stream: AudioStream, unit: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = max_dist
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	vehicle.add_child(p)
	return p


func honk() -> void:
	if _horn_audio and not _horn_audio.playing:
		_horn_audio.pitch_scale = _rng.randf_range(0.9, 1.1)
		_horn_audio.play()


func _update_audio(dt: float) -> void:
	if _engine_audio == null:
		return
	var freq := vehicle.engine_rpm / 60.0 * 4.0
	_engine_audio.pitch_scale = clampf(freq / TrafficAudio.BASE_FREQ, 0.5, 12.0)
	_engine_audio.volume_db = linear_to_db(0.25 + 0.6 * vehicle.engine_load) - 8.0
	# Impatient honking at a player who blocks the road.
	_honk_cooldown -= dt
	if blocker_vehicle != null and blocker_vehicle == manager.player and vehicle.linear_velocity.length() < 1.0:
		_blocked_by_player += dt
	else:
		_blocked_by_player = 0.0
	if _blocked_by_player > 2.5 and _honk_cooldown <= 0.0:
		honk()
		_honk_cooldown = _rng.randf_range(3.0, 6.0)


func current_lane() -> TrafficNetwork.Lane:
	return _plan[0]["lane"] if not _plan.is_empty() else null


# =============================================================== routing ==

func _make_leg(lane: TrafficNetwork.Lane, from: float) -> Dictionary:
	var base := lane.wrap_s(from) if lane.closed else from
	var ordered: Array = []
	for g in lane.link_groups:
		var ahead: float = g["at"] - base
		if lane.closed:
			ahead = fposmod(ahead, lane.length)
			if ahead < 0.5:
				ahead += lane.length
		elif ahead < -0.01:
			continue
		ordered.append([ahead, g])
	ordered.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for k in ordered.size():
		var g: Dictionary = ordered[k][1]
		var mandatory := not lane.closed and k == ordered.size() - 1
		var links: Array = g["links"]
		if _avoid_dead_ends:
			# Long vehicles can't make the tight U-turns at dead ends.
			var ok := links.filter(func(l: Dictionary) -> bool: return not _net.leads_to_dead_end(l))
			if not ok.is_empty():
				links = ok
			elif not mandatory:
				continue
		if mandatory or _rng.randf() < lane.take_chance:
			return {"lane": lane, "from": from, "to": from + ordered[k][0], "link": links[_rng.randi() % links.size()]}
	if lane.closed:
		return {"lane": lane, "from": from, "to": from + lane.length, "link": {"to": lane.id, "to_at": from + lane.length}}
	return {"lane": lane, "from": from, "to": lane.length, "link": {}}


func _extend_plan() -> void:
	var ahead: float = _plan[0]["to"] - _s
	for i in range(1, _plan.size()):
		ahead += _plan[i]["to"] - _plan[i]["from"]
	while ahead < 170.0 and _plan.size() < 12:
		var link: Dictionary = _plan.back()["link"]
		if link.is_empty():
			break
		var leg := _make_leg(_net.lanes[link["to"]], link["to_at"])
		_plan.append(leg)
		ahead += leg["to"] - leg["from"]


func _path_point(ahead: float) -> Vector3:
	var s := _s
	for i in _plan.size():
		var leg: Dictionary = _plan[i]
		var avail: float = leg["to"] - s
		if ahead <= avail or i == _plan.size() - 1:
			return (leg["lane"] as TrafficNetwork.Lane).point_at(s + minf(ahead, maxf(avail, 0.0)))
		ahead -= maxf(avail, 0.0)
		s = _plan[i + 1]["from"]
	return vehicle.global_position


# =============================================================== driving ==

func _physics_process(dt: float) -> void:
	if vehicle == null or _plan.is_empty():
		return
	state_time += dt
	_update_audio(dt)
	match state:
		State.LOST:
			_pedals(0.0, 0.6, 0.0)
			return
		State.STUNNED:
			_pedals(0.0, 0.8, 0.0)
			if state_time > 2.5:
				_try_recover()
			return

	if vehicle.upside_down_time > 1.0 or vehicle.global_basis.y.y < 0.3:
		_lose("flipped")
		return

	_advance()
	var lane: TrafficNetwork.Lane = _plan[0]["lane"]
	var on_lane := lane.point_at(_s)
	var lateral := Vector2(on_lane.x - vehicle.global_position.x, on_lane.z - vehicle.global_position.z).length()
	if lateral > 8.0:
		_lose("off lane %.1fm on lane %d" % [lateral, lane.id])
		return

	_tick += 1
	if _tick % 4 == 0:
		_accel_cmd = _plan_speed()

	# Pure pursuit steering from the rear axle.
	var v := maxf(vehicle.forward_speed, 0.0)
	var ld := clampf(3.0 + _wheelbase * 0.8 + v * 0.45, 6.0, 24.0)
	var target := _path_point(ld)
	if _nudge > 0.0:
		target += vehicle.global_basis.x * _nudge
	var xf := vehicle.global_transform
	var rear := xf * Vector3(0, 0, _wheelbase * 0.5)
	var local := xf.basis.inverse() * (target - rear)
	var alpha := atan2(local.x, -local.z)
	var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
	var delta := atan(2.0 * _wheelbase * sin(alpha) / dist)
	var steer := rad_to_deg(delta) / maxf(vehicle.max_steer_at_speed(), 1.0)

	# Longitudinal control from the desired acceleration.
	var throttle := 0.0
	var brake := 0.0
	if _hold and v < 0.6:
		brake = 0.4
	elif _accel_cmd > 0.05:
		throttle = clampf(0.1 + _accel_cmd * 0.3 + v * 0.006, 0.0, 1.0)
	elif _accel_cmd < -0.5:
		brake = clampf(-_accel_cmd / 8.0, 0.05, 1.0)
	_pedals(throttle, brake, clampf(steer, -1.0, 1.0))

	# Give up if we've been trying to move but can't (wedged against something).
	if _accel_cmd > 0.5 and v < 0.3 and not _hold:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	_wait_time = _wait_time + dt if v < 0.3 else 0.0
	if _stuck_time > 6.0:
		_lose("stuck (wants %.1f m/s2, blocker '%s', grounded %d, gear %d, throttle %.2f)" % [_accel_cmd, blocker, vehicle.grounded_wheels, vehicle.gear, vehicle.throttle_input])
	elif _wait_time > 60.0:
		_lose("waited 60s for " + blocker)


func _pedals(throttle: float, brake: float, steer: float) -> void:
	vehicle.throttle_input = throttle
	vehicle.brake_input = brake
	vehicle.steer_input = steer
	vehicle.handbrake_input = false


func _advance() -> void:
	var leg: Dictionary = _plan[0]
	var lane: TrafficNetwork.Lane = leg["lane"]
	_s = lane.project(vehicle.global_position, _s, 6.0)
	while _s >= leg["to"] - 0.01 and not (leg["link"] as Dictionary).is_empty():
		var over: float = _s - leg["to"]
		_plan.pop_front()
		if _plan.is_empty():
			var link: Dictionary = leg["link"]
			_plan.append(_make_leg(_net.lanes[link["to"]], link["to_at"]))
		leg = _plan[0]
		_s = leg["from"] + over
		lane = leg["lane"]
	_extend_plan()


## Desired acceleration (m/s²) using IDM against the most restrictive leader.
func _plan_speed() -> float:
	var v := maxf(vehicle.forward_speed, 0.0)
	var horizon := clampf(v * v / (2.0 * COMFORT_DECEL) + 30.0, 40.0, 140.0)
	var v0 := INF
	var best := INF
	blocker = ""
	blocker_vehicle = null
	_hold = false

	_samples_p.clear()
	_samples_d.clear()
	_samples_dir.clear()
	var s := _s
	var d := 0.0
	for i in _plan.size():
		if d >= horizon:
			break
		var leg: Dictionary = _plan[i]
		var lane: TrafficNetwork.Lane = leg["lane"]
		var leg_to: float = leg["to"]
		var end_d := d + (leg_to - s)
		var lim := lane.speed * cruise_factor
		v0 = minf(v0, sqrt(lim * lim + 2.0 * COMFORT_DECEL * maxf(d, 0.0)))

		# Traffic light at the end of this lane.
		if lane.signal_id >= 0 and s <= lane.stop_at + 0.5 and leg_to >= lane.stop_at - 0.1:
			var stop_d := d + (lane.stop_at - s) - _front
			if stop_d > -1.0:
				if stop_d < 50.0:
					manager.request_signal(lane.signal_id, lane.signal_axis)
				var st := manager.signal_state(lane.signal_id, lane.signal_axis)
				var must_stop := st == TrafficNetwork.SignalState.RED
				if st == TrafficNetwork.SignalState.AMBER:
					must_stop = stop_d > v * v / (2.0 * 5.0) + 1.0
				if must_stop:
					var a := _idm(v, INF, maxf(stop_d, 0.0) + MIN_GAP - 0.5, 0.0)
					if a < best:
						best = a
						blocker = "signal"
					if stop_d < 3.0:
						_hold = true
		# Give way before entering a conflicting connector.
		if i + 1 < _plan.size():
			var nxt: TrafficNetwork.Lane = _plan[i + 1]["lane"]
			if nxt.yield_point != Vector3.INF:
				var yd := end_d - _front
				if yd > -1.0 and yd < 45.0 and _must_yield(nxt.yield_point):
					var a := _idm(v, INF, maxf(yd, 0.0) + MIN_GAP - 0.5, 0.0)
					if a < best:
						best = a
						blocker = "yield " + _yield_to
					if yd < 3.0:
						_hold = true
		# Dead end.
		if i == _plan.size() - 1 and (leg["link"] as Dictionary).is_empty():
			var a := _idm(v, INF, maxf(end_d - _front, 0.0) + MIN_GAP, 0.0)
			if a < best:
				best = a
				blocker = "dead end"

		# Sample the lane's own points for curvature and obstacle checks.
		var n := lane.points.size()
		var ws := lane.wrap_s(s)
		var idx := lane._segment(ws) + 1
		var steps := 0
		while d < horizon and steps < 200:
			steps += 1
			if idx >= n:
				if not lane.closed:
					break
				idx = 0
			var rel := lane.dist[idx] - ws
			if rel < 0.0:
				rel += lane.length
			if s + rel > leg_to:
				break
			var sd := d + rel
			if sd > horizon:
				break
			_samples_p.append(lane.points[idx])
			_samples_d.append(sd)
			_samples_dir.append(lane.dirs[idx])
			var k := lane.curv[idx]
			if k > 0.004:
				v0 = minf(v0, sqrt(LAT_ACCEL / k + 2.0 * COMFORT_DECEL * sd))
			idx += 1
		d = end_d
		if i + 1 < _plan.size():
			s = _plan[i + 1]["from"]

	# Other vehicles on our path. Path distance to a car is at least the
	# straight-line distance, which prunes most of the samples.
	var my_pos := vehicle.global_position
	var count := _samples_p.size()
	for other in manager.vehicles:
		if other == vehicle or not is_instance_valid(other):
			continue
		var op := other.global_position
		var straight := op.distance_to(my_pos)
		if straight > horizon + 5.0:
			continue
		var reach := _half_width + other.body_half_width + 0.3
		var best_l := reach * reach
		var best_i := -1
		var j := clampi(int((straight - 3.0) / 3.0), 0, count)
		while j < count:
			var sd: float = _samples_d[j]
			if sd > straight * 1.6 + 6.0:
				break
			var q := _samples_p[j]
			var dx := q.x - op.x
			var dz := q.z - op.z
			var l := dx * dx + dz * dz
			if l < best_l and absf(q.y - op.y) < 3.0:
				best_l = l
				best_i = j
			j += 1
		if best_i < 0 or _samples_d[best_i] < 2.0 or _yields_to_me(other):
			continue
		var gap := _samples_d[best_i] - _front - other.body_length() * 0.5
		var lead_v := maxf(other.linear_velocity.dot(_samples_dir[best_i]), 0.0)
		var a := _idm(v, INF, maxf(gap, 0.1), lead_v)
		if a < best:
			best = a
			blocker = "car %s" % other.name
			blocker_vehicle = other

	# Static obstacles (walls, knocked-over lamp posts...) along the path.
	var ray_len := minf(horizon, 25.0)
	_ray.from = vehicle.global_transform * Vector3(0, 0.55, -_front)
	_ray.to = _path_point(ray_len) + Vector3.UP * 0.55
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		var nrm: Vector3 = hit["normal"]
		var blocking := false
		if col is Vehicle:
			blocking = not _yields_to_me(col as Vehicle)
		elif col is RigidBody3D:
			blocking = (col as RigidBody3D).mass >= 80.0 and _in_corridor(hit["position"])
		elif nrm.y < 0.6:
			blocking = _in_corridor(hit["position"])
		if blocking:
			var gap: float = (hit["position"] as Vector3).distance_to(_ray.from)
			var a := _idm(v, INF, maxf(gap - 0.5, 0.1), 0.0)
			if a < best:
				best = a
				blocker = "obstacle %s" % (col as Node).name
				if col is Vehicle:
					blocker_vehicle = col

	# Bumper sensors straight ahead from the nose and both front corners:
	# catch things right in front that the path check misses while turning.
	var fwd := -vehicle.global_basis.z
	var reach := 3.5 + v * 0.5
	var space := vehicle.get_world_3d().direct_space_state
	var corner := _half_width - 0.1
	for side in [0.0, -corner, corner]:
		_ray.from = vehicle.global_transform * Vector3(side, 0.55, -_front + 0.3)
		_ray.to = _ray.from + fwd * reach
		hit = space.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var col: Object = hit["collider"]
		var blocking := false
		if col is Vehicle:
			blocking = not _yields_to_me(col as Vehicle)
		elif col is RigidBody3D:
			blocking = (col as RigidBody3D).mass >= 80.0 and _in_corridor(hit["position"])
		elif (hit["normal"] as Vector3).y < 0.6:
			blocking = _in_corridor(hit["position"])
		if blocking:
			var gap: float = (hit["position"] as Vector3).distance_to(_ray.from)
			var a := _idm(v, INF, maxf(gap - 0.3, 0.1), 0.0)
			if a < best:
				best = a
				blocker = "bumper %s" % (col as Node).name
				if col is Vehicle:
					blocker_vehicle = col

	# Oncoming cars close to the centre line: shift a little to the right.
	_nudge = 0.0
	var right := vehicle.global_basis.x
	for other in manager.vehicles:
		if other == vehicle or not is_instance_valid(other):
			continue
		var rel := other.global_position - my_pos
		var ahead := rel.dot(fwd)
		if ahead < -3.0 or ahead > 30.0:
			continue
		if other.linear_velocity.dot(fwd) > -1.0:
			continue  # not oncoming
		var side_off := rel.dot(right)
		var comfy := _half_width + other.body_half_width + 1.5
		if side_off < 0.0 and side_off > -comfy:
			_nudge = maxf(_nudge, clampf(comfy + side_off, 0.0, 0.9))

	var free := _idm(v, v0, INF, 0.0)
	return clampf(minf(free, best), -9.0, _max_accel)


## Is a world point inside our lane ahead (within ~1.4 m of the planned path)?
func _in_corridor(p: Vector3) -> bool:
	for j in _samples_p.size():
		var q := _samples_p[j]
		var dx := q.x - p.x
		var dz := q.z - p.z
		if dx * dx + dz * dz < (_half_width + 0.45) * (_half_width + 0.45):
			return true
	# Also the stretch between the car and the first sample.
	var my := vehicle.global_position
	var l := Vector2(p.x - my.x, p.z - my.z)
	var f := Vector2(-vehicle.global_basis.z.x, -vehicle.global_basis.z.z).normalized()
	return l.dot(f) > 0.0 and absf(l.cross(f)) < _half_width + 0.45 and l.length() < _front + 4.0


## True if `other` is an AI car that is itself stopped waiting for us and we
## win the tie-break, so we should go first instead of deadlocking.
func _yields_to_me(other: Vehicle) -> bool:
	var od := other.get_node_or_null("Driver") as TrafficDriver
	if od == null or od.blocker_vehicle != vehicle:
		return false
	if other.linear_velocity.length() > 1.0 or vehicle.linear_velocity.length() > 1.0:
		return false
	return vehicle.get_instance_id() < other.get_instance_id()


func _idm(v: float, v0: float, gap: float, v_lead: float) -> float:
	var free := 1.0
	if v0 < INF:
		free = 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	var inter := 0.0
	if gap < INF:
		var s_star := MIN_GAP + maxf(0.0, v * HEADWAY + v * (v - v_lead) / (2.0 * sqrt(_max_accel * COMFORT_DECEL)))
		inter = pow(s_star / maxf(gap, 0.1), 2.0)
	return _max_accel * (free - inter)


func _must_yield(point: Vector3) -> bool:
	var my_pos := vehicle.global_position
	var my_fwd := -vehicle.global_basis.z
	for other in manager.vehicles:
		if other == vehicle or not is_instance_valid(other):
			continue
		var op := other.global_position
		# Ignore traffic queued behind us.
		var rel := op - my_pos
		if rel.dot(my_fwd) < 0.0 and absf(rel.dot(vehicle.global_basis.x)) < 3.0:
			continue
		var to := point - op
		to.y = 0.0
		var dist := to.length()
		if dist > 50.0:
			continue
		var vel := other.linear_velocity
		vel.y = 0.0
		var speed := vel.length()
		if dist < 5.0 and speed > 1.0:
			_yield_to = other.name
			return true
		if dist > 0.1:
			var closing := vel.dot(to / dist)
			if closing > 1.5 and dist / closing < 4.5:
				_yield_to = other.name
				return true
	return false


# ============================================================ crash state ==

func _on_impact(strength: float, _pos: Vector3, _n: Vector3) -> void:
	if strength > 7000.0 * _mass_scale and _crash_audio and not _crash_audio.playing:
		_crash_audio.volume_db = linear_to_db(clampf(strength / (30000.0 * _mass_scale), 0.3, 1.0))
		_crash_audio.play()
	if state == State.DRIVING and strength > 9000.0 * _mass_scale:
		_set_state(State.STUNNED)
		_honk_cooldown = 0.6
		get_tree().create_timer(0.7).timeout.connect(honk)


func _lose(reason: String) -> void:
	lost_reason = reason
	_set_state(State.LOST)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0


func _try_recover() -> void:
	if vehicle.global_basis.y.y < 0.8:
		_lose("tipped after crash")
		return
	var lane: TrafficNetwork.Lane = _plan[0]["lane"]
	_s = lane.project(vehicle.global_position, _s, 40.0)
	var p := lane.point_at(_s)
	var lateral := Vector2(p.x - vehicle.global_position.x, p.z - vehicle.global_position.z).length()
	var heading_ok := (-vehicle.global_basis.z).dot(lane.dir_at(_s)) > 0.5
	if lateral < 4.0 and heading_ok:
		_set_state(State.DRIVING)
	else:
		_lose("knocked off lane")
