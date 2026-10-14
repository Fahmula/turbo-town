class_name Possession
extends Node
## What the player controls right now, their character on foot or a vehicle,
## and handing control from one to the other (getting in and out).
##
## Anything controllable has a Controllable component; its `kind` picks a
## rig: the input controller and camera for that kind (`rigs`). Exactly
## one rig has a pawn at a time, so the player can never drive the character
## and a vehicle at once, and a vehicle is only ever driven by one
## controller: entering a traffic car first takes it off its TrafficDriver
## (TrafficManager.claim).
##
## Getting in: the character walks to the nearest door (a fraction of a
## second, no collisions), the camera glides to the vehicle's chase camera,
## the character is hidden and the vehicle's controller takes over. Getting
## out: the vehicle brakes to a stop first if it's moving, VehicleEntry finds
## a safe spot by a door (or anywhere nearby), the character appears there
## and the camera glides back, keeping the direction you were looking.
## The player's LocalPlayer does the vehicle-side wiring (HUD, traffic, sound,
## lights) through adopt_vehicle / leave_vehicle. Each split-screen player
## has their own Possession.
##
## Riding along (split-screen): a player can sit in the passenger seat of the
## other player's vehicle (`ride`; VehicleEntry keeps the seats). They walk
## to the door the same way, then watch through their own camera for that
## kind of vehicle, aimed at the ride, with no controls of their own; the
## interact button gets them out once it has (nearly) stopped, on the
## passenger side. The vehicle stays the driver's: if the driver gets out the
## passenger stays in until they get out themselves.

## The player now controls `pawn` (the character or a vehicle).
signal changed(pawn: Node3D)

enum Mode { ON_FOOT, ENTERING, IN_VEHICLE, EXITING, BOARDING, RIDING }

const BLEND_IN := 0.85
const BLEND_OUT := 0.65
## Getting out of a moving vehicle brakes it first, for at most this long.
const EXIT_BRAKE_TIME := 3.0
const EXIT_SPEED := 1.6
## A passenger can't brake: they get out once the vehicle is this slow (m/s).
const RIDER_EXIT_SPEED := 2.5
## How often the character looks for something to interact with (s).
const SCAN_EVERY := 0.1
## The interact button is ignored this long after getting in or out, so a
## double press (or button mashing) doesn't undo it straight away.
const COOLDOWN := 0.6

var game: Game
## The player this is for (their HUD, input, vehicle wiring).
var player: LocalPlayer
var character: PlayerCharacter
var mode := Mode.ON_FOOT
## The vehicle the player is in, getting into or out of (null on foot).
var vehicle: Vehicle
## The vehicle the player rides in as a passenger, or is getting into as one
## (null otherwise; `vehicle` is null then).
var ride: Vehicle
## What the interact button would use now (on foot), or null.
var interactable: Interactable
var blend: CameraBlend
## Kind -> {"controller": Node with control(pawn), "camera": Camera3D with
## set_target(pawn)}. Game fills it in setup() and add_rig() (planes); a new
## kind of pawn (a boat...) adds its own rig the same way.
var rigs := {}

var _scan := 0.0
var _exit_time := 0.0
var _cooldown := 0.0
var _prompt := ""


func setup(g: Game, c: PlayerCharacter, character_rig: Dictionary, vehicle_rig: Dictionary, camera_blend: CameraBlend) -> void:
	game = g
	character = c
	rigs[Controllable.CHARACTER] = character_rig
	rigs[Controllable.VEHICLE] = vehicle_rig
	blend = camera_blend
	character.vehicle_requested.connect(func(v: Vehicle) -> void: enter(v))
	character.ride_requested.connect(func(v: Vehicle) -> void: ride_with(v))


## The controller and camera for another kind of pawn (Controllable.PLANE).
func add_rig(kind: StringName, rig: Dictionary) -> void:
	rigs[kind] = rig


## The kind of rig that drives `p` (its Controllable's kind).
func kind_of(p: Node) -> StringName:
	var c := Controllable.of(p)
	if c == null or not rigs.has(c.kind):
		return Controllable.VEHICLE
	return c.kind


