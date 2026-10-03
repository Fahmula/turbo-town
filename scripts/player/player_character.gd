class_name PlayerCharacter
extends CharacterBody3D
## The person the player walks around as. Like Vehicle, it doesn't read input
## itself: a controller writes move_input / walk_input / sprint_input /
## jump_input (PlayerCharacterController for the player). It walks, runs,
## sprints and jumps, steps up kerbs and stairs, turns smoothly toward where
## it's going, kicks light props out of the way, and gets bumped aside
## (unhurt) by moving vehicles. Animations come from the model's
## AnimationPlayer (see ANIMS); playback speed follows the ground speed so
## the feet don't slide. Footsteps play when an animated foot touches down,
## with the sound of what's underfoot (concrete, grass, wood).
##
## Getting in and out of vehicles is the Possession's job: VehicleEntry
## emits `vehicle_requested`, the Possession walks the character to the door
## (walk_to), hides it (set_hidden) and later puts it back (place).

signal vehicle_requested(vehicle: Vehicle)
## A vehicle bumped into us (strength = how fast it hit, m/s).
signal knocked(strength: float)

enum State { ACTIVE, KNOCKED, SCRIPTED, HIDDEN }

## Physics layer of characters ("characters" in the project settings).
const LAYER := 8
## Characters collide with the world, vehicles and props; vehicles don't
## collide with characters (a car would hit a person like a wall), the
## character gets out of their way instead (see _check_vehicles).
const MASK := 0b111

@export_group("Speeds (m/s)")
@export var walk_speed := 1.55
@export var run_speed := 4.3
@export var sprint_speed := 6.6
@export var ground_accel := 16.0
@export var air_accel := 4.0
## Turning toward the direction of travel (rad/s at full speed).
@export var turn_speed := 11.0

@export_group("Body")
@export var radius := 0.3
@export var height := 1.78
@export var step_height := 0.42
@export var gravity_scale := 1.6
@export var jump_speed := 5.2

@export_group("Animation")
## Natural ground speed of each locomotion clip (m/s at speed_scale 1).
@export var walk_anim_speed := 1.45
@export var run_anim_speed := 4.0
@export var sprint_anim_speed := 6.4
## Jump_Start opens with a crouch: the jump (already in the air) starts this
## far in, at the push-off.
@export var jump_anim_offset := 0.15

@export_group("Footsteps")
## Footstep loudness (dB) walking, running, sprinting; landings are louder.
@export var step_db := Vector3(-15.0, -10.0, -7.0)
@export var land_db := -4.0

## Footstep sounds per surface: file pattern (5 takes) and a level offset (dB).
const STEP_SOUNDS := {
	"concrete": ["res://assets/audio/foot/concrete_%d.wav", 0.0],
	"grass": ["res://assets/audio/foot/grass_%d.wav", 6.0],
	"wood": ["res://assets/audio/foot/wood_%d.wav", -2.0],
}

## Logical animation -> candidate clip names in the model (exact names first,
## then substrings; case-insensitive). The model's clips come from the
## Universal Animation Library (Godot drops their "_Loop" suffix on import).
const ANIMS := {
	"idle": ["idle"],
	"walk": ["walk"],
	"run": ["jog_fwd", "jog", "run"],
	"sprint": ["sprint"],
	"jump": ["jump_start"],
	"fall": ["jump", "fall"],
	"land": ["jump_land", "land"],
	"knocked": ["hit", "jump"],
}

# --- Inputs (written by a controller) ---
## Where to go, world space (horizontal); length 0..1 = how hard the stick is pushed.
var move_input := Vector3.ZERO
var walk_input := false
var sprint_input := false
var jump_input := false

var state := State.ACTIVE
var state_time := 0.0
## Current horizontal speed (m/s) and facing (radians, 0 = -Z).
var ground_speed := 0.0
var facing := 0.0
var airtime := 0.0

