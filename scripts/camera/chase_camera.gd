class_name ChaseCamera
extends Camera3D
## Smooth third-person driving camera.
##
## Follows the car's heading (not its pitch/roll, so crashes and flips don't spin
## the view), lags a little in yaw for a sense of motion, widens FOV with speed,
## avoids clipping into walls, and can be orbited with mouse / right stick.

enum Mode { CHASE, FAR, HOOD }

@export var target: Vehicle
@export var mode := Mode.CHASE

@export_group("Chase")
@export var distance := 6.2
@export var height := 1.9
@export var look_height := 1.0
@export var extra_distance_at_speed := 1.6
@export var yaw_follow := 4.5
@export var air_yaw_follow := 1.0
@export var vertical_follow := 7.0

@export_group("Field of view")
@export var base_fov := 68.0
@export var max_fov := 84.0
@export var fov_full_speed := 55.0

@export_group("Orbit")
@export var mouse_sensitivity := 0.0035
@export var stick_speed := 2.6
@export var orbit_return_delay := 1.4
@export var orbit_return_speed := 2.5

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var collision_margin := 0.35

var _yaw := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_idle := 99.0
var _pivot_y := 0.0
var _dist := 6.0
var _shake := 0.0
var _shake_time := 0.0
var _initialized := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if target:
		set_target(target)


func set_target(v: Vehicle) -> void:
	if target and target.impact.is_connected(_on_impact):
		target.impact.disconnect(_on_impact)
	target = v
	if target:
		target.impact.connect(_on_impact)
		if not target.vehicle_reset.is_connected(snap):
			target.vehicle_reset.connect(snap)
	_initialized = false


## Jump straight to the default view (after teleports/resets).
func snap() -> void:
	_initialized = false


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _on_impact(strength: float, _pos: Vector3, _normal: Vector3) -> void:
	add_shake(clampf(strength / 40000.0, 0.0, 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		_orbit_yaw -= rel.x * mouse_sensitivity
		_orbit_pitch = clampf(_orbit_pitch - rel.y * mouse_sensitivity, -0.5, 1.1)
		_orbit_idle = 0.0
	elif event.is_action_pressed("camera_cycle"):
		mode = ((mode + 1) % Mode.size()) as Mode
		_initialized = false


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t := target.get_global_transform_interpolated()
	var car_pos := t.origin
	var fwd := -t.basis.z

	# Right stick orbit.
	var stick := Vector2(Input.get_axis("camera_left", "camera_right"), Input.get_axis("camera_down", "camera_up"))
	if stick.length() > 0.1:
		_orbit_yaw -= stick.x * stick_speed * dt
		_orbit_pitch = clampf(_orbit_pitch + stick.y * stick_speed * 0.6 * dt, -0.5, 1.1)
		_orbit_idle = 0.0
	_orbit_idle += dt
	if _orbit_idle > orbit_return_delay:
		var k := 1.0 - exp(-orbit_return_speed * dt)
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, k)
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, k)

	var flat := Vector3(fwd.x, 0.0, fwd.z)
	var target_yaw := _yaw
	if flat.length() > 0.15:
		target_yaw = atan2(-flat.x, -flat.z)
	elif not _initialized:
		target_yaw = 0.0

	if not _initialized:
		_yaw = target_yaw
		_pivot_y = car_pos.y
		_dist = distance
		_initialized = true

	var speed := target.linear_velocity.length()
	var follow := yaw_follow if target.grounded_wheels > 0 else air_yaw_follow
	# Follow faster at speed so the camera stays behind in long high-speed curves.
	follow *= lerpf(0.8, 1.4, clampf(speed / 40.0, 0.0, 1.0))
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-follow * dt))
	_pivot_y = lerpf(_pivot_y, car_pos.y, 1.0 - exp(-vertical_follow * dt))
	# Never let the pivot fall far behind on big drops / climbs.
	_pivot_y = clampf(_pivot_y, car_pos.y - 1.5, car_pos.y + 1.5)

	var look_back := Input.is_action_pressed("look_back")
	fov = lerpf(fov, lerpf(base_fov, max_fov, clampf(speed / fov_full_speed, 0.0, 1.0)), 1.0 - exp(-3.0 * dt))

	if mode == Mode.HOOD:
		_process_hood(t, look_back)
	else:
		_process_chase(car_pos, speed, look_back, dt)

	_apply_shake(dt)


func _process_chase(car_pos: Vector3, speed: float, look_back: bool, dt: float) -> void:
	var dist := distance
	var h := height
	if mode == Mode.FAR:
		dist *= 1.6
		h *= 1.7
	dist += extra_distance_at_speed * clampf(speed / 50.0, 0.0, 1.0)

	var pivot := Vector3(car_pos.x, _pivot_y + look_height, car_pos.z)
	var yaw := _yaw + _orbit_yaw + (PI if look_back else 0.0)
	var pitch := atan2(h - look_height, dist) + _orbit_pitch
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

	# Pull in when something is between the car and the camera.
	var wanted := dist
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * (dist + collision_margin), collision_mask)
	q.exclude = [target.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		wanted = maxf(pivot.distance_to(hit.position) - collision_margin, 1.2)
	if wanted < _dist:
		_dist = wanted
	else:
		_dist = lerpf(_dist, wanted, 1.0 - exp(-3.0 * dt))

	var cam_pos := pivot + dir * _dist
	global_position = cam_pos
	look_at(pivot + Vector3.UP * 0.1, Vector3.UP)


func _process_hood(t: Transform3D, look_back: bool) -> void:
	var b := t.basis.orthonormalized()
	global_position = t * Vector3(0.0, 1.2, -0.2)
	var look_dir := (-b.z if not look_back else b.z)
	look_at(global_position + look_dir * 10.0 + Vector3.UP * 0.2, b.y)


func _apply_shake(dt: float) -> void:
	if _shake <= 0.001:
		return
	_shake_time += dt * 30.0
	var s := _shake * _shake
	var off := Vector3(sin(_shake_time * 1.1), sin(_shake_time * 1.7 + 1.3), 0.0) * s * 0.25
	global_position += global_basis * off
	rotate_object_local(Vector3.FORWARD, sin(_shake_time * 1.3) * s * 0.04)
	_shake = move_toward(_shake, 0.0, dt * 1.8)
