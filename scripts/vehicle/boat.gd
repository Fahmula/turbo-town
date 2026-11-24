class_name Boat
extends Vehicle
## A speedboat (scenes/vehicles/boat.tscn). It's a Vehicle, so the car's
## controls (PlayerVehicleController) and chase camera, getting in and out,
## the HUD, damage, fuel, sound, replays and stunts work as they do for a car;
## instead of wheels it floats on the sea (MapLayout.SEA_LEVEL, flat water):
##
## * Buoyancy: `float_points` on the hull (the keel, the chines and the
##   topsides at five stations), each pushing up with the water it displaces
##   (its `float_areas` x how far it is under the surface, up to the sheer),
##   damped, so it bobs, heels and pitches like a hull. At start the areas are
##   scaled so it floats with its origin on the water, and the centre of mass
##   goes over the centre of buoyancy (level trim).
## * Water: little drag along the hull, a lot across it (the keel), so it
##   carves its turns; planing lift that lifts the hull out of the water at
##   speed (less of it wet = less drag) with the bow up for a moment on the
##   way; air drag.
## * The outboard: thrust at the propeller while it's in the water (out of it
##   the engine just revs). Throttle goes forward; the brake pulls the lever
##   back (reverse thrust slows it down) and, nearly stopped, backs up.
## * Steering (made for a 7-year-old): the stick asks for a turn rate (it
##   turns a little even sitting still, for docking), and the hull leans into
##   the turn. The handbrake button (A / Space) lets the hull slide sideways:
##   a power slide with a spray.
## * Assists on (T / the Assists setting): it never capsizes for long (rights
##   itself after a moment upside down), and the help button puts it back on
##   the water: upright where it floats, or off a beach into the nearest open
##   water.
## * Nobody at the helm: it lies still as if moored (no drifting off).
##
## Inputs (PlayerVehicleController, a car's): throttle_input, brake_input,
## steer_input, handbrake_input (slide), horn_input.
##
## The model's moving parts are found by name under Body (make_boat.py):
## Outboard (turns about its local Y with the steering) and Propeller (its
## child, spins about its local Z).

const RHO := 1025.0
const G := 9.81
## Vertical damping of each float point, as seconds of its stiffness (heave
## about half critically damped).
const FLOAT_DAMP := 0.16
## The sideways grip left while sliding (handbrake), as a fraction.
const SLIDE_GRIP := 0.22
## Below this the propeller bites (m under the surface, a little above too).
const PROP_BITE := 0.25
## Assists on: upside down (or on its side) this long in the water, it rights
## itself (s).
const SELF_RIGHT_TIME := 2.2
## Stuck on land (no water under the hull, touching the ground, slow) this
## long counts as stranded: the HUD says how to get back in (s).
const STRANDED_TIME := 1.5
## Open water deep enough for the boat (m below the surface) when looking for
## a spot to put it (garage, teleports, the help button).
const SPOT_DEPTH := 1.3
## Far out at sea (m from the island's middle) a driven boat turns itself
## back toward the island, like the plane and the helicopter.
const TURN_BACK_RADIUS := 900.0

@export_group("Hull")
## Buoyancy sample points (local) and the water-plane area each stands for
## (m², scaled at start: see the class comment). From make_boat.py.
@export var float_points := PackedVector3Array()
@export var float_areas := PackedFloat32Array()
## The sheer (top of the hull side) above the origin: a float point stops
## adding buoyancy once the water reaches it.
@export var sheer_height := 0.85
## Height of the centre of mass above the waterline (m).
@export var com_height := 0.08
## The convex hull of the boat's collision shapes (local), for its size.
@export var hull_points := PackedVector3Array()

@export_group("Water")
## Drag along the hull: N per m/s and per (m/s)², times how much of the hull
## is wet. HUMP adds to the square term around HUMP_SPEED (the "getting on
## the plane" hump).
@export var drag_linear := 120.0
@export var drag_quadratic := 4.2
## Off the throttle the hull settles and the bow drops: the drag along it
## grows by this much (lets go = it slows down soon, kid-friendly).
@export var coast_drag := 1.0
@export var hump := 2.0
@export var hump_speed := 6.5
## Grip across the hull (the keel): N per m/s and per (m/s)².
@export var side_linear := 2600.0
@export var side_quadratic := 900.0
## Where that sideways grip acts, behind the centre of mass (m).
@export var side_grip_aft := 0.55
## Planing lift at full plane as a fraction of the weight, and the speeds
## (m/s) where it starts and is full.
@export var plane_lift := 0.42
@export var plane_from := 3.0
@export var plane_full := 12.0
@export var air_drag_area := 1.1

