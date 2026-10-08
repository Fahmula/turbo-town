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

## The player now controls `pawn` (the character or a vehicle).
signal changed(pawn: Node3D)

enum Mode { ON_FOOT, ENTERING, IN_VEHICLE, EXITING }

const BLEND_IN := 0.85
const BLEND_OUT := 0.65
## Getting out of a moving vehicle brakes it first, for at most this long.
const EXIT_BRAKE_TIME := 3.0
const EXIT_SPEED := 1.6
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


## The controller and camera for another kind of pawn (Controllable.PLANE).
func add_rig(kind: StringName, rig: Dictionary) -> void:
	rigs[kind] = rig


## The kind of rig that drives `p` (its Controllable's kind).
func kind_of(p: Node) -> StringName:
	var c := Controllable.of(p)
	if c == null or not rigs.has(c.kind):
		return Controllable.VEHICLE
	return c.kind


## The pawn the player controls (the character or the vehicle).
func pawn() -> Node3D:
	return character if mode == Mode.ON_FOOT or mode == Mode.ENTERING else vehicle


func on_foot() -> bool:
	return mode == Mode.ON_FOOT


## In a vehicle and driving it (not while getting in or out).
func driving() -> bool:
	return mode == Mode.IN_VEHICLE


func camera_of(kind: StringName) -> Camera3D:
	return rigs[kind]["camera"]


## The camera that should be showing for the current pawn.
func active_camera() -> Camera3D:
	return camera_of(Controllable.CHARACTER if pawn() == character else kind_of(vehicle))


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
	var entry := v.get_node_or_null("Entry") as VehicleEntry
	if entry == null or entry.prompt(character) == "" or entry.is_overturned():
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


## Hands input to the rig for `kind` (it gets `pawn`); every other rig lets go.
func _give(kind: StringName, p: Node3D) -> void:
	for k: StringName in rigs:
		var ctrl: Node = rigs[k]["controller"]
		if k != kind:
			ctrl.control(null)
	(rigs[kind]["controller"]).control(p)
	var cam: Camera3D = rigs[kind]["camera"]
	if cam.get("target") != p:
		cam.set_target(p)  # (re-targeting re-snaps it: not mid-glide)
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
