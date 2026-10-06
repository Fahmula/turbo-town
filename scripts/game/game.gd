class_name Game
extends Node3D
## Top-level game flow: title screen, pause menu, the garage (changing
## vehicle), spawning/teleporting the player, respawn after falling in the
## sea, applying settings, the replay / crash cam, and wiring the HUD to
## vehicle events.
##
## The player is a character who walks around and gets in and out of
## vehicles: the Possession decides what they control (see possession.gd).
## `vehicle` is the player's vehicle: the one they're driving, or on foot the
## one they last drove ("your car", shown on the map). Vehicles they got out
## of before that stay parked for a while (left_vehicles).

## DRIVING = playing (on foot or in a vehicle); the others are menus/replays.
enum State { TITLE, DRIVING, PAUSED, GARAGE, REPLAY }

## Crash cam: how big a crash (0..1) triggers it, how long to keep recording
## after the hit, and the least time between two automatic crash cams.
const CRASH_CAM_SEVERITY := 0.5
const CRASH_CAM_AFTER := 1.1
const CRASH_CAM_BEFORE := 1.7
const CRASH_CAM_SPEED := 0.35
const CRASH_CAM_COOLDOWN := 20.0
## Vehicles the player got out of (besides their current one) that are kept
## parked; older ones go once nobody can see them.
const MAX_LEFT_VEHICLES := 3
## Left vehicles further than this from the player are removed when unseen.
const LEFT_VEHICLE_RANGE := 320.0
const CHARACTER_SCENE := preload("res://scenes/player/player_character.tscn")

@export var world: WorldBuilder
@export var vehicle: Vehicle
@export var controller: PlayerVehicleController
@export var camera: ChaseCamera
@export var hud: Hud
@export var traffic: TrafficManager

var state := State.DRIVING
var spawn_index := 0
## The player's character, and what decides whether they're on foot or driving.
var character: PlayerCharacter
var possession: Possession
var foot_camera: OnFootCamera
var foot_controller: PlayerCharacterController
## The flying rig: a plane's controls and camera (the Possession hands them
## the plane when the player sits in one).
var flight_controller: PlayerAircraftController
var flight_camera: FlightCamera
var camera_blend: CameraBlend
## Vehicles the player got out of earlier (not `vehicle`), oldest first.
var left_vehicles: Array[Vehicle] = []
var picker: VehiclePicker
## The garage setup (paint, wheels...) on the player's vehicle.
var loadout: Loadout
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
## Start on foot next to your vehicle (normal play); dev/test runs start in
## it, as their scripted drives expect (--onfoot... starts on foot).
var start_on_foot := show_title or _has_arg("--onfoot")
var _garage_from := State.DRIVING
var _lost_timer := 0.0
var _crash_wait := -1.0
var _crash_time := 0.0
var _crash_pos := Vector3.ZERO
var _last_crash_cam := -INF
var _tidy_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false  # closing the window: see _notification
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
	var director := AudioDirector.new()
	director.name = "AudioDirector"
	add_child(director)
	replay = Replay.new()
	replay.name = "Replay"
	replay.game = self
	add_child(replay)
	replay.finished.connect(_on_replay_finished)
	vehicle.vehicle_reset.connect(replay.mark_cut)
	_make_character()

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
	possession.start_in_vehicle(vehicle)
	teleport_to(0)
	if start_on_foot:
		_step_out_beside(vehicle)
	else:
		_start_engine(vehicle)
	_fit_headlights()
	_fit_reflection()
	if show_title:
		_enter_title()
	else:
		_enter_driving()


