class_name FlightCamera
extends Camera3D
## The camera for flying (the "plane" rig): behind and a little above the
## plane, following its whole orientation with a soft lag so turns, loops
## and rolls read naturally. In gentle flight it only leans with part of the
## bank, so the horizon stays calm; climbing steeply or upside down it
## follows fully, so it never flips over. Wall/ground collision, a wider
## view at speed, shake on crashes.
##
## Mouse / right stick look around (it swings back after a moment), Q / LB
## looks back, C / RB cycles chase / far / cockpit.

enum Mode { CHASE, FAR, COCKPIT }

@export var target: Vehicle
@export var mode := Mode.CHASE

@export_group("Chase")
@export var distance := 10.5
@export var height := 2.4
## The camera aims this far ahead of the plane (m), so you see where it's going.
@export var look_ahead := 4.0
## How fast the view swings round after the plane (1/s).
@export var follow := 4.0
## How much of the bank the camera leans with in level flight (0..1).
@export var bank_follow := 0.35

@export_group("Field of view")
@export var base_fov := 70.0
@export var max_fov := 80.0
@export var fov_full_speed := 80.0

@export_group("Orbit")
@export var mouse_sensitivity := 0.0035
@export var stick_speed := 2.6
@export var orbit_return_delay := 1.4
@export var orbit_return_speed := 2.5

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var collision_margin := 0.5

var _rot := Quaternion.IDENTITY
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_idle := 99.0
var _dist := 10.0
var _shake := 0.0
var _shake_time := 0.0
var _initialized := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if target:
		set_target(target)


func set_target(v: Vehicle) -> void:
	if target and is_instance_valid(target) and target.impact.is_connected(_on_impact):
		target.impact.disconnect(_on_impact)
	target = v
	if target:
		target.impact.connect(_on_impact)
		if not target.vehicle_reset.is_connected(snap):
			target.vehicle_reset.connect(snap)
	_initialized = false


## Jump straight to the default view (after teleports and resets).
func snap() -> void:
	_initialized = false


## Starts out looking the way `cam` looks (getting into the plane), then
## swings round behind it.
func snap_view(cam: Camera3D) -> void:
	_initialized = false
	_orbit_pitch = 0.0
	if cam == null or target == null:
		_orbit_yaw = 0.0
		return
	var f := -cam.global_basis.z
	var fwd := -target.global_basis.z
	_orbit_yaw = wrapf(atan2(-f.x, -f.z) - atan2(-fwd.x, -fwd.z), -PI, PI)
	_orbit_idle = orbit_return_delay - 0.6


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _on_impact(strength: float, _pos: Vector3, _normal: Vector3) -> void:
	add_shake(clampf(strength / 40000.0, 0.0, 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		_orbit_yaw -= rel.x * mouse_sensitivity
		_orbit_pitch = clampf(_orbit_pitch - rel.y * mouse_sensitivity, -1.0, 1.2)
		_orbit_idle = 0.0
	elif event.is_action_pressed("camera_cycle"):
		mode = ((mode + 1) % Mode.size()) as Mode
		_initialized = false


## The plane's frame with part of its bank taken out (none when it's steep
## or upside down, where "level" means nothing).
func _frame(b: Basis) -> Basis:
	var fwd := -b.z
	var level_up := Vector3.UP - fwd * fwd.y
	if level_up.length() < 0.3:
		return b
	level_up = level_up.normalized()
	var bank := atan2(fwd.dot(level_up.cross(b.y)), level_up.dot(b.y))
	var keep := lerpf(bank_follow, 1.0, smoothstep(0.55, 0.9, absf(fwd.y)))
	keep = lerpf(keep, 1.0, smoothstep(deg_to_rad(80.0), deg_to_rad(130.0), absf(bank)))
	return (Basis(fwd, -bank * (1.0 - keep)) * b).orthonormalized()


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t := target.get_global_transform_interpolated()
	var b := t.basis.orthonormalized()
	var want := _frame(b).get_rotation_quaternion()
	if not _initialized:
		_rot = want
		_dist = distance
		_initialized = true
	else:
		_rot = _rot.slerp(want, 1.0 - exp(-follow * dt))
	var cb := Basis(_rot)

	var stick := Vector2(Input.get_axis("camera_left", "camera_right"), Input.get_axis("camera_down", "camera_up"))
	if stick.length() > 0.1 and current:
		_orbit_yaw -= stick.x * stick_speed * dt
		_orbit_pitch = clampf(_orbit_pitch + stick.y * stick_speed * 0.6 * dt, -1.0, 1.2)
		_orbit_idle = 0.0
	_orbit_idle += dt
	if _orbit_idle > orbit_return_delay:
		var k := 1.0 - exp(-orbit_return_speed * dt)
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, k)
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, k)

	var speed := target.linear_velocity.length()
	fov = lerpf(fov, lerpf(base_fov, max_fov, clampf(speed / fov_full_speed, 0.0, 1.0)), 1.0 - exp(-3.0 * dt))
	var look_back := Input.is_action_pressed("look_back")
	if mode == Mode.COCKPIT:
		_cockpit(t, b, look_back)
	else:
		_chase(t.origin, cb, speed, look_back, dt)
	_apply_shake(dt)


func _chase(origin: Vector3, cb: Basis, speed: float, look_back: bool, dt: float) -> void:
	var dist := distance * (1.7 if mode == Mode.FAR else 1.0) + clampf(speed / 60.0, 0.0, 1.0) * 1.5
	var h := height * (1.5 if mode == Mode.FAR else 1.0)
	var yaw := _orbit_yaw + (PI if look_back else 0.0)
	var orbit := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -_orbit_pitch)
	var offset := cb * (orbit * Vector3(0.0, h, dist))
	var pivot := origin + cb.y * 1.0
	var aim := origin + cb * (orbit * Vector3(0.0, h * 0.25, -look_ahead))
	# Pull in when the ground or a building is between the plane and the camera.
	var wanted := offset.length()
	var dir := offset / maxf(wanted, 0.001)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * (wanted + collision_margin), collision_mask)
	q.exclude = [target.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		wanted = maxf(pivot.distance_to(hit["position"]) - collision_margin, 2.0)
	if wanted < _dist:
		_dist = wanted
	else:
		_dist = lerpf(_dist, wanted, 1.0 - exp(-3.0 * dt))
	global_position = pivot + dir * _dist
	var up := cb.y
	if absf((aim - global_position).normalized().dot(up)) > 0.98:
		up = cb.z
	look_at(aim, up)


func _cockpit(t: Transform3D, b: Basis, look_back: bool) -> void:
	global_position = t * target.driver_eye
	var yaw := _orbit_yaw + (PI if look_back else 0.0)
	var dir := b * (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _orbit_pitch * 0.8) * Vector3.FORWARD)
	look_at(global_position + dir * 10.0, b.y)


func _apply_shake(dt: float) -> void:
	# A light buffet near the stall, so the kid feels it's too slow.
	var a := target as Aircraft
	if a and a.stall_warning > 0.3:
		_shake = maxf(_shake, a.stall_warning * 0.18)
	if _shake <= 0.001:
		return
	_shake_time += dt * 30.0
	var s := _shake * _shake
	var off := Vector3(sin(_shake_time * 1.1), sin(_shake_time * 1.7 + 1.3), 0.0) * s * 0.25
	global_position += global_basis * off
	rotate_object_local(Vector3.FORWARD, sin(_shake_time * 1.3) * s * 0.04)
	_shake = move_toward(_shake, 0.0, dt * 1.8)
