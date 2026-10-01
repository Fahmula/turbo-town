class_name Vehicle
extends RigidBody3D
## Custom raycast-suspension car.
##
## VehicleWheel children compute suspension and tire forces; this class owns the
## engine, automatic gearbox, steering, anti-roll bars, aero and driving assists.
## Anything can drive it (player, AI, replay) by writing the *_input variables.
## To make a new vehicle: inherit/duplicate a vehicle scene, swap the visuals and
## tweak the exported values — no code changes needed.

signal impact(strength: float, world_position: Vector3, normal: Vector3)
signal landed(airtime: float)
signal vehicle_reset

@export var display_name := "Car"
## Where the hood camera sits (local space, roughly the driver's eyes).
@export var driver_eye := Vector3(0.0, 1.2, -0.2)

@export_group("Engine")
@export var max_engine_torque := 430.0
@export var idle_rpm := 900.0
@export var redline_rpm := 7000.0
@export var gear_ratios := PackedFloat32Array([4.4, 2.7, 1.9, 1.45, 1.15])
@export var reverse_ratio := 3.8
@export var final_drive := 3.9
@export var drivetrain_efficiency := 0.85
@export var shift_up_rpm := 6600.0
@export var shift_down_rpm := 3200.0
@export var shift_time := 0.18
## Off-throttle engine braking, as a fraction of max torque.
@export var engine_braking := 0.15
@export var max_reverse_speed := 12.0

@export_group("Brakes")
@export var max_brake_torque := 2200.0
@export_range(0.0, 1.0) var front_brake_bias := 0.6

@export_group("Steering")
@export var max_steer_angle := 34.0
@export var high_speed_steer_angle := 5.5
## Speed (m/s) at which steering is reduced to high_speed_steer_angle.
@export var steer_falloff_speed := 40.0
@export var steer_speed := 150.0
@export var steer_return_speed := 220.0

@export_group("Chassis")
@export var anti_roll_front := 7000.0
@export var anti_roll_rear := 4000.0
@export var drag_coefficient := 0.42
@export var downforce_coefficient := 0.9
## Tire forces are applied this far above the contact patch. Raising it
## reduces body roll and rollover tendency.
@export var tire_force_height := 0.05
@export_flags_3d_physics var wheel_collision_mask := 0b111

@export_group("Assists")
## Traction control + stability control. Toggled together in-game (T key).
@export var traction_control := true
## How hard stability control fights unwanted yaw (spins). 0 disables.
@export var stability_control := 12.0
## Brakes gently when stopped with no input, so the car doesn't roll away.
@export var auto_hold := true
## Holding brake while stopped engages reverse (player style). AI turns this off.
@export var auto_reverse := true
## Gently levels the car in mid-air so jumps land on the wheels more often.
@export_range(0.0, 3.0) var air_stabilization := 1.0
@export var impact_threshold := 2500.0

@export_group("AI")
## Traffic drivers multiply lane speed limits by this (trucks/buses < 1).
@export var ai_speed_factor := 1.0
## Acceleration (m/s²) traffic drivers aim for when pulling away.
@export var ai_max_accel := 2.2

# --- Inputs (written by a controller) ---
var throttle_input := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake_input := false
var horn_input := false
## 0..1: how much of the mid-air leveling to use this tick (the player's air
## controls turn it down while they're steering in the air).
var air_assist_scale := 1.0
## Set by VehicleDamage: a smashed front pulls the steering (fraction of full
## lock, + = right) and loses engine power (1 = healthy).
var damage_steer_bias := 0.0
var damage_power := 1.0

# --- Read-only state ---
var wheels: Array[VehicleWheel] = []
var gear := 1  ## -1 reverse, 1..n forward
var engine_rpm := 900.0
var engine_load := 0.0
var forward_speed := 0.0
var speed_kmh := 0.0
var grounded_wheels := 0
var airtime := 0.0
var steer_angle := 0.0
var is_braking := false
var upside_down_time := 0.0
## Measured at startup from the collision boxes / wheels (metres).
var wheelbase := 2.7
var body_front := 2.2
var body_rear := 2.2
var body_half_width := 0.95
var body_top := 1.0

