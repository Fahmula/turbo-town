class_name StuntTracker
extends Node
## Spots the stunts the player pulls off — big air, flips, barrel rolls, air
## spins, loops, wall rides, near misses and drifts — and chains them into combos: every trick
## adds its points and bumps the multiplier; the combo is banked after a few
## quiet seconds on the ground, or lost in a wipeout (crash landing / big hit).

signal trick(trick_name: String, points: int)
## Current combo: list of [name, points], multiplier and running total.
signal combo_changed(tricks: Array, multiplier: int, total: int)
signal combo_banked(points: int, place: int)
signal combo_lost(reason: String)

const COMBO_WINDOW := 3.0
const MAX_MULTIPLIER := 10

var vehicle: Vehicle:
	set(v):
		if vehicle and vehicle.impact.is_connected(_on_impact):
			vehicle.impact.disconnect(_on_impact)
			vehicle.vehicle_reset.disconnect(_on_reset)
		vehicle = v
		if vehicle:
			vehicle.impact.connect(_on_impact)
			vehicle.vehicle_reset.connect(_on_reset)
		_reset_air()
		_end_drift(false)
var traffic: TrafficManager
## Points banked this session.
var score := 0
var enabled := true

var _combo: Array = []
var _combo_timer := 0.0
var _in_air := false
var _air_time := 0.0
var _rot := Vector3.ZERO
var _landing_check := -1.0
var _loop_pitch := 0.0
var _loop_air := 0.0
var _level_time := 0.0
var _wall_time := 0.0
var _drift_time := 0.0
var _drift_points := 0.0
var _drift_grace := 0.0
## instance id -> seconds left before that car can give another near miss.
var _near_cooldown := {}
## instance id -> {"t": seconds since the close pass}
var _near_pending := {}