## The pawn the player controls (the character or the vehicle), or the
## vehicle they ride in as a passenger.
func pawn() -> Node3D:
	match mode:
		Mode.ON_FOOT, Mode.ENTERING, Mode.BOARDING:
			return character
		Mode.RIDING:
			return ride
	return vehicle


func on_foot() -> bool:
	return mode == Mode.ON_FOOT


## In a vehicle and driving it (not while getting in or out).
func driving() -> bool:
	return mode == Mode.IN_VEHICLE


## Sitting in a passenger seat (not while getting in).
func riding() -> bool:
	return mode == Mode.RIDING


func camera_of(kind: StringName) -> Camera3D:
	return rigs[kind]["camera"]


## The camera that should be showing for the current pawn.
func active_camera() -> Camera3D:
	var p := pawn()
	return camera_of(Controllable.CHARACTER if p == character else kind_of(p))


## Shows the right camera (after a menu or replay): the blend if one is
## running, otherwise the pawn's camera.
func show_camera() -> void:
	if blend.blending:
		blend.current = true
	else:
		active_camera().current = true


## While playing, the new pawn's camera shows at once (menus, the title
## screen and replays keep their own cameras until they close).
func _show_if_playing() -> void:
	if game == null or game.state == Game.State.DRIVING:
		show_camera()


# --- Starting states (no transitions) --------------------------------------

## The player stands at `xform` on foot.
func start_on_foot(xform: Transform3D) -> void:
	_end_ride()
	if vehicle:
		_release(vehicle)
	mode = Mode.ON_FOOT
	vehicle = null
	character.set_hidden(false)
	character.place(xform)
	_give(Controllable.CHARACTER, character)
	camera_of(Controllable.CHARACTER).set_target(character)
	blend.cancel()
	_show_if_playing()
	changed.emit(character)


## The player sits in `v` straight away (game start in a vehicle, the
## garage, starting a race on foot).
func start_in_vehicle(v: Vehicle) -> void:
	if vehicle and vehicle != v:
		_release(vehicle)
	if not _claim(v):
		return
	_end_ride()
	mode = Mode.IN_VEHICLE
	vehicle = v
	character.set_hidden(true)
	_give(kind_of(v), v)
	blend.cancel()
	_set_prompt("")
	_show_if_playing()
	changed.emit(v)


## The garage swapped the player's vehicle for a new one: they sit in it.
func replace_vehicle(old: Vehicle, v: Vehicle) -> void:
	var c := Controllable.of(old)
	if c:
		c.drop(self)
	if vehicle == old:
		vehicle = null
	start_in_vehicle(v)


## Finishes a getting-in or -out in progress at once (teleports, the
## garage): getting in completes, getting out is called off.
func settle() -> void:
	match mode:
		Mode.ENTERING:
			_finish_enter(vehicle)
			blend.cancel()
		Mode.BOARDING:
			_finish_boarding(ride)
			blend.cancel()
		Mode.EXITING:
			mode = Mode.IN_VEHICLE
			vehicle.handbrake_input = false
			vehicle.brake_input = 0.0
			_give(kind_of(vehicle), vehicle)


# --- Getting in --------------------------------------------------------------

## Gets into `v` (from on foot). False if that isn't possible now.
func enter(v: Vehicle) -> bool:
	if mode != Mode.ON_FOOT or v == null or not is_instance_valid(v) or not character.can_act():
		return false
	if game and game.state != Game.State.DRIVING:
		return false
	var entry := VehicleEntry.of(v)
	if entry == null or entry.use_for(character) != VehicleEntry.Use.DRIVE:
		return false
	if not _claim(v):
		return false
	mode = Mode.ENTERING
	vehicle = v
	_set_prompt("")
	(rigs[Controllable.CHARACTER]["controller"]).control(null)
	var from_cam := _view_camera()
	if player:
		player.adopt_vehicle(v)
	var chase := camera_of(kind_of(v))
	if chase.get("target") != v:
		chase.set_target(v)
	if chase.has_method("snap_view"):
		chase.call("snap_view", from_cam)
	blend.start(from_cam, chase, BLEND_IN)
	var door := entry.door_spot(character.global_position)
	var face := v.global_position - door
	var walk := clampf(door.distance_to(character.global_position) / 2.6, 0.15, 0.55)
	character.walk_to(door, face, walk, _finish_enter.bind(v))
	return true


