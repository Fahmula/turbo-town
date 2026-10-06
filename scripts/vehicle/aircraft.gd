class_name Aircraft
extends Vehicle
## A propeller plane (scenes/vehicles/plane.tscn). It's a Vehicle, so its
## wheels, damage, sound, getting in and out, the HUD, the maps and replays
## work as they do for a car; its engine turns a propeller instead of the
## wheels, and aerodynamics fly it:
##
## * Forces: lift from the wing at its angle of attack (falling away past the
##   stall), drag (parasitic, induced, flaps and airbrake, and a wall past
##   ~250 km/h), a side force against sideslip, and propeller thrust that
##   fades with airspeed and near the ceiling.
## * Controls, fly-by-wire style: the stick asks for what the plane can
##   really do. Pitch asks for g: pull = more lift, the path curves up. With
##   assists on (the T key / Settings) a released stick holds the climb or
##   dive and eases it toward level, turns don't sink, and the wings level
##   themselves; with them off, a released stick is a plain 1 g and the nose
##   drops in turns. Lift is limited by the stall, so a slow plane can't pull
##   hard, and a stall mushes down nose-high until speed comes back (no
##   spins). The nose follows the airflow, so banking turns the plane.
##   Control authority grows with airspeed.
## * On the ground: three raycast wheels; the roll stick steers the nose
##   wheel, brake_input brakes the main wheels, and pulling back at speed
##   lifts the nose until the wing lifts the plane off.
##
## Inputs (PlayerAircraftController): throttle_input 0..1 (engine power),
## pitch_input (+ = nose up), roll_input (+ = right), yaw_input (rudder,
## + = right), brake_input (slow down: wheel brakes on the ground, flaps and
## airbrake in the air), handbrake_input (parking brake), trick_input (with
## assists on, the stick banks to ASSIST_BANK and holds it; with the trick
## held it rolls the plane all the way round).
##
## The model's moving parts are found by name under Body (make_plane.py):
## Propeller, PropDisc, AileronL/R, FlapL/R, Elevator, Rudder.

const AIR_DENSITY := 1.225
## Dynamic pressure at which the controls have full authority (~40 m/s).
const Q_FULL := 980.0
## A released stick (assists on) turns a climb or dive toward level this
## fast (1/s), and rolls the wings level this fast.
const LEVEL_RATE := 0.22
const ROLL_LEVEL_RATE := 1.8
## Landing (assists on): below this height with the power off, a released
## stick lets the plane settle onto its wheels at about SETTLE_SINK m/s
## instead of holding its height (flaring if it comes in steeper).
const SETTLE_HEIGHT := 7.0
const SETTLE_SINK := 2.0
## Speed protection (assists on): below this airspeed (m/s) a released stick
## lowers the nose to get speed back, so letting go after a steep climb
## never stalls the plane.
const SAFE_SPEED := 30.0
## With assists on, full stick banks this far (degrees) and holds the turn;
## trick_input (hold) rolls freely.
const ASSIST_BANK := 65.0
## Control surface throws for the visuals (radians).
const ELEVATOR_THROW := 0.38
const AILERON_THROW := 0.32
const RUDDER_THROW := 0.4
const FLAP_THROW := 0.6

@export_group("Flight")
@export var wing_area := 16.0
## Lift coefficient per radian of angle of attack, and at zero (camber and
## the wing's incidence).
@export var lift_slope := 5.0
@export var lift_zero := 0.22
@export var stall_angle := 15.0
@export var drag_zero := 0.026
@export var drag_induced := 0.05
@export var side_area := 5.0
## Propeller thrust standing still at full power (N); it fades to nothing at
## thrust_fade_speed (m/s).
@export var static_thrust := 2700.0
@export var thrust_fade_speed := 100.0
@export var max_g := 4.5
@export var min_g := -1.5
## Full-stick roll rate (rad/s) and rudder yaw rate.
@export var roll_rate := 2.6
@export var yaw_rate := 0.45
## Speed and power the plane cruises at with no power asked for (teleports
## and "help!" put it in the air at cruise_speed).
@export var cruise_speed := 47.0
@export var cruise_throttle := 0.55
@export var flap_lift := 0.35
@export var airbrake_drag := 0.05
## Above this height (m) the engine runs out of breath (a soft ceiling).
@export var ceiling := 650.0
## Most nose-up attitude on the ground (degrees): the tail stays off the runway.
@export var max_ground_pitch := 12.0
## The fuselage's half width: doors and exits go by it, not by the wings.
@export var fuselage_half_width := 0.58
## The landing light, in the left wing's leading edge (local).
@export var landing_light := Vector3(-1.45, 0.62, -0.6)

