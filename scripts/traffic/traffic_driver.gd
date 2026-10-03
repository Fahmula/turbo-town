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
## Sideways speed (m/s) when blending into a new lane / pulling over.
const LANE_CHANGE_RATE := 1.3
const PULL_RATE := 1.0
## Speed cap (m/s) while pulling over for a honking player or passing a parked car.
const CREEP_SPEED := 4.5

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
var _curv_limit := PackedFloat32Array()

var _net: TrafficNetwork
## Route legs: {"lane": Lane, "from": float, "to": float, "link": Dictionary}
var _plan: Array[Dictionary] = []
var _s := 0.0
var _rng := RandomNumberGenerator.new()
var _tick := 0
var _accel_cmd := 0.0
var _stuck_time := 0.0
var _wait_time := 0.0
var _moving_time := 0.0
var _reverse_time := 0.0
var _reverse_from := Vector3.ZERO
var _unstick_tries := 0
var _last_steer := 0.0
var _hold := false
var _ray := PhysicsRayQueryParameters3D.new()
var _samples_p := PackedVector3Array()
var _samples_d := PackedFloat32Array()
var _samples_dir := PackedVector3Array()
var _yield_to := ""
var _nudge := 0.0
var _audio: VehicleAudio
var _honk_cooldown := 0.0
var _blocked_by_player := 0.0
## What is currently limiting our speed (for debugging).
var blocker := ""
## The vehicle we're currently waiting for, if any.
var blocker_vehicle: Vehicle = null

# Lane changes, pulling over and passing. Offsets are metres to the right of
# the planned path; the steering target and the path checks are shifted by them.
var _lc_offset := 0.0
var _lc_cooldown := 3.0
var _lane_check := 0.0
var _pull_offset := 0.0
var _pull_time := 0.0
var _hurry_time := 0.0
var _still_blocked := 0.0
var _bypass_stalled := 0.0
## Passing a parked vehicle: {"obj": Vehicle, "lane": Lane, "from": s, "to": s, "offset": m}
var _bypass := {}
## Counters for the dev tests.
var age := 0.0
## Beyond this distance from the player the driver thinks at half rate
## (pedals and steering are held in between). Saves CPU; at that distance
## nobody can tell.
const LOD_DISTANCE := 140.0
var _lod_skip := false
var _lod_carry := 0.0
var _body: VehicleBodyVisual
var _indicator_timer := 0.0
var lane_changes := 0
var passes := 0


func setup(mgr: TrafficManager, lane: TrafficNetwork.Lane, s: float) -> void:
	manager = mgr
	_net = mgr.network
	vehicle = get_parent() as Vehicle
	_rng.randomize()
	_tick = _rng.randi() % 3
	_lod_skip = _rng.randi() % 2 == 0  # half the far cars think on odd ticks
	cruise_factor = _rng.randf_range(0.85, 1.05) * vehicle.ai_speed_factor
	_front = vehicle.body_front
	_half_width = vehicle.body_half_width
	_wheelbase = vehicle.wheelbase
	_max_accel = vehicle.ai_max_accel
	_mass_scale = maxf(vehicle.mass / 1300.0, 1.0)
	_avoid_dead_ends = _wheelbase > 3.2
	# Tightest path curvature this vehicle can follow at each speed (1 m/s
	# steps), keeping 20% of the steering lock in reserve for corrections.
	_curv_limit.resize(41)
	for sp in 41:
		_curv_limit[sp] = tan(deg_to_rad(0.8 * vehicle.max_steer_for_speed(sp))) / _wheelbase
	vehicle.auto_reverse = false
	var c := Controllable.of(vehicle)
	if c:
		c.take(self, true)  # the player may take the car
	vehicle.impact.connect(_on_impact)
	_body = vehicle.get_node_or_null("Body") as VehicleBodyVisual
	_ray.exclude = [vehicle.get_rid()]
	_ray.collision_mask = 0b111
	_s = s
	_plan = [_make_leg(lane, s)]
	_extend_plan()
	_setup_audio()
	# Run before the vehicle so it sees this tick's inputs.
	process_physics_priority = -10


## A car we remembered is still on the road (not freed, not back in the pool).
static func _alive(v: Variant) -> bool:
	return v != null and is_instance_valid(v) and (v as Node).is_inside_tree()


