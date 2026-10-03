class_name PlayerVehicleController
extends Node
## Feeds player input into a Vehicle and plays gamepad rumble for crashes and
## landings. The vehicle itself doesn't know or care who is driving (traffic
## uses a TrafficDriver instead). The Possession gives it the vehicle the
## player sits in (control()); on foot it has none.

## Swapping this moves input and rumble to the new vehicle.
@export var vehicle: Vehicle:
	set(v):
		if vehicle and vehicle.impact.is_connected(_on_impact):
			vehicle.impact.disconnect(_on_impact)
			vehicle.landed.disconnect(_on_landed)
		vehicle = v
		if vehicle:
			vehicle.impact.connect(_on_impact)
			vehicle.landed.connect(_on_landed)
## Keyboard steering is digital; this smooths it into a ramp (per second).
@export var keyboard_steer_speed := 5.0
## Air tricks. Plain steering spins the car gently (to aim a landing); with
## the handbrake held, gas/brake flip it and steering barrel-rolls it. Holding
## the gas through a jump does nothing, so normal jumps stay safe. Holding a
## trick turns at a steady rate (rad/s); letting go turns the car back to
## level for the rest of the jump so it lands on its wheels.
@export var air_spin_rate := 2.2
@export var air_flip_rate := 6.5
@export var air_roll_rate := 8.0
## Most angular acceleration the air controls can apply (rad/s²).
@export var air_max_accel := 24.0
## Off while menus are open: the car just sits there (auto-hold keeps it still).
var enabled := true

var _steer := 0.0
## Set after a trick in this jump: keep turning the car back to level.
var _righting := false


func _ready() -> void:
	# Run before the vehicle so it sees this tick's input.
	process_physics_priority = -10


## Takes control of `pawn` (a Vehicle), or lets go with null (the player is
## on foot). Called by the Possession.
func control(pawn: Node3D) -> void:
	if vehicle != pawn:
		vehicle = pawn as Vehicle
	_steer = 0.0
	_righting = false


func _physics_process(dt: float) -> void:
	if vehicle == null:
		return
	if not enabled:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = 0.0
		vehicle.handbrake_input = false
		vehicle.steer_input = 0.0
		vehicle.horn_input = false
		vehicle.air_assist_scale = 1.0
		_steer = 0.0
		return
	vehicle.throttle_input = Input.get_action_strength("accelerate")
	vehicle.brake_input = Input.get_action_strength("brake")
	vehicle.handbrake_input = Input.is_action_pressed("handbrake")
	vehicle.horn_input = Input.is_action_pressed("horn")
	var raw := Input.get_axis("steer_left", "steer_right")
	if absf(raw) > 0.0 and absf(raw) < 0.99:
		_steer = raw  # analog stick: use directly
	else:
		_steer = move_toward(_steer, raw, keyboard_steer_speed * dt)
	vehicle.steer_input = _steer
	_air_control(dt)


func _air_control(dt: float) -> void:
	vehicle.air_assist_scale = 1.0
	if vehicle.airtime < 0.15:
		_righting = false
		return
	var tricks := Input.is_action_pressed("handbrake")
	var pitch := (Input.get_action_strength("accelerate") - Input.get_action_strength("brake")) if tricks else 0.0
	var amount := maxf(absf(pitch), absf(_steer))
	var b := vehicle.global_basis
	# Angular velocity in the car's frame: x = pitch (+ = nose up), y = yaw
	# (+ = left), z = roll.
	var av := b.inverse() * vehicle.angular_velocity
	var want := av
	if amount >= 0.05:
		# The leveling assist steps aside while the player is doing tricks.
		vehicle.air_assist_scale = 1.0 - amount if tricks else 1.0 - amount * 0.5
		if tricks:
			want.x = -pitch * air_flip_rate  # brake = nose up = backflip
			want.z = -_steer * air_roll_rate
			_righting = true
		elif vehicle.airtime > 0.5:
			# Only on proper jumps, so steering over small bumps stays normal.
			want.y = -_steer * air_spin_rate
	elif _righting:
		# Let go of a flip/roll: swing back to level (the short way round),
		# leaving any spin alone, so it lands on its wheels.
		vehicle.air_assist_scale = 0.0
		var axis := b.y.cross(Vector3.UP)
		var err := asin(clampf(axis.length(), 0.0, 1.0))
		if b.y.y < 0.0:
			err = PI - err
		var world_want := axis.normalized() * minf(err * 5.0, 7.0) if axis.length() > 0.001 else b.x * 7.0
		want = b.inverse() * world_want
		want.y = av.y
	else:
		return
	var acc := (want - av) * 6.0
	acc = Vector3(clampf(acc.x, -air_max_accel, air_max_accel), clampf(acc.y, -air_max_accel, air_max_accel),
		clampf(acc.z, -air_max_accel, air_max_accel))
	var inertia := vehicle.inertia if vehicle.inertia != Vector3.ZERO else Vector3(2100, 2300, 700)
	vehicle.apply_torque(b * Vector3(acc.x * inertia.x, acc.y * inertia.y, acc.z * inertia.z))


func _unhandled_input(event: InputEvent) -> void:
	if vehicle == null or not enabled:
		return
	if event.is_action_pressed("reset_vehicle"):
		vehicle.reset_upright()


# --- Rumble ---------------------------------------------------------------

func _on_impact(strength: float, _pos: Vector3, _normal: Vector3) -> void:
	# Bigger vehicles shrug off bumps that would rattle a small car.
	var s := clampf(strength / (14000.0 * maxf(vehicle.mass / 1300.0, 1.0)), 0.0, 1.0)
	if s > 0.08:
		rumble(s * 0.6, s, 0.15 + s * 0.35)


func _on_landed(airtime: float) -> void:
	if airtime > 0.4:
		var s := clampf(airtime / 2.5, 0.2, 1.0)
		rumble(s * 0.5, s * 0.9, 0.12 + s * 0.2)


## Vibrates every connected gamepad (if vibration is on in the settings).
func rumble(weak: float, strong: float, duration: float) -> void:
	if not enabled or not Settings.get_value("vibration"):
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