# --- Inputs besides Vehicle's (written by a controller) ---
var pitch_input := 0.0
var roll_input := 0.0
var yaw_input := 0.0
var trick_input := false

# --- Read-only state ---
var airspeed := 0.0
## Angle of attack and sideslip (radians).
var aoa := 0.0
var sideslip := 0.0
## Bank angle (+ = right wing down) and the flight path's climb angle.
var bank := 0.0
var climb_angle := 0.0
var vertical_speed := 0.0
## Height above the ground (or the sea) under the plane, metres.
var altitude := 0.0
var on_ground := true
## Engine power 0..1 (follows throttle_input with a short spool).
var throttle := 0.0
var flaps := 0.0
## 0..1: how close the wing is to stalling (HUD warning, buffet).
var stall_warning := 0.0
var engine_running := true

var _audio: VehicleAudio
var _visual: VehicleBodyVisual
var _prop: Node3D
var _prop_rest := Basis.IDENTITY
var _prop_angle := 0.0
var _ghost_angle := 0.0
var _disc: MeshInstance3D
## Control surface name -> [node, rest basis, hinge axis, current angle].
var _surfaces := {}
var _alt_timer := 0.0
var _ride := 0.2
var _lights_on := -1.0


func _ready() -> void:
	if get_node_or_null("Controllable") == null:
		var c := Controllable.new()
		c.name = "Controllable"
		c.kind = Controllable.PLANE
		add_child(c)
	super._ready()
	# The wings set the footprint (where you can walk up to it); doors,
	# exits and the contact shadow go by the fuselage.
	footprint_half_width = body_half_width
	body_half_width = fuselage_half_width
	auto_reverse = false
	air_stabilization = 0.0
	_ride = ride_height()
	_audio = get_node_or_null("Audio") as VehicleAudio
	_visual = get_node_or_null("Body") as VehicleBodyVisual
	_find_parts()
	make_landing_light()


func _find_parts() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_prop = body.find_child("Propeller", true, false) as Node3D
	if _prop:
		_prop_rest = _prop.basis
	_disc = body.find_child("PropDisc", true, false) as MeshInstance3D
	if _disc:
		_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n: String in ["AileronL", "AileronR", "FlapL", "FlapR", "Elevator", "Rudder"]:
		var node := body.find_child(n, true, false) as Node3D
		if node:
			_surfaces[n] = [node, node.basis, Vector3.UP if n == "Rudder" else Vector3.RIGHT, 0.0]


## The landing light (a "Headlights" node like a car's, so the Game turns it
## on after dark while flying).
func make_landing_light() -> Node3D:
	var lights := get_node_or_null("Headlights") as Node3D
	if lights:
		return lights
	lights = Node3D.new()
	lights.name = "Headlights"
	lights.visible = false
	add_child(lights)
	var spot := SpotLight3D.new()
	spot.position = landing_light
	spot.rotation = Vector3(deg_to_rad(-3.0), 0.0, 0.0)
	spot.spot_range = 110.0
	spot.spot_angle = 20.0
	spot.light_energy = 7.0
	spot.light_color = Color(1.0, 0.96, 0.88)
	lights.add_child(spot)
	return lights


func _physics_process(dt: float) -> void:
	var v := linear_velocity
	forward_speed = v.dot(-global_basis.z)
	airspeed = v.length()
	speed_kmh = airspeed * 3.6
	vertical_speed = v.y

	_update_ground_controls(dt)
	var mass_share := mass / maxf(wheels.size(), 1)
	var was_airborne := grounded_wheels == 0
	grounded_wheels = 0
	for w in wheels:
		w.update_physics(dt, mass_share, false, tire_force_height)
		if w.grounded:
			grounded_wheels += 1
	on_ground = grounded_wheels > 0

	_update_engine(dt)
	_fly(dt)
	_update_air(dt, was_airborne)
	_update_altitude(dt)

	if global_basis.y.y < 0.2 and airspeed < 3.0:
		upside_down_time += dt
	else:
		upside_down_time = 0.0
	if _pending_impact > 0.0:
		impact.emit(_pending_impact, _pending_impact_pos, _pending_impact_normal)
		_pending_impact = 0.0