## The car is going back to the traffic pool (or the player takes it): let go of it.
func release() -> void:
	if vehicle.impact.is_connected(_on_impact):
		vehicle.impact.disconnect(_on_impact)
	var c := Controllable.of(vehicle)
	if c:
		c.drop(self)
	vehicle.auto_reverse = true
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steer_input = 0.0
	vehicle.handbrake_input = false
	vehicle.horn_input = false
	if _body:
		_body.indicator = VehicleBodyVisual.Blinker.OFF


## Turn signals before turns at junctions and for lane changes, pulling over
## and passing; hazard lights once crashed. Checked a few times a second.
func _update_indicator(dt: float) -> void:
	_indicator_timer -= dt
	if _body == null or _indicator_timer > 0.0:
		return
	_indicator_timer = 0.2
	var want := VehicleBodyVisual.Blinker.OFF
	if state != State.DRIVING:
		want = VehicleBodyVisual.Blinker.HAZARD
	elif absf(_lc_offset) > 0.35:
		# A lane change starts with the car offset toward its old lane.
		want = VehicleBodyVisual.Blinker.LEFT if _lc_offset > 0.0 else VehicleBodyVisual.Blinker.RIGHT
	elif not _bypass.is_empty():
		want = VehicleBodyVisual.Blinker.LEFT
	elif _pull_time > 0.0:
		want = VehicleBodyVisual.Blinker.RIGHT
	else:
		want = _turn_signal()
	_body.indicator = want


## The turn coming up within signalling distance (or the one we're in).
func _turn_signal() -> VehicleBodyVisual.Blinker:
	var d := 0.0
	for i in _plan.size():
		var leg: Dictionary = _plan[i]
		var lane: TrafficNetwork.Lane = leg["lane"]
		if d > 40.0:
			break
		if lane.connector and lane.length > 4.0:
			match TrafficNetwork._turn_kind(lane.dir_at(0.0), lane.dir_at(lane.length)):
				1:
					return VehicleBodyVisual.Blinker.RIGHT
				2, 3:
					return VehicleBodyVisual.Blinker.LEFT
		d += float(leg["to"]) - (_s if i == 0 else float(leg["from"]))
	return VehicleBodyVisual.Blinker.OFF


## The vehicle's own VehicleAudio (LITE) plays the engine, horn and crashes.
func _setup_audio() -> void:
	_audio = vehicle.get_node_or_null("Audio") as VehicleAudio


func honk() -> void:
	if _audio:
		_audio.honk(_rng.randf_range(0.3, 0.6))


func _update_audio(dt: float) -> void:
	# Impatient honking at a player who blocks the road (in a vehicle or on foot).
	_honk_cooldown -= dt
	var by_player := blocker == "pedestrian" or (blocker_vehicle != null and blocker_vehicle == manager.player)
	if by_player and vehicle.linear_velocity.length() < 1.0:
		_blocked_by_player += dt
	else:
		_blocked_by_player = 0.0
	if _blocked_by_player > 2.5 and _honk_cooldown <= 0.0:
		honk()
		_honk_cooldown = _rng.randf_range(3.0, 6.0)