var _shift_timer := 0.0
var _handbrake_timer := 0.0
var _wheel_radius := 0.37
var _front_pair: Array[VehicleWheel] = []
var _rear_pair: Array[VehicleWheel] = []
var _body_touching := false
var _pending_impact := 0.0
var _pending_impact_pos := Vector3.ZERO
var _pending_impact_normal := Vector3.UP
## What the last reported impact was against (for debugging).
var last_impact_collider: Object = null


func _ready() -> void:
	for child in get_children():
		if child is VehicleWheel:
			wheels.append(child)
	for w in wheels:
		w.setup(self, wheel_collision_mask)
		_wheel_radius = w.radius
	_front_pair = _find_pair(true)
	_rear_pair = _find_pair(false)
	if _front_pair.size() == 2 and _rear_pair.size() == 2:
		wheelbase = absf(_front_pair[0].position.z - _rear_pair[0].position.z)
	_measure_body()
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	can_sleep = false
	# Drag is modelled explicitly in _apply_aero(); the engine's default damping
	# would act like a huge speed-proportional brake.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.15


func _measure_body() -> void:
	var min_z := INF
	var max_z := -INF
	var max_x := 0.0
	var max_y := -INF
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var h := (cs.shape as BoxShape3D).size * 0.5
		for corner in [Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z)]:
			var p: Vector3 = cs.transform * corner
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
			max_x = maxf(max_x, absf(p.x))
			max_y = maxf(max_y, p.y)
	if min_z < INF:
		body_front = -min_z
		body_rear = max_z
		body_half_width = max_x
		body_top = max_y


## Height of the body origin above flat ground when standing still. Works
## before the vehicle enters the tree (reads the wheel children directly).
func ride_height() -> float:
	var h := 0.0
	var count := 0
	for child in get_children():
		if child is VehicleWheel:
			count += 1
	for child in get_children():
		var w := child as VehicleWheel
		if w:
			h = maxf(h, w.rest_drop(mass / maxi(count, 1)) + w.radius - w.position.y)
	return h


func body_length() -> float:
	return body_front + body_rear


func wheel_radius() -> float:
	return _wheel_radius


func _find_pair(front: bool) -> Array[VehicleWheel]:
	var left: VehicleWheel = null
	var right: VehicleWheel = null
	for w in wheels:
		if w.is_front != front:
			continue
		if w.is_left:
			left = w
		else:
			right = w
	if left and right:
		return [left, right]
	return []


func _physics_process(dt: float) -> void:
	forward_speed = linear_velocity.dot(-global_basis.z)
	speed_kmh = linear_velocity.length() * 3.6

	_update_steering(dt)
	_update_drivetrain(dt)

	var mass_share := mass / maxf(wheels.size(), 1)
	var was_airborne := grounded_wheels == 0
	grounded_wheels = 0
	for w in wheels:
		w.update_physics(dt, mass_share, traction_control, tire_force_height)
		if w.grounded:
			grounded_wheels += 1

	_apply_anti_roll(_front_pair, anti_roll_front)
	_apply_anti_roll(_rear_pair, anti_roll_rear)
	_apply_aero()
	_apply_stability(dt)
	_update_air(dt, was_airborne)

	if global_basis.y.y < 0.2 and linear_velocity.length() < 3.0:
		upside_down_time += dt
	else:
		upside_down_time = 0.0

	if _pending_impact > 0.0:
		impact.emit(_pending_impact, _pending_impact_pos, _pending_impact_normal)
		_pending_impact = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Only gathers collision info; forces are applied in _physics_process.
	_body_touching = state.get_contact_count() > 0
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		var other := state.get_contact_collider_object(i)
		if other and other.has_method("on_vehicle_hit"):
			other.call_deferred("on_vehicle_hit", self, impulse)
		if other and other.has_meta("no_impact"):
			continue  # scraping along a loop / wall ride isn't a crash
		if impulse > impact_threshold and impulse > _pending_impact:
			_pending_impact = impulse
			last_impact_collider = other
			_pending_impact_pos = state.get_contact_collider_position(i)
			_pending_impact_normal = state.get_contact_local_normal(i)


## Current steering lock in degrees (it shrinks with speed).
func max_steer_at_speed() -> float:
	return max_steer_for_speed(forward_speed)


func max_steer_for_speed(speed: float) -> float:
	var speed_t := clampf(absf(speed) / steer_falloff_speed, 0.0, 1.0)
	return lerpf(max_steer_angle, high_speed_steer_angle, speed_t * (2.0 - speed_t))


