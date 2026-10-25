class_name RainFx
extends Node3D
## Rain round one player's camera (Weather makes one per camera): GPU
## particles falling through a box that follows the camera, pushed ahead of
## it while it moves so you drive into rain that's already falling. Drawn as
## thin streaks (rain.gdshader). Stops under a roof (a bridge, the tunnel):
## a ray down from high above the camera a few times a second (road decks
## and the terrain only collide from above). ART_BIBLE.md §23.

## Drops in the box per graphics level (Low, Medium, High, Ultra).
const DROPS := [2500, 4000, 6000, 9000]
## Half the box's width and height (m); it reaches from just below the
## camera to about 15 m above it.
const HALF := 14.0
const HALF_HEIGHT := 8.0
const FALL_SPEED := 10.0
## How far ahead of a moving camera the box goes (seconds of travel).
const LEAD := 0.7
## Anything of the world (layer 1) between 2.5 m and this far above the
## camera keeps the rain off. Cars are on another layer, so the hood
## camera's own roof doesn't count.
const ROOF_RAY := 60.0

var _particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial
var _cover := 1.0
var _open := true
var _check := 0.0
var _last := Vector3.INF
var _vel := Vector3.ZERO


func _ready() -> void:
	var level := clampi(int(Settings.get_value("graphics")), 0, DROPS.size() - 1)
	_particles = GPUParticles3D.new()
	_particles.amount = DROPS[level]
	_particles.lifetime = 1.6
	_particles.preprocess = 1.6
	_particles.local_coords = false
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var r := HALF + FALL_SPEED * LEAD * 3.0
	_particles.visibility_aabb = AABB(Vector3(-r, -HALF_HEIGHT * 3.0, -r), Vector3(r * 2.0, HALF_HEIGHT * 5.0, r * 2.0))
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(HALF, HALF_HEIGHT, HALF)
	_process_mat.direction = Vector3.DOWN
	_process_mat.spread = 2.0
	_process_mat.initial_velocity_min = FALL_SPEED * 0.9
	_process_mat.initial_velocity_max = FALL_SPEED * 1.1
	_process_mat.gravity = Vector3.ZERO
	_process_mat.particle_flag_align_y = true
	_particles.process_material = _process_mat
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/rain.gdshader")
	quad.material = mat
	_particles.draw_pass_1 = quad
	add_child(_particles)


## Follows `cam` (none: hidden). `amount` 0-1 is how hard it rains; `view`
## is the player's split-screen view (the rain is drawn only in that view).
func follow(cam: Camera3D, amount: float, view: int) -> void:
	var dt := get_process_delta_time()
	if cam == null or amount <= 0.0:
		_particles.emitting = false
		visible = false
		_last = Vector3.INF
		return
	var p := cam.global_position
	if _last == Vector3.INF or p.distance_to(_last) > 40.0:
		# First frame, or a teleport: start full of rain right here.
		_vel = Vector3.ZERO
		_place(p)
		_particles.restart()
	elif dt > 0.0:
		_vel = _vel.lerp((p - _last) / dt, clampf(dt * 4.0, 0.0, 1.0))
	_last = p
	_place(p)
	_check -= dt
	if _check <= 0.0:
		_check = 0.2
		_open = not _roof_over(cam, p)
	_cover = move_toward(_cover, 1.0 if _open else 0.0, dt * 3.0)
	var ratio := clampf(amount * _cover, 0.0, 1.0)
	visible = ratio > 0.01
	_particles.emitting = visible
	_particles.amount_ratio = ratio
	# Storm rain comes down slanted, blown by the wind.
	_process_mat.gravity = Vector3(1.0, 0.0, 0.6) * smoothstep(0.6, 1.0, amount) * 3.0
	_particles.layers = Views.VIEW_LAYERS[view] if Views.is_split() and view < Views.VIEW_LAYERS.size() else 1


func _place(p: Vector3) -> void:
	var lead := Vector3(_vel.x, 0.0, _vel.z) * LEAD
	if lead.length() > HALF * 1.5:
		lead = lead.normalized() * HALF * 1.5
	global_position = p + lead + Vector3.UP * (HALF_HEIGHT - 1.0)


func _roof_over(cam: Camera3D, p: Vector3) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * ROOF_RAY, p + Vector3.UP * 2.5, 1)
	return not space.intersect_ray(q).is_empty()
