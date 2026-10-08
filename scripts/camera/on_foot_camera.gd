class_name OnFootCamera
extends Camera3D
## Third-person camera for walking around: orbits the character with the
## mouse / right stick, sits a little above and behind the shoulders, pulls in
## when a wall is in the way (not for vehicles: standing by a car would pull
## it in to a close-up of the face), and drifts back behind the
## character on its own while walking forward without touching the camera
## (so a gamepad player who never uses the right stick still sees ahead).
## C / RB switches between a close and a wider view.

@export var target: PlayerCharacter

@export_group("Framing")
@export var distance := 3.6
@export var far_distance := 5.4
@export var pivot_height := 1.5
## Sideways offset of the pivot (m, + = right): a slight over-the-shoulder view.
@export var shoulder := 0.25
@export var base_fov := 70.0
@export var sprint_fov := 76.0
@export var default_pitch := 0.22

@export_group("Orbit")
@export var mouse_sensitivity := 0.0032
@export var stick_yaw_speed := 2.8
@export var stick_pitch_speed := 1.8
@export var min_pitch := -0.75
@export var max_pitch := 1.15
## Seconds without camera input before it starts drifting behind the character.
@export var follow_delay := 1.2
@export var follow_rate := 1.4

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var collision_radius := 0.22

## Whose stick and buttons move it (split-screen: one player's devices).
var input := PlayerInput.shared()

var yaw := 0.0
var pitch := 0.22
## The wider view (C / RB).
var wide := false
var _idle := 99.0
var _pivot := Vector3.ZERO
var _dist := 3.6
var _initialized := false
var _fov := 70.0
var _probe := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fov = base_fov
	fov = base_fov
	_probe.radius = collision_radius
	_query.shape = _probe
	_query.collision_mask = collision_mask


func set_target(c: Node3D) -> void:
	target = c as PlayerCharacter
	_initialized = false


## Jump straight to the default view behind the character.
func snap() -> void:
	_initialized = false


## Starts looking the way `cam` looks (keeps the view's heading when the
## player gets out of a vehicle, instead of swinging round).
func match_view(cam: Camera3D) -> void:
	var f := -cam.global_basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = clampf(asin(clampf(-f.y, -1.0, 1.0)) + 0.05, min_pitch, max_pitch)
	_idle = 0.0
	if target:
		_pivot = _pivot_target()
	_dist = _wanted_distance()
	_initialized = true


func _unhandled_input(event: InputEvent) -> void:
	handle_input(event)


## Mouse look and the camera button (see ChaseCamera.handle_input).
func handle_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and input.keyboard and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		yaw -= rel.x * mouse_sensitivity
		pitch = clampf(pitch + rel.y * mouse_sensitivity, min_pitch, max_pitch)
		_idle = 0.0
	elif input.event_pressed(event, "camera_cycle"):
		wide = not wide


func _pivot_target() -> Vector3:
	var t := target.get_global_transform_interpolated()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return t.origin + Vector3.UP * pivot_height + right * shoulder


func _wanted_distance() -> float:
	var d := far_distance if wide else distance
	if target and target.ground_speed > target.run_speed + 0.5:
		d += 0.5
	return d


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var stick := Vector2(input.axis("camera_left", "camera_right"), input.axis("camera_down", "camera_up"))
	if current and stick.length() > 0.1:
		yaw -= stick.x * stick_yaw_speed * dt
		pitch = clampf(pitch - stick.y * stick_pitch_speed * dt, min_pitch, max_pitch)
		_idle = 0.0
	_idle += dt

	if not _initialized:
		yaw = target.facing
		pitch = default_pitch
		_pivot = _pivot_target()
		_dist = _wanted_distance()
		_initialized = true

	# Drift behind the character while it heads away from the camera.
	var speed := target.ground_speed
	if _idle > follow_delay and speed > 0.5 and target.state == PlayerCharacter.State.ACTIVE:
		var diff := angle_difference(yaw, target.facing)
		if absf(diff) < deg_to_rad(75.0):
			var k := 1.0 - exp(-follow_rate * clampf(speed / target.run_speed, 0.3, 1.2) * dt)
			yaw = lerp_angle(yaw, target.facing, k)
			pitch = lerpf(pitch, default_pitch, k * 0.5)

	var want_pivot := _pivot_target()
	# Smooth vertical follow hides kerb steps; sideways follows tightly.
	_pivot.x = want_pivot.x
	_pivot.z = want_pivot.z
	_pivot.y = lerpf(_pivot.y, want_pivot.y, 1.0 - exp(-10.0 * dt))
	_pivot.y = clampf(_pivot.y, want_pivot.y - 0.6, want_pivot.y + 0.6)

	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var wanted := _wanted_distance()
	# Pull in when something is between the character and the camera.
	_query.transform = Transform3D(Basis.IDENTITY, _pivot)
	_query.motion = dir * wanted
	var space := get_world_3d().direct_space_state
	var hit := space.cast_motion(_query)
	if not hit.is_empty() and hit[0] < 1.0:
		wanted = maxf(wanted * hit[0], 0.6)
	if wanted < _dist:
		_dist = wanted
	else:
		_dist = lerpf(_dist, wanted, 1.0 - exp(-2.5 * dt))

	global_position = _pivot + dir * _dist
	look_at(_pivot + Vector3.UP * 0.05, Vector3.UP)
	var want_fov := sprint_fov if speed > target.run_speed + 0.5 else base_fov
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-3.0 * dt))
	fov = Views.fit_fov(self, _fov)
