class_name Replay
extends Node
## Instant replay and the slow-motion crash cam. Keeps the last RECORD_SECONDS
## of the player's vehicle (body, wheels) and the traffic around it, and plays
## a stretch of it back with camera cuts while the game is paused. Afterwards
## everything is put back exactly as it was, so driving carries on as if
## nothing happened. (Damage, debris and props aren't recorded: they show as
## they are now.)

signal finished

const RECORD_SECONDS := 10.0
const SAMPLE_EVERY := 2  # physics ticks (60 samples a second at 120 Hz)
const NEARBY := 120.0
const SHOT_SECONDS := 2.4

var game: Game
var playing := false
## Seconds of game time recorded so far (sample timestamps use this clock).
var now := 0.0

## Samples, oldest first: {"t", "player": Transform3D, "wheels": [[wheel, visual]],
## "others": {instance_id: Transform3D}, "cut": bool (teleported just before)}
var _samples: Array[Dictionary] = []
var _tick := 0
var _cut := false
var _play_t := 0.0
var _play_from := 0.0
var _play_to := 0.0
var _speed := 1.0
var _focus := Vector3.INF  # crash cam: where the crash happened
var _restore := []  # [body, transform, linear velocity, angular velocity, visible]
var _wheel_restore := []
var _camera: Camera3D
var _shot := -1
var _anchor := Vector3.ZERO
var _overlay: CanvasLayer
var _title: Label
var _dot: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = Camera3D.new()
	_camera.name = "ReplayCamera"
	_camera.far = 3000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_build_overlay()


## Forgets everything (the player changed vehicle).
func clear() -> void:
	_samples.clear()


## The car was teleported: don't blend across the jump.
func mark_cut() -> void:
	_cut = true


func _physics_process(dt: float) -> void:
	if playing or get_tree().paused or game == null or game.state != Game.State.DRIVING or not game.driving() or game.is_split():
		return
	now += dt
	_tick += 1
	if _tick % SAMPLE_EVERY != 0:
		return
	var v := game.vehicle
	var wheels := []
	for w in v.wheels:
		var vis := w.get_node_or_null("Visual") as Node3D
		wheels.append([w.transform, vis.transform if vis else Transform3D.IDENTITY])
	var others := {}
	if game.traffic:
		for o in game.traffic.vehicles:
			if o != v and is_instance_valid(o) and o.global_position.distance_squared_to(v.global_position) < NEARBY * NEARBY:
				others[o.get_instance_id()] = o.global_transform
	_samples.append({"t": now, "player": v.global_transform, "wheels": wheels, "others": others, "cut": _cut})
	_cut = false
	while not _samples.is_empty() and now - float(_samples[0]["t"]) > RECORD_SECONDS:
		_samples.pop_front()


## Seconds of recording available.
func recorded() -> float:
	if _samples.size() < 2:
		return 0.0
	return float(_samples[_samples.size() - 1]["t"]) - float(_samples[0]["t"])


## Instant replay: the last `seconds` at `speed`.
func play_last(seconds := RECORD_SECONDS, speed := 1.0) -> bool:
	return play_range(now - seconds, now, speed)


## Plays recorded time `from_t`..`to_t` at `speed`. With a `focus` point it's
## the crash cam: one slow shot around that spot. False if there's nothing
## recorded to play.
func play_range(from_t: float, to_t: float, speed: float, focus := Vector3.INF) -> bool:
	if playing or recorded() < 1.0:
		return false
	_play_from = maxf(from_t, float(_samples[0]["t"]))
	_play_to = minf(to_t, float(_samples[_samples.size() - 1]["t"]))
	if _play_to - _play_from < 0.5:
		return false
	playing = true
	_play_t = _play_from
	_speed = speed
	_focus = focus
	_shot = -1
	# Remember the live state to put back afterwards.
	_restore.clear()
	var bodies: Array[Vehicle] = [game.vehicle]
	if game.traffic:
		for o in game.traffic.vehicles:
			if o != game.vehicle and is_instance_valid(o):
				bodies.append(o)
	for b in bodies:
		_restore.append([b, b.global_transform, b.linear_velocity, b.angular_velocity, b.visible])
	_wheel_restore.clear()
	for w in game.vehicle.wheels:
		var vis := w.get_node_or_null("Visual") as Node3D
		_wheel_restore.append([w.transform, vis.transform if vis else Transform3D.IDENTITY])
	var crash := focus != Vector3.INF
	_title.text = "CRASH CAM" if crash else "REPLAY"
	_overlay.visible = true
	_camera.current = true
	_apply(_play_t)
	return true


func stop() -> void:
	if not playing:
		return
	playing = false
	for r: Array in _restore:
		var b: Vehicle = r[0]
		if is_instance_valid(b):
			b.global_transform = r[1]
			b.linear_velocity = r[2]
			b.angular_velocity = r[3]
			b.visible = r[4]
			b.reset_physics_interpolation()
	_set_wheels(_wheel_restore)
	_restore.clear()
	_overlay.visible = false
	game.possession.show_camera()
	finished.emit()


