class_name VehicleWheel
extends Node3D
## One wheel of a Vehicle: raycast suspension plus a simple slip-based tire model.
##
## Place this node at the suspension mount point (top of travel). The wheel
## hangs `suspension_travel` below it at full droop. The optional child named
## "Visual" is moved/spun to show suspension travel and rolling.
## The parent Vehicle calls update_physics() every physics tick.

@export_group("Layout")
@export var steers := false
@export var driven := false
@export var has_handbrake := false

@export_group("Wheel")
@export var radius := 0.37

@export_group("Suspension")
## Distance from the mount point to the wheel centre at full droop (m).
@export var suspension_travel := 0.3
@export var spring_stiffness := 30000.0
@export var compression_damping := 2600.0
@export var rebound_damping := 3200.0
@export var bump_stop_stiffness := 160000.0
## Clamp on damper speed so sharp steps (curbs) don't produce huge spikes.
@export var max_damper_speed := 4.0

@export_group("Tire")
## Friction coefficient on a surface with grip 1.0.
@export var grip := 1.15
## Lateral slip (≈ tan of slip angle) where grip peaks.
@export var peak_slip := 0.12
## Fraction of peak grip left when sliding hard.
@export var slide_grip := 0.8
## Lateral grip multiplier while the handbrake locks this wheel.
@export var handbrake_lateral_grip := 0.5
@export var rolling_resistance := 0.015

# --- Set by the vehicle every tick ---
var steer_angle := 0.0
var drive_torque := 0.0
var brake_torque := 0.0
var handbrake_engaged := false

# --- Read-only state, useful for effects/audio/HUD ---
var grounded := false
## 0 at full droop, grows as the suspension compresses (m).
var compression := 0.0
var tire_load := 0.0
var contact_point := Vector3.ZERO
var contact_normal := Vector3.UP
var contact_collider: Object = null
var surface_grip := 1.0
var forward_speed := 0.0
var lateral_speed := 0.0
## 0..1, how much this tire is sliding (for skid sound/smoke/marks).
var skid := 0.0
## How fast the suspension is compressing (m/s, + = bump), for knock sounds.
var compression_speed := 0.0
## Wheel angular speed (rad/s), visual only.
var spin_speed := 0.0
var is_left := false
var is_front := false

var _vehicle: RigidBody3D
var _ray := PhysicsRayQueryParameters3D.new()
var _prev_compression := 0.0
var _spin_angle := 0.0
var _visual: Node3D
var _visual_len := 0.0
var _caliper: Node3D

## Caliper materials by colour, shared by every wheel using that colour.
static var _caliper_mats := {}


func setup(vehicle: RigidBody3D, collision_mask: int) -> void:
	_vehicle = vehicle
	_ray.exclude = [vehicle.get_rid()]
	_ray.collision_mask = collision_mask
	_ray.hit_back_faces = false
	_visual = get_node_or_null("Visual") as Node3D
	is_left = position.x < 0.0
	is_front = position.z < 0.0
	_visual_len = suspension_travel


## Mounts a brake caliper (brake_caliper.glb from make_wheels.py) behind
## the spokes: it steers and follows the suspension with the wheel but
## doesn't spin. Sized and mirrored like the wheel model under Visual.
func add_caliper(scene: PackedScene, color: Color) -> void:
	var vis := get_node_or_null("Visual") as Node3D
	var model := vis.get_child(0) as Node3D if vis and vis.get_child_count() > 0 else null
	if model == null or _caliper:
		return
	_caliper = scene.instantiate() as Node3D
	_caliper.name = "Caliper"
	var size := model.transform.basis.get_scale().abs().x
	var mirror := Basis(Vector3.UP, PI) if position.x < 0.0 else Basis.IDENTITY
	# Behind the axle and up a little, where real calipers sit.
	_caliper.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(38.0)) * mirror * Basis.from_scale(Vector3.ONE * size), vis.position)
	add_child(_caliper)
	if not _caliper_mats.has(color):
		var src: Material = null
		for mi in _caliper.find_children("*", "MeshInstance3D", true, false):
			src = (mi as MeshInstance3D).get_active_material(0)
		var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D if src is BaseMaterial3D else StandardMaterial3D.new()
		m.albedo_color = color
		_caliper_mats[color] = m
	for mi in _caliper.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		g.set_surface_override_material(0, _caliper_mats[color])
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 45.0
		g.layers = 2