func _finish_enter(v: Vehicle) -> void:
	if mode != Mode.ENTERING or vehicle != v:
		return
	if not is_instance_valid(v) or not v.is_inside_tree():
		# The vehicle went away while we walked to it: stay on foot.
		mode = Mode.ON_FOOT
		vehicle = null
		_give(Controllable.CHARACTER, character)
		blend.start(_view_camera(), camera_of(Controllable.CHARACTER), BLEND_OUT)
		return
	character.set_hidden(true)
	mode = Mode.IN_VEHICLE
	_cooldown = COOLDOWN
	_give(kind_of(v), v)
	changed.emit(v)


## Takes `v` for the player: off its traffic driver if it has one. False if
## someone else holds it.
func _claim(v: Vehicle) -> bool:
	var c := Controllable.of(v)
	if c == null:
		return false
	if not c.is_free() and c.yields and c.controller != self:
		# A traffic car: its driver lets go.
		if game == null or game.traffic == null or not game.traffic.claim(v):
			return false
	return c.take(self)


# --- Riding along -------------------------------------------------------------

## Gets into a passenger seat of `v` (from on foot): the other player drives
## it. False if that isn't possible now.
func ride_with(v: Vehicle) -> bool:
	if mode != Mode.ON_FOOT or v == null or not is_instance_valid(v) or not character.can_act():
		return false
	if game and game.state != Game.State.DRIVING:
		return false
	var entry := VehicleEntry.of(v)
	if entry == null or entry.use_for(character) != VehicleEntry.Use.RIDE or not entry.add_rider(self):
		return false
	mode = Mode.BOARDING
	ride = v
	_set_prompt("")
	(rigs[Controllable.CHARACTER]["controller"]).control(null)
	var from_cam := _view_camera()
	var cam := camera_of(kind_of(v))
	if cam.get("target") != v:
		cam.set_target(v)
	cam.set("passenger", true)
	if cam.has_method("snap_view"):
		cam.call("snap_view", from_cam)
	blend.start(from_cam, cam, BLEND_IN)
	var door := entry.door_spot(character.global_position)
	var face := v.global_position - door
	var walk := clampf(door.distance_to(character.global_position) / 2.6, 0.15, 0.55)
	character.walk_to(door, face, walk, _finish_boarding.bind(v))
	return true


func _finish_boarding(v: Vehicle) -> void:
	if mode != Mode.BOARDING or ride != v:
		return
	if not is_instance_valid(v) or not v.is_inside_tree():
		# The vehicle went away while we walked to it: stay on foot.
		_end_ride()
		mode = Mode.ON_FOOT
		_give(Controllable.CHARACTER, character)
		blend.start(_view_camera(), camera_of(Controllable.CHARACTER), BLEND_OUT)
		return
	character.set_hidden(true)
	mode = Mode.RIDING
	_cooldown = COOLDOWN
	_give(kind_of(v), v, true)
	changed.emit(v)


## The player sits in a passenger seat of `v` straight away (the driver
## swapped vehicles in the garage). False if there's no free seat.
func start_riding(v: Vehicle) -> bool:
	if vehicle:
		_release(vehicle)
		vehicle = null
	_end_ride()
	var entry := VehicleEntry.of(v)
	if entry == null or not entry.add_rider(self):
		return false
	mode = Mode.RIDING
	ride = v
	character.set_hidden(true)
	_give(kind_of(v), v, true)
	blend.cancel()
	_set_prompt("")
	_show_if_playing()
	changed.emit(v)
	return true


