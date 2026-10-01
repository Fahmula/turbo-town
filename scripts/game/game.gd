class_name Game
extends Node3D
## Top-level game flow: title screen, pause menu, the garage (changing
## vehicle), spawning/teleporting the player, respawn after falling in the
## sea, applying settings, the replay / crash cam, and wiring the HUD to
## vehicle events.

enum State { TITLE, DRIVING, PAUSED, GARAGE, REPLAY }

## Crash cam: how big a crash (0..1) triggers it, how long to keep recording
## after the hit, and the least time between two automatic crash cams.
const CRASH_CAM_SEVERITY := 0.5
const CRASH_CAM_AFTER := 1.1
const CRASH_CAM_BEFORE := 1.7
const CRASH_CAM_SPEED := 0.35
const CRASH_CAM_COOLDOWN := 20.0

@export var world: WorldBuilder
@export var vehicle: Vehicle
@export var controller: PlayerVehicleController
@export var camera: ChaseCamera
@export var hud: Hud
@export var traffic: TrafficManager

var state := State.DRIVING
var spawn_index := 0
var picker: VehiclePicker
var menu: GameMenu
var title_camera: MenuCamera
var stunts: StuntTracker
var world_map: WorldMap
var race: RaceManager
var day_night: DayNight
var replay: Replay
## Start on the title screen. Off for dev/test runs (they pass command-line
## args) so they start driving straight away.
var show_title := OS.get_cmdline_user_args().is_empty()
var _garage_from := State.DRIVING
var _lost_timer := 0.0
var _crash_wait := -1.0
var _crash_time := 0.0
var _crash_pos := Vector3.ZERO
var _last_crash_cam := -INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Gameplay (world, traffic, the car...) stops while the tree is paused;
	# menus, the HUD and the replay set themselves to keep running.
	for child in get_children():
		if child.process_mode == Node.PROCESS_MODE_INHERIT:
			child.process_mode = Node.PROCESS_MODE_PAUSABLE
	picker = VehiclePicker.new()
	picker.name = "VehiclePicker"
	add_child(picker)
	picker.picked.connect(_on_vehicle_picked)
	picker.cancelled.connect(_on_garage_cancelled)
	menu = GameMenu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.action.connect(_on_menu_action)
	title_camera = MenuCamera.new()
	title_camera.name = "TitleCamera"
	add_child(title_camera)
	replay = Replay.new()
	replay.name = "Replay"
	replay.game = self
	add_child(replay)
	replay.finished.connect(_on_replay_finished)
	vehicle.vehicle_reset.connect(replay.mark_cut)

	stunts = StuntTracker.new()
	stunts.name = "Stunts"
	stunts.process_mode = Node.PROCESS_MODE_PAUSABLE
	stunts.traffic = traffic
	add_child(stunts)
	stunts.trick.connect(_on_trick)
	stunts.combo_changed.connect(hud.show_combo)
	stunts.combo_banked.connect(_on_combo_banked)
	stunts.combo_lost.connect(func(reason: String) -> void: hud.show_popup(reason, 1.6, Color(1.0, 0.35, 0.3)))
	Records.record_broken.connect(func(what: String) -> void: hud.show_toast("NEW RECORD: %s!" % what, 3.0))
	var t0 := Time.get_ticks_msec()
	world_map = WorldMap.new(world)
	world_map.name = "WorldMap"
	add_child(world_map)
	print("World map drawn in %d ms" % (Time.get_ticks_msec() - t0))
	var spots: Array = []
	for sp: Dictionary in world.spawn_points:
		spots.append({"name": sp["name"], "pos": (sp["xform"] as Transform3D).origin})
	hud.setup_map(world_map, traffic, spots)
	hud.minimap.visible = Settings.get_value("minimap")
	race = RaceManager.new()
	race.name = "Races"
	race.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(race)
	race.setup(self)
	race.finished.connect(_on_race_finished)
	vehicle.vehicle_reset.connect(race.on_teleport)
	hud.race = race
	menu.races = race.races
	_load_choice()
	stunts.vehicle = vehicle
	_watch_damage(vehicle)
	vehicle.traction_control = Settings.get_value("assists")
	hud.speedometer.use_mph = Settings.get_value("units_mph")
	Settings.changed.connect(_on_setting_changed)
	GraphicsQuality.apply(Settings.get_value("graphics"), get_viewport(), world)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(day_night)
	day_night.setup(world)
	day_night.night_changed.connect(func(_on: bool) -> void: _fit_headlights())
	day_night.set_mode(Settings.get_value("time_of_day"))
	_fit_headlights()
	teleport_to(0)
	if show_title:
		_enter_title()
	else:
		_enter_driving()