func _update_steering(dt: float) -> void:
	var max_angle := max_steer_at_speed()
	var target := -clampf(steer_input + damage_steer_bias, -1.0, 1.0) * max_angle
	var rate := steer_speed if absf(target) > absf(steer_angle) else steer_return_speed
	steer_angle = move_toward(steer_angle, target, rate * dt)
	var rad := deg_to_rad(steer_angle)
	for w in wheels:
		if w.steers:
			w.steer_angle = rad


func _update_drivetrain(dt: float) -> void:
	# W/S act as throttle/brake going forward and swap roles in reverse.
	if gear >= 1:
		if auto_reverse and brake_input > 0.3 and throttle_input < 0.1 and forward_speed < 0.8:
			gear = -1
	elif throttle_input > 0.3 and brake_input < 0.1 and forward_speed > -0.8:
		gear = 1

	var accel := throttle_input if gear >= 1 else brake_input
	var brake := brake_input if gear >= 1 else throttle_input
	if handbrake_input:
		accel = 0.0
	if gear == -1 and forward_speed < -max_reverse_speed:
		accel = 0.0

	var ratio := _current_ratio()
	var driven_count := 0
	var wheel_spin := 0.0
	var driven_grounded := 0
	for w in wheels:
		if w.driven:
			driven_count += 1
			wheel_spin += absf(w.spin_speed)
			if w.grounded:
				driven_grounded += 1
	if driven_count > 0:
		wheel_spin /= driven_count
	# Locked (handbraked) wheels shouldn't make the gearbox think we've stopped.
	wheel_spin = maxf(wheel_spin, absf(forward_speed) / _wheel_radius)

	# Engine speed follows the wheels; a slipping "clutch" lets it rev at launch.
	var wheel_rpm := wheel_spin * absf(ratio) * 60.0 / TAU
	var launch_rpm := idle_rpm + accel * 2600.0 * clampf(1.0 - absf(forward_speed) / 10.0, 0.0, 1.0)
	var target_rpm := maxf(wheel_rpm, launch_rpm)
	if driven_grounded == 0:
		target_rpm = lerpf(idle_rpm, redline_rpm * 0.97, accel)
	engine_rpm = lerpf(engine_rpm, clampf(target_rpm, idle_rpm, redline_rpm * 1.02), 1.0 - exp(-14.0 * dt))

	var torque := 0.0
	if _shift_timer > 0.0:
		_shift_timer -= dt
	elif engine_rpm < redline_rpm:
		torque = _torque_curve(engine_rpm / redline_rpm) * max_engine_torque * accel * damage_power
	engine_load = accel if _shift_timer <= 0.0 else 0.0

	var wheel_torque := torque * ratio * drivetrain_efficiency
	var engine_brake := 0.0
	if accel < 0.05 and not handbrake_input:
		engine_brake = engine_braking * max_engine_torque * absf(ratio) * (engine_rpm / redline_rpm)

	# Auto-hold keeps the car still on slopes when there's no input.
	var hold := auto_hold and accel < 0.05 and brake < 0.05 and absf(forward_speed) < 0.6 and grounded_wheels >= 3

	is_braking = brake > 0.05
	for w in wheels:
		w.handbrake_engaged = handbrake_input
		w.drive_torque = wheel_torque / driven_count if (w.driven and driven_count > 0) else 0.0
		var bias := front_brake_bias if w.is_front else 1.0 - front_brake_bias
		var b := brake * max_brake_torque * bias * 2.0
		if w.driven and driven_count > 0:
			b += engine_brake / driven_count
		if hold:
			b = maxf(b, max_brake_torque * 0.5)
		w.brake_torque = b

	# Automatic gearbox.
	if gear >= 1 and _shift_timer <= 0.0 and driven_grounded > 0:
		if engine_rpm > shift_up_rpm and gear < gear_ratios.size() and (accel > 0.1 or engine_rpm > redline_rpm * 0.97):
			gear += 1
			_shift_timer = shift_time
		elif engine_rpm < shift_down_rpm and gear > 1 and not handbrake_input:
			gear -= 1
			_shift_timer = shift_time * 0.5


