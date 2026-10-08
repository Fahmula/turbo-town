class_name Game
extends Node3D
## Top-level game flow: title screen, pause menu, the garage (changing
## vehicle), the players, split-screen, applying settings, the replay /
## crash cam, and the in-game keys.
##
## Each player on this machine is a LocalPlayer (local_player.gd): a character
## who walks around and gets in and out of vehicles (the Possession decides
## what they control), their vehicle, cameras, HUD and controls. There is one
## player, or two in split-screen (add_player / remove_player). The old
## single-player fields (`vehicle`, `camera`, `hud`, `character`...) and
## methods (`teleport_to`, `change_vehicle`...) lead to player 1. Replays, the
## crash cam, races and the saved vehicle choice are player 1's.

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
## Player 2's vehicle when they haven't picked one in the garage yet.
const P2_DEFAULT_VEHICLE := "sedan"

@export var world: WorldBuilder
## Player 1's vehicle (see LocalPlayer.vehicle). main.tscn sets the first one.
@export var vehicle: Vehicle:
	get:
		return p1.vehicle if p1 else _start_vehicle
	set(v):
		if p1:
			p1.vehicle = v
		else:
			_start_vehicle = v
@export var controller: PlayerVehicleController:
	get:
		return p1.controller if p1 else _start_controller
	set(v):
		if p1:
			p1.controller = v
		else:
			_start_controller = v
@export var camera: ChaseCamera:
	get:
		return p1.camera if p1 else _start_camera
	set(v):
		if p1:
			p1.camera = v
		else:
			_start_camera = v
@export var hud: Hud:
	get:
		return p1.hud if p1 else _start_hud
	set(v):
		if p1:
			p1.hud = v
		else:
			_start_hud = v
@export var traffic: TrafficManager

var state := State.DRIVING
## The players on this machine: player 1, plus player 2 in split-screen.
var players: Array[LocalPlayer] = []
var p1: LocalPlayer
## The two views while two players play (null with one).
var split: SplitScreen

# Player 1's things (see LocalPlayer).
var spawn_index: int:
	get:
		return p1.spawn_index
	set(v):
		p1.spawn_index = v
var character: PlayerCharacter:
	get:
		return p1.character if p1 else null
var possession: Possession:
	get:
		return p1.possession if p1 else null
var foot_camera: OnFootCamera:
	get:
		return p1.foot_camera if p1 else null
var foot_controller: PlayerCharacterController:
	get:
		return p1.foot_controller if p1 else null
var flight_controller: PlayerAircraftController:
	get:
		return p1.flight_controller if p1 else null
var flight_camera: FlightCamera:
	get:
		return p1.flight_camera if p1 else null
var camera_blend: CameraBlend:
	get:
		return p1.camera_blend if p1 else null
var left_vehicles: Array[Vehicle]:
	get:
		return p1.left_vehicles
var loadout: Loadout:
	get:
		return p1.loadout
	set(v):
		p1.loadout = v
var stunts: StuntTracker:
	get:
		return p1.stunts if p1 else null