func teleport_to(index: int) -> void:
	if world.spawn_points.is_empty():
		return
	if race and race.is_active():
		race.end_race()
	spawn_index = wrapi(index, 0, world.spawn_points.size())
	var sp: Dictionary = world.spawn_points[spawn_index]
	vehicle.teleport(sp["xform"])
	camera.snap()
	if state == State.DRIVING:
		hud.show_toast(sp["name"])


func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	# Fell into the sea or off the island: respawn after a moment.
	var p := vehicle.global_position
	var lost := p.y < MapLayout.SEA_LEVEL - 0.8 or p.y < -60.0 or absf(p.x) > 1500.0 or absf(p.z) > 1500.0
	if lost:
		if _lost_timer == 0.0:
			hud.show_popup("SPLASH!" if p.y > -60.0 else "WHOOPS!")
		_lost_timer += dt
		if _lost_timer > 2.0:
			_lost_timer = 0.0
			respawn()
	else:
		_lost_timer = 0.0
	if _crash_wait >= 0.0:
		_crash_wait -= dt
		if _crash_wait < 0.0 and state == State.DRIVING and not race.is_active():
			start_replay(true)


func _on_trick(trick_name: String, _points: int) -> void:
	if trick_name != "NEAR MISS" and not trick_name.begins_with("AIR "):
		hud.show_popup(trick_name + "!", 1.3)


func _on_combo_banked(points: int, _place: int) -> void:
	hud.set_score(stunts.score)
	if points >= 300:
		hud.show_popup("+%s" % Hud.format_points(points), 1.5, Color(0.5, 1.0, 0.45))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		get_tree().quit()
		return
	if state == State.REPLAY:
		for skip in ["menu_accept", "menu_back", "pause", "instant_replay"]:
			if event.is_action_pressed(skip):
				replay.stop()
				get_viewport().set_input_as_handled()
				return
	if state != State.DRIVING:
		return  # menus and the garage read their own input
	if event.is_action_pressed("pause"):
		_enter_pause()
	elif event.is_action_pressed("instant_replay"):
		if not start_replay():
			hud.show_toast("Nothing to replay yet")
	elif event.is_action_pressed("change_vehicle"):
		open_garage()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("respawn"):
		respawn()
	elif event.is_action_pressed("teleport_next"):
		teleport_to(spawn_index + 1)
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("toggle_map"):
		hud.toggle_big_map()
	elif event.is_action_pressed("toggle_traffic") and traffic:
		traffic.set_enabled(not traffic.enabled)
		hud.show_toast("Traffic ON" if traffic.enabled else "Traffic OFF")
	elif event.is_action_pressed("toggle_units"):
		Settings.set_value("units_mph", not Settings.get_value("units_mph"))
	elif event.is_action_pressed("toggle_traction_control"):
		Settings.set_value("assists", not Settings.get_value("assists"))
		hud.show_toast("Assists ON" if vehicle.traction_control else "Assists OFF - drift mode!")
	else:
		for i in mini(9, world.spawn_points.size()):
			if event.is_action_pressed("teleport_%d" % (i + 1)):
				teleport_to(i)
				break


## Back to the spawn point, or during a race to the last gate passed.
func respawn() -> void:
	if race and race.is_active():
		vehicle.teleport(race.respawn_point())
		camera.snap()
	else:
		teleport_to(spawn_index)


func _on_race_finished(r: Dictionary, t: float, medal: int, best: bool) -> void:
	hud.show_popup("FINISH!  %s" % RaceCatalog.format_time(t), 3.0, Color(0.4, 1.0, 0.45))
	var msg := ""
	if medal >= 0:
		msg = "%s MEDAL!" % RaceCatalog.MEDAL_NAMES[medal]
	else:
		msg = "Gold time: %s" % RaceCatalog.format_time(r["medals"][0])
	if best:
		msg += "   NEW BEST TIME!"
	hud.show_toast(msg, 5.0)


