class_name RaceManager
extends Node3D
## Checkpoint races. Each race has a glowing start circle in the world (drive
## in and stop, or pick the race in the menu): 3-2-1 countdown, then drive through
## the gates in order. The next gate is lit up, an arrow over the car points
## at it and the minimap marks it. Finish times earn medals and best times.

signal started(race: Dictionary)
signal finished(race: Dictionary, time: float, medal: int, best: bool)
signal ended

enum Phase { IDLE, COUNTDOWN, RACING }

const START_RADIUS := 6.0
const COUNTDOWN := 3.0

var game: Game
var races: Array[Dictionary] = []
var phase := Phase.IDLE
var race: Dictionary = {}
var next_cp := 0
var time := 0.0

var _countdown := 0.0
var _last_count := -1
var _gates: Array[Node3D] = []
var _markers: Array[Node3D] = []
## Which start circles the car was inside last tick. A race starts when you
## drive into its circle and stop there (driving through does nothing, and
## being teleported into one doesn't count).
var _inside: Array[bool] = []
var _armed := -1
var _stopped_time := 0.0
var _skip_check := 0
var _arrow: MeshInstance3D
var _gate_mats: Array[StandardMaterial3D] = []


func setup(g: Game) -> void:
	game = g
	races = RaceCatalog.build(game.world)
	for i in races.size():
		var m := _make_start_marker(races[i])
		add_child(m)
		_markers.append(m)
	_inside.resize(races.size())
	_arrow = _make_arrow()
	_arrow.visible = false
	add_child(_arrow)
	_gate_mats = [_glow(Color(1.0, 0.82, 0.2)), _glow(Color(1, 1, 1, 0.9)), _glow(Color(0.3, 1.0, 0.45))]


func index_of(id: String) -> int:
	for i in races.size():
		if races[i]["id"] == id:
			return i
	return -1


func is_active() -> bool:
	return phase != Phase.IDLE


## Where to put the car back during a race: the last gate passed (facing the
## next one), or the start.
func respawn_point() -> Transform3D:
	if next_cp == 0:
		return race["start"]
	var cps: Array = race["checkpoints"]
	var p: Vector3 = cps[next_cp - 1]
	var fwd: Vector3 = (cps[next_cp] as Vector3) - p
	fwd.y = 0.0
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), p + Vector3.UP * 0.8)


## HUD line while racing.
func status_text() -> String:
	if phase == Phase.COUNTDOWN:
		return "%s   get ready..." % String(race["name"]).to_upper()
	if phase == Phase.RACING:
		return "%s    %s    GATE %d / %d" % [String(race["name"]).to_upper(), RaceCatalog.format_time(time),
			next_cp + 1, (race["checkpoints"] as Array).size()]
	return ""


## Teleports to race `index`'s start and begins the countdown (in the
## player's vehicle, getting them into it if they're on foot).
func start(index: int) -> void:
	end_race(false)
	game.ensure_driving()
	race = races[index]
	game.vehicle.teleport(race["start"])
	game.camera.snap()
	next_cp = 0
	time = 0.0
	_countdown = COUNTDOWN
	_last_count = -1
	phase = Phase.COUNTDOWN
	game.controller.enabled = false
	_build_gates()
	for m in _markers:
		m.visible = false
	_arrow.visible = true
	started.emit(race)


## Stops the race (from the menu, or after finishing).
func end_race(emit := true) -> void:
	if phase == Phase.IDLE and race.is_empty():
		return
	phase = Phase.IDLE
	race = {}
	_skip_check = 2
	_armed = -1
	for g in _gates:
		g.queue_free()
	_gates.clear()
	for m in _markers:
		m.visible = true
	_arrow.visible = false
	if game and game.state == Game.State.DRIVING:
		game.controller.enabled = true
	if emit:
		ended.emit()