## How far the wheel centre hangs below the mount point when standing still
## and carrying `supported_mass` kg (springs only; used for previews/placement).
func rest_drop(supported_mass: float) -> float:
	return suspension_travel - clampf(supported_mass * 9.81 / spring_stiffness, 0.0, suspension_travel * 0.85)


## Puts the "Visual" child at its resting height (for frozen preview models).
func pose_at_rest(supported_mass: float) -> void:
	var vis := get_node_or_null("Visual") as Node3D
	if vis:
		vis.position = Vector3(0.0, -rest_drop(supported_mass), 0.0)
		if _caliper:
			_caliper.position = vis.position


func reset_state() -> void:
	_prev_compression = 0.0
	compression = 0.0
	compression_speed = 0.0
	spin_speed = 0.0
	skid = 0.0
	grounded = false


func update_physics(dt: float, mass_share: float, traction_control: bool, tire_force_height: float) -> void:
	if steers:
		rotation.y = steer_angle

	var body := _vehicle
	var up := body.global_basis.y
	var origin := global_position
	var ray_len := suspension_travel + radius
	_ray.from = origin
	_ray.to = origin - up * ray_len
	var hit := body.get_world_3d().direct_space_state.intersect_ray(_ray)

	if hit.is_empty():
		grounded = false
		tire_load = 0.0
		compression = 0.0
		_prev_compression = 0.0
		compression_speed = 0.0
		skid = 0.0
		contact_collider = null
		# Free-spinning wheel: throttle spins it up, otherwise it slowly coasts down.
		if handbrake_engaged and has_handbrake:
			spin_speed = 0.0
		elif driven and absf(drive_torque) > 1.0:
			spin_speed = move_toward(spin_speed, signf(drive_torque) * 90.0, 120.0 * dt)
		else:
			spin_speed = move_toward(spin_speed, 0.0, 8.0 * dt)
		_update_visual(dt, suspension_travel)
		return

	grounded = true
	contact_point = hit.position
	contact_normal = hit.normal
	contact_collider = hit.collider
	surface_grip = 1.0
	if contact_collider and contact_collider.has_meta("surface_grip"):
		surface_grip = contact_collider.get_meta("surface_grip")

	# --- Suspension ---
	var dist := origin.distance_to(contact_point)
	compression = clampf(ray_len - dist, 0.0, ray_len)
	var comp_speed := clampf((compression - _prev_compression) / dt, -max_damper_speed, max_damper_speed)
	compression_speed = comp_speed
	_prev_compression = compression
	var spring := spring_stiffness * compression
	var damper := comp_speed * (compression_damping if comp_speed > 0.0 else rebound_damping)
	var bump_start := suspension_travel * 0.85
	var bump := 0.0
	if compression > bump_start:
		bump = (compression - bump_start) * bump_stop_stiffness
	var susp_force := maxf(spring + damper + bump, 0.0)
	var body_offset := contact_point - body.global_position
	body.apply_force(up * susp_force, body_offset)

	# --- Tire ---
	var n := contact_normal
	var wheel_fwd := -global_basis.z
	var fwd := (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
	var right := fwd.cross(n)
	var com := body.global_transform * body.center_of_mass
	var vel := body.linear_velocity + body.angular_velocity.cross(contact_point - com)
	var ground_body := contact_collider as RigidBody3D
	if ground_body:
		var g_com := ground_body.global_transform * ground_body.center_of_mass
		vel -= ground_body.linear_velocity + ground_body.angular_velocity.cross(contact_point - g_com)
	var v_long := vel.dot(fwd)
	var v_lat := vel.dot(right)
	forward_speed = v_long
	lateral_speed = v_lat

	# Tire load is capped so hard landings don't turn into super-grip.
	tire_load = minf(susp_force, mass_share * 9.81 * 3.0)
	var max_f := grip * surface_grip * tire_load
	var locked := has_handbrake and handbrake_engaged
	var stop_force := -v_long * mass_share / dt

	# Lateral: slip-based curve that peaks then falls off into a slide.
	var slip := v_lat / maxf(absf(v_long), 3.0)
	var x := absf(slip) / peak_slip
	var curve := sin(x * PI * 0.5) if x < 1.0 else lerpf(1.0, slide_grip, clampf((x - 1.0) * 0.5, 0.0, 1.0))
	var lat_mult := handbrake_lateral_grip if locked else 1.0
	var f_lat := -signf(v_lat) * curve * max_f * lat_mult
	# At very low speed, cancel sideways creep directly (parking on slopes).
	var low_speed := clampf(1.0 - absf(v_long) / 3.0, 0.0, 1.0)
	if low_speed > 0.0:
		var hold := clampf(-v_lat * mass_share / dt * 0.5, -max_f, max_f)
		f_lat = lerpf(f_lat, hold, low_speed)

	# Longitudinal: drive, brakes, rolling resistance.
	var f_drive := drive_torque / radius
	var wheelspin := 0.0
	if absf(f_drive) > max_f:
		wheelspin = clampf((absf(f_drive) - max_f) / maxf(max_f, 1.0), 0.0, 1.0)
	if traction_control:
		# Only use the grip that cornering leaves over, so power can't spin the car.
		var avail := sqrt(maxf(max_f * max_f - f_lat * f_lat, 0.0))
		avail = maxf(avail, max_f * 0.3) * 0.97
		if absf(f_drive) > avail:
			f_drive = signf(f_drive) * avail
		wheelspin *= 0.1
	var f_long := f_drive
	var brake_f := brake_torque / radius
	if locked:
		brake_f = maxf(brake_f, max_f * slide_grip)
	if brake_f > 0.0:
		f_long += clampf(stop_force, -brake_f, brake_f)
	var rr := rolling_resistance * tire_load
	f_long += clampf(stop_force, -rr, rr)

	# Friction circle (longitudinal first, but always keep some cornering grip).
	var slide_limit := max_f * (slide_grip if locked else 1.0)
	f_long = clampf(f_long, -slide_limit, slide_limit)
	var lat_limit := sqrt(maxf(max_f * max_f - f_long * f_long, max_f * max_f * 0.09)) * lat_mult
	f_lat = clampf(f_lat, -lat_limit, lat_limit)

	var tire_force := fwd * f_long + right * f_lat
	body.apply_force(tire_force, contact_point + up * tire_force_height - body.global_position)

	# Newton's third law for dynamic things we're standing on (crates, parked cars...).
	if ground_body and not ground_body.freeze:
		ground_body.apply_force(-(up * susp_force + tire_force) * 0.5, contact_point - ground_body.global_position)

	# --- Effects state ---
	var lat_skid := clampf((x - 1.3) / 1.5, 0.0, 1.0) * clampf((absf(v_lat) - 1.0) / 2.0, 0.0, 1.0)
	var lock_skid := 1.0 if (locked and absf(v_long) > 2.0) else 0.0
	skid = maxf(maxf(lat_skid, lock_skid), wheelspin) * clampf(tire_load / (mass_share * 4.0), 0.0, 1.0) * 1.5
	skid = clampf(skid, 0.0, 1.0)

	if locked:
		spin_speed = 0.0
	else:
		spin_speed = v_long / radius + signf(drive_torque) * wheelspin * 40.0

	_update_visual(dt, dist - radius)


func _update_visual(dt: float, target_len: float) -> void:
	if _visual == null:
		return
	target_len = clampf(target_len, 0.0, suspension_travel)
	# Visual follows the physics closely but smooths single-tick pops.
	_visual_len = lerpf(_visual_len, target_len, 1.0 - exp(-40.0 * dt))
	_spin_angle = wrapf(_spin_angle + spin_speed * dt, -PI, PI)
	_visual.position = Vector3(0.0, -_visual_len, 0.0)
	_visual.rotation = Vector3(-_spin_angle, 0.0, 0.0)
	if _caliper:
		_caliper.position = _visual.position