var _gravity := 9.8
var _model: Node3D
var _anim: AnimationPlayer
var _clips := {}
var _current_anim := ""
var _coyote := 0.0
var _jump_buffer := 0.0
var _jumped := false
var _script_from := Vector3.ZERO
var _script_to := Vector3.ZERO
var _script_face := 0.0
var _script_time := 0.0
var _script_done: Callable
var _query_shape: CapsuleShape3D
var _knock_cooldown := 0.0
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _skeleton: Skeleton3D
## Foot and toe bones, [left, right], and whether each foot is lifted (a
## step plays when it comes down again).
var _feet := PackedInt32Array()
var _toes := PackedInt32Array()
var _foot_up := [false, false]
var _steps: Array[AudioStreamPlayer3D] = []
var _step_i := 0
var _rng := RandomNumberGenerator.new()
## Time in the air of the last drop, until the landing is played (0 = none).
var _landed_air := 0.0
var _land_time := 0.0
## Physics ticks counted: the vehicle check and the footstep check take turns
## (60 Hz each is plenty).
var _tick := 0
## Surface -> [AudioStream] (shared by every character).
static var _step_streams := {}


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	if get_node_or_null("Controllable") == null:
		var c := Controllable.new()
		c.name = "Controllable"
		c.kind = Controllable.CHARACTER
		add_child(c)
	collision_layer = LAYER
	collision_mask = MASK
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_block_on_wall = true
	safe_margin = 0.02
	var cs := get_node_or_null("Shape") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "Shape"
		add_child(cs)
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3.UP * height * 0.5
	_query_shape = CapsuleShape3D.new()
	_query_shape.radius = radius + 0.02
	_query_shape.height = height - 0.2
	_shape_query.shape = _query_shape
	_shape_query.collision_mask = 2  # vehicles
	_model = get_node_or_null("Model") as Node3D
	if _model:
		var players := _model.find_children("*", "AnimationPlayer", true, false)
		_anim = players[0] as AnimationPlayer if not players.is_empty() else null
		for gi in _model.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			(gi as GeometryInstance3D).layers = Vehicle.VISUAL_LAYER
	_resolve_clips()
	_play("idle", 0.0)
	_setup_steps()


# --- Used by the Possession ------------------------------------------------

## Shape used to test whether the character fits somewhere (a little slimmer
## top and bottom than the real capsule, lifted off the ground).
func query_shape() -> Shape3D:
	return _query_shape


## Height of the query shape's centre above the feet.
func query_shape_center() -> float:
	return 0.15 + _query_shape.height * 0.5


## Free to start something (getting into a vehicle...).
func can_act() -> bool:
	return state == State.ACTIVE


## Puts the character at `xform` (feet; only the heading of the basis is
## used), standing still.
func place(xform: Transform3D) -> void:
	var fwd := -xform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		facing = atan2(-fwd.x, -fwd.z)
	global_transform = Transform3D(Basis.IDENTITY, xform.origin)
	velocity = Vector3.ZERO
	ground_speed = 0.0
	airtime = 0.0
	_jumped = false
	_land_time = 0.0
	_landed_air = 0.0
	_apply_facing()
	reset_physics_interpolation()
	if state != State.HIDDEN:
		_set_state(State.ACTIVE)
	_play("idle", 0.0)


## Hidden = in a vehicle: invisible, no collisions, no physics, no animation.
func set_hidden(hidden: bool) -> void:
	visible = not hidden
	if _anim:
		_anim.active = not hidden
	collision_layer = 0 if hidden else LAYER
	collision_mask = 0 if hidden else MASK
	velocity = Vector3.ZERO
	move_input = Vector3.ZERO
	jump_input = false
	_set_state(State.HIDDEN if hidden else State.ACTIVE)
	if not hidden:
		_play("idle", 0.0)


## Walks (scripted, no collisions) to `point` in `seconds`, turning to face
## `face` (world direction), then calls `done`.
func walk_to(point: Vector3, face: Vector3, seconds: float, done: Callable) -> void:
	_script_from = global_position
	_script_to = point
	face.y = 0.0
	_script_face = atan2(-face.x, -face.z) if face.length() > 0.01 else facing
	_script_time = maxf(seconds, 0.01)
	_script_done = done
	collision_mask = 0
	velocity = Vector3.ZERO
	_set_state(State.SCRIPTED)


# --- Simulation ------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	state_time = 0.0


func _physics_process(dt: float) -> void:
	state_time += dt
	_knock_cooldown -= dt
	match state:
		State.HIDDEN:
			return
		State.SCRIPTED:
			_scripted(dt)
			return
		State.KNOCKED:
			if state_time > 0.9 and is_on_floor():
				_set_state(State.ACTIVE)
	_move(dt)
	_tick += 1
	if _tick % 2 == 0:
		_check_vehicles()
	else:
		_footsteps()
	_animate()