## Position along the current lane (m).
func lane_s() -> float:
	return _s


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
			# Long vehicles can't make the tight U-turns at dead ends, and their
			# tail swings into waiting cars on left turns: avoid both if possible.
			var ok := links.filter(func(l: Dictionary) -> bool: return not _net.leads_to_dead_end(l) and not _net.is_left_turn(l))
			if ok.is_empty() and mandatory:
				ok = links.filter(func(l: Dictionary) -> bool: return not _net.leads_to_dead_end(l))
			if not ok.is_empty():
				links = ok
			elif not mandatory:
				continue
		if mandatory or _rng.randf() < lane.take_chance:
			# Links in a group can start at slightly different spots (right
			# turns begin earlier): the leg ends where the chosen one starts.
			var link: Dictionary = links[_rng.randi() % links.size()]
			var ahead: float = link["at"] - base
			if lane.closed:
				ahead = fposmod(ahead, lane.length)
				if ahead < 0.5:
					ahead += lane.length
			return {"lane": lane, "from": from, "to": from + ahead, "link": link}
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
	if vehicle.global_position.distance_squared_to(manager.focus_position()) > LOD_DISTANCE * LOD_DISTANCE:
		_lod_skip = not _lod_skip
		if _lod_skip:
			_lod_carry += dt
			return
	dt += _lod_carry
	_lod_carry = 0.0
	state_time += dt
	age += dt
	_update_audio(dt)
	_update_indicator(dt)
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

	if _reverse_time > 0.0:
		_back_up(dt)
		return

	_lane_logic(dt)
	_tick += 1
	if _tick % 4 == 0:
		_accel_cmd = _plan_speed()

	# Pure pursuit steering from the rear axle.
	var v := maxf(vehicle.forward_speed, 0.0)
	var ld := clampf(3.0 + _wheelbase * 0.8 + v * 0.45, 6.0, 24.0)
	var target := _path_point(ld)
	var lat := _offset_at(ld, _s + ld, _plan[0]["lane"])
	if lat != 0.0:
		target += (_path_point(ld + 1.0) - target).cross(Vector3.UP).normalized() * lat
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
	_last_steer = clampf(steer, -1.0, 1.0)
	_pedals(throttle, brake, _last_steer)

	# Wedged against something (wants to move but can't): back up a little and
	# try again, like a real driver. Give up after a few attempts.
	if _accel_cmd > 0.5 and v < 0.3 and not _hold:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	if v > 3.0:
		_moving_time += dt
		if _moving_time > 6.0:
			_unstick_tries = 0
	else:
		_moving_time = 0.0
	_wait_time = _wait_time + dt if v < 0.3 else 0.0
	if _stuck_time > 2.5:
		if _unstick_tries < 3 and _rear_clearance() > 2.5:
			_unstick_tries += 1
			_stuck_time = 0.0
			_reverse_time = _rng.randf_range(1.0, 1.8)
			_reverse_from = vehicle.global_position
		elif _stuck_time > 5.0:
			_lose("stuck (wants %.1f m/s2, blocker '%s', tries %d)" % [_accel_cmd, blocker, _unstick_tries])
	elif _wait_time > 60.0:
		_lose("waited 60s for " + blocker)


func _back_up(dt: float) -> void:
	_reverse_time -= dt
	var moved := vehicle.global_position.distance_to(_reverse_from)
	if _rear_clearance() < 1.0 or moved > 3.0:
		_reverse_time = 0.0
	if _reverse_time <= 0.0:
		vehicle.gear = 1
		_pedals(0.0, 0.5, 0.0)
		return
	vehicle.gear = -1
	# In reverse, the brake pedal drives backwards. Counter-steer to open a gap
	# (long vehicles back up straight: their tail would swing into the next lane).
	_pedals(0.0, 0.45, 0.0 if _avoid_dead_ends else -_last_steer * 0.6)


