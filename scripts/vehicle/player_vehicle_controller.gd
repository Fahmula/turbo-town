class_name PlayerVehicleController
extends Node
## Feeds player input into a Vehicle and plays gamepad rumble for crashes and
## landings. The vehicle itself doesn't know or care who is driving (traffic
## uses a TrafficDriver instead).

## Swapping this (the garage does) moves input and rumble to the new vehicle.
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
## Off while menus are open: the car just sits there (auto-hold keeps it still).
var enabled := true

var _steer := 0.0


func _ready() -> void:
	# Run before the vehicle so it sees this tick's input.
	process_physics_priority = -10


func _physics_process(dt: float) -> void:
	if vehicle == null:
		return
	if not enabled:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = 0.0
		vehicle.handbrake_input = false
		vehicle.steer_input = 0.0
		vehicle.horn_input = false
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