func _scripted(dt: float) -> void:
	var t := clampf(state_time / _script_time, 0.0, 1.0)
	var k := t * t * (3.0 - 2.0 * t)
	var p := _script_from.lerp(_script_to, k)
	var step := p.distance_to(global_position)
	global_position = p
	ground_speed = step / maxf(dt, 0.0001)
	facing = lerp_angle(facing, _script_face, 1.0 - exp(-14.0 * dt))
	_apply_facing()
	_play("walk" if ground_speed > 0.3 else "idle", 0.15)
	if _anim and _current_anim == "walk":
		_anim.speed_scale = clampf(ground_speed / walk_anim_speed, 0.6, 1.6)
	if t >= 1.0:
		collision_mask = MASK
		_set_state(State.ACTIVE)
		var done := _script_done
		_script_done = Callable()
		if done.is_valid():
			done.call()


func target_speed() -> float:
	var mag := clampf(move_input.length(), 0.0, 1.0)
	if mag < 0.08:
		return 0.0
	if walk_input:
		return walk_speed * clampf(mag / 0.6, 0.4, 1.0)
	if sprint_input and mag > 0.5:
		return sprint_speed
	# Analog stick: a gentle push walks, further runs. Keys are always 1 (run).
	if mag <= 0.6:
		return walk_speed * maxf(mag / 0.6, 0.4)
	return lerpf(walk_speed, run_speed, (mag - 0.6) / 0.4)


func _move(dt: float) -> void:
	var on_floor := is_on_floor()
	var control := state == State.ACTIVE
	var dir := Vector3(move_input.x, 0.0, move_input.z)
	if dir.length() > 0.001:
		dir = dir.normalized()
	var want := dir * target_speed() if control else Vector3.ZERO
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if control:
		var accel := ground_accel if on_floor else air_accel
		# Turning round or stopping is quicker than speeding up.
		if on_floor and (want.length() < horiz.length() or want.dot(horiz) < 0.0):
			accel *= 1.4
		horiz = horiz.move_toward(want, accel * dt)
	elif on_floor:
		horiz = horiz.move_toward(Vector3.ZERO, 9.0 * dt)
	velocity.x = horiz.x
	velocity.z = horiz.z

	# Jumping: a short grace period after walking off an edge, and a press
	# just before landing still counts.
	_coyote = 0.12 if on_floor else _coyote - dt
	_jump_buffer = 0.12 if jump_input else _jump_buffer - dt
	jump_input = false
	if control and _jump_buffer > 0.0 and _coyote > 0.0 and not _jumped:
		velocity.y = jump_speed
		_jumped = true
		_coyote = 0.0
		_jump_buffer = 0.0
		on_floor = false
		_play("jump", 0.06, jump_anim_offset)
	if not on_floor:
		velocity.y -= _gravity * dt
		airtime += dt
	else:
		if airtime > 0.0:
			_landed_air = airtime
		airtime = 0.0
		if velocity.y <= 0.0:
			_jumped = false

	if on_floor and horiz.length() > 0.2:
		_step_up(horiz * dt)
	move_and_slide()
	_push_props()

	ground_speed = Vector3(velocity.x, 0.0, velocity.z).length()
	var face_dir := horiz if horiz.length() > 0.3 else (dir if control and dir.length() > 0.0 else Vector3.ZERO)
	if face_dir.length() > 0.01:
		var rate := turn_speed * (0.7 if ground_speed > run_speed + 0.5 else 1.0)
		if not on_floor:
			rate *= 0.4
		facing = lerp_angle(facing, atan2(-face_dir.x, -face_dir.z), 1.0 - exp(-rate * dt))
		_apply_facing()


## Climbs kerbs and steps: if the way ahead is blocked at the feet but clear
## a step higher, and there's floor to stand on up there, hop up onto it.
func _step_up(motion: Vector3) -> void:
	var probe := motion.normalized() * maxf(motion.length(), radius * 0.5)
	if not test_move(global_transform, probe):
		return
	var up := Vector3.UP * step_height
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return  # a wall, not a step
	var col := KinematicCollision3D.new()
	var ahead := raised.translated(probe)
	if not test_move(ahead, Vector3.DOWN * (step_height + 0.05), col):
		return
	if col.get_normal().y < 0.7:
		return
	var rise := step_height - col.get_travel().length()
	if rise < 0.02:
		return
	global_position += Vector3.UP * (rise + 0.01)
	velocity.y = maxf(velocity.y, 0.0)


