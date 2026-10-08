class_name LocalPlayer
extends Node
## One player on this machine: their character, the vehicle they drive, the
## rigs that control them (on foot, driving, flying: a controller and a camera
## each), their HUD, stunt scoring and input devices. With one player there is
## one LocalPlayer and Game's old fields (game.vehicle, game.camera...) lead to
## it. Split-screen adds a second one (Game.add_player), each with their own
## view (SplitScreen) and controller.
##
## `vehicle` is the player's vehicle: the one they're driving, or on foot the
## one they last drove ("your car", shown on the map; the other player can't
## take it). Vehicles they got out of before that stay parked for a while
## (left_vehicles). The rig nodes are children of Game (player 1's keep their
## old names: "Character", "FootCamera"...; player 2's end in "2").

const CHARACTER_SCENE := preload("res://scenes/player/player_character.tscn")
## Each player's colour: their arrow on the maps, the marker over them in the
## other player's view and the chip on their HUD (ART_BIBLE.md §5).
const COLORS: Array[Color] = [Color(1.0, 0.3, 0.25), Color(0.35, 0.62, 1.0)]
## Player 2's T-shirt (sRGB). Player 1 wears the model's red-orange.
const P2_SHIRT := Color(0.2, 0.42, 0.8)
## Meta on a player's vehicle and character: which player (0, 1) it belongs to.
const OWNER_META := Controllable.OWNER_META

var game: Game
## 0 = player 1, 1 = player 2.
var index := 0
var input := PlayerInput.shared()
var vehicle: Vehicle
var controller: PlayerVehicleController
var camera: ChaseCamera
var hud: Hud
var character: PlayerCharacter
var possession: Possession
var foot_camera: OnFootCamera
var foot_controller: PlayerCharacterController
## The flying rig: a plane's controls and camera (the Possession hands them
## the plane when the player sits in one).
var flight_controller: PlayerAircraftController
var flight_camera: FlightCamera
var camera_blend: CameraBlend
var stunts: StuntTracker
## Vehicles the player got out of earlier (not `vehicle`), oldest first.
var left_vehicles: Array[Vehicle] = []
## The garage setup (paint, wheels...) on the player's vehicle.
var loadout: Loadout
var spawn_index := 0
## The SplitScreen view this player sees (null with one player).
var view: SubViewport

## Split-screen: the marker over this player, shown in the other's view.
var _tag: Label3D
var _lost_timer := 0.0
var _tidy_timer := 0.0