func _current_ratio() -> float:
	if gear == -1:
		return -reverse_ratio * final_drive
	return gear_ratios[clampi(gear - 1, 0, gear_ratios.size() - 1)] * final_drive


func _torque_curve(t: float) -> float:
	# Rises from idle, flat-ish mid range, tails off near the redline.
	if t < 0.6:
		return lerpf(0.6, 1.0, t / 0.6)
	return lerpf(1.0, 0.8, (t - 0.6) / 0.4)


func _apply_anti_roll(pair: Array[VehicleWheel], stiffness: float) -> void:
	if pair.is_empty():
		return
	var l := pair[0]
	var r := pair[1]
	var diff := minf(l.compression, l.suspension_travel) - minf(r.compression, r.suspension_travel)
	var f := diff * stiffness
	var up := global_basis.y
	if l.grounded:
		apply_force(up * f, l.global_position - global_position)
	if r.grounded:
		apply_force(-up * f, r.global_position - global_position)


## Simple ESC: damps yaw beyond what the steering asks for, so the car doesn't
## spin out on its own. Off while (and shortly after) using the handbrake so
## handbrake turns and drifts still work.
func _apply_stability(dt: float) -> void:
	if handbrake_input:
		_handbrake_timer = 1.2
	_handbrake_timer = maxf(_handbrake_timer - dt, 0.0)
	if not traction_control or stability_control <= 0.0 or _handbrake_timer > 0.0:
		return
	if grounded_wheels < 3 or forward_speed < 4.0:
		return
	var up := global_basis.y
	var expected := forward_speed * tan(deg_to_rad(steer_angle)) / wheelbase
	var grip_limit := 11.0 / forward_speed
	expected = clampf(expected, -grip_limit, grip_limit)
	var actual := angular_velocity.dot(up)
	var err := actual - expected
	var margin := 0.12
	if absf(err) > margin:
		var correction := (absf(err) - margin) * signf(err)
		apply_torque(-up * correction * inertia.y * stability_control)


func _apply_aero() -> void:
	var v := linear_velocity
	apply_central_force(-v * v.length() * drag_coefficient)
	if grounded_wheels > 0:
		apply_central_force(-global_basis.y * downforce_coefficient * forward_speed * forward_speed)


func _update_air(dt: float, was_airborne: bool) -> void:
	if grounded_wheels == 0 and _body_touching:
		# Sliding on the roof/side is not "air".
		airtime = 0.0
	elif grounded_wheels == 0:
		airtime += dt
		if airtime > 0.2 and air_stabilization > 0.0:
			# Torque that rotates the car's up axis toward world up, plus some
			# damping. Fades out when badly tilted or spinning fast, so jumps
			# land cleaner but real crashes still tumble.
			var up := global_basis.y
			var axis := up.cross(Vector3.UP)
			var ang := angular_velocity - Vector3.UP * angular_velocity.dot(Vector3.UP)
			var strength := air_stabilization * air_assist_scale * smoothstep(0.35, 0.75, up.y) * (1.0 - smoothstep(2.5, 5.0, ang.length()))
			# Tuned on the 1.3 t sports car; scale so heavy vehicles feel the same.
			var inertia_scale := inertia.x / 2100.0 if inertia.x > 0.0 else 1.0
			apply_torque((axis * 2500.0 - ang * 900.0) * strength * inertia_scale)
	else:
		if was_airborne and airtime > 0.35:
			landed.emit(airtime)
		airtime = 0.0


## Flips the car upright where it is (R key).
func reset_upright() -> void:
	var xform := upright_ground_transform()
	teleport(xform.translated(Vector3.UP * 1.2))


## Upright, same heading, origin on the ground below the car (or at the car if
## there is no ground under it).
func upright_ground_transform() -> Transform3D:
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = global_basis.y
		fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	var pos := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 4.0, pos + Vector3.DOWN * 30.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		pos = hit.position
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)


## Places the car at a transform with all motion cleared.
func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer_angle = 0.0
	gear = 1
	engine_rpm = idle_rpm
	airtime = 0.0
	upside_down_time = 0.0
	for w in wheels:
		w.reset_state()
	reset_physics_interpolation()
	vehicle_reset.emit()


func get_skid_amount() -> float:
	var s := 0.0
	for w in wheels:
		s = maxf(s, w.skid)
	return s