## Nose wheel steering (the roll stick and the rudder), the main wheels'
## brakes, and a parking hold when it's stopped with no power.
func _update_ground_controls(dt: float) -> void:
	steer_input = clampf(roll_input + yaw_input, -1.0, 1.0)
	_update_steering(dt)
	is_braking = brake_input > 0.05
	var hold := throttle_input < 0.05 and absf(forward_speed) < 0.6 and brake_input < 0.05
	for w in wheels:
		w.drive_torque = 0.0
		w.handbrake_engaged = handbrake_input
		var bt := 0.0
		if not w.steers:
			bt = brake_input * max_brake_torque
			if hold:
				bt = max_brake_torque
		w.brake_torque = bt


## Engine power spools toward the throttle; the propeller's rpm (what the
## engine sound follows) runs from idle to the redline with power, and a
## little higher in a fast dive.
func _update_engine(dt: float) -> void:
	engine_running = _audio == null or _audio.engine_running
	var want := clampf(throttle_input, 0.0, 1.0) * damage_power if engine_running else 0.0
	throttle = move_toward(throttle, want, dt * (0.9 if want > throttle else 1.4))
	engine_load = throttle
	var target := 0.0
	if engine_running:
		target = lerpf(idle_rpm, redline_rpm, throttle) + maxf(airspeed - 30.0, 0.0) * 6.0 * (1.0 - throttle)
	engine_rpm = move_toward(engine_rpm, minf(target, redline_rpm * 1.04), dt * (1100.0 if engine_running else 450.0))


func _lift_coefficient(a: float) -> float:
	var stall := deg_to_rad(stall_angle)
	var neg_stall := -deg_to_rad(stall_angle * 0.8)
	if a > stall:
		# Past the stall the lift falls away to a flat plate's.
		return lerpf(lift_zero + lift_slope * stall, 0.9 * sin(2.0 * a), clampf((a - stall) / deg_to_rad(12.0), 0.0, 1.0))
	if a < neg_stall:
		return lerpf(lift_zero + lift_slope * neg_stall, 0.9 * sin(2.0 * a), clampf((neg_stall - a) / deg_to_rad(12.0), 0.0, 1.0))
	return lift_zero + lift_slope * a


