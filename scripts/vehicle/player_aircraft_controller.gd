class_name PlayerAircraftController
extends PlayerVehicleController
## Feeds the player's stick into an Aircraft (the "plane" rig; the
## Possession gives it the plane the player sits in). Rumble on crashes and
## landings comes from PlayerVehicleController.
##
## Controls, made for a 7-year-old on a gamepad:
## * Power (RT / Shift): hold for full power. Let go in the air and the plane
##   cruises on its own; on the ground it idles (and the brakes hold it when
##   it stops).
## * Slow down (LT / Ctrl): wheel brakes on the ground; in the air the
##   engine idles and the flaps and airbrake come out (for landing).
## * Left stick / W A S D, arrows: bank left and right (steers on the
##   ground), and the nose: pull back (S, stick down) to climb, push to
##   dive. "Flying controls" in Settings swaps that (push to climb). With
##   assists on the stick banks up to 65 degrees and the wings level when
##   it's let go.
## * Trick (A / Space) + stick left or right: roll all the way round.
## Far out over the sea the plane turns itself back toward the island.

## Turn back toward the island beyond this distance from its centre (m).
const TURN_BACK_RADIUS := 950.0
## Keyboard pitch / roll are digital; this smooths them into a ramp (/s).
const KEY_RAMP := 3.5

## The plane being flown (null on foot or in a road vehicle).
var aircraft: Aircraft:
	get:
		return vehicle as Aircraft

var _pitch := 0.0
var _roll := 0.0
## True while the island boundary is turning the plane back.
var turning_back := false


func control(pawn: Node3D) -> void:
	var old := aircraft
	if old and old != pawn:
		# The plane left behind keeps no stick input (control surfaces centre).
		old.pitch_input = 0.0
		old.roll_input = 0.0
		old.yaw_input = 0.0
		old.trick_input = false
	super.control(pawn as Aircraft)
	_pitch = 0.0
	_roll = 0.0
	turning_back = false


func _physics_process(dt: float) -> void:
	var a := aircraft
	if a == null:
		return
	if not enabled:
		a.pitch_input = 0.0
		a.roll_input = 0.0
		a.yaw_input = 0.0
		a.brake_input = 0.0
		a.handbrake_input = false
		a.trick_input = false
		a.throttle_input = a.cruise_throttle if not a.on_ground else 0.0
		_pitch = 0.0
		_roll = 0.0
		return
	var pitch := _smooth(Input.get_axis("fly_nose_down", "fly_nose_up"), _pitch, dt)
	_pitch = pitch
	var roll := _smooth(Input.get_axis("fly_bank_left", "fly_bank_right"), _roll, dt)
	_roll = roll
	if Settings.get_value("flight_invert"):
		pitch = -pitch
	var power := Input.get_action_strength("fly_power")
	var slow := Input.get_action_strength("fly_slow")
	var throttle := lerpf(0.0 if a.on_ground else a.cruise_throttle, 1.0, power)
	a.throttle_input = lerpf(throttle, 0.0, slow)
	a.brake_input = slow
	a.handbrake_input = false
	a.horn_input = false
	a.yaw_input = 0.0
	a.trick_input = Input.is_action_pressed("fly_trick")
	a.pitch_input = pitch
	a.roll_input = roll
	_turn_back(a)


## Analog sticks pass straight through; keys ramp in and out.
func _smooth(raw: float, last: float, dt: float) -> float:
	if absf(raw) > 0.0 and absf(raw) < 0.99:
		return raw
	return move_toward(last, raw, KEY_RAMP * dt)


## Far out over the sea, banks the plane round toward the island (the
## player's own roll is overridden until it points back in).
func _turn_back(a: Aircraft) -> void:
	var p := a.global_position
	var flat := Vector2(p.x, p.z)
	var heading := Vector2(a.linear_velocity.x, a.linear_velocity.z)
	if a.on_ground or heading.length() < 5.0:
		turning_back = false
		return
	var outward := heading.normalized().dot(flat.normalized())
	if flat.length() > TURN_BACK_RADIUS and outward > -0.5:
		turning_back = true
	elif flat.length() < TURN_BACK_RADIUS - 100.0 or outward < -0.9:
		turning_back = false
	if not turning_back:
		return
	# Bank about 35 degrees toward the island's centre.
	var to_centre := -flat.normalized()
	var err := heading.normalized().angle_to(to_centre)
	# In (x, z) a positive angle turns east toward south: clockwise seen from
	# above, a right turn, so a right bank (+).
	var want_bank := clampf(err * 1.2, -0.6, 0.6)
	a.roll_input = clampf((want_bank - a.bank) * 2.0, -1.0, 1.0)
	a.pitch_input = maxf(a.pitch_input, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if aircraft == null or not enabled:
		return
	if event.is_action_pressed("reset_vehicle"):
		aircraft.reset_upright()