## Gets out of the passenger seat (once the vehicle has stopped or nearly).
## False if the player isn't riding.
func leave_ride() -> bool:
	if mode != Mode.RIDING:
		return false
	var v := ride
	var driver := _driver_name(v)
	var plane := v as Aircraft
	if plane and (not plane.on_ground or plane.airspeed > 12.0):
		_toast(("Wait until %s lands!" % driver) if driver != "" else "Wait until it lands!")
		return true
	if v.linear_velocity.length() > RIDER_EXIT_SPEED:
		_toast(("Wait until %s stops!" % driver) if driver != "" else "Too fast to get out!")
		return true
	var entry := VehicleEntry.of(v)
	var spot: Variant = entry.find_exit(character, true) if entry else null
	if spot == null:
		_toast("No room to get out here!")
		return true
	_step_off(spot, true)
	return true


## Out of the passenger seat at once, wherever there's room (teleports, the
## garage, player 2 leaving). Does nothing if the player isn't riding.
func leave_ride_now() -> void:
	if mode != Mode.RIDING and mode != Mode.BOARDING:
		return
	var v := ride
	var spot: Variant = null
	if is_instance_valid(v):
		var entry := VehicleEntry.of(v)
		spot = entry.find_exit(character, true) if entry else null
		if spot == null:
			var ground := v.upright_ground_transform()
			spot = ground.translated_local(Vector3(v.body_half_width + 0.9, 0.0, 0.0))
	else:
		spot = Transform3D(Basis.IDENTITY, character.global_position)
	_step_off(spot, false)


## Stands the passenger up at `spot` (on foot again); `glide`: the camera
## glides back to the on-foot camera, else it's there at once.
func _step_off(spot: Transform3D, glide: bool) -> void:
	var from_cam := _view_camera()
	_end_ride()
	mode = Mode.ON_FOOT
	character.set_hidden(false)
	character.place(spot)
	var foot := camera_of(Controllable.CHARACTER)
	foot.set_target(character)
	if foot is OnFootCamera:
		(foot as OnFootCamera).match_view(from_cam)
	_give(Controllable.CHARACTER, character)
	if glide:
		blend.start(from_cam, foot, BLEND_OUT)
	else:
		blend.cancel()
		_show_if_playing()
	_scan = 0.0
	_cooldown = COOLDOWN
	changed.emit(character)


## Frees the passenger seat (if any) and gives the cameras back.
func _end_ride() -> void:
	if ride == null:
		return
	var entry := VehicleEntry.of(ride)
	if entry:
		entry.remove_rider(self)
	for k: StringName in rigs:
		var cam: Camera3D = rigs[k]["camera"]
		if "passenger" in cam:
			cam.set("passenger", false)
	# The chase camera goes back to the player's own vehicle.
	var chase := camera_of(Controllable.VEHICLE)
	if player and is_instance_valid(player.vehicle) and chase.get("target") == ride:
		chase.set_target(player.vehicle)
	ride = null


## "Player 1" if a player drives `v`, else "".
func _driver_name(v: Vehicle) -> String:
	var c := Controllable.of(v)
	var p := c.controller as Possession if c and not c.is_free() else null
	if p and p != self and p.player:
		return "Player %d" % (p.player.index + 1)
	return ""


func _toast(text: String) -> void:
	if player:
		player.hud.show_toast(text, 2.0)


# --- Getting out -------------------------------------------------------------

## Gets out of the vehicle (stopping it first if it's moving). False if the
## player isn't driving.
func exit() -> bool:
	if mode != Mode.IN_VEHICLE or vehicle == null:
		return false
	var plane := vehicle as Aircraft
	if plane and (not plane.on_ground or plane.airspeed > 12.0):
		# No getting out of a flying plane: land it first.
		if player:
			player.hud.show_toast("Land the plane first!" if not plane.on_ground else "Slow down first!", 2.0)
		return true
	mode = Mode.EXITING
	_exit_time = 0.0
	(rigs[kind_of(vehicle)]["controller"]).control(null)
	return true


func _physics_process(dt: float) -> void:
	_cooldown -= dt
	match mode:
		Mode.EXITING:
			_exiting(dt)
		Mode.RIDING:
			if not is_instance_valid(ride) or not ride.is_inside_tree():
				leave_ride_now()  # (the vehicle went away)
			else:
				# The hidden character goes along, so getting out of a vehicle
				# that vanished leaves them where it was.
				character.global_position = ride.global_position
		Mode.ON_FOOT:
			_scan -= dt
			if _scan <= 0.0:
				_scan = SCAN_EVERY
				_update_interactable()