# --- Replay / crash cam ------------------------------------------------------

## Instant replay of the last few seconds, or (`crash`) the slow-motion crash
## cam around the last big crash. False if there's nothing to show.
func start_replay(crash := false) -> bool:
	if state != State.DRIVING:
		return false
	var ok := false
	if crash:
		ok = replay.play_range(_crash_time - CRASH_CAM_BEFORE, _crash_time + CRASH_CAM_AFTER, CRASH_CAM_SPEED, _crash_pos)
	else:
		ok = replay.play_last(8.0, 1.0)
	if not ok:
		return false
	_crash_wait = -1.0
	state = State.REPLAY
	get_tree().paused = true
	hud.visible = false
	return true


func _on_replay_finished() -> void:
	if state == State.REPLAY:
		state = State.PAUSED  # so _enter_driving doesn't treat it as the title
		_enter_driving()


func _on_crash(severity: float) -> void:
	if severity < CRASH_CAM_SEVERITY or _crash_wait >= 0.0 or not Settings.get_value("crash_cam"):
		return
	if state != State.DRIVING or race.is_active() or replay.now - _last_crash_cam < CRASH_CAM_COOLDOWN:
		return
	_last_crash_cam = replay.now
	_crash_time = replay.now
	_crash_pos = vehicle.global_position
	_crash_wait = CRASH_CAM_AFTER


# --- States -----------------------------------------------------------------

func _enter_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	controller.enabled = false
	stunts.enabled = false
	hud.visible = false
	title_camera.target = vehicle
	title_camera.current = true
	menu.set_ride_name(vehicle.display_name)
	menu.show_page("title")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enter_driving() -> void:
	var from_title := state == State.TITLE
	state = State.DRIVING
	get_tree().paused = false
	controller.enabled = true
	stunts.enabled = true
	hud.visible = true
	camera.current = true
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if from_title:
		camera.snap()
		hud.show_help_for(14.0)