@export_group("Outboard")
## Thrust standing still at full throttle (N); it fades to nothing at
## prop_speed (m/s): the top speed is where it meets the drag.
@export var max_thrust := 9000.0
@export var prop_speed := 31.0
@export var reverse_thrust := 0.45
## The propeller (local): thrust acts here.
@export var prop_point := Vector3(0.0, -0.5, 3.47)
## The motor turns this far (degrees) with full steering.
@export var max_rudder := 30.0

@export_group("Handling")
## Full-stick turn rate (rad/s) standing still, at `turn_peak_speed` and at
## top speed.
@export var turn_rate_still := 0.45
@export var turn_rate_peak := 1.15
@export var turn_peak_speed := 7.0
@export var turn_rate_fast := 0.78
@export var top_speed := 22.0
## Lean into turns: degrees of bank per (m/s x rad/s) and at most.
@export var bank_gain := 1.0
@export var max_bank := 16.0

# --- Read-only state ---
## Fraction of the hull's resting displacement under water now (0 = out of
## the water, about 1 at rest, less when planing).
var wet := 0.0
## The motor's angle (degrees, + = steering right).
var rudder := 0.0
## How far the propeller is in the water (0..1).
var prop_bite := 0.0
## Seconds stuck on land (see STRANDED_TIME).
var stuck_time := 0.0
## Bank angle (radians, + = right side down).
var bank := 0.0
## True while the island's edge is turning it back (the HUD says so).
var turning_back := false

var _k := PackedFloat32Array()
var _rest_wet := 1.0
var _float_max := PackedFloat32Array()
var _outboard: Node3D
var _outboard_rest := Basis.IDENTITY
var _prop: Node3D
var _prop_rest := Basis.IDENTITY
var _prop_angle := 0.0
var _visual: VehicleBodyVisual
var _audio: VehicleAudio
var _lights_on := -1.0
var _capsized_time := 0.0
## Touching a jump ramp this tick (no sand drag on it).
var _on_ramp := false


func _ready() -> void:
	super._ready()
	auto_hold = false
	air_stabilization = 1.0
	_visual = get_node_or_null("Body") as VehicleBodyVisual
	_audio = get_node_or_null("Audio") as VehicleAudio
	_setup_floats()
	_find_parts()
	_make_light()


## Scales the float areas so the boat floats with its origin on the water,
## and puts the centre of mass over the centre of buoyancy.
func _setup_floats() -> void:
	var n := mini(float_points.size(), float_areas.size())
	var vol := 0.0
	var moment := 0.0
	for i in n:
		var d := maxf(-float_points[i].y, 0.0)
		vol += float_areas[i] * d
		moment += float_areas[i] * d * float_points[i].z
	var scale := mass / (RHO * vol) if vol > 0.0 else 1.0
	_k.resize(n)
	_float_max.resize(n)
	_rest_wet = 0.0
	for i in n:
		_k[i] = RHO * G * float_areas[i] * scale
		_float_max[i] = maxf(sheer_height - float_points[i].y, 0.1)
		_rest_wet += _k[i] * maxf(-float_points[i].y, 0.0)
	_rest_wet = maxf(_rest_wet, 1.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, com_height, moment / vol if vol > 0.0 else 0.0)


## The boat's size from its hull points (and the motor behind the transom):
## Vehicle's measure only reads boxes.
func _measure_body() -> void:
	if hull_points.is_empty():
		super._measure_body()
		return
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in hull_points:
		lo = lo.min(p)
		hi = hi.max(p)
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size * 0.5
			lo = lo.min(cs.position - h)
			hi = hi.max(cs.position + h)
	body_front = -lo.z
	body_rear = maxf(hi.z, prop_point.z + 0.15)
	body_half_width = maxf(absf(lo.x), hi.x)
	footprint_half_width = body_half_width
	body_top = hi.y


## Standing on solid ground (the garage's turntable, a beach) it rests on its
## keel: the origin (the water line) is this far up. On the water the origin
## is on the surface.
func ride_height() -> float:
	var low := 0.0
	for p in hull_points:
		low = minf(low, p.y)
	return -low