## Free space behind the rear bumper (m), up to 4 m.
func _rear_clearance() -> float:
	var space := vehicle.get_world_3d().direct_space_state
	var best := 4.0
	var back := vehicle.global_basis.z
	for side in [0.0, -_half_width + 0.1, _half_width - 0.1]:
		_ray.from = vehicle.global_transform * Vector3(side, 0.55, vehicle.body_rear - 0.3)
		_ray.to = _ray.from + back * 4.3
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			best = minf(best, (hit["position"] as Vector3).distance_to(_ray.from) - 0.3)
	return best


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
	if _pull_time > 0.0 or not _bypass.is_empty():
		v0 = CREEP_SPEED
	var s := _s
	var d := 0.0
	for i in _plan.size():
		if d >= horizon:
			break
		var leg: Dictionary = _plan[i]
		var lane: TrafficNetwork.Lane = leg["lane"]
		var leg_to: float = leg["to"]
		var end_d := d + (leg_to - s)
		var lim := lane.speed * cruise_factor * (1.2 if _hurry_time > 0.0 else 1.0)
		v0 = minf(v0, sqrt(lim * lim + 2.0 * COMFORT_DECEL * maxf(d, 0.0)))

		# Traffic lights along this leg.
		for stop: Dictionary in lane.stops:
			var stop_s: float = stop["at"]
			if lane.closed:
				stop_s = s + fposmod(stop_s - s + 0.5, lane.length) - 0.5
			if stop_s < s - 0.5 or stop_s > leg_to + 0.1:
				continue
			var stop_d := d + (stop_s - s) - _front
			if stop_d > -1.0:
				if stop_d < 50.0 + v * 2.0:
					manager.request_signal(stop["id"], stop["axis"])
				var st := manager.signal_state(stop["id"], stop["axis"])
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
			var sp := lane.points[idx]
			var off := _offset_at(sd, s + rel, lane)
			if off != 0.0:
				sp += lane.dirs[idx].cross(Vector3.UP).normalized() * off
			_samples_p.append(sp)
			_samples_d.append(sd)
			_samples_dir.append(lane.dirs[idx])
			var k := lane.curv[idx]
			if k > 0.004:
				var vc := minf(sqrt(LAT_ACCEL / k), _speed_for_curvature(k))
				v0 = minf(v0, sqrt(vc * vc + 2.0 * COMFORT_DECEL * sd))
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
		if not _bypass.is_empty() and other == _bypass["obj"]:
			continue
		var op := other.global_position
		var straight := op.distance_to(my_pos)
		if straight > horizon + 8.0:
			continue
		var reach := _half_width + other.body_half_width + 0.3
		# Long vehicles also count by their nose and tail, so a bus turning
		# across our lane still blocks it while its tail swings through.
		var pts: Array[Vector3] = [op]
		# How far each point sits inside the vehicle's end (for the gap).
		var insets: Array[float] = [other.body_length() * 0.5]
		if other.body_length() > 5.5:
			var ofwd := -other.global_basis.z
			pts.append(op + ofwd * (other.body_front - 1.0))
			pts.append(op - ofwd * (other.body_rear - 1.0))
			insets.append_array([1.0, 1.0])
			reach = _half_width + 1.3
		var best_l := reach * reach
		var best_i := -1
		var best_inset := insets[0]
		for pi in pts.size():
			var opt := pts[pi]
			var j := clampi(int((opt.distance_to(my_pos) - 3.0) / 3.0), 0, count)
			while j < count:
				var sd: float = _samples_d[j]
				if sd > straight * 1.6 + 10.0:
					break
				var q := _samples_p[j]
				var dx := q.x - opt.x
				var dz := q.z - opt.z
				var l := dx * dx + dz * dz
				if l < best_l and absf(q.y - opt.y) < 3.0:
					best_l = l
					best_i = j
					best_inset = insets[pi]
				j += 1
		if best_i < 0 or _samples_d[best_i] < 2.0 or _yields_to_me(other):
			continue
		var gap := _samples_d[best_i] - _front - best_inset
		if other.body_length() > 6.0:
			gap -= 2.5  # room for a long vehicle's tail to swing when it turns
		var lead_v := maxf(other.linear_velocity.dot(_samples_dir[best_i]), 0.0)
		var a := _idm(v, INF, maxf(gap, 0.1), lead_v)
		if a < best:
			best = a
			blocker = "car %s" % other.name
			blocker_vehicle = other

	# People on foot in our lane: stop for them (they're not on the physics
	# layers the sensor rays see). Stopped with someone right beside the car
	# (walking up to the door), stay put.
	for ped in manager.pedestrians:
		if not _alive(ped) or not ped.visible:
			continue
		var pp := ped.global_position
		var straight := pp.distance_to(my_pos)
		if straight > horizon or absf(pp.y - my_pos.y) > 3.0:
			continue
		var gap := INF
		if _in_corridor(pp):
			gap = maxf(straight - _front - 1.2, 0.1)
		elif v < 3.0:
			var local := vehicle.global_transform.affine_inverse() * pp
			if absf(local.x) < _half_width + 1.6 and local.z > -_front - 2.0 and local.z < vehicle.body_rear + 1.0:
				gap = 0.1
		if gap == INF:
			continue
		var a := _idm(v, INF, gap, 0.0)
		if a < best:
			best = a
			blocker = "pedestrian"
			blocker_vehicle = null
			if gap <= 0.1:
				_hold = true

	# Static obstacles (walls, knocked-over lamp posts...) along the path.
	var ray_len := minf(horizon, 25.0)
	_ray.from = vehicle.global_transform * Vector3(0, 0.55, -_front)
	var ray_end := _path_point(ray_len)
	var ray_off := _offset_at(ray_len, _s + ray_len, _plan[0]["lane"])
	if ray_off != 0.0:
		ray_end += (_path_point(ray_len + 1.0) - ray_end).cross(Vector3.UP).normalized() * ray_off
	_ray.to = ray_end + Vector3.UP * 0.55
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty() and not _bypass.is_empty() and hit["collider"] == _bypass["obj"]:
		hit = {}
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
	# Corner rays sit just outside the body so corner-to-corner overlaps count.
	var corner := _half_width + 0.05
	for side in [0.0, -corner, corner]:
		_ray.from = vehicle.global_transform * Vector3(side, 0.55, -_front + 0.3)
		_ray.to = _ray.from + fwd * reach
		hit = space.intersect_ray(_ray)
		if hit.is_empty() or (not _bypass.is_empty() and hit["collider"] == _bypass["obj"]):
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
	# Also the short stretch between the car and the first path sample (only
	# that far: straight ahead of a turning car is usually off the path).
	var first := _samples_d[0] if not _samples_d.is_empty() else 3.0
	var my := vehicle.global_position
	var l := Vector2(p.x - my.x, p.z - my.z)
	var f := Vector2(-vehicle.global_basis.z.x, -vehicle.global_basis.z.z).normalized()
	return l.dot(f) > 0.0 and absf(l.cross(f)) < _half_width + 0.45 and l.length() < maxf(first, _front) + 0.5


