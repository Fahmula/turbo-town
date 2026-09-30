class_name PlayerVehicleController
extends Node
## Feeds player input into a Vehicle. Swap this for an AI controller later —
## the vehicle itself doesn't know or care who is driving.

@export var vehicle: Vehicle
## Keyboard steering is digital; this smooths it into a ramp (per second).
@export var keyboard_steer_speed := 5.0

var _steer := 0.0


func _ready() -> void:
	# Run before the vehicle so it sees this tick's input.
	process_physics_priority = -10


func _physics_process(dt: float) -> void:
	if vehicle == null:
		return
	vehicle.throttle_input = Input.get_action_strength("accelerate")
	vehicle.brake_input = Input.get_action_strength("brake")
	vehicle.handbrake_input = Input.is_action_pressed("handbrake")
	var raw := Input.get_axis("steer_left", "steer_right")
	if absf(raw) > 0.0 and absf(raw) < 0.99:
		_steer = raw  # analog stick: use directly
	else:
		_steer = move_toward(_steer, raw, keyboard_steer_speed * dt)
	vehicle.steer_input = _steer


func _unhandled_input(event: InputEvent) -> void:
	if vehicle == null:
		return
	if event.is_action_pressed("reset_vehicle"):
		vehicle.reset_upright()