func _find_parts() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	_outboard = body.find_child("Outboard", true, false) as Node3D
	if _outboard:
		_outboard_rest = _outboard.basis
	_prop = body.find_child("Propeller", true, false) as Node3D
	if _prop:
		_prop_rest = _prop.basis


## A searchlight on the foredeck (a "Headlights" node like a car's, so the
## Game turns it on after dark while you drive).
func _make_light() -> void:
	if get_node_or_null("Headlights"):
		return
	var lights := Node3D.new()
	lights.name = "Headlights"
	lights.visible = false
	add_child(lights)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.0, 1.3, -body_front + 0.6)
	spot.rotation = Vector3(deg_to_rad(-7.0), 0.0, 0.0)
	spot.spot_range = 90.0
	spot.spot_angle = 24.0
	spot.light_energy = 6.0
	spot.light_color = Color(1.0, 0.96, 0.88)
	lights.add_child(spot)


# --- Physics -------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var b := global_basis.orthonormalized()
	var v := linear_velocity
	forward_speed = v.dot(-b.z)
	speed_kmh = v.length() * 3.6
	var was_airborne := grounded_wheels == 0
	_float(b, v)
	bank = atan2(-b.x.y, b.y.y)
	var in_water := wet > 0.02
	var moored := in_water and _nobody_at_helm()
	_turn_back(moored)
	_update_gear()
	var thrust := _thrust_force(dt)
	_update_engine(dt, thrust)
	if in_water:
		_hydro(b, v, dt, moored)
		_steer(b, dt, moored)
	elif _body_touching and not _on_ramp:
		# Aground (a beach): the hull drags in the sand, so it stops a boat
		# length or two up the beach instead of skating inland.
		var flat := Vector3(v.x, 0.0, v.z)
		apply_central_force(-flat.limit_length(10.0) * mass * 0.9)
	if prop_bite > 0.0 and thrust != 0.0:
		var dir := b * (Basis(Vector3.UP, deg_to_rad(rudder) * 0.25) * Vector3.FORWARD)
		apply_force(dir * thrust * prop_bite, b * prop_point)
	# Air drag.
	push_central(-v * v.length() * 0.5 * 1.2 * air_drag_area)
	_update_air(dt, was_airborne)
	_update_capsize(dt, b, in_water)
	if _pending_impact > 0.0:
		impact.emit(_pending_impact, _pending_impact_pos, _pending_impact_normal)
		_pending_impact = 0.0


## Far out at sea, steers it round toward the island and on in (the
## player's own steering is overridden until it points in).
func _turn_back(moored: bool) -> void:
	var flat := Vector2(global_position.x, global_position.z)
	var nose3 := -global_basis.z
	var nose := Vector2(nose3.x, nose3.z).normalized()
	var outward := nose.dot(flat.normalized())
	if moored:
		turning_back = false
		return
	if flat.length() > TURN_BACK_RADIUS and outward > -0.5:
		turning_back = true
	elif flat.length() < TURN_BACK_RADIUS - 80.0 or outward < -0.9:
		turning_back = false
	if not turning_back:
		return
	var err := nose.angle_to(-flat.normalized())
	# In (x, z) a positive angle turns east toward south: a right turn.
	steer_input = clampf(err * 1.5, -1.0, 1.0)
	throttle_input = maxf(throttle_input, 0.4)
	brake_input = 0.0


## Is anyone (a player) at the helm? Left alone it lies still.
func _nobody_at_helm() -> bool:
	var c := Controllable.of(self)
	return c == null or c.is_free()


## Buoyancy and its damping at every float point; `wet` and grounded_wheels
## (float points in the water: the camera and the stunts read it as
## "on the ground").
func _float(b: Basis, v: Vector3) -> void:
	var sea := MapLayout.SEA_LEVEL
	var origin := global_position
	var com := origin + _com_offset
	var count := 0
	var held := 0.0
	for i in _k.size():
		var off := b * float_points[i]
		var p := origin + off
		var depth := sea - p.y
		if depth <= 0.0:
			continue
		count += 1
		depth = minf(depth, _float_max[i])
		held += _k[i] * depth
		var pv := v + angular_velocity.cross(p - com)
		var f := _k[i] * depth - pv.y * _k[i] * FLOAT_DAMP * clampf(depth / 0.15, 0.0, 1.0)
		apply_force(Vector3.UP * f, off)
	grounded_wheels = count
	wet = held / _rest_wet