var picker: VehiclePicker
var menu: GameMenu
var title_camera: MenuCamera
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
## Who the garage is open for.
var _garage_player: LocalPlayer
var _crash_wait := -1.0
var _crash_time := 0.0
var _crash_pos := Vector3.ZERO
var _last_crash_cam := -INF
var _start_vehicle: Vehicle
var _start_controller: PlayerVehicleController
var _start_camera: ChaseCamera
var _start_hud: Hud
## The grass around player 2 in split-screen.
var _grass2: GrassField
var _root_listener := true


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
	_start_vehicle.vehicle_reset.connect(replay.mark_cut)
	p1 = LocalPlayer.new(self, 0)
	add_child(p1)
	players.append(p1)
	p1.setup(_start_vehicle, _start_controller, _start_camera, _start_hud)
	if traffic:
		traffic.pedestrians = [p1.character]

	Records.record_broken.connect(func(what: String) -> void: hud.show_toast("NEW RECORD: %s!" % what, 3.0))
	var t0 := Time.get_ticks_msec()
	world_map = WorldMap.new(world)
	world_map.name = "WorldMap"
	add_child(world_map)
	print("World map drawn in %d ms" % (Time.get_ticks_msec() - t0))
	hud.setup_map(world_map, traffic, _map_spots())
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
	p1._watch_damage(vehicle)
	vehicle.traction_control = Settings.get_value("assists")
	hud.speedometer.use_mph = Settings.get_value("units_mph")
	Settings.changed.connect(_on_setting_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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


## The teleport spots for the maps: [{"name", "pos"}].
func _map_spots() -> Array:
	var spots: Array = []
	for sp: Dictionary in world.spawn_points:
		spots.append({"name": sp["name"], "pos": (sp["xform"] as Transform3D).origin})
	return spots


# --- Player 1 (the single-player API) ------------------------------------------

func teleport_to(index: int) -> void:
	p1.teleport_to(index)


func respawn() -> void:
	p1.respawn()


func change_vehicle(index: int, setup: Loadout = null, place_here := true) -> void:
	p1.change_vehicle(index, setup, place_here)


func adopt_vehicle(car: Vehicle, fresh := false) -> void:
	p1.adopt_vehicle(car, fresh)


func leave_vehicle(car: Vehicle) -> void:
	p1.leave_vehicle(car)


func ensure_driving() -> void:
	p1.ensure_driving()


## Is player 1 driving (not on foot, not getting in or out)?
func driving() -> bool:
	return p1 == null or p1.driving()


func snap_camera() -> void:
	p1.snap_camera()


func _step_out_beside(v: Vehicle) -> void:
	p1._step_out_beside(v)


func _start_engine(v: Vehicle) -> void:
	p1._start_engine(v)


func _tidy_left_vehicles() -> void:
	p1._tidy_left_vehicles()


func _fit_headlights() -> void:
	for p in players:
		p._fit_headlights()


func _fit_reflection() -> void:
	for p in players:
		p._fit_reflection()


## Player 1 has `car` now (`old` before): the title screen, replays and races
## follow it.
func on_player_vehicle(p: LocalPlayer, car: Vehicle, old: Vehicle) -> void:
	if p != p1:
		return
	title_camera.target = car
	if race and not car.vehicle_reset.is_connected(race.on_teleport):
		car.vehicle_reset.connect(race.on_teleport)
	if replay and not car.vehicle_reset.is_connected(replay.mark_cut):
		car.vehicle_reset.connect(replay.mark_cut)
	if old != car and replay:
		replay.clear()


## Player `p` got out of their vehicle.
func on_player_left_vehicle(p: LocalPlayer) -> void:
	if p != p1:
		return
	if race.is_active():
		race.end_race()
	_crash_wait = -1.0


## Where a plane starts on the ground: the runway's west end, facing down it,
## `lane` m off the middle (split-screen: one side each).
func runway_start(plane: Vehicle, lane := 0.0) -> Transform3D:
	var p := MapLayout.RUNWAY_A + Vector3(18.0, 0.0, lane)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 10.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var y: float = (hit["position"] as Vector3).y if not hit.is_empty() else p.y
	return Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(p.x, y + plane.ride_height() + 0.05, p.z))


## The teleport spot nearest to `pos` (its index in world.spawn_points).
func nearest_spawn_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in world.spawn_points.size():
		var d := (world.spawn_points[i]["xform"] as Transform3D).origin.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_spawn(pos: Vector3) -> Dictionary:
	return world.spawn_points[nearest_spawn_index(pos)]


## Where `car` can stand on the ground at `base` (upright, its origin
## lifted to ride height): {"xform": Transform3D}, or {} if the spot is
## blocked. Traffic cars in the way are removed; light props (cones,
## crates...) just get pushed aside. `exclude`: bodies to ignore; `mask`:
## what counts (default world, vehicles and props; add 0b1000 so a car never
## lands on a player standing there).
func find_room(car: Vehicle, base: Transform3D, exclude: Array[RID], mask := 0b111) -> Dictionary:
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
			q.collision_mask = mask
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


func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	for p in players:
		p.physics_tick(dt)
	if _crash_wait >= 0.0:
		_crash_wait -= dt
		if _crash_wait < 0.0 and state == State.DRIVING and not race.is_active():
			start_replay(true)


func _on_trick(trick_name: String, points: int) -> void:
	p1._on_trick(trick_name, points)


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
	for p in players:
		if _player_key(p, event):
			return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The in-game keys of player `p` (their own buttons in split-screen). True