func _process(dt: float) -> void:
	if not playing:
		return
	_dot.modulate.a = 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6 else 0.15
	_play_t += dt * _speed
	if _play_t >= _play_to:
		stop()
		return
	_apply(_play_t)


## Puts every recorded vehicle where it was at replay time `t`.
func _apply(t: float) -> void:
	var i := 0
	while i < _samples.size() - 2 and float(_samples[i + 1]["t"]) <= t:
		i += 1
	var a: Dictionary = _samples[i]
	var b: Dictionary = _samples[i + 1]
	var f := clampf((t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001), 0.0, 1.0)
	if b["cut"]:
		f = 0.0
	var v := game.vehicle
	var xf := (a["player"] as Transform3D).interpolate_with(b["player"], f)
	v.global_transform = xf
	v.reset_physics_interpolation()
	_set_wheels(a["wheels"])
	var ao: Dictionary = a["others"]
	var bo: Dictionary = b["others"]
	for r: Array in _restore:
		var o: Vehicle = r[0]
		if o == v or not is_instance_valid(o):
			continue
		var id := o.get_instance_id()
		# Cars that weren't nearby then (or didn't exist yet) are hidden.
		o.visible = ao.has(id)
		if o.visible:
			o.global_transform = (ao[id] as Transform3D).interpolate_with(bo[id], f) if bo.has(id) else ao[id]
			o.reset_physics_interpolation()
	_update_camera(xf)


func _set_wheels(poses: Array) -> void:
	var wheels := game.vehicle.wheels
	for k in mini(wheels.size(), poses.size()):
		var pose: Array = poses[k]
		wheels[k].transform = pose[0]
		var vis := wheels[k].get_node_or_null("Visual") as Node3D
		if vis:
			vis.transform = pose[1]


func _update_camera(car_xf: Transform3D) -> void:
	var car := car_xf.origin + Vector3.UP * 0.7
	var fwd := -car_xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var elapsed := _play_t - _play_from
	var want: Vector3
	if _focus != Vector3.INF:
		# Crash cam: low and to the side of the crash, slowly circling it.
		if _shot < 0:
			_shot = 0
			_anchor = right  # side-on to the way the car came in
		var dir := _anchor.rotated(Vector3.UP, elapsed * 0.35)
		want = _focus + dir * 9.0 + Vector3.UP * 2.2
	else:
		var shot := int(elapsed / SHOT_SECONDS) % 3
		if shot != _shot or _anchor.distance_to(car) > 90.0:
			_shot = shot
			# Trackside: a spot ahead of the car that it drives past.
			var side := 1.0 if (int(elapsed / SHOT_SECONDS) / 3) % 2 == 0 else -1.0
			_anchor = car + fwd * 18.0 + right * 7.0 * side + Vector3.UP * 1.0
		match shot:
			0:
				want = _anchor
			1:
				want = car - fwd * 7.0 + right * 2.5 + Vector3.UP * 1.6
			_:
				var ang := elapsed * 0.5
				want = car + Vector3(cos(ang) * 10.0, 5.0, sin(ang) * 10.0)
	want = _unblocked(car, want)
	_camera.global_position = want
	if want.distance_to(car) > 0.5:
		_camera.look_at(car, Vector3.UP)
	# Zoom in on far-away cars so they stay a good size on screen.
	_camera.fov = clampf(rad_to_deg(2.0 * atan(5.0 / maxf(want.distance_to(car), 0.1))), 14.0, 62.0)


## `want`, pulled in towards the car if a wall or hill is in the way, and
## kept above the ground.
func _unblocked(car: Vector3, want: Vector3) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(car, want, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		want = (hit["position"] as Vector3) + (car - want).normalized() * 0.4
	if game.world and game.world.terrain:
		want.y = maxf(want.y, game.world.terrain.height_at(want.x, want.z) + 0.6)
	return want


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 5
	_overlay.visible = false
	add_child(_overlay)
	# Letterbox bars for a TV-replay look.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		else:
			bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.anchor_top = 0.0 if top else 0.9
		bar.anchor_bottom = 0.1 if top else 1.0
		bar.offset_top = 0
		bar.offset_bottom = 0
		_overlay.add_child(bar)
	var row := HBoxContainer.new()
	row.position = Vector2(36, 18)
	row.add_theme_constant_override("separation", 10)
	_overlay.add_child(row)
	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(20, 20)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.add_theme_stylebox_override("panel", UiKit.box(Color(1.0, 0.25, 0.2), 10, 0))
	row.add_child(_dot)
	_title = UiKit.label("REPLAY", 34, Color.WHITE)
	row.add_child(_title)
	var hint := UiKit.label("Enter / A: skip", 20, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -36
	hint.offset_bottom = -22
	_overlay.add_child(hint)
