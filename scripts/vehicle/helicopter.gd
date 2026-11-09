class_name Helicopter
extends Aircraft
## A light helicopter (scenes/vehicles/helicopter.tscn). It's an Aircraft, so
## getting in and out ("land first!"), the HUD's flight readouts, teleports in
## the air, the island's edge, replays and damage work as for the plane; its
## own rig (Controllable.HELI: PlayerHelicopterController + HeliCamera) flies
## it.
##
## * The rotor spools up for a few seconds after the engine starts (it can't
##   lift off before) and winds down slowly after it stops. Its thrust points
##   along the body's up axis, so the helicopter moves the way it leans.
## * Assists on (kid mode; T / the Assists setting): the stick asks for a
##   speed along the nose (forward, or a little backward) and a turn rate,
##   the triggers for a climb or sink rate. Let go and it slows to a hover and
##   holds its height. It leans into turns by itself (the faster, the wider
##   the turn). Near the ground the sink rate eases off for a soft landing.
##   Trick + stick flips or rolls it once round (high enough up).
## * Assists off: the stick tilts it (it keeps drifting the way it leans
##   until you lean back), the triggers set the rotor's pull directly (lean
##   over and it sinks unless you pull more), tricks spin it freely.
## * On the ground: four skid contact points (raycast "wheels", always
##   braked). It sits still until the climb button lifts it.
##
## Inputs (PlayerHelicopterController): lift_input -1..1 (+ = climb),
## pitch_input (+ = stick back: slow down / back up; - = fly forward),
## yaw_input (+ = turn right), trick_input.
##
## The model's moving parts are found by name under Body (make_heli.py):
## MainRotor (spins about its local Y), TailRotor (local X), RotorDisc and
## TailDisc (the blur discs).

## Vertical speed hold (1/s), horizontal speed hold (1/s).
const LIFT_GAIN := 2.2
const SPEED_GAIN := 0.8
## Attitude -> wanted rotation rate (1/s), and how hard rates are held (1/s).
const TILT_GAIN := 5.0
const RATE_GAIN := 9.0
## Most angular acceleration the rotor can give (rad/s²).
const MAX_ANGULAR_ACCEL := 12.0
## How fast the nose may go down or up (the forward / back push it leans
## for, m/s per second): about 0.7 s to 20°, not a snap.
const LEAN_RATE := 8.0
## Flips and rolls (assists on): rate (rad/s), the height they need (m).
const TRICK_RATE := 5.2
const TRICK_HEIGHT := 10.0
## Assists on: below this height a descent slows to SOFT_SINK (m/s) at the
## ground; hovering lower than LAND_HEIGHT with nothing pressed, it settles
## onto its skids.
const SOFT_HEIGHT := 14.0
const SOFT_SINK := 1.4
const LAND_HEIGHT := 0.6
## Assists off: full stick leans it this far (degrees).
const PRO_TILT := 35.0
## Most bank the assisted turn may use (degrees).
const TURN_BANK := 55.0

@export_group("Helicopter")
## Full stick forward / back (m/s).
@export var max_speed := 55.0
@export var max_back_speed := 9.0
## Full climb / sink with the triggers (m/s).
@export var climb_rate := 9.0
@export var sink_rate := 7.0
## Most forward / backward lean (degrees) when speeding up or slowing down.
@export var max_tilt := 30.0
## Rotor thrust at full speed, as a multiple of the weight.
@export var max_thrust := 2.1
## Full-stick turn rate hovering and at speed (rad/s).
@export var turn_rate := 1.6
@export var fast_turn_rate := 0.8
## Drag area (Cd x A, m²) moving along, and the rotor's resistance to moving
## up and down.
@export var drag_area := 3.2
@export var vertical_drag_area := 9.0
## Seconds for the rotor to reach flying speed, and to stop.
@export var spool_up := 4.5
@export var spool_down := 14.0
## The rotors' real speeds (rpm at full speed; the visuals and blur).
@export var rotor_rpm := 400.0
@export var tail_rotor_rpm := 2300.0
@export var rotor_radius := 5.05
@export var tail_rotor_radius := 0.78

# --- Inputs besides Aircraft's (written by a controller) ---
var lift_input := 0.0

# --- Read-only state ---
## Rotor speed 0..1 (1 = flying speed).
var rotor := 0.0
## Which way the nose points on the map (radians, 0 = -Z), kept through flips.
var heading := 0.0
## Radians left in the flip or roll under way (0 = none).
var trick_left := 0.0