## True if `other` is an AI car that is itself stopped waiting for us and we
## win the tie-break, so we should go first instead of deadlocking.
func _yields_to_me(other: Vehicle) -> bool:
	var od := other.get_node_or_null("Driver") as TrafficDriver
	if od == null or od.blocker_vehicle != vehicle:
		return false
	if other.linear_velocity.length() > 1.0 or vehicle.linear_velocity.length() > 1.0:
		return false
	return vehicle.get_instance_id() < other.get_instance_id()


## Fastest speed at which our steering can still follow curvature `k`.
func _speed_for_curvature(k: float) -> float:
	if k <= _curv_limit[40]:
		return INF
	var sp := 40
	while sp > 1 and _curv_limit[sp] < k:
		sp -= 1
	return maxf(float(sp), 1.5)


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
		var vel := other.linear_velocity
		vel.y = 0.0
		var speed := vel.length()
		# Fast traffic (highway) has to be seen from further away.
		if dist > maxf(50.0, speed * 5.0):
			continue
		if dist < 5.0 and speed > 1.0:
			_yield_to = other.name
			return true
		if dist > 0.1:
			var closing := vel.dot(to / dist)
			if closing > 1.5 and dist / closing < 4.5:
				_yield_to = other.name
				return true
	return false


# ========================================== lane changes, pulling over ==

## Metres right of the planned path at `ahead` metres along it (lane `lane`,
## lane position `lane_s`): the lane-change blend and pull-over offset shrink
## the way the car will actually move, plus the passing manoeuvre's shape.
func _offset_at(ahead: float, lane_s: float, lane: TrafficNetwork.Lane) -> float:
	var travel := ahead / maxf(vehicle.forward_speed, 3.0)
	var off := move_toward(_lc_offset, 0.0, LANE_CHANGE_RATE * travel)
	var pull_goal := _pull_goal()
	off += move_toward(_pull_offset, pull_goal, PULL_RATE * travel)
	if not _bypass.is_empty() and lane == _bypass["lane"]:
		var a: float = _bypass["from"]
		var e: float = _bypass["to"]
		var full: float = _bypass["offset"]
		if lane_s >= a and lane_s < e:
			off += full * smoothstep(a, a + 7.0, lane_s)
		elif lane_s >= e:
			off += full * (1.0 - smoothstep(e, e + 9.0, lane_s))
	return off


func _pull_goal() -> float:
	if _pull_time <= 0.0 or _plan.is_empty():
		return 0.0
	return (_plan[0]["lane"] as TrafficNetwork.Lane).pull_room