## if `event` was one.
func _player_key(p: LocalPlayer, event: InputEvent) -> bool:
	var inp := p.input
	if inp.event_pressed(event, "pause"):
		_enter_pause()
	elif inp.event_pressed(event, "instant_replay") or inp.event_pressed(event, "regroup"):
		if is_split():
			# No replays with two players: the button takes you to the other one.
			p.regroup(players[1 - p.index])
		elif inp.event_pressed(event, "regroup"):
			return false
		elif not p.driving():
			p.hud.show_toast("Replays are for driving")
		elif not start_replay():
			p.hud.show_toast("Nothing to replay yet")
	elif inp.event_pressed(event, "change_vehicle"):
		open_garage(p)
	elif inp.event_pressed(event, "respawn"):
		p.respawn()
	elif inp.event_pressed(event, "teleport_next"):
		p.teleport_to(p.spawn_index + 1)
	elif inp.event_pressed(event, "toggle_help"):
		p.hud.toggle_help()
	elif inp.event_pressed(event, "toggle_map"):
		p.hud.toggle_big_map()
	elif inp.event_pressed(event, "toggle_traffic") and traffic:
		traffic.set_enabled(not traffic.enabled)
		for q in players:
			q.hud.show_toast("Traffic ON" if traffic.enabled else "Traffic OFF")
	elif inp.event_pressed(event, "toggle_units"):
		Settings.set_value("units_mph", not Settings.get_value("units_mph"))
	elif inp.event_pressed(event, "toggle_traction_control"):
		Settings.set_value("assists", not Settings.get_value("assists"))
		if p.vehicle is Aircraft and p.driving():
			p.hud.show_toast("Flying assists ON" if p.vehicle.traction_control else "Flying assists OFF - fly it all yourself!")
		else:
			p.hud.show_toast("Assists ON" if p.vehicle.traction_control else "Assists OFF - drift mode!")
	else:
		for i in mini(9, world.spawn_points.size()):
			if inp.event_pressed(event, "teleport_%d" % (i + 1)):
				p.teleport_to(i)
				return true
		return false
	return true


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
## cam around the last big crash. False if there's nothing to show. (Not in
## split-screen: it's player 1's car only.)
func start_replay(crash := false) -> bool:
	if state != State.DRIVING or not driving() or is_split():
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
	if state != State.DRIVING or race.is_active() or replay.now - _last_crash_cam < CRASH_CAM_COOLDOWN or is_split():
		return
	_last_crash_cam = replay.now
	_crash_time = replay.now
	_crash_pos = vehicle.global_position
	_crash_wait = CRASH_CAM_AFTER


# --- States -----------------------------------------------------------------

func _enter_title() -> void:
	if is_split():
		remove_player()
	state = State.TITLE
	get_tree().paused = false
	for p in players:
		p.set_controls(false)
		p.stunts.enabled = false
		p.hud.visible = false
	title_camera.target = vehicle
	title_camera.current = true
	menu.set_ride_name(vehicle.display_name)
	menu.show_page("title")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enter_driving() -> void:
	var from_title := state == State.TITLE
	state = State.DRIVING
	get_tree().paused = false
	for p in players:
		p.set_controls(true)
		p.stunts.enabled = p.stunts_wanted()
		p.hud.visible = true
		p.possession.show_camera()
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if from_title:
		for p in players:
			p.snap_camera()
			p.foot_camera.snap()
			p.hud.show_help_for(14.0)


func _enter_pause(note := "") -> void:
	state = State.PAUSED
	menu.racing = race.is_active()
	menu.two_players = is_split()
	get_tree().paused = true
	for p in players:
		p.hud.visible = false
	menu.show_page("pause")
	menu.set_note(note)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_menu_action(action_name: String) -> void:
	match action_name:
		"drive", "resume":
			_enter_driving()
		"garage":
			# Whoever pressed GARAGE (split-screen: their own garage).
			open_garage(_player_with_device(menu._last_device))
		"title":
			race.end_race()
			_enter_title()
		"quit":
			VehicleAudio.quit_quietly(get_tree())
		"end_race":
			race.end_race()
			_enter_driving()
		"remove_player":
			remove_player()
			_enter_driving()
			hud.show_toast("Player 2 left")
		_:
			if action_name.begins_with("race:"):
				_enter_driving()
				ensure_driving()
				race.start(int(action_name.substr(5)))
			elif action_name.begins_with("join:"):
				# "join:<player 1's device>:<player 2's device>" (-1 = keyboard).
				var parts := action_name.split(":")
				add_player(int(parts[1]), int(parts[2]))
				_enter_driving()


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"assists":
			for p in players:
				p.vehicle.traction_control = value
		"units_mph":
			for p in players:
				p.hud.speedometer.use_mph = value
		"minimap":
			for p in players:
				p.hud.minimap.visible = value
		"graphics":
			GraphicsQuality.apply(value, get_viewport(), world)
			if split:
				split.apply_graphics(value)
			day_night.refresh()
			get_tree().call_group("night_lights", "set_night", day_night.is_night)
			_fit_reflection()
		"time_of_day":
			day_night.set_mode(value)