func _fly(dt: float) -> void:
	var b := global_basis.orthonormalized()
	var inv := b.inverse()
	var right := b.x
	var up := b.y
	var fwd := -b.z
	var v := linear_velocity
	var speed := v.length()
	var dir := v / speed if speed > 0.5 else fwd
	var local_v := inv * v
	var q := 0.5 * AIR_DENSITY * speed * speed
	if speed > 0.5:
		aoa = atan2(-local_v.y, maxf(-local_v.z, 0.5))
		sideslip = atan2(local_v.x, maxf(-local_v.z, 0.5))
	else:
		aoa = 0.0
		sideslip = 0.0
	bank = atan2(-right.y, up.y)
	climb_angle = asin(clampf(dir.y, -1.0, 1.0))
	# The slow-down control lowers the flaps and opens the airbrake in the
	# air (slower, steeper approaches); they tuck away on the ground.
	var slow := 0.0 if on_ground else clampf(brake_input, 0.0, 1.0)
	flaps = move_toward(flaps, slow, dt * 0.8)

	# --- Forces ---
	var weight := mass * 9.81
	var cl := _lift_coefficient(aoa) + flaps * flap_lift
	var lift := Vector3.ZERO
	var drag := Vector3.ZERO
	var side := Vector3.ZERO
	if speed > 0.5:
		lift = right.cross(dir).normalized() * q * wing_area * cl
		var over := maxf(speed - 70.0, 0.0)
		var cd := drag_zero + drag_induced * cl * cl + flaps * 0.03 + slow * airbrake_drag
		drag = -dir * (q * wing_area * cd + over * over * 8.0)
		side = -right * q * side_area * clampf(sideslip, -0.6, 0.6) * 1.2
	var breath := clampf((ceiling - global_position.y) / 120.0, 0.0, 1.0)
	var thrust := fwd * static_thrust * throttle * clampf(1.0 - speed / thrust_fade_speed, 0.0, 1.0) * breath
	apply_central_force(lift + drag + side + thrust)
	stall_warning = 0.0 if on_ground or speed < 4.0 else smoothstep(deg_to_rad(stall_angle - 3.5), deg_to_rad(stall_angle), aoa)

	# --- Controls: the rate each axis should turn at (body axes) ---
	var w_local := inv * angular_velocity
	var pitch_now := w_local.x       # + = nose up
	var yaw_now := -w_local.y        # + = nose right
	var roll_now := -w_local.z       # + = rolling right
	var want_pitch := 0.0
	var want_yaw := 0.0
	var want_roll := 0.0
	var authority := clampf(q / Q_FULL, 0.0, 1.3)
	var assists := traction_control
	if on_ground:
		# The elevator sits in the propeller's blast: it can lift the nose
		# wheel well before the wing flies.
		authority = clampf(q / (Q_FULL * 0.45), 0.0, 1.3)
		# Rotate for take-off only when asked, and keep the tail off the runway.
		var nose := asin(clampf(fwd.y, -1.0, 1.0))
		if pitch_input > 0.05 and nose < deg_to_rad(max_ground_pitch):
			want_pitch = pitch_input * 0.5
	else:
		authority = maxf(authority, 0.08)
		# Pitch: the stick asks for g. Released (assists), it holds the path,
		# eases it toward level and pulls just enough to keep turns level.
		var neutral := cos(climb_angle)
		if assists:
			var target := 0.0
			var rate := LEVEL_RATE
			if altitude < SETTLE_HEIGHT and throttle < 0.35:
				target = -asin(clampf(SETTLE_SINK / maxf(speed, 1.0), 0.0, 0.25))
				rate = 0.9
			elif speed < SAFE_SPEED:
				var low := clampf((SAFE_SPEED - speed) / 10.0, 0.0, 1.0)
				target = -0.3 * low
				rate = lerpf(LEVEL_RATE, 0.7, low)
			var hold := cos(climb_angle) - rate * (climb_angle - target) * speed / 9.81
			neutral = clampf(hold / maxf(cos(bank), 0.5), -0.5, 2.0) if absf(bank) < PI * 0.5 else 0.5
		var g := neutral + (pitch_input * (max_g - neutral) if pitch_input > 0.0 else pitch_input * (neutral - min_g))
		var aoa_want := (g * weight / maxf(q * wing_area, 1.0) - lift_zero - flaps * flap_lift) / lift_slope
		aoa_want = clampf(aoa_want, -deg_to_rad(stall_angle * 0.8 - 1.0), deg_to_rad(stall_angle - 1.0))
		# The path's own turn rate (lift and gravity bend it): the nose
		# follows it, plus a correction toward the angle of attack wanted.
		var acc := (lift + side + thrust + drag) / mass + Vector3.DOWN * 9.81
		var turn := inv * (dir.cross(acc - dir * acc.dot(dir)) / maxf(speed, 5.0))
		want_pitch = turn.x + (aoa_want - aoa) * 4.0
		want_yaw = -turn.y + sideslip * 3.0 + yaw_input * yaw_rate
		if not assists or trick_input:
			want_roll = roll_input * roll_rate
		elif absf(fwd.y) > 0.85 or (pitch_input > 0.5 and absf(roll_input) < 0.05):
			# Going vertical, or pulling through a loop: leave the wings be
			# (levelling them at the top would turn the loop into a half one).
			want_roll = roll_input * roll_rate
		else:
			# The stick sets the bank, up to ASSIST_BANK; let go and the
			# wings come level (upside down, the short way round).
			var target := roll_input * deg_to_rad(ASSIST_BANK) if absf(bank) < PI * 0.6 else 0.0
			want_roll = clampf((target - bank) * 2.5, -roll_rate, roll_rate)
			if absf(roll_input) < 0.05:
				want_roll = clampf(-bank * ROLL_LEVEL_RATE, -roll_rate * 0.6, roll_rate * 0.6)
	# Each axis turns toward its rate as hard as its control surface can at
	# this airspeed (on the ground the wheels steer, so no roll or yaw).
	var I := inertia if inertia != Vector3.ZERO else Vector3(1400, 2200, 1100)
	var acc_pitch := clampf((want_pitch - pitch_now) * 8.0, -7.0, 7.0) * authority
	var acc_yaw := 0.0 if on_ground else clampf((want_yaw - yaw_now) * 6.0, -4.0, 4.0) * authority
	var acc_roll := 0.0 if on_ground else clampf((want_roll - roll_now) * 8.0, -12.0, 12.0) * authority
	apply_torque(b * Vector3(acc_pitch * I.x, -acc_yaw * I.y, -acc_roll * I.z))