func _lane_logic(dt: float) -> void:
	_lc_cooldown -= dt
	_lc_offset = move_toward(_lc_offset, 0.0, LANE_CHANGE_RATE * dt)
	_pull_time -= dt
	_pull_offset = move_toward(_pull_offset, _pull_goal(), PULL_RATE * dt)
	_hurry_time -= dt
	var lane: TrafficNetwork.Lane = _plan[0]["lane"]
	if not _bypass.is_empty():
		var obj: Vehicle = _bypass["obj"] if _alive(_bypass["obj"]) else null
		if lane != _bypass["lane"] or _s > float(_bypass["to"]) + 10.0 or obj == null \
				or obj.global_position.distance_to(_bypass["obj_pos"]) > 2.0:
			_bypass = {}
		elif vehicle.forward_speed < 0.5 and blocker != "":
			# Something (oncoming traffic) is in the way: give up, back off.
			_bypass_stalled += dt
			if _bypass_stalled > 1.5:
				_bypass = {}
				if _rear_clearance() > 2.0:
					_reverse_time = 1.2
					_reverse_from = vehicle.global_position
		else:
			_bypass_stalled = 0.0
	# Waiting behind something that isn't going anywhere (the player parked in
	# our lane, a wreck)?
	var parked := _alive(blocker_vehicle) \
		and blocker_vehicle.linear_velocity.length() < 0.4 and _is_parked(blocker_vehicle)
	if parked and vehicle.forward_speed < 1.0 and _bypass.is_empty():
		_still_blocked += dt
	else:
		_still_blocked = 0.0

	_lane_check -= dt
	if _lane_check > 0.0:
		return
	_lane_check = 0.5
	if _still_blocked > 3.0:
		if _change_lane(-1, true) or _change_lane(1, true) or _try_bypass(blocker_vehicle):
			_still_blocked = 0.0
		return
	_consider_lane_change()


## Parked = the player's vehicle (stopped), one they left, or a traffic car
## that gave up after a crash.
func _is_parked(v: Vehicle) -> bool:
	var d := manager.driver_of(v)
	return d == null or d.state == State.LOST


func _consider_lane_change() -> void:
	var lane: TrafficNetwork.Lane = _plan[0]["lane"]
	if _lc_cooldown > 0.0 or vehicle.forward_speed < 8.0 or lane.connector:
		return
	if lane.left_id < 0 and lane.right_id < 0:
		return
	var desired := lane.speed * cruise_factor
	var lead_gap := INF
	var lead_v := INF
	if blocker.begins_with("car") and _alive(blocker_vehicle):
		lead_v = blocker_vehicle.linear_velocity.length()
		lead_gap = blocker_vehicle.global_position.distance_to(vehicle.global_position)
	elif blocker != "":
		return  # lights, junctions, obstacles: stay put
	# Catching up with a slower car: overtake on the left (rarely on the right).
	if lead_gap < 50.0 and lead_v < desired - 2.0:
		if _change_lane(-1, false) or (_rng.randf() < 0.25 and _change_lane(1, false)):
			return
	if lead_gap < 35.0:
		return
	# Free road: keep right now and then (trucks and buses more eagerly),
	# and once in a while move left just for variety.
	var heavy := vehicle.ai_speed_factor < 0.9
	if lane.right_id >= 0 and _rng.randf() < (0.15 if heavy else 0.03):
		_change_lane(1, false)
	elif lane.left_id >= 0 and not heavy and _rng.randf() < 0.012:
		_change_lane(-1, false)


## Moves to the neighbouring lane on the left (dir -1) or right (+1) if
## there's a safe gap. `urgent`: we're stopped behind something parked.
func _change_lane(dir: int, urgent: bool) -> bool:
	var lane: TrafficNetwork.Lane = _plan[0]["lane"]
	var id := lane.left_id if dir < 0 else lane.right_id
	if id < 0 or lane.connector:
		return false
	# Not right before a junction/exit we're planning to take.
	if float(_plan[0]["to"]) - _s < (25.0 if urgent else 70.0):
		return false
	var target := _net.lanes[id]
	var hint := _s * target.length / maxf(lane.length, 1.0)
	var st := target.project(vehicle.global_position, hint, 40.0)
	if not _lane_is_clear(target, st, maxf(vehicle.forward_speed, 0.0)):
		return false
	var q := target.point_at(st)
	var right := target.dir_at(st).cross(Vector3.UP).normalized()
	_lc_offset = (vehicle.global_position - q).dot(right)
	_plan = [_make_leg(target, st)]
	_s = st
	_extend_plan()
	_lc_cooldown = _rng.randf_range(7.0, 12.0)
	_bypass = {}
	lane_changes += 1
	return true