func _update_gear() -> void:
	# The brake backs up once it's nearly stopped; throttle goes forward again.
	if gear >= 1:
		if brake_input > 0.3 and throttle_input < 0.1 and forward_speed < 0.8:
			gear = -1
	elif throttle_input > 0.3 and brake_input < 0.1 and forward_speed > -0.8:
		gear = 1


## The propeller's push this tick (N, + = forward), and how far it's in the
## water (prop_bite).
func _thrust_force(_dt: float) -> float:
	var p := global_transform * prop_point
	prop_bite = clampf((MapLayout.SEA_LEVEL - p.y + 0.08) / PROP_BITE, 0.0, 1.0)
	var power := damage_power * fuel_power
	var fwd := forward_speed
	var t := 0.0
	if gear >= 1:
		var accel := throttle_input
		if fuel_max_speed > 0.0:
			accel *= clampf((fuel_max_speed - absf(fwd)) / 3.0, 0.0, 1.0)
		t = max_thrust * accel * clampf(1.0 - fwd / prop_speed, 0.0, 1.0) * power
		# Lever pulled back while moving: reverse thrust slows it down.
		if brake_input > 0.05 and fwd > 0.5:
			t -= max_thrust * reverse_thrust * brake_input * power
	else:
		var back := brake_input
		t = -max_thrust * reverse_thrust * back * clampf(1.0 - (-fwd) / max_reverse_speed, 0.0, 1.0) * power
		if throttle_input > 0.05 and fwd < -0.5:
			t += max_thrust * reverse_thrust * throttle_input * power
	is_braking = (gear >= 1 and brake_input > 0.05) or (gear < 0 and throttle_input > 0.05)
	return t


## Engine revs follow the throttle and the speed; with the propeller out of
## the water (a jump) it races.
func _update_engine(dt: float, thrust: float) -> void:
	var lever := throttle_input if gear >= 1 else brake_input
	var engine_on := _audio == null or _audio.engine_running
	var target := idle_rpm
	if engine_on:
		var speed_t := clampf(absf(forward_speed) / top_speed, 0.0, 1.0)
		target = lerpf(idle_rpm, redline_rpm, clampf(0.55 * lever + 0.55 * speed_t * maxf(lever, 0.35), 0.0, 1.0))
		if prop_bite < 0.3 and lever > 0.1:
			target = redline_rpm * 0.97
	engine_rpm = move_toward(engine_rpm, target, dt * (4200.0 if target > engine_rpm else 2600.0))
	engine_load = clampf(lever, 0.0, 1.0) if thrust != 0.0 or lever > 0.0 else 0.0


## Water drag, the keel's grip, planing lift (in the water).
func _hydro(b: Basis, v: Vector3, _dt: float, moored: bool) -> void:
	var local := b.inverse() * v
	var fwd := -local.z
	var side := local.x
	var w := clampf(wet, 0.0, 1.3)
	var bump := 1.0 + hump * exp(-pow((absf(fwd) - hump_speed) / 3.0, 2.0))
	var along := (drag_linear * absf(fwd) + drag_quadratic * fwd * fwd * bump) * signf(fwd) * w
	var lever := throttle_input if gear >= 1 else brake_input
	if lever < 0.05 and not moored:
		along *= 1.0 + coast_drag
	var grip := SLIDE_GRIP if handbrake_input and not moored else 1.0
	var across := (side_linear * side + side_quadratic * side * absf(side)) * w * grip
	apply_central_force(b * Vector3(0.0, 0.0, along))
	apply_force(b * Vector3(-across, 0.0, 0.0), b * Vector3(0.0, com_height, center_of_mass.z + side_grip_aft))
	# Planing: the hull lifts as it speeds up, the lift moving aft (bow up on
	# the way onto the plane, then flatter).
	var plane := smoothstep(plane_from, plane_full, fwd)
	if plane > 0.0:
		var lift := mass * G * plane_lift * plane * minf(w * 1.6, 1.0)
		var at := lerpf(-0.9, -0.15, smoothstep(hump_speed, plane_full + 6.0, fwd))
		apply_force(Vector3.UP * lift, b * Vector3(0.0, 0.0, center_of_mass.z + at))
	if moored:
		# Tied up / anchored: it stops drifting.
		var flat := Vector3(v.x, 0.0, v.z)
		apply_central_force(-flat * mass * 1.2)
		apply_torque(-b.y * angular_velocity.dot(b.y) * inertia.y * 2.0)