func _exiting(dt: float) -> void:
	var v := vehicle
	if v == null or not is_instance_valid(v):
		mode = Mode.IN_VEHICLE
		return
	_exit_time += dt
	# Brake to a stop (handbrake too; no brake pedal at a standstill, where
	# it would mean reverse).
	v.throttle_input = 0.0
	v.steer_input = 0.0
	v.horn_input = false
	v.handbrake_input = true
	v.brake_input = 1.0 if absf(v.forward_speed) > 1.0 else 0.0
	var speed := v.linear_velocity.length()
	if speed > EXIT_SPEED and _exit_time < EXIT_BRAKE_TIME:
		return
	if speed > 6.0:
		_cancel_exit("Too fast to get out!")
		return
	var entry := v.get_node_or_null("Entry") as VehicleEntry
	var spot: Variant = entry.find_exit(character) if entry else null
	if spot == null:
		_cancel_exit("No room to get out here!")
		return
	var from_cam := _view_camera()
	_release(v)
	mode = Mode.ON_FOOT
	vehicle = null
	character.set_hidden(false)
	character.place(spot)
	var foot := camera_of(Controllable.CHARACTER)
	foot.set_target(character)
	if foot is OnFootCamera:
		(foot as OnFootCamera).match_view(from_cam)
	_give(Controllable.CHARACTER, character)
	blend.start(from_cam, foot, BLEND_OUT)
	_scan = 0.0
	_cooldown = COOLDOWN
	changed.emit(character)


func _cancel_exit(why: String) -> void:
	mode = Mode.IN_VEHICLE
	vehicle.handbrake_input = false
	vehicle.brake_input = 0.0
	_give(kind_of(vehicle), vehicle)
	if player:
		player.hud.show_toast(why, 2.0)


## Lets go of `v`: it's parked (handbrake on), the Game turns it off.
func _release(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	(rigs[kind_of(v)]["controller"]).control(null)
	v.throttle_input = 0.0
	v.brake_input = 0.0
	v.steer_input = 0.0
	v.horn_input = false
	v.handbrake_input = true
	var c := Controllable.of(v)
	if c:
		c.drop(self)
	if player:
		player.leave_vehicle(v)


## Hands input to the rig for `kind` (it gets `pawn`); every other rig lets
## go. A `passenger` gets the camera only: every controller lets go.
func _give(kind: StringName, p: Node3D, passenger := false) -> void:
	for k: StringName in rigs:
		var ctrl: Node = rigs[k]["controller"]
		if k != kind or passenger:
			ctrl.control(null)
	if not passenger:
		(rigs[kind]["controller"]).control(p)
	var cam: Camera3D = rigs[kind]["camera"]
	if cam.get("target") != p:
		cam.set_target(p)  # (re-targeting re-snaps it: not mid-glide)
	if "passenger" in cam:
		cam.set("passenger", passenger)
	if p is PlayerCharacter:
		Controllable.of(p).take(self)
	else:
		Controllable.of(character).drop(self)


# --- Interaction -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.state != Game.State.DRIVING:
		return
	if not (player.input.event_pressed(event, "interact") if player else event.is_action_pressed("interact")):
		return
	if _cooldown > 0.0:
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.ON_FOOT:
		_update_interactable()
		if interactable and interactable.interact(character):
			get_viewport().set_input_as_handled()
			_scan = 0.0
	elif mode == Mode.IN_VEHICLE:
		if exit():
			get_viewport().set_input_as_handled()
	elif mode == Mode.RIDING:
		if leave_ride():
			get_viewport().set_input_as_handled()


func _update_interactable() -> void:
	interactable = null
	if character.can_act():
		interactable = Interactable.best_for(character, character.global_position)
	_set_prompt(interactable.prompt(character) if interactable else "")


func _set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	if player:
		player.hud.show_prompt(text)


## The camera this player sees through now (the blend's view, in split-screen
## their own view's camera).
func _view_camera() -> Camera3D:
	return blend.get_viewport().get_camera_3d() if blend and blend.is_inside_tree() else get_viewport().get_camera_3d()