## Is there a big enough gap in `target` around lane position `st`?
func _lane_is_clear(target: TrafficNetwork.Lane, st: float, v: float) -> bool:
	var my := vehicle.global_position
	for other in manager.vehicles:
		if other == vehicle or not is_instance_valid(other):
			continue
		var op := other.global_position
		if op.distance_squared_to(my) > 100.0 * 100.0:
			continue
		var so := target.project(op, st, 100.0)
		var q := target.point_at(so)
		if Vector2(q.x - op.x, q.z - op.z).length() > other.body_half_width + 1.6:
			# Not in that lane, unless it's moving into it right now (from the
			# lane on its other side, say).
			var od := manager.driver_of(other)
			if od == null or od.current_lane() != target:
				continue
		var ov := other.linear_velocity.dot(target.dir_at(so))
		var rel := so - st
		if rel >= 0.0:
			if rel - _front - other.body_rear < 6.0 + maxf(v - ov, 0.0) * 1.5:
				return false
		elif -rel - vehicle.body_rear - other.body_front < 5.0 + maxf(ov - v, 0.0) * 2.5:
			return false
	return true


## Starts passing parked vehicle `obj` on the left through the oncoming lane
## (two-lane roads), if the way is clear.
func _try_bypass(obj: Vehicle) -> bool:
	var leg: Dictionary = _plan[0]
	var lane: TrafficNetwork.Lane = leg["lane"]
	# Long vehicles can't swing out and back in on a two-lane street.
	if obj == null or lane.connector or lane.pass_room <= 0.0 or _avoid_dead_ends:
		return false
	var op := obj.global_position
	var so := lane.project(op, _s + 8.0, 25.0)
	var right := lane.dir_at(so).cross(Vector3.UP).normalized()
	var lat := (op - lane.point_at(so)).dot(right)
	var off := -(obj.body_half_width + _half_width + 0.8 - lat)
	if off > -0.3 or off < -lane.pass_room:
		return false
	var to := so + obj.body_length() * 0.5 + vehicle.body_rear + 2.5
	if to + 10.0 > float(leg["to"]):
		return false  # would still be on the wrong side at the junction
	if not _passing_clear(lane, to + 10.0 - _s, off, obj):
		return false
	_bypass = {"obj": obj, "obj_pos": op, "lane": lane, "from": _s, "to": to, "offset": off}
	_bypass_stalled = 0.0
	passes += 1
	return true


## No oncoming traffic or obstacles along a pass of `length` metres at `off`.
func _passing_clear(lane: TrafficNetwork.Lane, length: float, off: float, obj: Vehicle) -> bool:
	var my := vehicle.global_position
	var fwd := lane.dir_at(_s)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	for other in manager.vehicles:
		if other == vehicle or other == obj or not is_instance_valid(other):
			continue
		var rel := other.global_position - my
		var ahead := rel.dot(fwd)
		var side := rel.dot(right)
		if ahead < -3.0 or ahead > length + 110.0 or side > -1.0 or side < off - 3.5:
			continue
		if ahead < length + 8.0:
			return false  # something in the passing lane right here
		var closing := -other.linear_velocity.dot(fwd)
		if closing > 0.5 and (ahead - length) / closing < length / CREEP_SPEED + 3.0:
			return false
	# Walls, posts, parked props along the passing line.
	var space := vehicle.get_world_3d().direct_space_state
	for side_off in [off, off - _half_width + 0.2]:
		_ray.from = my + right * side_off * 0.5 + Vector3.UP * 0.6
		_ray.to = lane.point_at(_s + length) + right * side_off + Vector3.UP * 0.6
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and hit["collider"] != obj and (hit["normal"] as Vector3).y < 0.6:
			return false
	return true


## The player honked near us (called by the TrafficManager).
func on_player_horn(player: Vehicle) -> void:
	if state != State.DRIVING or _pull_time > 0.0 or _hurry_time > 0.0:
		return
	var rel := player.global_position - vehicle.global_position
	var fwd := -vehicle.global_basis.z
	var behind := -rel.dot(fwd)
	if behind < 2.0 or behind > 35.0 or absf(rel.dot(vehicle.global_basis.x)) > 4.5:
		return
	if (-player.global_basis.z).dot(fwd) < 0.5:
		return  # not coming the same way
	if vehicle.forward_speed > 3.0:
		# Let them through: a lane to the right, or pull over and slow down.
		if not _change_lane(1, false) and (_plan[0]["lane"] as TrafficNetwork.Lane).pull_room > 0.0:
			_pull_time = 5.0
	elif blocker == "" or blocker.begins_with("car"):
		_hurry_time = 6.0
	if _rng.randf() < 0.3:
		get_tree().create_timer(0.6).timeout.connect(honk)


# ============================================================ crash state ==

func _on_impact(strength: float, _pos: Vector3, _n: Vector3) -> void:
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