var _trick_axis := Vector3.ZERO
## The forward (+) / back push the nose leans for (m/s²), eased by LEAN_RATE.
var _lean := 0.0
var _main_rotor: Node3D
var _main_rest := Basis.IDENTITY
var _tail_rotor: Node3D
var _tail_rest := Basis.IDENTITY
var _main_angle := 0.0
var _tail_angle := 0.0
var _ghost := 0.0
var _blur_set := false


func _ready() -> void:
	if get_node_or_null("Controllable") == null:
		var c := Controllable.new()
		c.name = "Controllable"
		c.kind = Controllable.HELI
		add_child(c)
	super._ready()
	heading = _yaw_of(global_basis)


func _find_parts() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_main_rotor = body.find_child("MainRotor", true, false) as Node3D
	if _main_rotor:
		_main_rest = _main_rotor.basis
	_tail_rotor = body.find_child("TailRotor", true, false) as Node3D
	if _tail_rotor:
		_tail_rest = _tail_rotor.basis
	for n: String in ["RotorDisc", "TailDisc"]:
		var disc := body.find_child(n, true, false) as MeshInstance3D
		if disc:
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _yaw_of(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


## The nose's direction on the map (unit, horizontal).
func heading_dir() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _physics_process(dt: float) -> void:
	var v := linear_velocity
	forward_speed = v.dot(-global_basis.z)
	airspeed = v.length()
	speed_kmh = airspeed * 3.6
	vertical_speed = v.y
	# The skids: always braked, so it stands still and slides to a stop.
	steer_input = 0.0
	is_braking = false
	for w in wheels:
		w.drive_torque = 0.0
		w.brake_torque = max_brake_torque
		w.handbrake_engaged = false
	var mass_share := mass / maxf(wheels.size(), 1)
	var was_airborne := grounded_wheels == 0
	grounded_wheels = 0
	for w in wheels:
		w.update_physics(dt, mass_share, false, tire_force_height)
		if w.grounded:
			grounded_wheels += 1
	on_ground = grounded_wheels > 0

	_update_rotor(dt)
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


## The rotor spools toward flying speed while the engine runs; the turbine's
## rpm (what the engine sound follows) rises with it, a little more under load.
func _update_rotor(dt: float) -> void:
	engine_running = _audio == null or _audio.engine_running
	if engine_running:
		rotor = move_toward(rotor, 1.0, dt / spool_up)
	else:
		rotor = move_toward(rotor, 0.0, dt / spool_down)
	var target := redline_rpm * 0.9 * rotor
	if engine_running:
		target = lerpf(idle_rpm, redline_rpm * 0.93, rotor) + redline_rpm * 0.07 * throttle
	engine_rpm = move_toward(engine_rpm, target, dt * 3000.0)
	engine_load = throttle


func _fly(dt: float) -> void:
	var b := global_basis.orthonormalized()
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var v := linear_velocity
	var g := 9.81
	var weight := mass * g
	var assists := traction_control
	if up.y > 0.5 and absf(fwd.y) < 0.85 and trick_left <= 0.0:
		heading = _yaw_of(b)
	bank = atan2(-right.y, up.y)
	var speed := v.length()
	climb_angle = asin(clampf(v.y / speed, -1.0, 1.0)) if speed > 0.5 else 0.0
	aoa = 0.0
	sideslip = 0.0
	stall_warning = 0.0

	# What the rotor can give: less with a slow rotor, damage or thin air.
	var breath := clampf((ceiling - global_position.y) / 120.0, 0.0, 1.0)
	var t_max := max_thrust * weight * rotor * rotor * damage_power * lerpf(0.35, 1.0, breath)
	var hd := heading_dir()
	var hr := hd.cross(Vector3.UP)
	var v_h := Vector3(v.x, 0.0, v.z)
	var v_fwd := v_h.dot(hd)
	var lift := clampf(lift_input, -1.0, 1.0)

	# Turning: the stick's turn rate, but never faster than a banked turn at
	# this speed can follow (so the nose doesn't outrun where it's going).
	var lat_lim := g * tan(deg_to_rad(TURN_BANK))
	var rate := lerpf(turn_rate, fast_turn_rate, clampf(absf(v_fwd) / 40.0, 0.0, 1.0))
	rate = minf(rate, maxf(lat_lim * 0.9 / maxf(absf(v_fwd), 1.0), 0.25))
	var yaw_w := -clampf(yaw_input, -1.0, 1.0) * rate

	var want_up := Vector3.UP
	var thrust := 0.0
	var resting := on_ground and lift < 0.1 and trick_left <= 0.0
	if assists:
		var vs_want := lift * (climb_rate if lift > 0.0 else sink_rate)
		if altitude < SOFT_HEIGHT and lift <= 0.0:
			vs_want = maxf(vs_want, -lerpf(SOFT_SINK, sink_rate, altitude / SOFT_HEIGHT))
			if altitude < LAND_HEIGHT and v_h.length() < 3.0 and trick_left <= 0.0:
				vs_want = minf(vs_want, -0.8)
		var a_up := clampf((vs_want - v.y) * LIFT_GAIN, -0.9 * g, 1.2 * g)
		# The stick asks for a speed along the nose; the lean that gets there
		# also holds that speed against the drag.
		var speed_want := -clampf(pitch_input, -1.0, 1.0) * (max_speed if pitch_input < 0.0 else max_back_speed)
		var drag_acc := v_h * (0.5 * AIR_DENSITY * drag_area * v_h.length() / mass)
		var a_h := (hd * speed_want - v_h) * SPEED_GAIN + drag_acc
		var a_f := clampf(a_h.dot(hd), -g * tan(deg_to_rad(max_tilt)), g * tan(deg_to_rad(max_tilt)))
		var a_s := clampf(a_h.dot(hr), -lat_lim, lat_lim)
		if resting:
			a_f = 0.0
			a_s = 0.0
		_lean = move_toward(_lean, a_f, LEAN_RATE * dt)
		want_up = (hd * _lean + hr * a_s + Vector3.UP * (g + a_up)).normalized()
		thrust = mass * (g + a_up) / maxf(up.y, 0.35)
	else:
		# The stick leans it; turns bank by themselves so they stay tidy.
		var lean := -clampf(pitch_input, -1.0, 1.0) * tan(deg_to_rad(PRO_TILT))
		var turn_bank := clampf(v_fwd * -yaw_w / g, -1.0, 1.0)
		_lean = move_toward(_lean, lean * g, LEAN_RATE * dt)
		want_up = (Vector3.UP + hd * (_lean / g) + hr * turn_bank).normalized()
		thrust = weight * (1.0 + 0.85 * lift)

	# Flips and rolls.
	var trick_w := Vector3.ZERO
	var free_spin := false
	if trick_input and not on_ground and rotor > 0.8:
		if not assists:
			free_spin = true
			trick_w = b * Vector3(clampf(pitch_input, -1.0, 1.0) * 3.2, 0.0, -clampf(yaw_input, -1.0, 1.0) * 3.2)
		elif trick_left <= 0.0 and altitude > TRICK_HEIGHT and maxf(absf(pitch_input), absf(yaw_input)) > 0.5:
			trick_left = TAU - 0.35
			if absf(pitch_input) >= absf(yaw_input):
				_trick_axis = Vector3(signf(pitch_input), 0.0, 0.0)
			else:
				_trick_axis = Vector3(0.0, 0.0, -signf(yaw_input))
	if trick_left > 0.0:
		var axis := b * _trick_axis
		trick_w = axis * TRICK_RATE
		trick_left -= absf(angular_velocity.dot(axis)) * dt
		thrust = weight * 0.6
		if on_ground:
			trick_left = 0.0

	if resting:
		thrust = minf(thrust, weight * 0.25)
	thrust = clampf(thrust, 0.0, t_max)
	throttle = move_toward(throttle, minf(thrust / maxf(max_thrust * weight, 1.0) * 1.6, 1.0), dt * 3.0)

	# Forces: rotor thrust along the body's up axis, drag (much more against
	# moving up and down through the rotor).
	var drag := -v_h * (0.5 * AIR_DENSITY * drag_area * v_h.length())
	drag += Vector3.DOWN * signf(v.y) * 0.5 * AIR_DENSITY * vertical_drag_area * v.y * v.y
	apply_central_force(up * thrust + drag)

	# Torque: turn the up axis toward want_up and the nose at yaw_w (or spin
	# for a trick), as hard as the rotor can at its speed. Standing on the
	# skids it leaves them be.
	if resting:
		return
	var w_want := trick_w
	if trick_left <= 0.0 and not free_spin:
		var axis := up.cross(want_up)
		var s := axis.length()
		if s > 1e-4:
			w_want = axis / s * atan2(s, up.dot(want_up)) * TILT_GAIN
		w_want += Vector3.UP * yaw_w
	var dw := (w_want - angular_velocity) * RATE_GAIN
	if dw.length() > MAX_ANGULAR_ACCEL:
		dw = dw.normalized() * MAX_ANGULAR_ACCEL
	var I := inertia if inertia != Vector3.ZERO else Vector3(3600, 3400, 1400)
	var local := b.transposed() * dw
	apply_torque(b * Vector3(local.x * I.x, local.y * I.y, local.z * I.z) * clampf(rotor * rotor * 1.3, 0.0, 1.0))


## R / gamepad Y. On the ground: upright where it is, like a car. In the
## air: level, hovering where it is (lifted clear if it was about to hit the
## ground): a kid's "help!" button.
func reset_upright() -> void:
	if on_ground or altitude < 3.0:
		super.reset_upright()
		return
	place_in_flight(global_position + Vector3.UP * maxf(12.0 - altitude, 0.0), heading_dir())


## Puts the helicopter level at `pos`, nose along `dir`, hovering (or moving
## along `dir` at `speed`), its rotor at flying speed, repaired.
func place_in_flight(pos: Vector3, dir: Vector3, speed := -1.0) -> void:
	teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
	linear_velocity = dir * maxf(speed, 0.0)
	rotor = 1.0
	engine_rpm = redline_rpm * 0.93
	throttle = 0.5
	on_ground = false
	_alt_timer = 0.0


func teleport(xform: Transform3D) -> void:
	super.teleport(xform)
	lift_input = 0.0
	trick_left = 0.0
	_lean = 0.0
	heading = _yaw_of(xform.basis)


# --- Looks ------------------------------------------------------------------

func _process(dt: float) -> void:
	_spin_rotors(dt)
	var lit := 1.0 if engine_running else 0.0
	if lit != _lights_on and _visual:
		_lights_on = lit
		var nav := _visual.material("nav")
		if nav:
			nav.set_shader_parameter("lights", lit)


## The blades turn at their real speed while slow; fast, they turn at a rate
## the eye can follow and the blur discs fade in over them. Two blades look
## like they spin backward past a quarter turn a frame, so at full speed the
## main rotor shows ~22 rad/s (215 rpm) and the tail ~38 rad/s: both safe
## at 30 fps too.
func _spin_rotors(dt: float) -> void:
	var w := rotor * rotor_rpm * TAU / 60.0
	var shown := w if w < 12.0 else 12.0 + (w - 12.0) * 0.35
	_main_angle = wrapf(_main_angle + shown * dt, 0.0, TAU)
	var wt := rotor * tail_rotor_rpm * TAU / 60.0
	var shown_t := wt if wt < 20.0 else 20.0 + (wt - 20.0) * 0.08
	_tail_angle = wrapf(_tail_angle + shown_t * dt, 0.0, TAU)
	_ghost = wrapf(_ghost + minf(w, 30.0) * 0.03 * dt, 0.0, TAU)
	if _main_rotor:
		_main_rotor.basis = _main_rest * Basis(Vector3.UP, _main_angle)
	if _tail_rotor:
		_tail_rotor.basis = _tail_rest * Basis(Vector3.RIGHT, -_tail_angle)
	if _visual == null:
		return
	var main := _visual.material("rotor")
	var tail := _visual.material("tail_rotor")
	if not _blur_set:
		_blur_set = true
		if main:
			main.set_shader_parameter("axis", 1)
			main.set_shader_parameter("radius", rotor_radius)
			main.set_shader_parameter("inner", 0.1)
			main.set_shader_parameter("tip_strength", 0.3)
		if tail:
			tail.set_shader_parameter("axis", 2)
			tail.set_shader_parameter("radius", tail_rotor_radius)
			tail.set_shader_parameter("inner", 0.16)
	if main:
		main.set_shader_parameter("amount", smoothstep(10.0, 34.0, w) * 0.55)
		main.set_shader_parameter("spin", _ghost)
	if tail:
		tail.set_shader_parameter("amount", smoothstep(30.0, 150.0, wt) * 0.8)
		tail.set_shader_parameter("spin", _ghost * 3.0)