func _physics_process(dt: float) -> void:
	if game == null:
		return
	var v := game.vehicle
	match phase:
		Phase.IDLE:
			_check_start_circles(v)
		Phase.COUNTDOWN:
			_countdown -= dt
			var c := ceili(_countdown)
			if c != _last_count and c > 0:
				_last_count = c
				game.hud.show_popup(str(c), 0.9)
			if _countdown <= 0.0:
				phase = Phase.RACING
				game.controller.enabled = true
				game.hud.show_popup("GO!", 1.0, Color(0.4, 1.0, 0.45))
		Phase.RACING:
			time += dt
			var cps: Array = race["checkpoints"]
			var cp: Vector3 = cps[next_cp]
			var flat := Vector2(v.global_position.x - cp.x, v.global_position.z - cp.z).length()
			if flat < float(race["width"]) * 0.5 + 1.5 and absf(v.global_position.y - cp.y) < 7.0:
				_passed()
	if phase != Phase.IDLE:
		_update_arrow(v)
	_update_markers()


## Call after teleporting the player so a circle it lands in doesn't fire.
func on_teleport() -> void:
	_skip_check = 2


func _check_start_circles(v: Vehicle) -> void:
	var allowed := game.state == Game.State.DRIVING and _skip_check <= 0 and game.driving()
	_skip_check -= 1
	for i in races.size():
		var inside := v.global_position.distance_to((races[i]["start"] as Transform3D).origin) < START_RADIUS
		if inside and not _inside[i] and allowed:
			_armed = i
			_stopped_time = 0.0
			if v.linear_velocity.length() < 8.0:  # not when just cruising past
				game.hud.show_toast("RACE: %s - stop in the circle to start" % races[i]["name"], 2.5)
		elif not inside and _armed == i:
			_armed = -1
		_inside[i] = inside
	if _armed >= 0 and allowed:
		_stopped_time = _stopped_time + get_physics_process_delta_time() if v.linear_velocity.length() < 1.5 else 0.0
		if _stopped_time > 0.8:
			var i := _armed
			_armed = -1
			start(i)


func _passed() -> void:
	var cps: Array = race["checkpoints"]
	next_cp += 1
	if next_cp >= cps.size():
		_finish()
		return
	_refresh_gates()
	game.hud.show_toast("CHECKPOINT %d / %d" % [next_cp, cps.size()], 1.2)


func _finish() -> void:
	var r := race
	var t := time
	var medal := RaceCatalog.medal_for(r, t)
	var best := Records.report_race_time(r["id"], t)
	end_race(false)
	finished.emit(r, t, medal, best)


# --- Visuals -------------------------------------------------------------------

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_gates() -> void:
	var cps: Array = race["checkpoints"]
	var w: float = race["width"]
	for i in cps.size():
		var p: Vector3 = cps[i]
		var nxt: Vector3 = cps[i + 1] if i + 1 < cps.size() else p + (p - (cps[i - 1] as Vector3))
		var fwd := nxt - p
		if i > 0:
			fwd = (nxt - p).normalized() + (p - (cps[i - 1] as Vector3)).normalized()
		fwd.y = 0.0
		var gate := _make_gate(w, i == cps.size() - 1, i + 1)
		gate.transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), p)
		add_child(gate)
		_gates.append(gate)
	_refresh_gates()


## Next gate bright yellow, the one after white (green if it's the finish),
## the rest hidden so a loop's finish doesn't show at the start.
func _refresh_gates() -> void:
	for i in _gates.size():
		var g := _gates[i]
		var finish := i == _gates.size() - 1
		g.visible = i == next_cp or i == next_cp + 1
		var mat: StandardMaterial3D = _gate_mats[2] if finish else (_gate_mats[0] if i == next_cp else _gate_mats[1])
		for child in g.get_children():
			if child is MeshInstance3D and child.name != "Curtain":
				(child as MeshInstance3D).material_override = mat
		var curtain := g.get_node_or_null("Curtain") as MeshInstance3D
		if curtain:
			curtain.visible = i == next_cp