## Height above whatever is under the plane (a ray every 0.1 s, dead
## reckoning in between).
func _update_altitude(dt: float) -> void:
	_alt_timer -= dt
	if _alt_timer > 0.0:
		altitude = maxf(altitude + vertical_speed * dt, 0.0)
		return
	_alt_timer = 0.1
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2000.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground := MapLayout.SEA_LEVEL
	if not hit.is_empty():
		ground = maxf((hit["position"] as Vector3).y, MapLayout.SEA_LEVEL)
	altitude = maxf(from.y - ground - _ride, 0.0)


## R / gamepad Y. On the ground: upright where it is, like a car. In the
## air: levelled out where it is (a little higher if it was about to hit
## the ground) with flying speed: a kid's "help!" button.
func reset_upright() -> void:
	if on_ground or altitude < 4.0:
		super.reset_upright()
		return
	var heading := linear_velocity if linear_velocity.length() > 5.0 else -global_basis.z
	heading.y = 0.0
	if heading.length() < 0.1:
		heading = Vector3.FORWARD
	place_in_flight(global_position + Vector3.UP * maxf(40.0 - altitude, 0.0), heading.normalized())


## Puts the plane in level flight at `pos`, flying along `heading` at
## `speed` (cruise speed by default), repaired.
func place_in_flight(pos: Vector3, heading: Vector3, speed := -1.0) -> void:
	teleport(Transform3D(Basis.looking_at(heading, Vector3.UP), pos))
	linear_velocity = heading * (cruise_speed if speed < 0.0 else speed)
	throttle = cruise_throttle
	engine_rpm = lerpf(idle_rpm, redline_rpm, throttle)
	flaps = 0.0
	on_ground = false
	_alt_timer = 0.0


func teleport(xform: Transform3D) -> void:
	super.teleport(xform)
	throttle = 0.0
	flaps = 0.0
	pitch_input = 0.0
	roll_input = 0.0
	yaw_input = 0.0
	trick_input = false
	_alt_timer = 0.0


# --- Looks ------------------------------------------------------------------

func _process(dt: float) -> void:
	_spin_propeller(dt)
	_move_surfaces(dt)
	var lit := 1.0 if engine_running else 0.0
	if lit != _lights_on and _visual:
		_lights_on = lit
		var nav := _visual.material("nav")
		if nav:
			nav.set_shader_parameter("lights", lit)


## The blades turn at their real speed while slow; fast, they turn at a
## rate the eye can follow and the blur disc fades in over them.
func _spin_propeller(dt: float) -> void:
	var w := engine_rpm * TAU / 60.0
	var shown := w if w < 30.0 else 30.0 + (w - 30.0) * 0.06
	_prop_angle = wrapf(_prop_angle + shown * dt, 0.0, TAU)
	_ghost_angle = wrapf(_ghost_angle + minf(w, 40.0) * 0.035 * dt, 0.0, TAU)
	if _prop:
		_prop.basis = _prop_rest * Basis(Vector3.BACK, -_prop_angle)
	if _visual:
		var disc := _visual.material("prop")
		if disc:
			disc.set_shader_parameter("amount", smoothstep(22.0, 95.0, w) * 0.9)
			disc.set_shader_parameter("spin", _ghost_angle)


func _move_surfaces(dt: float) -> void:
	if _surfaces.is_empty():
		return
	var rudder := steer_input if on_ground else yaw_input + roll_input * 0.25
	var want := {
		"Elevator": -pitch_input * ELEVATOR_THROW,
		"AileronL": roll_input * AILERON_THROW,
		"AileronR": -roll_input * AILERON_THROW,
		"FlapL": flaps * FLAP_THROW,
		"FlapR": flaps * FLAP_THROW,
		"Rudder": clampf(rudder, -1.0, 1.0) * RUDDER_THROW,
	}
	for n: String in _surfaces:
		var s: Array = _surfaces[n]
		var angle := move_toward(float(s[3]), float(want[n]), dt * 2.2)
		if angle == float(s[3]) and dt > 0.0:
			continue
		s[3] = angle
		(s[0] as Node3D).basis = (s[1] as Basis) * Basis(s[2] as Vector3, angle)