func _init(g: Game, i: int) -> void:
	game = g
	index = i
	name = "Player%d" % (i + 1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## "" for player 1, "2" for player 2 (node names).
func suffix() -> String:
	return "" if index == 0 else str(index + 1)


func color() -> Color:
	return COLORS[mini(index, COLORS.size() - 1)]


## Hands the player their starting vehicle and the scene's driving rig
## (player 1: the nodes in main.tscn), then builds the rest.
func setup(car: Vehicle, ctrl: PlayerVehicleController, cam: ChaseCamera, h: Hud) -> void:
	vehicle = car
	controller = ctrl
	camera = cam
	hud = h
	if car:
		car.set_meta(OWNER_META, index)
	_make_character()
	_make_stunts()
	set_input(input)


## The character, its camera and controls, and the Possession that moves the
## player between the character and vehicles.
func _make_character() -> void:
	var sfx := suffix()
	character = CHARACTER_SCENE.instantiate() as PlayerCharacter
	character.name = "Character" + sfx
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	character.set_meta(OWNER_META, index)
	game.add_child(character)
	character.set_hidden(true)
	character.knocked.connect(_on_character_knocked)
	if index > 0:
		_dress(character)
	foot_camera = OnFootCamera.new()
	foot_camera.name = "FootCamera" + sfx
	foot_camera.far = camera.far
	foot_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(foot_camera)
	foot_controller = PlayerCharacterController.new()
	foot_controller.name = "FootController" + sfx
	foot_controller.camera = foot_camera
	foot_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(foot_controller)
	camera_blend = CameraBlend.new()
	camera_blend.name = "CameraBlend" + sfx
	camera_blend.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(camera_blend)
	flight_camera = FlightCamera.new()
	flight_camera.name = "FlightCamera" + sfx
	flight_camera.far = camera.far
	flight_camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(flight_camera)
	flight_controller = PlayerAircraftController.new()
	flight_controller.name = "FlightController" + sfx
	flight_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(flight_controller)
	possession = Possession.new()
	possession.name = "Possession" + sfx
	possession.process_mode = Node.PROCESS_MODE_PAUSABLE
	possession.player = self
	game.add_child(possession)
	possession.setup(game, character,
		{"controller": foot_controller, "camera": foot_camera},
		{"controller": controller, "camera": camera}, camera_blend)
	possession.add_rig(Controllable.PLANE, {"controller": flight_controller, "camera": flight_camera})
	possession.changed.connect(_on_pawn_changed)


## Player 2 wears a blue T-shirt, so the two characters look different.
func _dress(c: PlayerCharacter) -> void:
	for node in c.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "Char_Shirt" and mat is BaseMaterial3D:
				var shirt := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				shirt.albedo_texture = null
				shirt.albedo_color = P2_SHIRT
				mi.set_surface_override_material(s, shirt)


func _make_stunts() -> void:
	stunts = StuntTracker.new()
	stunts.name = "Stunts" + suffix()
	stunts.process_mode = Node.PROCESS_MODE_PAUSABLE
	stunts.traffic = game.traffic
	game.add_child(stunts)
	stunts.trick.connect(_on_trick)
	stunts.combo_changed.connect(hud.show_combo)
	stunts.combo_banked.connect(_on_combo_banked)
	stunts.combo_lost.connect(func(reason: String) -> void: hud.show_popup(reason, 1.6, Color(1.0, 0.35, 0.3)))
	stunts.vehicle = vehicle


func _on_trick(trick_name: String, _points: int) -> void:
	if trick_name != "NEAR MISS" and not trick_name.begins_with("AIR "):
		hud.show_popup(trick_name + "!", 1.3)


func _on_combo_banked(points: int, _place: int) -> void:
	hud.set_score(stunts.score)
	if points >= 300:
		hud.show_popup("+%s" % Hud.format_points(points), 1.5, Color(0.5, 1.0, 0.45))


## Gives every controller and camera of this player `inp` (their devices).
func set_input(inp: PlayerInput) -> void:
	input = inp
	for n: Object in [controller, flight_controller, foot_controller, camera, foot_camera, flight_camera]:
		if n:
			n.set("input", inp)
	if hud:
		hud.input = inp


## Turns all of this player's controls on or off (menus).
func set_controls(on: bool) -> void:
	controller.enabled = on
	foot_controller.enabled = on
	flight_controller.enabled = on


## The rig nodes that render this player's view: the cameras and the HUD.
func _view_nodes() -> Array[Node]:
	return [camera, foot_camera, flight_camera, camera_blend, hud]


## Split-screen: this player now sees the world through `v` (their half of
## the screen); null puts everything back in the main viewport.
func enter_view(v: SubViewport) -> void:
	view = v
	var parent: Node = v if v else game
	var active := possession.active_camera() if not camera_blend.blending else camera_blend
	for n in _view_nodes():
		if n.get_parent() != parent:
			n.reparent(parent)
	# The marker over the other player shows in this view only; the grass
	# around the other player doesn't.
	var mask := 0xFFFFF
	if v:
		mask &= ~Views.ALL_VIEW_LAYERS
		mask |= Views.VIEW_LAYERS[index]
	for cam: Camera3D in [camera, foot_camera, flight_camera, camera_blend]:
		cam.cull_mask = mask
	if v:
		active.current = true
	hud.set_compact(v != null, index)
	_fit_tag()


## Split-screen: a marker over this player ("P1" in their colour) that only
## the other player sees.
func _fit_tag() -> void:
	var want := view != null and game.players.size() > 1
	if want and _tag == null:
		_tag = Label3D.new()
		_tag.name = "Tag" + suffix()
		_tag.text = "P%d" % (index + 1)
		_tag.font_size = 64
		_tag.outline_size = 14
		_tag.modulate = color()
		_tag.outline_modulate = UiKit.OUTLINE
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.fixed_size = true
		_tag.pixel_size = 0.0009
		_tag.render_priority = 10
		_tag.outline_render_priority = 9
		_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tag.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		game.add_child(_tag)
	if _tag and not want:
		_tag.queue_free()
		_tag = null
	if _tag:
		_tag.visible = want
		# Seen in every view but this player's own.
		var layers := 0
		for i in Views.VIEW_LAYERS.size():
			if i != index:
				layers |= Views.VIEW_LAYERS[i]
		_tag.layers = layers


func _process(_dt: float) -> void:
	if _tag and _tag.visible:
		var p := possession.pawn()
		if p and is_instance_valid(p):
			var top := 2.25
			if p is Vehicle:
				top = (p as Vehicle).body_top + 1.2
			_tag.global_position = p.get_global_transform_interpolated().origin + Vector3.UP * top


## The camera this player sees through now.
func view_camera() -> Camera3D:
	if camera_blend.blending:
		return camera_blend
	return possession.active_camera()


## What traffic lives around: the character on foot, else the vehicle.
func focus_node() -> Node3D:
	return possession.pawn() if possession else vehicle


## Removes this player's nodes (player 2 leaving). They stop at once: their
## split-screen actions are going away.
func free_rig() -> void:
	set_input(PlayerInput.shared())
	for n: Node in [character, foot_camera, foot_controller, camera_blend, flight_camera, flight_controller,
			possession, stunts, _tag, controller, camera, hud]:
		if n and is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.queue_free()
	process_mode = Node.PROCESS_MODE_DISABLED


# --- Being driven by the Possession -----------------------------------------

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
	if game.traffic and index == 0:
		game.traffic.focus = pawn
	hud.set_flying(plane != null)
	hud.set_on_foot(foot, character, foot_camera)
	stunts.enabled = stunts_wanted()
	_fit_headlights()
	_fit_reflection()
	if not foot:
		hud.show_prompt_for("Get out", 4.0)
	if plane and plane.on_ground and game.state == Game.State.DRIVING:
		_take_off_tip()
	game.refresh_friends()


## How to take off, for the controller in use.
func _take_off_tip() -> void:
	if hud.using_pad:
		hud.show_toast("Hold RT for power, pull the stick back at 80 km/h!", 5.0)
	else:
		hud.show_toast("Hold Shift for power, press S at 80 km/h!", 5.0)


## Stunt scoring is for driving: not on foot, not in a plane.
func stunts_wanted() -> bool:
	return game.state == Game.State.DRIVING and driving() and not (vehicle is Aircraft)


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


# --- Places ------------------------------------------------------------------

func teleport_to(i: int) -> void:
	var world := game.world
	if world.spawn_points.is_empty():
		return
	if game.race and game.race.is_active():
		game.race.end_race()
	spawn_index = wrapi(i, 0, world.spawn_points.size())
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
	if game.state == Game.State.DRIVING:
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
		plane.teleport(game.runway_start(plane, _runway_lane()))
	else:
		var xf: Transform3D = sp["xform"]
		var heading := -xf.basis.z
		heading.y = 0.0
		# Side by side when both players fly to the same place.
		var side := heading.cross(Vector3.UP).normalized() * _runway_lane() if heading.length() > 0.1 else Vector3.ZERO
		plane.place_in_flight(xf.origin + Vector3.UP * 90.0 + side * 2.0, heading.normalized() if heading.length() > 0.1 else Vector3.FORWARD)
	snap_camera()


## Split-screen: each player has their own side of the runway (m off the
## middle; 0 with one player).
func _runway_lane() -> float:
	if game.players.size() < 2:
		return 0.0
	return -7.0 if index == 0 else 7.0


## Puts the player's plane on the runway, ready for take-off (a vehicle
## someone left standing there is cleared away first).
func _put_on_runway(plane: Aircraft) -> void:
	var start := game.runway_start(plane, _runway_lane())
	for p in game.players:
		for v: Vehicle in p.left_vehicles.duplicate():
			if is_instance_valid(v) and v != plane and v.global_position.distance_to(start.origin) < 12.0:
				p.left_vehicles.erase(v)
				if game.traffic:
					game.traffic.untrack(v)
				v.queue_free()
	plane.teleport(start)
	for i in game.world.spawn_points.size():
		if game.world.spawn_points[i]["name"] == "Airfield":
			spawn_index = i
	snap_camera()


## Snaps the vehicle cameras behind the player's vehicle (after teleports).
func snap_camera() -> void:
	camera.snap()
	if flight_camera:
		flight_camera.snap()


## Back to the spawn point, or during a race to the last gate passed.
func respawn() -> void:
	var race := game.race
	if index == 0 and race and race.is_active() and driving():
		vehicle.teleport(race.respawn_point())
		snap_camera()
	else:
		teleport_to(spawn_index)


## Split-screen: goes to where the other player is (their vehicle comes
## too). Flying players meet in the air, everyone else on the ground beside
## the other player.
func regroup(other: LocalPlayer) -> void:
	if possession:
		possession.settle()
	var them := other.focus_node()
	if them == null or not is_instance_valid(them):
		return
	var t := them.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var their_plane := them as Aircraft
	var flying_there := their_plane != null and not their_plane.on_ground
	var plane := vehicle as Aircraft
	var msg := "With Player %d!" % (other.index + 1)
	if plane and driving() and flying_there:
		plane.place_in_flight(t.origin + right * 18.0 - fwd * 12.0 + Vector3.UP * 4.0, fwd)
		snap_camera()
		hud.show_toast("Flying with Player %d!" % (other.index + 1))
		return
	var near: Node3D = them
	if flying_there:
		# They're in the air: meet them at the nearest place on the ground.
		near = null
	if plane:
		# A plane stays where it is: walk over on foot (or wait at the runway).
		if not possession.on_foot():
			hud.show_toast("Land and get out first!")
			return
		var spot := _ground_near(near.global_position if near else game.nearest_spawn(t.origin)["xform"].origin, fwd)
		if spot.is_empty():
			teleport_to(game.nearest_spawn_index(t.origin))
			return
		character.place(spot["xform"])
		foot_camera.snap()
	else:
		var room := spot_near(near, vehicle) if near else {}
		if room.is_empty():
			teleport_to(game.nearest_spawn_index(t.origin))
			return
		vehicle.teleport(room["xform"])
		snap_camera()
		if possession.on_foot():
			_step_out_beside(vehicle)
	if game.state == Game.State.DRIVING:
		hud.show_toast(msg)


## Room for `car` on the ground beside `them` (a player's character or
## vehicle), facing the way they face: {"xform"} or {}.
func spot_near(them: Node3D, car: Vehicle) -> Dictionary:
	if them == null or not is_instance_valid(them):
		return {}
	var t := them.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var width := car.body_half_width + 1.6
	if them is Vehicle:
		width += (them as Vehicle).body_half_width
	var exclude: Array[RID] = []
	if car.is_inside_tree():
		exclude.append(car.get_rid())
	for off: Vector3 in [right * width, -right * width, -fwd * 8.0, fwd * 8.0, right * (width + 4.0), -right * (width + 4.0)]:
		var ground := _ground_near(t.origin + off, fwd)
		if ground.is_empty():
			continue
		# (Characters count too: the new car mustn't land on anyone.)
		var room := game.find_room(car, ground["xform"], exclude, 0b1111)
		if not room.is_empty():
			return room
	return {}


## The ground under `at` (within a few metres up or down), facing `fwd`:
## {"xform"} or {} over water or nothing.
func _ground_near(at: Vector3, fwd: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit["position"] as Vector3).y < MapLayout.SEA_LEVEL:
		return {}
	return {"xform": Transform3D(Basis.looking_at(fwd, Vector3.UP), hit["position"])}


# --- Every tick ----------------------------------------------------------------

func physics_tick(dt: float) -> void:
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
	_tidy_timer -= dt
	if _tidy_timer <= 0.0:
		_tidy_timer = 2.0
		_tidy_left_vehicles()


func _input(event: InputEvent) -> void:
	if input.owns(event):
		input.note(event)


func _unhandled_input(event: InputEvent) -> void:
	# In split-screen the cameras sit in this player's view, which gets no
	# input of its own: pass on their mouse look and camera button.
	if view == null or not input.owns(event):
		return
	if game.state != Game.State.DRIVING:
		return
	for cam: Node in [camera, foot_camera, flight_camera]:
		cam.handle_input(event)


# --- Changing vehicle ----------------------------------------------------------

## Replaces the player's vehicle with catalog entry `i`, set up as `setup`
## says (default: as saved in the garage), with the player in it. It's parked
## upright where the old one was if the player was driving, or next to the
## character if they were on foot (or at the current spawn point if there's
## no room). With `place_here` false the caller positions it (e.g. a
## teleport right after).
func change_vehicle(i: int, setup: Loadout = null, place_here := true) -> void:
	var old := vehicle
	var car := VehicleCatalog.scene(i).instantiate() as Vehicle
	car.traction_control = old.traction_control
	loadout = setup.copy() if setup else Loadout.saved(VehicleCatalog.ENTRIES[i]["id"])
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
			spot = game.find_room(car, old.upright_ground_transform(), [old.get_rid()])

	var slot := old.get_index()
	_unwire(old)
	left_vehicles.erase(old)
	if game.traffic:
		game.traffic.untrack(old)
	game.remove_child(old)
	old.queue_free()
	car.name = "PlayerCar" + suffix()
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Put it in place before it enters the tree (see TrafficManager._spawn).
	if not spot.is_empty():
		car.transform = spot["xform"]
	elif not game.world.spawn_points.is_empty():
		car.transform = game.world.spawn_points[spawn_index]["xform"]
	game.add_child(car)
	game.move_child(car, slot)
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
	var space := game.get_world_3d().direct_space_state
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
		var room := game.find_room(car, base, skip)
		if not room.is_empty():
			return room
	return {}


# --- The player's vehicle ------------------------------------------------------

## Makes `car` the player's vehicle as they get into it: the chase camera,
## HUD, maps, traffic, stunts, damage messages, headlights, reflections and
## full engine sound follow it (and for player 1 the replays and races). The
## Possession hands it the controls. The vehicle they had before stays parked
## as a left vehicle. `fresh`: a brand-new vehicle (from the garage), started
## from cold.
func adopt_vehicle(car: Vehicle, fresh := false) -> void:
	var old := vehicle
	if car.get_parent() != game:
		# A traffic car: it's the player's now (never pooled or despawned).
		var lv := car.linear_velocity
		var av := car.angular_velocity
		car.reparent(game)
		car.linear_velocity = lv
		car.angular_velocity = av
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	var audio := car.get_node_or_null("Audio") as VehicleAudio
	var was_off := audio != null and not audio.engine_running
	if old and old != car and is_instance_valid(old):
		_unwire(old)
		_park_left(old)
	left_vehicles.erase(car)
	# Someone else's old parked car: it's this player's now.
	for p in game.players:
		if p != self:
			p.left_vehicles.erase(car)
	if game.traffic:
		game.traffic.untrack(car)
	vehicle = car
	car.set_meta(OWNER_META, index)
	car.traction_control = Settings.get_value("assists")
	car.auto_reverse = true
	camera.set_target(car)
	hud.set_vehicle(car)
	if game.traffic:
		if index == 0:
			game.traffic.set_player(car)
		else:
			game.traffic.refresh_players()
	stunts.vehicle = car
	game.on_player_vehicle(self, car, old)
	if old != car:
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
	game.refresh_friends()


## The player got out of `car`: it stays parked where it is (handbrake on,
## engine off, lights out) and is still their vehicle; the camera, HUD and
## traffic follow the character now.
func leave_vehicle(car: Vehicle) -> void:
	game.on_player_left_vehicle(self)
	stunts.bank_now()
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
	if game.traffic:
		game.traffic.track(car)


## Disconnects the player-only signals from a vehicle the player no longer has.
func _unwire(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	if v.get_meta(OWNER_META, -1) == index:
		v.remove_meta(OWNER_META)
	var pairs: Array = [[v.vehicle_reset, camera.snap]]
	if game.race:
		pairs.append([v.vehicle_reset, game.race.on_teleport])
	if game.replay:
		pairs.append([v.vehicle_reset, game.replay.mark_cut])
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg:
		if dmg.part_lost.is_connected(_on_part_lost):
			dmg.part_lost.disconnect(_on_part_lost)
		if dmg.crashed.is_connected(game._on_crash):
			dmg.crashed.disconnect(game._on_crash)


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
	if game.traffic:
		game.traffic.track(v)


## Removes left vehicles that are far away, or beyond the limit, once nobody
## can see them.
func _tidy_left_vehicles() -> void:
	var here := possession.pawn().global_position if possession else vehicle.global_position
	for v: Vehicle in left_vehicles.duplicate():
		if not is_instance_valid(v):
			left_vehicles.erase(v)
			continue
		var too_many := left_vehicles.size() > Game.MAX_LEFT_VEHICLES and v == left_vehicles[0]
		var far := v.global_position.distance_to(here) > Game.LEFT_VEHICLE_RANGE or v.global_position.y < MapLayout.SEA_LEVEL - 2.0
		var seen := Views.sees(game, v.global_position, 260.0)
		if (too_many or far) and not seen:
			left_vehicles.erase(v)
			if game.traffic:
				game.traffic.untrack(v)
			v.queue_free()


func _watch_damage(v: Vehicle) -> void:
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg and not dmg.part_lost.is_connected(_on_part_lost):
		dmg.part_lost.connect(_on_part_lost)
		if index == 0:
			dmg.crashed.connect(game._on_crash)


func _on_part_lost(part_name: String) -> void:
	if driving():
		hud.show_toast("%s FELL OFF!" % part_name, 2.0)


## Real headlights on the player's vehicle (only after dark, and only while
## driving it; traffic cars just have glowing lamps, to keep the light count
## low).
func _fit_headlights() -> void:
	if vehicle == null or game.day_night == null:
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
	lights.visible = game.day_night.is_night and driving()


## The player's vehicle gets the full sound and starts its engine.
func _start_engine(v: Vehicle) -> void:
	var audio := v.get_node_or_null("Audio") as VehicleAudio
	if audio:
		audio.set_detail(VehicleAudio.Detail.FULL)
		audio.start_engine()


## Real reflections in the player car's paint and glass on High
## (VehicleReflection), while driving it; Medium and Low keep the sky-only
## reflections. Split-screen skips them: the probe re-renders the world
## around the car, and two of those on top of two views are too much.
func _fit_reflection() -> void:
	if vehicle == null:
		return
	var probe := vehicle.get_node_or_null("Reflection") as VehicleReflection
	# (Not on planes: they'd re-capture it several times a second.)
	var want: bool = Settings.get_value("graphics") >= GraphicsQuality.HIGH and driving() and not (vehicle is Aircraft) \
		and not Views.is_split()
	if want and probe == null:
		probe = VehicleReflection.new()
		probe.vehicle = vehicle
		vehicle.add_child(probe)
	elif not want and probe:
		probe.queue_free()