## A player's gamepad was unplugged (or ran out of battery) mid-game: pause,
## so nobody drives on without them. Plugged back in, it works again.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or not is_split() or state != State.DRIVING:
		return
	for p in players:
		if p.input.pads.has(device):
			_enter_pause("Player %d's controller is disconnected" % (p.index + 1))
			return


# --- Garage / changing vehicle -----------------------------------------------

## Opens the garage for `who` (default player 1).
func open_garage(who: LocalPlayer = null) -> void:
	var p := who if who else p1
	race.end_race()
	p.possession.settle()
	_garage_from = state
	_garage_player = p
	state = State.GARAGE
	get_tree().paused = true
	for q in players:
		q.hud.visible = false
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	picker.open(VehicleCatalog.index_of_vehicle(p.vehicle), p.loadout)


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
	var p := _garage_p()
	_keep_garage_changes()
	if index != VehicleCatalog.index_of_vehicle(p.vehicle):
		p.change_vehicle(index, picker.loadouts.get(VehicleCatalog.ENTRIES[index]["id"]))
	elif not p.possession.driving() and _garage_from != State.TITLE:
		p._drive_up(p.vehicle)
	_save_choice(index, p)
	# Coming from the title screen, picking a vehicle starts the game.
	if _garage_from == State.TITLE:
		state = State.TITLE
	_enter_driving()
	p.hud.show_toast(VehicleCatalog.ENTRIES[index]["name"])


func _garage_p() -> LocalPlayer:
	return _garage_player if _garage_player and is_instance_valid(_garage_player) and players.has(_garage_player) else p1


## Garage changes stick even when backing out: every vehicle's setup is
## saved, and the vehicle you're in gets its new look.
func _keep_garage_changes() -> void:
	var p := _garage_p()
	for l: Loadout in picker.loadouts.values():
		l.save()
	var mine: Loadout = picker.loadouts.get(p.loadout.vehicle_id)
	if mine and mine.values != p.loadout.values:
		p.loadout = mine.copy()
		p.loadout.apply(p.vehicle)


## Remembers which vehicle you drive (each one's setup is saved by the garage).
func _save_choice(index: int, p: LocalPlayer = null) -> void:
	# Sessions start on the road: a plane isn't remembered as your vehicle.
	if VehicleCatalog.ENTRIES[index].get("air", false):
		return
	Settings.set_value("vehicle_p2" if p and p.index == 1 else "vehicle", VehicleCatalog.ENTRIES[index]["id"])


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


# --- Two players ---------------------------------------------------------------

func is_split() -> bool:
	return players.size() > 1


## Player 2 joins: the screen splits in two (player 1 on top). `p1_device`
## and `p2_device` are each player's gamepad (-1 = the keyboard and mouse).
## Player 1 also keeps the keyboard unless player 2 took it.
func add_player(p1_device: int, p2_device: int) -> void:
	if is_split():
		return
	var p2_keys := p2_device < 0
	var p1_pads: Array[int] = []
	if p1_device >= 0:
		p1_pads.append(p1_device)
	var p2_pads: Array[int] = []
	if p2_device >= 0:
		p2_pads.append(p2_device)
	InputSetup.make_player_actions("p1_", not p2_keys, p1_pads)
	InputSetup.make_player_actions("p2_", p2_keys, p2_pads)
	p1.set_input(PlayerInput.for_player("p1_", p1_device, not p2_keys))

	var ctrl := PlayerVehicleController.new()
	ctrl.name = "PlayerController2"
	ctrl.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ctrl)
	var cam := ChaseCamera.new()
	cam.name = "ChaseCamera2"
	cam.far = camera.far
	cam.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cam)
	var h := Hud.new()
	h.name = "HUD2"
	add_child(h)
	var p2 := LocalPlayer.new(self, 1)
	add_child(p2)
	players.append(p2)
	if traffic:
		traffic.others = [p2]

	# Their vehicle (as picked in the garage last time), next to player 1.
	var index := VehicleCatalog.index_of_id(Settings.get_value("vehicle_p2"))
	if index < 0 or VehicleCatalog.ENTRIES[index].get("air", false):
		index = VehicleCatalog.index_of_id(P2_DEFAULT_VEHICLE)
	var car := VehicleCatalog.scene(index).instantiate() as Vehicle
	p2.loadout = Loadout.saved(VehicleCatalog.ENTRIES[index]["id"])
	p2.loadout.apply(car)
	car.name = "PlayerCar2"
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	var spot := p2.spot_near(p1.focus_node(), car)
	if spot.is_empty():
		var sp := nearest_spawn(p1.focus_node().global_position)
		spot = {"xform": (sp["xform"] as Transform3D).translated_local(Vector3(-5.0, 0.0, 0.0))}
	car.transform = spot["xform"]
	add_child(car)
	car.teleport(spot["xform"])
	p2.setup(car, ctrl, cam, h)
	p2.set_input(PlayerInput.for_player("p2_", p2_device, p2_keys))
	p2.spawn_index = nearest_spawn_index(car.global_position)
	h.setup_map(world_map, traffic, _map_spots())
	h.minimap.visible = Settings.get_value("minimap")
	h.speedometer.use_mph = Settings.get_value("units_mph")
	p2.vehicle = null
	p2.adopt_vehicle(car, true)
	p2.possession.start_in_vehicle(car)
	p2._step_out_beside(car)
	p2.set_controls(state == State.DRIVING)
	if traffic:
		traffic.pedestrians = [p1.character, p2.character]
		traffic.refresh_players()
	_start_split()
	refresh_friends()