## Turning: the stick asks for a turn rate (at any speed, a little standing
## still), the hull leans into the turn; plus roll damping in the water.
func _steer(b: Basis, dt: float, moored: bool) -> void:
	var steer := clampf(steer_input + damage_steer_bias, -1.0, 1.0)
	rudder = move_toward(rudder, steer * max_rudder, dt * 150.0)
	if moored:
		return
	var fwd := forward_speed
	var a := absf(fwd)
	var rate := turn_rate_still
	if a < turn_peak_speed:
		rate = lerpf(turn_rate_still, turn_rate_peak, a / turn_peak_speed)
	else:
		rate = lerpf(turn_rate_peak, turn_rate_fast, clampf((a - turn_peak_speed) / (top_speed - turn_peak_speed), 0.0, 1.0))
	if handbrake_input:
		rate *= 1.45
	# Backing up, the stern leads: the stick still means "turn that way".
	var want := -steer * rate * (1.0 if fwd > -0.5 else -1.0)
	var yaw := angular_velocity.dot(b.y)
	var w := clampf(wet * 1.5, 0.0, 1.0)
	var I := inertia if inertia != Vector3.ZERO else Vector3(900, 4600, 4000)
	push_torque(b.y * clampf((want - yaw) * 4.0, -3.0, 3.0) * I.y * w)
	# Lean into the turn (+ bank = right side down), held against the water.
	var want_bank := clampf(-fwd * yaw * deg_to_rad(bank_gain), -deg_to_rad(max_bank), deg_to_rad(max_bank))
	var roll_axis := -b.z
	var roll_rate := angular_velocity.dot(roll_axis)
	var upright := smoothstep(0.3, 0.7, b.y.y)
	push_torque(roll_axis * ((want_bank - bank) * 28.0 - roll_rate * 5.0) * I.z * w * upright)


## Upside down in the water: with assists on it rights itself after a
## moment. Stuck on land: stuck_time counts up (the HUD tells you about the
## help button).
func _update_capsize(dt: float, b: Basis, in_water: bool) -> void:
	if b.y.y < 0.2 and linear_velocity.length() < 4.0:
		upside_down_time += dt
		_capsized_time += dt if in_water else 0.0
	else:
		upside_down_time = 0.0
		_capsized_time = 0.0
	if _capsized_time > SELF_RIGHT_TIME and traction_control and not _nobody_at_helm():
		_capsized_time = 0.0
		reset_upright()
	if not in_water and grounded_wheels == 0 and _body_touching and linear_velocity.length() < 2.0:
		stuck_time += dt
	else:
		stuck_time = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	_on_ramp = false
	for i in state.get_contact_count():
		if state.get_contact_collider_object(i) is Ramp:
			_on_ramp = true
			break


## Is it floating (any of the hull in the water)?
func floating() -> bool:
	return wet > 0.02


# --- Placing it --------------------------------------------------------------

## R / gamepad Y: on the water, upright where it floats; on land (a beach,
## a ramp) back into the nearest open water.
func reset_upright() -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = global_basis.y
		fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var here := Vector3(global_position.x, MapLayout.SEA_LEVEL, global_position.z)
	if water_depth(get_world_3d().direct_space_state, here) >= 0.7:
		teleport(Transform3D(Basis.looking_at(fwd, Vector3.UP), here + Vector3.UP * 0.1))
		return
	var spot := water_spot(self, global_position, 70.0)
	if spot.is_empty():
		spot = nearest_boat_spot(self, global_position)
	if not spot.is_empty():
		teleport(spot["xform"])


## Upright, same heading, on the water surface where it is (the frame exits
## and the garage measure from: there's no ground under a boat).
func upright_ground_transform() -> Transform3D:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	if not floating():
		return super.upright_ground_transform()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(global_position.x, MapLayout.SEA_LEVEL, global_position.z))


func teleport(xform: Transform3D) -> void:
	super.teleport(xform)
	rudder = 0.0
	stuck_time = 0.0
	_capsized_time = 0.0
	wet = 1.0