## Walking into light props (cones, bins, crates) shoves them along.
func _push_props() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null or rb is Vehicle or rb.mass > 120.0 or rb.freeze:
			continue
		var push := -col.get_normal()
		push.y = 0.0
		if push.length() < 0.1:
			continue
		var speed := maxf(ground_speed, 1.0)
		rb.apply_impulse(push.normalized() * minf(rb.mass, 40.0) * 0.06 * speed, col.get_position() - rb.global_position)


## A moving vehicle pushing into us knocks us aside (no harm done).
func _check_vehicles() -> void:
	if state != State.ACTIVE or _knock_cooldown > 0.0:
		return
	_shape_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * query_shape_center())
	var hits := get_world_3d().direct_space_state.intersect_shape(_shape_query, 4)
	for hit in hits:
		var v := hit["collider"] as Vehicle
		if v == null:
			continue
		var rel_pos := global_position - v.global_position
		var point_vel := v.linear_velocity + v.angular_velocity.cross(rel_pos)
		var rel := point_vel - velocity
		rel.y = 0.0
		var strength := rel.length()
		if strength < 1.2:
			continue
		# Shoved mostly sideways, out of the vehicle's path (so it doesn't
		# run into us again), carried along a little.
		var flat_vel := Vector3(point_vel.x, 0.0, point_vel.z)
		var along := flat_vel.normalized() if flat_vel.length() > 0.1 else Vector3.ZERO
		var side := Vector3(rel_pos.x, 0.0, rel_pos.z)
		side -= along * side.dot(along)
		if side.length() < 0.2:
			side = along.cross(Vector3.UP)
		var push := flat_vel * 0.5 + side.normalized() * (3.0 + strength * 0.35)
		velocity = push + Vector3.UP * clampf(2.0 + strength * 0.12, 2.0, 5.0)
		_set_state(State.KNOCKED)
		_knock_cooldown = 0.6
		_play("knocked", 0.08)
		knocked.emit(strength)
		return


# --- Footsteps -------------------------------------------------------------

func _setup_steps() -> void:
	_rng.randomize()
	if _model:
		var found := _model.find_children("*", "Skeleton3D", true, false)
		_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if _skeleton:
		for side in ["L", "R"]:
			_feet.append(_skeleton.find_bone("DEF-foot." + side))
			_toes.append(_skeleton.find_bone("DEF-toe." + side))
		if _feet.has(-1) or _toes.has(-1):
			_skeleton = null
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Surface"
		p.unit_size = 4.0
		p.max_db = 0.0
		p.max_distance = 40.0
		p.position = Vector3.UP * 0.05
		add_child(p)
		_steps.append(p)
	if _step_streams.is_empty():
		for key: String in STEP_SOUNDS:
			var takes: Array[AudioStream] = []
			for k in 5:
				var s := load(String(STEP_SOUNDS[key][0]) % (k + 1)) as AudioStream
				if s:
					takes.append(s)
			_step_streams[key] = takes


## A step when a foot (its lowest point: ankle or toe) comes down after
## being lifted; landings from a jump or fall thump with both feet.
func _footsteps() -> void:
	var on_floor := is_on_floor()
	if _landed_air > 0.3:
		_step(land_db + clampf(_landed_air - 0.3, 0.0, 1.0) * 3.0)
		# A real drop: absorb it (unless running straight on).
		if _landed_air > 0.45 and ground_speed < 1.5:
			_land_time = 0.45
	_landed_air = 0.0
	if _skeleton == null or not on_floor or ground_speed < 0.3:
		_foot_up = [false, false]
		return
	var gait := 0 if ground_speed < (walk_speed + run_speed) * 0.5 else (1 if ground_speed < (run_speed + sprint_speed) * 0.5 else 2)
	for i in 2:
		var low := minf(_skeleton.get_bone_global_pose(_feet[i]).origin.y - 0.09, _skeleton.get_bone_global_pose(_toes[i]).origin.y)
		if low > 0.1:
			_foot_up[i] = true
		elif low < 0.05 and _foot_up[i]:
			_foot_up[i] = false
			_step(step_db[gait])