## Player 2 leaves: their character and vehicles go, the screen is whole again.
func remove_player() -> void:
	if not is_split():
		return
	var p2: LocalPlayer = players[1]
	_end_split()
	players.remove_at(1)
	if traffic:
		traffic.pedestrians = [p1.character]
		traffic.others = []
	for v: Vehicle in p2.left_vehicles + [p2.vehicle]:
		if v and is_instance_valid(v):
			if traffic:
				traffic.untrack(v)
			v.queue_free()
	p2.left_vehicles.clear()
	p2.vehicle = null
	p2.free_rig()
	p2.queue_free()
	if traffic:
		traffic.refresh_players()
	p1.set_input(PlayerInput.shared())
	InputSetup.remove_player_actions("p1_")
	InputSetup.remove_player_actions("p2_")
	refresh_friends()


func _start_split() -> void:
	split = SplitScreen.new()
	add_child(split)
	split.build(players.size())
	Views.set_split(split.views)
	GraphicsQuality.apply(Settings.get_value("graphics"), get_viewport(), world)
	split.apply_graphics(Settings.get_value("graphics"))
	var root := get_viewport()
	_root_listener = root.audio_listener_enable_3d
	root.audio_listener_enable_3d = false
	root.disable_3d = true
	for i in players.size():
		players[i].enter_view(split.views[i])
	# Grass grows around each player, each in their own view only.
	var grass := _grass()
	if grass:
		grass.view = 0
		_grass2 = GrassField.new()
		world.add_child(_grass2)
		_grass2.setup(world.terrain)
		_grass2.name = "Grass2"
		_grass2.view = 1
	race.start_circles_on = false
	replay.clear()  # (it doesn't record with two players)
	VehicleAudio.set_split_listeners(true, get_tree())
	_fit_reflection()


func _end_split() -> void:
	if split == null:
		return
	for p in players:
		p.enter_view(null)
	Views.set_split([])
	GraphicsQuality.apply(Settings.get_value("graphics"), get_viewport(), world)
	var root := get_viewport()
	root.disable_3d = false
	root.audio_listener_enable_3d = _root_listener
	split.queue_free()
	split = null
	var grass := _grass()
	if grass:
		grass.view = -1
	if _grass2:
		_grass2.queue_free()
		_grass2 = null
	race.start_circles_on = true
	VehicleAudio.set_split_listeners(false, get_tree())
	_fit_reflection()
	if state == State.DRIVING:
		p1.possession.show_camera()


func _grass() -> GrassField:
	for g in world.find_children("*", "GrassField", true, false):
		if g != _grass2:
			return g as GrassField
	return null


## The player using `device` (a gamepad, -1 = keyboard and mouse); player 1
## if nobody does.
func _player_with_device(device: int) -> LocalPlayer:
	for p in players:
		if (device < 0 and p.input.keyboard) or (device >= 0 and p.input.pads.has(device)):
			return p
	return p1


## Each player's maps show where the other one is.
func refresh_friends() -> void:
	for p in players:
		if p.hud == null:
			continue
		var others: Array[Dictionary] = []
		for q in players:
			if q != p and q.possession:
				others.append({"node": q.focus_node(), "color": q.color(), "label": "P%d" % (q.index + 1)})
		p.hud.set_friends(others)