func _physics_process(dt: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not enabled:
		return
	_track_air(dt)
	_track_loop(dt)
	_track_drift(dt)
	_track_near_misses(dt)
	# Bank the combo after a quiet spell (the clock stops in the air and while drifting).
	if not _combo.is_empty() and not _in_air and _drift_time <= 0.0 and _landing_check < 0.0 and _wall_time <= 0.0:
		_combo_timer -= dt
		if _combo_timer <= 0.0:
			_bank()


## Banks the combo in progress now (the player got out of the vehicle).
func bank_now() -> void:
	_end_drift(true)
	if not _combo.is_empty() and vehicle and is_instance_valid(vehicle):
		_bank()


func combo_total() -> int:
	var sum := 0
	for t: Array in _combo:
		sum += int(t[1])
	return sum * mini(_combo.size(), MAX_MULTIPLIER)


func _add(trick_name: String, points: int) -> void:
	_combo.append([trick_name, points])
	_combo_timer = COMBO_WINDOW
	trick.emit(trick_name, points)
	combo_changed.emit(_combo, mini(_combo.size(), MAX_MULTIPLIER), combo_total())


func _bank() -> void:
	var total := combo_total()
	var names: Array[String] = []
	for t: Array in _combo:
		names.append(t[0])
	_combo.clear()
	score += total
	var place := Records.add_combo(total, vehicle.display_name, ", ".join(names))
	combo_banked.emit(total, place)
	combo_changed.emit(_combo, 0, 0)


func _lose(reason: String) -> void:
	_end_drift(false)
	if _combo.is_empty():
		return
	_combo.clear()
	combo_lost.emit(reason)
	combo_changed.emit(_combo, 0, 0)


# --- Air ---------------------------------------------------------------------

func _reset_air() -> void:
	_in_air = false
	_air_time = 0.0
	_rot = Vector3.ZERO
	_landing_check = -1.0


func _track_air(dt: float) -> void:
	var v := vehicle
	if _landing_check >= 0.0:
		# Just landed: if it ends up on its roof or side, that's a wipeout.
		_landing_check -= dt
		if v.global_basis.y.y < 0.3:
			_landing_check = -1.0
			_lose("WIPEOUT!")
	if v.airtime > 0.0:
		if not _in_air:
			_in_air = true
			_rot = Vector3.ZERO
		_air_time = v.airtime
		# Rotation in the car's own frame: x = pitch (flips), y = yaw (spins),
		# z = roll (barrel rolls).
		_rot += (v.global_basis.inverse() * v.angular_velocity) * dt
	elif _in_air:
		_in_air = false
		_score_jump()


## Scores a jump the moment the car touches down.
func _score_jump() -> void:
	var v := vehicle
	var air := _air_time
	var flips := int((absf(_rot.x) + 0.7) / TAU)
	var rolls := int((absf(_rot.z) + 0.7) / TAU)
	var half_spins := int((absf(_rot.y) + 0.45) / PI)
	if v.global_basis.y.y < 0.5:
		if air > 0.8 or flips + rolls > 0:
			_lose("WIPEOUT!")
		return
	if air < 0.6 and flips + rolls + half_spins == 0:
		return
	_landing_check = 1.0
	if air >= 0.8:
		var label := "HUGE AIR" if air >= 2.5 else ("BIG AIR" if air >= 1.5 else "AIR")
		_add("%s %.1fs" % [label, air], int(air * 100.0))
		Records.report_air(air)
	if flips > 0:
		var back := _rot.x > 0.0  # nose up = backwards
		var flip_name := ("BACKFLIP" if back else "FRONTFLIP")
		_add(flip_name if flips == 1 else "%s x%d" % [flip_name, flips], 500 * flips * flips)
	if rolls > 0:
		_add("BARREL ROLL" if rolls == 1 else "BARREL ROLL x%d" % rolls, 400 * rolls * rolls)
	if flips + rolls > 0:
		Records.report_flips(flips + rolls)
	if half_spins > 0:
		_add("%d SPIN" % (half_spins * 180), 150 * half_spins)
	if air >= 1.0 and v.global_basis.y.y > 0.95:
		_add("PERFECT LANDING", 100)


# --- Loops and wall rides -----------------------------------------------------

func _track_loop(dt: float) -> void:
	var v := vehicle
	var b := v.global_basis
	_loop_pitch += (b.inverse() * v.angular_velocity).x * dt
	if v.airtime > 0.0:
		_loop_air += dt
	# A loop = a whole turn nose-over-tail while staying on the wheels; judged
	# once the car is level on the ground again.
	var level := b.y.y > 0.95 and v.grounded_wheels >= 3
	_level_time = _level_time + dt if level else 0.0
	if _level_time > 0.5:
		# Long cars slide over the top a little, so they don't quite turn a
		# full 360 on paper; 260 degrees one way on the wheels is only a loop
		# (half pipes go up and come back down).
		if absf(_loop_pitch) > 4.5 and _loop_air < 0.6:
			_add("LOOP-THE-LOOP", 1000)
		_loop_pitch = 0.0
		_loop_air = 0.0
	# Wall ride: driving along a wall with the car tipped right over sideways.
	var on_wall := v.grounded_wheels >= 3 and absf(b.x.y) > 0.75 and v.forward_speed > 6.0
	if on_wall:
		_wall_time += dt
	elif _wall_time > 0.0:
		if _wall_time > 1.0:
			_add("WALL RIDE %.1fs" % _wall_time, int(150.0 * _wall_time))
		_wall_time = 0.0


# --- Drift -------------------------------------------------------------------

func _track_drift(dt: float) -> void:
	var v := vehicle
	var vel := v.linear_velocity
	var fwd := -v.global_basis.z
	var speed := vel.length()
	var slip := 0.0
	if speed > 1.0:
		slip = rad_to_deg(acos(clampf(vel.normalized().dot(fwd), -1.0, 1.0)))
	var drifting := v.grounded_wheels >= 3 and speed > 9.0 and slip > 14.0 and slip < 100.0
	if drifting:
		_drift_time += dt
		_drift_points += speed * dt * (slip / 30.0) * 2.0
		_drift_grace = 0.45
	elif _drift_time > 0.0:
		_drift_grace -= dt
		if _drift_grace <= 0.0:
			_end_drift(true)


func _end_drift(score_it: bool) -> void:
	if score_it and _drift_time >= 1.2:
		_add("DRIFT %.1fs" % _drift_time, int(_drift_points))
		Records.report_drift(_drift_time)
	_drift_time = 0.0
	_drift_points = 0.0


# --- Near misses ---------------------------------------------------------------

func _track_near_misses(dt: float) -> void:
	for id in _near_cooldown.keys():
		_near_cooldown[id] -= dt
		if _near_cooldown[id] <= 0.0:
			_near_cooldown.erase(id)
	for id in _near_pending.keys():
		_near_pending[id] += dt
		if _near_pending[id] > 0.5:
			_near_pending.erase(id)
			_near_cooldown[id] = 4.0
			Records.add_near_miss()
			_add("NEAR MISS", 150)
	if traffic == null or vehicle.forward_speed < 12.0:
		return
	var v := vehicle
	var xf := v.global_transform
	for other in traffic.vehicles:
		if other == v or not is_instance_valid(other):
			continue
		var id := other.get_instance_id()
		if _near_cooldown.has(id) or _near_pending.has(id):
			continue
		var rel := other.global_position - xf.origin
		if rel.length_squared() > 100.0:
			continue
		var local := xf.basis.inverse() * rel
		var side_gap := absf(local.x) - v.body_half_width - other.body_half_width
		var overlap := absf(local.z) < (v.body_length() + other.body_length()) * 0.5
		var closing := (v.linear_velocity - other.linear_velocity).length()
		if overlap and side_gap > 0.05 and side_gap < 1.1 and closing > 8.0 and absf(local.y) < 2.0:
			_near_pending[id] = 0.0


# Teleports, respawns and flip-resets: whatever was in the air doesn't count.
func _on_reset() -> void:
	_reset_air()
	_loop_pitch = 0.0
	_wall_time = 0.0
	_end_drift(false)
	_near_pending.clear()


func _on_impact(strength: float, _pos: Vector3, _normal: Vector3) -> void:
	# Touching the car you just squeezed past isn't a near miss.
	_near_pending.clear()
	# Hard landings aren't crashes (a landing that ends on the roof is a
	# wipeout instead): only big hits on the ground lose the combo.
	var hard := 9000.0 * maxf(vehicle.mass / 1300.0, 1.0)
	if strength > hard and not _in_air and _landing_check < 0.0 and vehicle.airtime <= 0.0:
		_lose("CRASH!")