func _step(db: float) -> void:
	if _steps.is_empty():
		return
	var key := _surface()
	var takes: Array = _step_streams.get(key, [])
	if takes.is_empty():
		return
	var p := _steps[_step_i]
	_step_i = (_step_i + 1) % _steps.size()
	p.stream = takes[_rng.randi() % takes.size()]
	p.volume_db = db + float(STEP_SOUNDS[key][1])
	p.pitch_scale = _rng.randf_range(0.92, 1.08)
	p.play()


## What's underfoot: "wood" (piers, marked with meta "surface"), "grass"
## (the terrain: its body has a surface_grip below 0.95) or "concrete".
func _surface() -> String:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.5, MASK)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "concrete"
	var col := hit["collider"] as CollisionObject3D
	if col == null:
		return "concrete"
	var owner_id := col.shape_find_owner(int(hit["shape"]))
	var shape_node := col.shape_owner_get_owner(owner_id) if owner_id >= 0 else null
	if shape_node and shape_node.has_meta("surface"):
		return String(shape_node.get_meta("surface"))
	if col.has_meta("surface"):
		return String(col.get_meta("surface"))
	if col.has_meta("surface_grip") and float(col.get_meta("surface_grip")) < 0.95:
		return "grass"
	return "concrete"


# --- Animation -------------------------------------------------------------

func _apply_facing() -> void:
	if _model:
		_model.rotation.y = facing


func _resolve_clips() -> void:
	_clips.clear()
	if _anim == null:
		return
	var names := _anim.get_animation_list()
	for key: String in ANIMS:
		var found := ""
		for cand: String in ANIMS[key]:
			for n: String in names:
				if n.to_lower() == cand:
					found = n
					break
			if found != "":
				break
		if found == "":
			for cand: String in ANIMS[key]:
				for n: String in names:
					if n.to_lower().contains(cand):
						found = n
						break
				if found != "":
					break
		if found != "":
			_clips[key] = found
	for key in ["idle", "walk", "run", "sprint", "fall"]:
		if _clips.has(key):
			var a := _anim.get_animation(_clips[key])
			if a:
				a.loop_mode = Animation.LOOP_LINEAR


func has_clip(key: String) -> bool:
	return _clips.has(key)


func _play(key: String, blend: float, from := 0.0) -> void:
	if _anim == null:
		return
	if not _clips.has(key):
		key = {"sprint": "run", "run": "walk", "land": "idle", "jump": "fall", "knocked": "fall"}.get(key, "idle")
		if not _clips.has(key):
			key = "idle"
		if not _clips.has(key):
			return
	if key == _current_anim:
		return
	_current_anim = key
	_anim.play(_clips[key], blend)
	if from > 0.0:
		_anim.seek(from, true)
	_anim.speed_scale = 1.0


func _animate() -> void:
	if _anim == null:
		return
	if state == State.KNOCKED:
		if state_time > 0.3 and not is_on_floor():
			_play("fall", 0.2)
		return
	if not is_on_floor() and (airtime > 0.18 or _jumped):
		if _current_anim != "jump" or (_anim.current_animation_position >= _anim.current_animation_length - 0.05) or velocity.y < -1.0:
			_play("fall", 0.25)
		return
	var s := ground_speed
	_land_time -= get_physics_process_delta_time()
	if _land_time > 0.0 and s < 1.5:
		_play("land", 0.08)
		_anim.speed_scale = 1.3
		return
	var key := "idle"
	# Thresholds with a little hysteresis around the current gait.
	var up := 0.15 if _current_anim in ["walk", "run", "sprint"] else 0.0
	if s > 0.25 - up:
		key = "walk"
	if s > (walk_speed + run_speed) * 0.5 - up:
		key = "run"
	if s > (run_speed + sprint_speed) * 0.5 - up:
		key = "sprint"
	_play(key, 0.22 if key != "idle" else 0.3)
	match _current_anim:
		"walk":
			_anim.speed_scale = clampf(s / walk_anim_speed, 0.55, 1.5)
		"run":
			_anim.speed_scale = clampf(s / run_anim_speed, 0.7, 1.35)
		"sprint":
			_anim.speed_scale = clampf(s / sprint_anim_speed, 0.75, 1.3)
		_:
			_anim.speed_scale = 1.0