static func _has_arg(prefix: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return true
	return false


## The character, its camera and controls, and the Possession that moves the
## player between the character and vehicles.
func _make_character() -> void:
	character = CHARACTER_SCENE.instantiate() as PlayerCharacter
	character.name = "Character"
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(character)
	character.set_hidden(true)
	character.knocked.connect(_on_character_knocked)
	foot_camera = OnFootCamera.new()
	foot_camera.name = "FootCamera"
	foot_camera.far = camera.far
	foot_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(foot_camera)
	foot_controller = PlayerCharacterController.new()
	foot_controller.name = "FootController"
	foot_controller.camera = foot_camera
	foot_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(foot_controller)
	camera_blend = CameraBlend.new()
	camera_blend.name = "CameraBlend"
	camera_blend.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(camera_blend)
	flight_camera = FlightCamera.new()
	flight_camera.name = "FlightCamera"
	flight_camera.far = camera.far
	flight_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(flight_camera)
	flight_controller = PlayerAircraftController.new()
	flight_controller.name = "FlightController"
	flight_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(flight_controller)
	possession = Possession.new()
	possession.name = "Possession"
	possession.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(possession)
	possession.setup(self, character,
		{"controller": foot_controller, "camera": foot_camera},
		{"controller": controller, "camera": camera}, camera_blend)
	possession.add_rig(Controllable.PLANE, {"controller": flight_controller, "camera": flight_camera})
	possession.changed.connect(_on_pawn_changed)
	if traffic:
		traffic.pedestrians = [character]


## Puts the player on foot next to `v`'s door (start of the game, teleports
## on foot).
func _step_out_beside(v: Vehicle) -> void:
	var entry := v.get_node_or_null("Entry") as VehicleEntry
	var spot: Variant = entry.find_exit(character) if entry else null
	if spot == null:
		# No safe spot found: on the driver's side anyway.
		var ground := v.upright_ground_transform()
		spot = ground.translated_local(Vector3(-(v.body_half_width + 0.9), 0.0, 0.0))
	if possession.mode != Possession.Mode.ON_FOOT:
		possession.start_on_foot(spot)
	else:
		character.place(spot)
	foot_camera.snap()


## The player is on foot or in a vehicle now (`pawn`): everything that
## follows the player follows it.
func _on_pawn_changed(pawn: Node3D) -> void:
	var foot := pawn == character
	var plane := pawn as Aircraft
	if traffic:
		traffic.focus = pawn
	hud.set_flying(plane != null)
	hud.set_on_foot(foot, character, foot_camera)
	stunts.enabled = _stunts_wanted()
	_fit_headlights()
	_fit_reflection()
	if not foot:
		hud.show_prompt_for("Get out", 4.0)
	if plane and plane.on_ground and state == State.DRIVING:
		_take_off_tip()


## How to take off, for the controller in use.
func _take_off_tip() -> void:
	if hud.using_pad:
		hud.show_toast("Hold RT for power, pull the stick back at 80 km/h!", 5.0)
	else:
		hud.show_toast("Hold Shift for power, press S at 80 km/h!", 5.0)


## Stunt scoring is for driving: not on foot, not in a plane.
func _stunts_wanted() -> bool:
	return state == State.DRIVING and driving() and not (vehicle is Aircraft)


## Is the player driving (not on foot, not getting in or out)?
func driving() -> bool:
	return possession == null or possession.driving()


## Gets the player into their vehicle straight away if they're on foot
## (races, which need one).
func ensure_driving() -> void:
	possession.settle()
	if not possession.driving():
		adopt_vehicle(vehicle)
		possession.start_in_vehicle(vehicle)
		snap_camera()


func _on_character_knocked(strength: float) -> void:
	controller.rumble(0.3, clampf(strength / 10.0, 0.3, 0.8), 0.25)


func teleport_to(index: int) -> void:
	if world.spawn_points.is_empty():
		return
	if race and race.is_active():
		race.end_race()
	spawn_index = wrapi(index, 0, world.spawn_points.size())
	var sp: Dictionary = world.spawn_points[spawn_index]
	if possession:
		possession.settle()
	if vehicle is Aircraft:
		_teleport_plane(vehicle as Aircraft, sp)
	else:
		vehicle.teleport(sp["xform"])
		snap_camera()
		# On foot your vehicle comes along and you stand next to it.
		if possession and possession.on_foot():
			_step_out_beside(vehicle)
	if state == State.DRIVING:
		hud.show_toast(sp["name"])


## Teleporting with a plane. Flying, it flies on over the place (the
## Airfield puts it on the runway, ready to take off); on foot the plane
## stays parked where it is and you walk off at the place.
func _teleport_plane(plane: Aircraft, sp: Dictionary) -> void:
	if possession and possession.on_foot():
		character.place(sp["xform"])
		foot_camera.snap()
		return
	if sp["name"] == "Airfield":
		plane.teleport(runway_start(plane))
	else:
		var xf: Transform3D = sp["xform"]
		var heading := -xf.basis.z
		heading.y = 0.0
		plane.place_in_flight(xf.origin + Vector3.UP * 90.0, heading.normalized() if heading.length() > 0.1 else Vector3.FORWARD)
	snap_camera()


## Where a plane starts on the ground: the runway's west end, facing down it.
func runway_start(plane: Vehicle) -> Transform3D:
	var p := MapLayout.RUNWAY_A + Vector3(18.0, 0.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 10.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var y: float = (hit["position"] as Vector3).y if not hit.is_empty() else p.y
	return Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(p.x, y + plane.ride_height() + 0.05, p.z))


## Puts the player's plane on the runway, ready for take-off.
func _put_on_runway(plane: Aircraft) -> void:
	plane.teleport(runway_start(plane))
	for i in world.spawn_points.size():
		if world.spawn_points[i]["name"] == "Airfield":
			spawn_index = i
	snap_camera()


## Snaps the vehicle cameras behind the player's vehicle (after teleports).
func snap_camera() -> void:
	camera.snap()
	if flight_camera:
		flight_camera.snap()


func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	# Fell into the sea or off the island: respawn after a moment. Planes
	# may fly further out (they're turned back toward the island).
	var pawn := possession.pawn()
	var p := pawn.global_position
	var edge := 2600.0 if pawn is Aircraft else 1500.0
	var lost := p.y < MapLayout.SEA_LEVEL - 0.8 or p.y < -60.0 or absf(p.x) > edge or absf(p.z) > edge
	hud.turning_back = flight_controller.turning_back
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
	_tidy_timer -= dt
	if _tidy_timer <= 0.0:
		_tidy_timer = 2.0
		_tidy_left_vehicles()


func _on_trick(trick_name: String, _points: int) -> void:
	if trick_name != "NEAR MISS" and not trick_name.begins_with("AIR "):
		hud.show_popup(trick_name + "!", 1.3)


func _on_combo_banked(points: int, _place: int) -> void:
	hud.set_score(stunts.score)
	if points >= 300:
		hud.show_popup("+%s" % Hud.format_points(points), 1.5, Color(0.5, 1.0, 0.45))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		VehicleAudio.quit_quietly(get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		VehicleAudio.quit_quietly(get_tree())
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
		if not driving():
			hud.show_toast("Replays are for driving")
		elif not start_replay():
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
	if race and race.is_active() and driving():
		vehicle.teleport(race.respawn_point())
		snap_camera()
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
	if state != State.DRIVING or not driving():
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
	if severity < CRASH_CAM_SEVERITY or _crash_wait >= 0.0 or not Settings.get_value("crash_cam") or not driving():
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
	foot_controller.enabled = false
	flight_controller.enabled = false
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
	foot_controller.enabled = true
	flight_controller.enabled = true
	stunts.enabled = _stunts_wanted()
	hud.visible = true
	possession.show_camera()
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if from_title:
		snap_camera()
		foot_camera.snap()
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
			VehicleAudio.quit_quietly(get_tree())
		"end_race":
			race.end_race()
			_enter_driving()
		_:
			if action_name.begins_with("race:"):
				_enter_driving()
				ensure_driving()
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
			day_night.refresh()
			get_tree().call_group("night_lights", "set_night", day_night.is_night)
			_fit_reflection()
		"time_of_day":
			day_night.set_mode(value)


# --- Garage / changing vehicle -----------------------------------------------

func open_garage() -> void:
	race.end_race()
	possession.settle()
	_garage_from = state
	state = State.GARAGE
	get_tree().paused = true
	hud.visible = false
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	picker.open(VehicleCatalog.index_of_vehicle(vehicle), loadout)


func _on_garage_cancelled() -> void:
	_keep_garage_changes()
	match _garage_from:
		State.TITLE:
			_enter_title()
		State.PAUSED:
			_enter_pause()
		_:
			_enter_driving()


## Picking a vehicle in the garage means "drive it": on foot it's brought to
## you and you get straight in.
func _on_vehicle_picked(index: int) -> void:
	_keep_garage_changes()
	if index != VehicleCatalog.index_of_vehicle(vehicle):
		change_vehicle(index, picker.loadouts.get(VehicleCatalog.ENTRIES[index]["id"]))
	elif not possession.driving() and _garage_from != State.TITLE:
		_drive_up(vehicle)
	_save_choice(index)
	# Coming from the title screen, picking a vehicle starts the game.
	if _garage_from == State.TITLE:
		state = State.TITLE
	_enter_driving()
	hud.show_toast(VehicleCatalog.ENTRIES[index]["name"])


## Garage changes stick even when backing out: every vehicle's setup is
## saved, and the vehicle you're in gets its new look.
func _keep_garage_changes() -> void:
	for l: Loadout in picker.loadouts.values():
		l.save()
	var mine: Loadout = picker.loadouts.get(loadout.vehicle_id)
	if mine and mine.values != loadout.values:
		loadout = mine.copy()
		loadout.apply(vehicle)


## Replaces the player's vehicle with catalog entry `index`, set up as `setup`
## says (default: as saved in the garage), with the player in it. It's parked
## upright where the old one was if the player was driving, or next to the
## character if they were on foot (or at the current spawn point if there's
## no room). With `place_here` false the caller positions it (e.g. a
## teleport right after).
func change_vehicle(index: int, setup: Loadout = null, place_here := true) -> void:
	var old := vehicle
	var car := VehicleCatalog.scene(index).instantiate() as Vehicle
	car.traction_control = old.traction_control
	loadout = setup.copy() if setup else Loadout.saved(VehicleCatalog.ENTRIES[index]["id"])
	loadout.apply(car)
	var on_foot := possession != null and not possession.driving()
	var plane := car as Aircraft
	var spot := {}
	if place_here and plane == null and not (old is Aircraft and not (old as Aircraft).on_ground):
		# (Planes go to the runway; a car never appears in the sky under a
		# flying plane: it goes to the spawn point.)
		if on_foot:
			spot = _room_beside_character(car, old)
		else:
			spot = _find_room(car, old.upright_ground_transform(), [old.get_rid()])

	var slot := old.get_index()
	_unwire(old)
	left_vehicles.erase(old)
	if traffic:
		traffic.untrack(old)
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
	vehicle = null  # the old one is gone: nothing to park
	adopt_vehicle(car, true)
	if possession:
		possession.replace_vehicle(old, car)
	if not place_here:
		return
	if plane:
		_put_on_runway(plane)
	elif spot.is_empty():
		teleport_to(spawn_index)
	else:
		car.teleport(spot["xform"])
		snap_camera()


## Brings the player's vehicle next to the character and puts them in it
## (the garage, picking the vehicle you already have while on foot).
func _drive_up(v: Vehicle) -> void:
	if v is Aircraft:
		_put_on_runway(v as Aircraft)
		adopt_vehicle(v)
		possession.start_in_vehicle(v)
		return
	var spot := _room_beside_character(v, v)
	if not spot.is_empty():
		v.teleport(spot["xform"])
	adopt_vehicle(v)
	possession.start_in_vehicle(v)
	snap_camera()


## Room for `car` where the character stands or just beside it, facing the
## way the camera looks: {"xform"} or {}.
func _room_beside_character(car: Vehicle, exclude: Vehicle) -> Dictionary:
	var f := -foot_camera.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := f.cross(Vector3.UP)
	var p := character.global_position
	var space := get_world_3d().direct_space_state
	for off: Vector3 in [Vector3.ZERO, r * 2.8, -r * 2.8, f * 4.0, -f * 4.0]:
		var at := p + off
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var base := Transform3D(Basis.looking_at(f, Vector3.UP), hit["position"])
		var skip: Array[RID] = []
		if is_instance_valid(exclude):
			skip.append(exclude.get_rid())
		var room := _find_room(car, base, skip)
		if not room.is_empty():
			return room
	return {}


## Where `car` can stand on the ground at `base` (upright, its origin
## lifted to ride height): {"xform": Transform3D}, or {} if the spot is
## blocked. Traffic cars in the way are removed; light props (cones,
## crates...) just get pushed aside. `exclude`: bodies to ignore.
func _find_room(car: Vehicle, base: Transform3D, exclude: Array[RID]) -> Dictionary:
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
			q.exclude = exclude
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


# --- The player's vehicle ------------------------------------------------------

## Makes `car` the player's vehicle as they get into it: the chase camera,
## HUD, maps, traffic, stunts, replays, races, damage messages, headlights,
## reflections and full engine sound follow it. (The Possession hands it the
## controls.) The vehicle they had before stays parked as a left vehicle.
## `fresh`: a brand-new vehicle (from the garage), started from cold.
func adopt_vehicle(car: Vehicle, fresh := false) -> void:
	var old := vehicle
	if car.get_parent() != self:
		# A traffic car: it's the player's now (never pooled or despawned).
		var lv := car.linear_velocity
		var av := car.angular_velocity
		car.reparent(self)
		car.linear_velocity = lv
		car.angular_velocity = av
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	var audio := car.get_node_or_null("Audio") as VehicleAudio
	var was_off := audio != null and not audio.engine_running
	if old and old != car and is_instance_valid(old):
		_unwire(old)
		_park_left(old)
	left_vehicles.erase(car)
	if traffic:
		traffic.untrack(car)
	vehicle = car
	car.traction_control = Settings.get_value("assists")
	car.auto_reverse = true
	camera.set_target(car)
	title_camera.target = car
	hud.set_vehicle(car)
	if traffic:
		traffic.set_player(car)
	stunts.vehicle = car
	if not car.vehicle_reset.is_connected(race.on_teleport):
		car.vehicle_reset.connect(race.on_teleport)
	if not car.vehicle_reset.is_connected(replay.mark_cut):
		car.vehicle_reset.connect(replay.mark_cut)
	if old != car:
		replay.clear()
		# The garage's setup is for this vehicle type; a car taken from
		# traffic keeps its own look until the garage changes it.
		var id := VehicleCatalog.id_of_vehicle(car)
		if id != "" and (loadout == null or loadout.vehicle_id != id):
			loadout = Loadout.saved(id)
	_watch_damage(car)
	_fit_headlights()
	_fit_reflection()
	if fresh or was_off:
		_start_engine(car)
	elif audio:
		audio.set_detail(VehicleAudio.Detail.FULL)


## The player got out of `car`: it stays parked where it is (handbrake on,
## engine off, lights out) and is still their vehicle; the camera, HUD and
## traffic follow the character now.
func leave_vehicle(car: Vehicle) -> void:
	if race.is_active():
		race.end_race()
	stunts.bank_now()
	_crash_wait = -1.0
	var audio := car.get_node_or_null("Audio") as VehicleAudio
	if audio:
		audio.set_detail(VehicleAudio.Detail.LITE)
		audio.stop_engine()
	var lights := car.get_node_or_null("Headlights") as Node3D
	if lights:
		lights.visible = false
	var probe := car.get_node_or_null("Reflection")
	if probe:
		probe.queue_free()
	if traffic:
		traffic.track(car)


## Disconnects the player-only signals from a vehicle the player no longer has.
func _unwire(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	for pair: Array in [[v.vehicle_reset, race.on_teleport], [v.vehicle_reset, replay.mark_cut],
			[v.vehicle_reset, camera.snap]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg:
		if dmg.part_lost.is_connected(_on_part_lost):
			dmg.part_lost.disconnect(_on_part_lost)
		if dmg.crashed.is_connected(_on_crash):
			dmg.crashed.disconnect(_on_crash)


## Keeps a vehicle the player swapped for another one parked for a while.
func _park_left(v: Vehicle) -> void:
	var audio := v.get_node_or_null("Audio") as VehicleAudio
	if audio and audio.detail == VehicleAudio.Detail.FULL:
		audio.set_detail(VehicleAudio.Detail.LITE)
		audio.stop_engine()
	var lights := v.get_node_or_null("Headlights") as Node3D
	if lights:
		lights.queue_free()
	var probe := v.get_node_or_null("Reflection")
	if probe:
		probe.queue_free()
	if not left_vehicles.has(v):
		left_vehicles.append(v)
	if traffic:
		traffic.track(v)


## Removes left vehicles that are far away, or beyond the limit, once nobody
## can see them.
func _tidy_left_vehicles() -> void:
	var here := possession.pawn().global_position if possession else vehicle.global_position
	var cam := get_viewport().get_camera_3d()
	for v: Vehicle in left_vehicles.duplicate():
		if not is_instance_valid(v):
			left_vehicles.erase(v)
			continue
		var too_many := left_vehicles.size() > MAX_LEFT_VEHICLES and v == left_vehicles[0]
		var far := v.global_position.distance_to(here) > LEFT_VEHICLE_RANGE or v.global_position.y < MapLayout.SEA_LEVEL - 2.0
		var seen := cam != null and cam.global_position.distance_to(v.global_position) < 260.0 and cam.is_position_in_frustum(v.global_position)
		if (too_many or far) and not seen:
			left_vehicles.erase(v)
			if traffic:
				traffic.untrack(v)
			v.queue_free()


func _watch_damage(v: Vehicle) -> void:
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg and not dmg.part_lost.is_connected(_on_part_lost):
		dmg.part_lost.connect(_on_part_lost)
		dmg.crashed.connect(_on_crash)


func _on_part_lost(part_name: String) -> void:
	if driving():
		hud.show_toast("%s FELL OFF!" % part_name, 2.0)


## Real headlights on the player's vehicle (only after dark, and only while
## driving it; traffic cars just have glowing lamps, to keep the light count
## low).
func _fit_headlights() -> void:
	if vehicle == null or day_night == null:
		return
	var lights := vehicle.get_node_or_null("Headlights") as Node3D
	if lights == null and vehicle is Aircraft:
		lights = (vehicle as Aircraft).make_landing_light()
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
	lights.visible = day_night.is_night and driving()


## The player's vehicle gets the full sound and starts its engine.
func _start_engine(v: Vehicle) -> void:
	var audio := v.get_node_or_null("Audio") as VehicleAudio
	if audio:
		audio.set_detail(VehicleAudio.Detail.FULL)
		audio.start_engine()


## Real reflections in the player car's paint and glass on High
## (VehicleReflection), while driving it; Medium and Low keep the sky-only
## reflections.
func _fit_reflection() -> void:
	if vehicle == null:
		return
	var probe := vehicle.get_node_or_null("Reflection") as VehicleReflection
	# (Not on planes: they'd re-capture it several times a second.)
	var want: bool = Settings.get_value("graphics") >= GraphicsQuality.HIGH and driving() and not (vehicle is Aircraft)
	if want and probe == null:
		probe = VehicleReflection.new()
		probe.vehicle = vehicle
		vehicle.add_child(probe)
	elif not want and probe:
		probe.queue_free()


## Remembers which vehicle you drive (each one's setup is saved by the garage).
func _save_choice(index: int) -> void:
	# Sessions start on the road: a plane isn't remembered as your vehicle.
	if VehicleCatalog.ENTRIES[index].get("air", false):
		return
	Settings.set_value("vehicle", VehicleCatalog.ENTRIES[index]["id"])


## Puts the player in the vehicle stored in the settings, set up as saved.
func _load_choice() -> void:
	var index := VehicleCatalog.index_of_id(Settings.get_value("vehicle"))
	var here := VehicleCatalog.index_of_vehicle(vehicle)
	if index >= 0 and VehicleCatalog.ENTRIES[index].get("air", false):
		index = -1
	if index < 0 or index == here:
		loadout = Loadout.saved(VehicleCatalog.ENTRIES[maxi(here, 0)]["id"])
		loadout.apply(vehicle)
	else:
		change_vehicle(index, null, false)