## How deep the water is at `p` (m below the surface; 0 on land, 99 beyond
## the sea floor).
static func water_depth(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, MapLayout.SEA_LEVEL + 40.0, p.z), Vector3(p.x, MapLayout.SEA_LEVEL - 60.0, p.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return maxf(MapLayout.SEA_LEVEL - (hit["position"] as Vector3).y, 0.0)


## Can `boat` float at `xform` (deep enough under the hull, nothing solid in
## the way)? `exclude`: bodies to ignore (the boat itself...).
static func fits_at(boat: Vehicle, xform: Transform3D, exclude: Array[RID] = []) -> bool:
	var space := boat.get_world_3d().direct_space_state
	var fwd := -xform.basis.z
	for along: float in [0.0, -boat.body_front + 0.4, boat.body_rear - 0.4]:
		if water_depth(space, xform.origin + fwd * -along) < SPOT_DEPTH:
			return false
	for child in boat.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = xform.translated(Vector3.UP * 0.15) * cs.transform
		q.collision_mask = 0b1111
		q.exclude = exclude
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


## Open water for `boat` near `near` (within `radius` m), nearest first,
## facing away from `near` (out to sea from someone on the shore):
## {"xform"} or {}.
static func water_spot(boat: Vehicle, near: Vector3, radius := 40.0, exclude_extra: Array[RID] = []) -> Dictionary:
	var exclude: Array[RID] = exclude_extra.duplicate()
	if boat.is_inside_tree():
		exclude.append(boat.get_rid())
	var flat_near := Vector3(near.x, MapLayout.SEA_LEVEL, near.z)
	var r := 0.0
	while r <= radius:
		var count := 1 if r == 0.0 else maxi(8, int(TAU * r / 6.0))
		for k in count:
			var a := TAU * k / count
			var p := flat_near + Vector3(cos(a), 0.0, sin(a)) * r
			var dir := (p - flat_near).normalized() if r > 0.0 else -boat.global_basis.z
			dir.y = 0.0
			if dir.length() < 0.1:
				dir = Vector3.FORWARD
			var xf := Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p + Vector3.UP * 0.1)
			if fits_at(boat, xf, exclude):
				return {"xform": xf}
		r += 5.0 if r < 20.0 else 8.0
	return {}


## The marked boat spot (MapLayout.BOAT_SPOTS) nearest to `near` that has
## room (another boat there: a few metres along): {"xform"} or {}.
static func nearest_boat_spot(boat: Vehicle, near: Vector3, exclude_extra: Array[RID] = []) -> Dictionary:
	var spots := MapLayout.BOAT_SPOTS.duplicate()
	spots.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		return Vector2(a.x, a.y).distance_squared_to(Vector2(near.x, near.z)) < Vector2(b.x, b.y).distance_squared_to(Vector2(near.x, near.z)))
	var exclude: Array[RID] = exclude_extra.duplicate()
	if boat.is_inside_tree():
		exclude.append(boat.get_rid())
	for s: Vector4 in spots:
		var dir := Vector3(s.z, 0.0, s.w).normalized()
		var side := dir.cross(Vector3.UP)
		for off: float in [0.0, 7.0, -7.0, 14.0, -14.0]:
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(s.x, MapLayout.SEA_LEVEL + 0.1, s.y) + side * off)
			if fits_at(boat, xf, exclude):
				return {"xform": xf}
	return {}


# --- Looks ------------------------------------------------------------------

func _process(dt: float) -> void:
	if _outboard:
		_outboard.basis = _outboard_rest * Basis(Vector3.UP, deg_to_rad(rudder))
	if _prop:
		# The real speed is a blur under water; this reads as "spinning".
		var w := (engine_rpm - idle_rpm * 0.5) / redline_rpm * 38.0 if engine_load > 0.02 or engine_rpm > idle_rpm * 1.1 else 0.0
		if gear < 0:
			w = -w
		_prop_angle = wrapf(_prop_angle + w * dt, 0.0, TAU)
		_prop.basis = _prop_rest * Basis(Vector3.BACK, _prop_angle)
	var lit := 1.0 if _audio == null or _audio.engine_running else 0.0
	if lit != _lights_on and _visual:
		_lights_on = lit
		var nav := _visual.material("nav")
		if nav:
			nav.set_shader_parameter("lights", lit)