func _make_gate(width: float, finish: bool, number: int) -> Node3D:
	var gate := Node3D.new()
	var half := width * 0.5
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.34
		cyl.height = 6.0
		post.mesh = cyl
		post.position = Vector3(side * half, 3.0, 0)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.8, 1.0, 0.4)
	bar.mesh = box
	bar.position = Vector3(0, 6.0, 0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(bar)
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain"
	var quad := QuadMesh.new()
	quad.size = Vector2(width, 5.5)
	curtain.mesh = quad
	curtain.position = Vector3(0, 2.75, 0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 0.85, 0.3, 0.16)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain.material_override = cm
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(curtain)
	var label := Label3D.new()
	label.text = "FINISH" if finish else str(number)
	label.font_size = 96
	label.pixel_size = 0.012
	label.outline_size = 18
	label.modulate = Color(0.08, 0.1, 0.18)
	label.outline_modulate = Color(1, 1, 1)
	label.position = Vector3(0, 6.0, -0.25)
	label.rotation = Vector3(0, PI, 0)
	label.double_sided = true
	gate.add_child(label)
	return gate


func _make_start_marker(r: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.transform = Transform3D(Basis.IDENTITY, (r["start"] as Transform3D).origin + Vector3.DOWN * 0.45)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = START_RADIUS - 0.6
	torus.outer_radius = START_RADIUS
	torus.rings = 48
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	ring.material_override = _glow(Color(0.3, 1.0, 0.45))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = START_RADIUS - 0.5
	cyl.bottom_radius = START_RADIUS - 0.5
	cyl.height = 0.04
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.3, 1.0, 0.45, 0.18)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var label := Label3D.new()
	label.text = "RACE\n%s" % String(r["name"]).to_upper()
	label.font_size = 72
	label.pixel_size = 0.012
	label.outline_size = 16
	label.modulate = Color(0.3, 1.0, 0.45)
	label.outline_modulate = Color(0.05, 0.08, 0.15)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 4.0, 0)
	root.add_child(label)
	return root


## Minimap / big map markers: the next two gates while racing, otherwise the
## race start circles.
func _update_markers() -> void:
	var list: Array[Dictionary] = []
	if phase != Phase.IDLE:
		var cps: Array = race["checkpoints"]
		if next_cp < cps.size():
			list.append({"pos": cps[next_cp], "color": Color(1.0, 0.82, 0.2), "big": true, "pin": true})
		if next_cp + 1 < cps.size():
			list.append({"pos": cps[next_cp + 1], "color": Color(1, 1, 1)})
	else:
		for r in races:
			list.append({"pos": (r["start"] as Transform3D).origin, "color": Color(0.3, 1.0, 0.45)})
	game.hud.minimap.markers = list
	game.hud.big_map.markers = list


func _make_arrow() -> MeshInstance3D:
	var mb := MeshBuilder.new()
	# Flat chevron pointing along -Z.
	var col := Color(1.0, 0.82, 0.2)
	var pts := [Vector3(0, 0, -1.3), Vector3(0.9, 0, 0.3), Vector3(0.35, 0, 0.3), Vector3(0.35, 0, 1.0),
		Vector3(-0.35, 0, 1.0), Vector3(-0.35, 0, 0.3), Vector3(-0.9, 0, 0.3)]
	var c := Vector3(0, 0, 0)
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		mb.add_tri(c, b, a, col)
		mb.add_tri(c, a, b, col)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(_glow(col))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _update_arrow(v: Vehicle) -> void:
	var cps: Array = race.get("checkpoints", [])
	if cps.is_empty():
		return
	var target: Vector3 = cps[mini(next_cp, cps.size() - 1)]
	var top := v.get_global_transform_interpolated().origin + Vector3.UP * (v.body_top + 1.6)
	var to := target - top
	to.y = 0.0
	if to.length() > 0.5:
		_arrow.global_transform = Transform3D(Basis.looking_at(to.normalized(), Vector3.UP), top)