func _enter_pause() -> void:
	state = State.PAUSED
	menu.racing = race.is_active()
	get_tree().paused = true
	hud.visible = false
	menu.show_page("pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_menu_action(action_name: String) -> void:
	match action_name:
		"drive", "resume":
			_enter_driving()
		"garage":
			open_garage()
		"title":
			race.end_race()
			_enter_title()
		"quit":
			get_tree().quit()
		"end_race":
			race.end_race()
			_enter_driving()
		_:
			if action_name.begins_with("race:"):
				_enter_driving()
				race.start(int(action_name.substr(5)))


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"assists":
			vehicle.traction_control = value
		"units_mph":
			hud.speedometer.use_mph = value
		"minimap":
			hud.minimap.visible = value
		"graphics":
			GraphicsQuality.apply(value, get_viewport(), world)
			get_tree().call_group("night_lights", "set_night", day_night.is_night)
		"time_of_day":
			day_night.set_mode(value)


# --- Garage / changing vehicle -----------------------------------------------

func open_garage() -> void:
	race.end_race()
	_garage_from = state
	state = State.GARAGE
	get_tree().paused = true
	hud.visible = false
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	picker.open(VehicleCatalog.index_of_vehicle(vehicle), _paint_of(vehicle))


func _on_garage_cancelled() -> void:
	match _garage_from:
		State.TITLE:
			_enter_title()
		State.PAUSED:
			_enter_pause()
		_:
			_enter_driving()


func _on_vehicle_picked(index: int, color: Color) -> void:
	if index == VehicleCatalog.index_of_vehicle(vehicle):
		var body := vehicle.get_node_or_null("Body") as VehicleBodyVisual
		if body:
			body.set_paint_color(color)
	else:
		change_vehicle(index, color)
	_save_choice(index, color)
	# Coming from the title screen, picking a vehicle starts the game.
	if _garage_from == State.TITLE:
		state = State.TITLE
	_enter_driving()
	hud.show_toast(VehicleCatalog.ENTRIES[index]["name"])


## Replaces the player's vehicle with catalog entry `index`, parked upright where
## the old one was (or at the current spawn point if there's no room there).
## With `place_here` false the caller positions it (e.g. a teleport right after).
func change_vehicle(index: int, color: Color, place_here := true) -> void:
	var old := vehicle
	var car := VehicleCatalog.scene(index).instantiate() as Vehicle
	car.traction_control = old.traction_control
	var body := car.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.paint_color = color
	var spot := _find_room(car, old) if place_here else {}

	var slot := old.get_index()
	remove_child(old)
	old.queue_free()
	car.name = "PlayerCar"
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Put it in place before it enters the tree (see TrafficManager._spawn).
	if not spot.is_empty():
		car.transform = spot["xform"]
	elif not world.spawn_points.is_empty():
		car.transform = world.spawn_points[spawn_index]["xform"]
	add_child(car)
	move_child(car, slot)
	vehicle = car
	controller.vehicle = car
	camera.set_target(car)
	title_camera.target = car
	hud.set_vehicle(car)
	if traffic:
		traffic.set_player(car)
	stunts.vehicle = car
	car.vehicle_reset.connect(race.on_teleport)
	car.vehicle_reset.connect(replay.mark_cut)
	replay.clear()
	_watch_damage(car)
	_fit_headlights()
	if not place_here:
		return
	if spot.is_empty():
		teleport_to(spawn_index)
	else:
		car.teleport(spot["xform"])
		camera.snap()


## Where `car` can be placed in place of `old`: {"xform": Transform3D}, or {} if
## the spot is blocked. Traffic cars in the way are removed; light props
## (cones, crates...) just get pushed aside.
func _find_room(car: Vehicle, old: Vehicle) -> Dictionary:
	var base := old.upright_ground_transform()
	var ride := car.ride_height()
	var space := get_world_3d().direct_space_state
	for lift: float in [0.15, 0.8]:
		var xform := base.translated(Vector3.UP * (ride + lift))
		var in_traffic: Array[Vehicle] = []
		var blocked := false
		for child in car.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = xform * cs.transform
			q.collision_mask = 0b111
			q.exclude = [old.get_rid()]
			for hit in space.intersect_shape(q, 16):
				var col: Object = hit["collider"]
				if traffic and col is Vehicle and traffic.driver_of(col):
					in_traffic.append(col as Vehicle)
				elif not (col is RigidBody3D and (col as RigidBody3D).mass < 400.0):
					blocked = true
		if not blocked:
			for v in in_traffic:
				traffic.remove_vehicle(v)
			return {"xform": xform}
	return {}


func _watch_damage(v: Vehicle) -> void:
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg and not dmg.part_lost.is_connected(_on_part_lost):
		dmg.part_lost.connect(_on_part_lost)
		dmg.crashed.connect(_on_crash)


func _on_part_lost(part_name: String) -> void:
	hud.show_toast("%s FELL OFF!" % part_name, 2.0)


## Real headlights on the player's vehicle (only after dark; traffic cars
## just have glowing lamps, to keep the light count low).
func _fit_headlights() -> void:
	if vehicle == null or day_night == null:
		return
	var lights := vehicle.get_node_or_null("Headlights") as Node3D
	if lights == null:
		lights = Node3D.new()
		lights.name = "Headlights"
		vehicle.add_child(lights)
		for side in [-1.0, 1.0]:
			var spot := SpotLight3D.new()
			spot.position = Vector3(side * vehicle.body_half_width * 0.6, 0.45, -vehicle.body_front + 0.2)
			spot.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
			spot.spot_range = 55.0
			spot.spot_angle = 30.0
			spot.light_energy = 4.0
			spot.light_color = Color(1.0, 0.95, 0.85)
			lights.add_child(spot)
	lights.visible = day_night.is_night


func _paint_of(v: Vehicle) -> Color:
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	return body.paint_color if body else Color.RED


func _save_choice(index: int, color: Color) -> void:
	Settings.set_value("vehicle", VehicleCatalog.ENTRIES[index]["id"])
	Settings.set_value("paint", color)


## Puts the player in the vehicle + paint stored in the settings.
func _load_choice() -> void:
	var index := VehicleCatalog.index_of_id(Settings.get_value("vehicle"))
	var color: Color = Settings.get_value("paint")
	if index < 0:
		return
	if index == VehicleCatalog.index_of_vehicle(vehicle):
		var body := vehicle.get_node_or_null("Body") as VehicleBodyVisual
		if body:
			body.set_paint_color(color)
	else:
		change_vehicle(index, color, false)
