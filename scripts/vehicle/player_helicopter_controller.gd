class_name PlayerHelicopterController
extends PlayerVehicleController
## Feeds the player's stick into a Helicopter (the "heli" rig; the Possession
## gives it the helicopter the player sits in). Rumble on crashes and
## landings comes from PlayerVehicleController.
##
## Controls, made for a 7-year-old on a gamepad (the same buttons as the
## plane):
## * Up (RT / Shift) and down (LT / Ctrl). Let go of both and it holds its
##   height (assists on).
## * Left stick / W A S D, arrows: forward and back (push forward to fly
##   forward, whatever the "Flying controls" setting says), turn left and
##   right. Let go and it slows to a hover.
## * Trick (A / Space) + stick: a flip (forward / back) or a roll (left /
##   right).
## Far out over the sea it turns itself back toward the island.

## Turn back toward the island beyond this distance from its centre (m).
const TURN_BACK_RADIUS := 950.0
## Keyboard stick keys are digital; this smooths them into a ramp (/s).
const KEY_RAMP := 3.0

## The helicopter being flown (null on foot or in another vehicle).
var heli: Helicopter:
	get:
		return vehicle as Helicopter

var _pitch := 0.0
var _yaw := 0.0
## True while the island boundary is turning the helicopter back.
var turning_back := false


func control(pawn: Node3D) -> void:
	var old := heli
	if old and old != pawn:
		# The helicopter left behind keeps no stick input.
		_clear(old)
	super.control(pawn as Helicopter)
	_pitch = 0.0
	_yaw = 0.0
	turning_back = false


func _clear(h: Helicopter) -> void:
	h.lift_input = 0.0
	h.pitch_input = 0.0
	h.yaw_input = 0.0
	h.roll_input = 0.0
	h.trick_input = false
	h.throttle_input = 0.0
	h.brake_input = 0.0
	h.handbrake_input = false
	h.horn_input = false


func _physics_process(dt: float) -> void:
	var h := heli
	if h == null:
		return
	if not enabled:
		_clear(h)
		_pitch = 0.0
		_yaw = 0.0
		return
	_pitch = _smooth(input.axis("fly_nose_down", "fly_nose_up"), _pitch, dt)
	_yaw = _smooth(input.axis("fly_bank_left", "fly_bank_right"), _yaw, dt)
	h.lift_input = input.strength("fly_power") - input.strength("fly_slow")
	h.throttle_input = maxf(h.lift_input, 0.0)
	h.brake_input = 0.0
	h.handbrake_input = false
	h.horn_input = false
	h.roll_input = 0.0
	h.pitch_input = _pitch
	h.yaw_input = _yaw
	h.trick_input = input.pressed("fly_trick")
	_turn_back(h)


## Analog sticks pass straight through; keys ramp in and out.
func _smooth(raw: float, last: float, dt: float) -> float:
	if absf(raw) > 0.0 and absf(raw) < 0.99:
		return raw
	return move_toward(last, raw, KEY_RAMP * dt)


## Far out over the sea, turns the helicopter round toward the island and
## flies it back in (the player's own stick is overridden until it points in).
func _turn_back(h: Helicopter) -> void:
	var p := h.global_position
	var flat := Vector2(p.x, p.z)
	var nose := h.heading_dir()
	var outward := Vector2(nose.x, nose.z).dot(flat.normalized())
	if flat.length() > TURN_BACK_RADIUS and outward > -0.5:
		turning_back = true
	elif flat.length() < TURN_BACK_RADIUS - 100.0 or outward < -0.9:
		turning_back = false
	if h.on_ground or not turning_back:
		turning_back = turning_back and not h.on_ground
		return
	var to_centre := -flat.normalized()
	var err := Vector2(nose.x, nose.z).angle_to(to_centre)
	# In (x, z) a positive angle turns east toward south: clockwise seen from
	# above, a right turn.
	h.yaw_input = clampf(err * 1.5, -1.0, 1.0)
	h.pitch_input = minf(h.pitch_input, -0.4 if absf(err) < 0.6 else 0.2)
	h.trick_input = false


func _unhandled_input(event: InputEvent) -> void:
	if heli == null or not enabled:
		return
	if input.event_pressed(event, "reset_vehicle"):
		heli.reset_upright()
