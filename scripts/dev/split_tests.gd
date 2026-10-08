extends RefCounted
## The split-screen dev tests (run from DevTools):
##   --split=<dir>       two players: joining from the menu with a second
##                       gamepad, each player's own buttons and sticks (no
##                       cross-talk), walking, getting in, driving, the other
##                       player's car, cameras / HUD / grass / markers in the
##                       right view, teleports, going to the other player,
##                       the garage for player 2, planes side by side on the
##                       runway, traffic around both, night lights, pause and
##                       an unplugged controller, leaving and joining again
##                       (keyboard as player 2), back to the title, leak
##                       check (checks and shots)
##   --splitbench=<dir>  what split-screen costs: GPU time, frame time and
##                       draw calls for one view and for two, in city,
##                       highway, country and flying views and along a drive,
##                       at Low / Medium / High (run it with --gpu-index 0 and
##                       --resolution 1280x800: the Deck's screen on the
##                       iGPU, about 1.6x slower than a Deck)
## Gamepads are simulated with joypad events from devices 0 and 1, so the
## real per-device bindings are what's tested.

var tools: Node
var game: Game
var dir := ""
var fails := 0
var checks := 0
var _lines: PackedStringArray = []


func _init(t: Node, g: Game, d: String) -> void:
	tools = t
	game = g
	dir = d


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := tools.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("shot: ", name)


func wait(frames: int) -> void:
	for i in frames:
		await tools.get_tree().process_frame


func wait_s(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()


## A gamepad button press and release from `device`.
func pad(device: int, button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = device
		ev.button_index = button
		ev.pressed = pressed
		ev.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)
		await wait(3)


## A stick or trigger on `device` held at `value`.
func axis(device: int, a: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = a
	ev.axis_value = value
	Input.parse_input_event(ev)


func key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)


func release_pads() -> void:
	for device in [0, 1]:
		for a: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			axis(device, a, 0.0)


## Brakes player `p`'s car to a stop with their gamepad (`device`): the
## brake reverses once stopped, so it's let go then.
func stop(p: LocalPlayer, device: int) -> void:
	axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	var t := 0.0
	while t < 4.0 and absf(p.vehicle.forward_speed) > 0.8:
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()
	axis(device, JOY_AXIS_TRIGGER_LEFT, 0.0)
	await wait_s(0.5)


## The highest speed `v` reaches in `seconds` (km/h).
func top_speed(v: Vehicle, seconds: float) -> float:
	var best := 0.0
	var t := 0.0
	while t < seconds:
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()
		best = maxf(best, v.speed_kmh)
	return best


## True if `v`'s sound players fade with distance (split-screen), false if
## they play at their set level (one player).
func _engine_fades(v: Vehicle) -> bool:
	var audio := v.get_node_or_null("Audio")
	if audio == null:
		return false
	for c in audio.get_children():
		if c is AudioStreamPlayer3D and c.has_meta("looping"):
			return (c as AudioStreamPlayer3D).attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED
	return false


func flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


## Player 1 (gamepad `p1_device`, -1 = keyboard) opens the 2 PLAYERS page
## from the pause menu; player 2 presses A on `p2_device` (-1 = Enter).
func join(p1_device: int, p2_device: int) -> void:
	game._enter_pause()
	await wait(3)
	game.menu._last_device = p1_device
	game.menu._open_join()
	await wait(3)
	if p2_device >= 0:
		await pad(p2_device, JOY_BUTTON_A)
	else:
		key(KEY_ENTER, true)
		await wait(2)
		key(KEY_ENTER, false)
	await wait(10)


# =========================================================================
# --split
# =========================================================================

func run() -> void:
	var g := game
	var root := tools.get_tree().root
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(1.0)
	g.ensure_driving()
	g.possession.settle()
	g._step_out_beside(g.vehicle)  # player 1 on foot by their car
	await wait_s(0.5)
	var kids_before := g.get_children().map(func(n: Node) -> String: return String(n.name))
	var views_before := root.find_children("*", "SubViewport", true, false).size()
	var actions_before := InputMap.get_actions().size()

	# --- Joining from the menu ----------------------------------------------
	g._enter_pause()
	await wait(3)
	check(g.menu.page == "pause" and g.menu._player2_button.text == "ADD PLAYER 2", "pause menu offers ADD PLAYER 2")
	g.menu._last_device = 0
	g.menu._open_join()
	await wait(3)
	check(g.menu.page == "join", "2 PLAYERS page open")
	await shot("join_page")
	await pad(0, JOY_BUTTON_A)
	check(g.menu.page == "join" and not g.is_split() and g.menu._join_note.text.begins_with("That's player 1's"), "player 1's own A doesn't join (%s)" % g.menu._join_note.text)
	await pad(1, JOY_BUTTON_A)
	await wait(10)
	check(g.is_split() and g.players.size() == 2, "a second gamepad's A joins player 2")
	check(g.state == Game.State.DRIVING, "back to playing after joining")
	var p1 := g.players[0]
	var p2 := g.players[1]
	check(p1.input.prefix == "p1_" and p1.input.pads == [0] and p1.input.keyboard, "player 1: pad 0 + keyboard (%s %s %s)" % [p1.input.prefix, p1.input.pads, p1.input.keyboard])
	check(p2.input.prefix == "p2_" and p2.input.pads == [1] and not p2.input.keyboard, "player 2: pad 1 only")

	# --- Views ------------------------------------------------------------------
	var views := g.split.views
	check(views.size() == 2 and Views.is_split(), "two views")
	check(tools.get_viewport().disable_3d, "the main viewport stops drawing the world")
	var in_view := func(p: LocalPlayer, v: SubViewport) -> bool:
		for n: Node in [p.camera, p.foot_camera, p.flight_camera, p.camera_blend, p.hud]:
			if n.get_parent() != v:
				return false
		return true
	check(in_view.call(p1, views[0]) and in_view.call(p2, views[1]), "each player's cameras and HUD are in their own view")
	check(views[0].get_camera_3d() == p1.view_camera() and views[1].get_camera_3d() == p2.view_camera(), "each view shows its player's camera")
	check(Views.cameras(g).size() == 2, "Views sees both cameras")
	check(views[0].audio_listener_enable_3d and views[1].audio_listener_enable_3d and not tools.get_viewport().audio_listener_enable_3d,
		"both views listen, the main viewport doesn't")
	var vs := views[0].size
	check(vs.y > 300 and vs.x > vs.y * 2.2, "views are wide strips (%s)" % vs)
	check(p1.camera.fov < 60.0 and p1.foot_camera.fov < 60.0, "split field of view keeps the sideways view (foot %.0f)" % p1.foot_camera.fov)
	check(p1.hud.compact and p2.hud.compact and p2.hud._chip_label.text == "P2", "compact HUDs with P1 / P2 chips")
	check(p1.foot_camera.cull_mask & Views.VIEW_LAYERS[0] and not (p1.foot_camera.cull_mask & Views.VIEW_LAYERS[1]), "player 1's cameras see view-1 things only")
	check(p2.foot_camera.cull_mask & Views.VIEW_LAYERS[1] and not (p2.foot_camera.cull_mask & Views.VIEW_LAYERS[0]), "player 2's cameras see view-2 things only")
	var grass := g.world.find_children("*", "GrassField", true, false)
	check(grass.size() == 2 and (grass[0] as GrassField).view != (grass[1] as GrassField).view, "grass around each player, one per view")
	check(p1._tag and p1._tag.visible and p1._tag.layers == Views.VIEW_LAYERS[1], "player 1's marker shows in player 2's view")
	check(p2._tag and p2._tag.visible and p2._tag.layers == Views.VIEW_LAYERS[0], "player 2's marker shows in player 1's view")
	check(p1.hud.minimap.friends.size() == 1 and p1.hud.minimap.friends[0]["node"] == p2.focus_node(), "player 1's map shows player 2")
	check(_engine_fades(p1.vehicle) and _engine_fades(p2.vehicle), "both players' car sounds fade with distance (two listeners)")

	# --- Player 2 arrives -------------------------------------------------------
	check(p2.possession.on_foot() and flat_dist(p2.character, p1.character) < 20.0, "player 2 starts on foot near player 1 (%.1f m)" % flat_dist(p2.character, p1.character))
	check(p2.vehicle != null and p2.vehicle != p1.vehicle and flat_dist(p2.vehicle, p2.character) < 8.0, "player 2's own car next to them")
	check(p2.vehicle.get_meta(Controllable.OWNER_META, -1) == 1 and p1.vehicle.get_meta(Controllable.OWNER_META, -1) == 0, "cars know their owners")
	var dressed := false
	for mi in p2.character.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).get_surface_override_material_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(s) as BaseMaterial3D
			if m and m.albedo_color == LocalPlayer.P2_SHIRT:
				dressed = true
	check(dressed, "player 2 wears the blue T-shirt")
	await wait_s(0.5)
	await shot("split_start")
	# Out to the open Dirt Fields for the controls tests (nothing to walk or
	# drive into).
	p1.teleport_to(4)
	await wait_s(0.5)
	p2.regroup(p1)
	await wait_s(0.8)
	var field: Transform3D = g.world.spawn_points[4]["xform"]
	for p in [p1, p2]:
		var at := field.origin + field.basis.x * (12.0 if p == p1 else 20.0) - field.basis.z * 6.0
		var hit := g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 40.0, 1))
		p.character.place(Transform3D(field.basis, hit["position"] if not hit.is_empty() else at))
		p.foot_camera.snap()
	await wait_s(0.5)

	# --- Each player's own controls --------------------------------------------
	var a1 := p1.character.global_position
	var a2 := p2.character.global_position
	axis(1, JOY_AXIS_LEFT_Y, -1.0)
	await wait_s(1.5)
	axis(1, JOY_AXIS_LEFT_Y, 0.0)
	await wait_s(0.3)
	var m1 := p1.character.global_position.distance_to(a1)
	var m2 := p2.character.global_position.distance_to(a2)
	check(m2 > 2.5 and m1 < 0.3, "player 2's stick walks player 2 only (%.1f m / %.1f m)" % [m2, m1])
	a1 = p1.character.global_position
	a2 = p2.character.global_position
	axis(0, JOY_AXIS_LEFT_Y, -1.0)
	await wait_s(1.5)
	axis(0, JOY_AXIS_LEFT_Y, 0.0)
	await wait_s(0.3)
	m1 = p1.character.global_position.distance_to(a1)
	m2 = p2.character.global_position.distance_to(a2)
	check(m1 > 2.5 and m2 < 0.3, "player 1's stick walks player 1 only (%.1f m / %.1f m)" % [m1, m2])
	a1 = p1.character.global_position
	a2 = p2.character.global_position
	key(KEY_W, true)
	await wait_s(1.0)
	key(KEY_W, false)
	await wait_s(0.3)
	m1 = p1.character.global_position.distance_to(a1)
	m2 = p2.character.global_position.distance_to(a2)
	check(m1 > 1.5 and m2 < 0.3, "the keyboard is player 1's (%.1f m / %.1f m)" % [m1, m2])
	var yaw2 := p2.foot_camera.yaw
	var yaw1 := p1.foot_camera.yaw
	axis(1, JOY_AXIS_RIGHT_X, 1.0)
	await wait_s(0.6)
	axis(1, JOY_AXIS_RIGHT_X, 0.0)
	check(absf(angle_difference(yaw2, p2.foot_camera.yaw)) > 0.5 and absf(angle_difference(yaw1, p1.foot_camera.yaw)) < 0.05,
		"player 2's right stick turns player 2's camera only")
	var wide1 := p1.foot_camera.wide
	await pad(1, JOY_BUTTON_RIGHT_SHOULDER)
	check(p2.foot_camera.wide and p1.foot_camera.wide == wide1, "player 2's camera button reaches player 2's camera only")
	await pad(1, JOY_BUTTON_RIGHT_SHOULDER)

	# --- Cars -----------------------------------------------------------------------
	var p1_entry := p1.vehicle.get_node("Entry") as VehicleEntry
	var p2_entry := p2.vehicle.get_node("Entry") as VehicleEntry
	check(p1_entry.prompt(p2.character) == "" and p2_entry.prompt(p1.character) == "", "neither player can take the other's car")
	check(p2_entry.prompt(p2.character) != "", "player 2 can get in their own car")
	p2._step_out_beside(p2.vehicle)
	await wait_s(0.4)
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p2.possession.driving() and p2.possession.vehicle == p2.vehicle, "player 2 gets in with B")
	check(p1.possession.on_foot(), "player 1 still on foot")
	check(p2.hud.vehicle == p2.vehicle and p1.hud.vehicle == p1.vehicle, "each HUD follows its own player's car")
	check(views[1].get_camera_3d() == p2.camera, "player 2's view shows their chase camera")
	var p1_car_at := p1.vehicle.global_position
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var sp := await top_speed(p2.vehicle, 3.0)
	await shot("split_p2_driving")
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await stop(p2, 1)
	check(sp > 15.0, "player 2's trigger drives their car (%.0f km/h)" % sp)
	check(p1.vehicle.global_position.distance_to(p1_car_at) < 0.5, "player 1's car stays put")
	# Player 1 drives too, at the same time.
	p1._step_out_beside(p1.vehicle)
	await wait_s(0.3)
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.driving() and p2.possession.driving(), "both players driving")
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var s1 := 0.0
	var s2 := 0.0
	var t := 0.0
	while t < 2.0:
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()
		s1 = maxf(s1, p1.vehicle.speed_kmh)
		s2 = maxf(s2, p2.vehicle.speed_kmh)
	await shot("split_both_driving")
	release_pads()
	await stop(p1, 0)
	await stop(p2, 1)
	check(s1 > 10.0 and s2 > 10.0, "both drive at once (%.0f / %.0f km/h)" % [s1, s2])
	check(not p1.controller.enabled or p1.controller.vehicle == p1.vehicle, "controllers stay on their own cars")

	# --- Places -----------------------------------------------------------------------
	var where1 := p1.vehicle.global_position
	await pad(1, JOY_BUTTON_DPAD_RIGHT)
	await wait_s(1.0)
	check(p2.vehicle.global_position.distance_to(where1) > 60.0 and p1.vehicle.global_position.distance_to(where1) < 2.0,
		"player 2's D-pad teleports player 2 only (%s)" % g.world.spawn_points[p2.spawn_index]["name"])
	await shot("split_apart")
	await pad(1, JOY_BUTTON_X)
	await wait_s(1.0)
	var d := p2.vehicle.global_position.distance_to(p1.vehicle.global_position)
	check(d < 25.0, "X takes player 2 back to player 1 (%.1f m)" % d)
	check(p1.vehicle.global_position.distance_to(where1) < 2.0, "player 1 stays where they were")
	await shot("split_regroup")
	# Big map in player 2's half.
	await pad(1, JOY_BUTTON_DPAD_LEFT)
	await wait(5)
	check(p2.hud.big_map.visible and not p1.hud.big_map.visible, "player 2's map opens in their half only")
	await shot("split_p2_map")
	await pad(1, JOY_BUTTON_DPAD_LEFT)

	# --- Garage for player 2 ---------------------------------------------------------
	await pad(1, JOY_BUTTON_DPAD_DOWN)
	await wait(10)
	check(g.state == Game.State.GARAGE and g._garage_player == p2, "player 2's D-pad down opens the garage for player 2")
	await shot("split_garage")
	var p1_car := p1.vehicle
	# Player 2's D-pad picks the pickup, A drives it.
	var steps := VehicleCatalog.index_of_id("pickup") - g.picker.index
	for i in steps:
		await pad(1, JOY_BUTTON_DPAD_RIGHT)
	await pad(1, JOY_BUTTON_A)
	await wait_s(1.0)
	check(not g.picker.is_open and g.state == Game.State.DRIVING, "player 2's A drives off from the garage")
	check(VehicleCatalog.id_of_vehicle(p2.vehicle) == "pickup" and p1.vehicle == p1_car, "player 2 gets the pickup, player 1 keeps theirs")
	check(Settings.get_value("vehicle_p2") == "pickup" and Settings.get_value("vehicle") != "pickup", "player 2's choice is remembered separately")
	check(p2.possession.driving() and p2.camera.target == p2.vehicle and p2.hud.vehicle == p2.vehicle, "player 2 drives the new car (camera, HUD)")

	# --- Planes side by side ----------------------------------------------------------
	var plane_i := VehicleCatalog.index_of_id("plane")
	p1.change_vehicle(plane_i)
	p2.change_vehicle(plane_i)
	await wait_s(1.5)
	var gap := p1.vehicle.global_position.distance_to(p2.vehicle.global_position)
	check(p1.vehicle is Aircraft and p2.vehicle is Aircraft and gap > 11.0 and gap < 20.0, "both planes on the runway, side by side (%.1f m apart)" % gap)
	await shot("split_planes")
	p1.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	p2.change_vehicle(VehicleCatalog.index_of_id("sedan"))
	p1.teleport_to(0)
	p2.regroup(p1)
	await wait_s(1.0)

	# --- Traffic around both ----------------------------------------------------------
	g.traffic.set_enabled(true)
	p2.teleport_to(1)  # the highway
	await wait_s(8.0)
	var near1 := 0
	var near2 := 0
	for drv in g.traffic.drivers:
		if not is_instance_valid(drv.vehicle):
			continue
		if drv.vehicle.global_position.distance_to(p1.vehicle.global_position) < 330.0:
			near1 += 1
		if drv.vehicle.global_position.distance_to(p2.vehicle.global_position) < 330.0:
			near2 += 1
	check(near1 > 2 and near2 > 2, "traffic around both players (%d / %d cars)" % [near1, near2])
	check(g.traffic.drivers.size() <= g.traffic.max_cars, "no more traffic than one player gets (%d <= %d)" % [g.traffic.drivers.size(), g.traffic.max_cars])
	check(g.traffic.vehicles.has(p2.vehicle), "traffic avoids player 2's car")
	await shot("split_traffic")
	# Far apart: player 1's cars move over to player 2 as player 2 needs them.
	p1.teleport_to(0)
	await wait_s(8.0)
	p2.teleport_to(6)  # the airfield, ~600 m away
	await wait_s(14.0)
	near1 = 0
	near2 = 0
	for drv in g.traffic.drivers:
		if not is_instance_valid(drv.vehicle):
			continue
		if drv.vehicle.global_position.distance_to(p1.focus_node().global_position) < 330.0:
			near1 += 1
		if drv.vehicle.global_position.distance_to(p2.focus_node().global_position) < 330.0:
			near2 += 1
	check(near1 >= 6 and near2 >= 4, "far apart, both still get traffic (%d / %d cars)" % [near1, near2])

	# --- Night ---------------------------------------------------------------------------
	Settings.set_value("time_of_day", 2)
	await wait_s(1.0)
	var lights2 := p2.vehicle.get_node_or_null("Headlights") as Node3D
	var lights1 := p1.vehicle.get_node_or_null("Headlights") as Node3D
	check(lights1 and lights1.visible and lights2 and lights2.visible, "both players' headlights at night")
	await shot("split_night")
	Settings.set_value("time_of_day", 0)
	await wait_s(0.5)

	# --- Pause, a controller unplugged ---------------------------------------------------
	await pad(1, JOY_BUTTON_START)
	await wait(5)
	check(g.state == Game.State.PAUSED and g.menu._player2_button.text == "PLAYER 2: LEAVE" and not g.menu._races_button.visible,
		"player 2's Start pauses; the menu offers PLAYER 2: LEAVE, no races")
	await shot("split_pause")
	g._enter_driving()
	await wait(5)
	g._on_joy_connection_changed(1, false)
	await wait(5)
	check(g.state == Game.State.PAUSED and g.menu._note.visible, "unplugging player 2's controller pauses (%s)" % g.menu._note.text)
	g._enter_driving()
	await wait(5)
	check(not g.start_replay(), "no instant replay with two players")

	# --- Leaving and joining again -------------------------------------------------------
	g._enter_pause()
	g._on_menu_action("remove_player")
	await wait(10)
	check(not g.is_split() and g.players.size() == 1 and g.split == null, "player 2 leaves")
	check(not tools.get_viewport().disable_3d and tools.get_viewport().audio_listener_enable_3d, "the main viewport draws and listens again")
	check(p1.camera.get_parent() == g and p1.hud.get_parent() == g and not p1.hud.compact, "player 1's cameras and HUD are back in the main view")
	check(p1.input.prefix == "" and not InputMap.has_action("p2_accelerate"), "player 1 back on the shared controls")
	check(g.world.find_children("*", "GrassField", true, false).size() == 1, "one grass field again")
	check(not _engine_fades(p1.vehicle), "player 1's car sound is unattenuated again")
	check(g.get_node_or_null("Character2") == null and g.get_node_or_null("PlayerCar2") == null, "player 2's character and car are gone")
	var stale := g.traffic.vehicles.filter(func(v: Vehicle) -> bool: return not is_instance_valid(v) or v.is_queued_for_deletion())
	check(stale.is_empty(), "traffic forgot player 2's car")
	check(Views.cameras(g).size() == 1 and g.camera.fov > 60.0, "one camera, normal field of view")
	await shot("split_left")
	# Keyboard player 2 this time (player 1 on pad 0).
	await join(0, -1)
	check(g.is_split(), "joins again")
	p1 = g.players[0]
	p2 = g.players[1]
	check(p2.input.keyboard and not p1.input.keyboard and p1.input.pads == [0], "Enter makes the keyboard player 2's")
	p2.possession.settle()
	p1.possession.settle()
	a1 = p1.focus_node().global_position
	a2 = p2.character.global_position
	key(KEY_W, true)
	await wait_s(1.0)
	key(KEY_W, false)
	await wait_s(0.3)
	m1 = p1.focus_node().global_position.distance_to(a1)
	m2 = p2.character.global_position.distance_to(a2)
	check(m2 > 1.5 and m1 < 0.5, "W walks keyboard player 2 (%.1f m / %.1f m)" % [m2, m1])
	# The main menu ends split-screen.
	g._on_menu_action("title")
	await wait(10)
	check(not g.is_split() and g.state == Game.State.TITLE, "MAIN MENU: back to one player")
	await shot("split_title")
	g._enter_driving()
	g.traffic.set_enabled(false)
	await wait_s(1.0)
	var kids_after := g.get_children().map(func(n: Node) -> String: return String(n.name))
	var extra := kids_after.filter(func(n: String) -> bool: return not kids_before.has(n))
	check(extra.is_empty(), "nothing of player 2's left in the game (%s)" % ", ".join(extra))
	check(root.find_children("*", "SubViewport", true, false).size() == views_before, "no split views left")
	check(InputMap.get_actions().size() == actions_before, "no player actions left behind")
	print("SPLIT: %d checks, %d failed" % [checks, fails])


# =========================================================================
# --splitbench
# =========================================================================

## [name, player 1's camera (position, look at), player 2's camera]
func _scenarios() -> Array:
	var hw: PackedVector3Array = game.world.roads.highway.points
	var hp := hw[hw.size() / 3]
	var hn := hw[hw.size() / 3 + 2]
	var beach: Transform3D = game.world.spawn_points[5]["xform"]
	var bf := -beach.basis.z
	return [
		# The city centre teleport (ART_BIBLE §27's heaviest view, on foot): one
		# player looking east down the street, the other west.
		["centre", [Vector3(-113.6, 2.1, 3.0), Vector3(-80.0, 1.5, 3.0)], [Vector3(-106.4, 2.1, 3.0), Vector3(-140.0, 1.5, 3.0)]],
		["city_city", [Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0)], [Vector3(2.4, 2.4, -30.0), Vector3(2.4, 1.4, -62.0)]],
		["city_highway", [Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0)], [hp + Vector3.UP * 2.6 - (hn - hp).normalized() * 7.0, hn + Vector3.UP * 1.2]],
		["country", [Vector3(6.0, 3.5, -280.0), Vector3(25.0, 6.0, -322.0)], [beach.origin - bf * 7.5 + Vector3.UP * 2.6, beach.origin + bf * 25.0 + Vector3.UP]],
		["fly_city", [Vector3(95.0, 70.0, 15.0), Vector3(-10.0, 0.0, -110.0)], [Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0)]],
	]


func _cams_off() -> void:
	for p in game.players:
		for c: Camera3D in [p.camera, p.foot_camera, p.flight_camera, p.camera_blend]:
			c.set_process(false)


func _aim(p: LocalPlayer, at: Array) -> void:
	var cam := p.view_camera()
	cam.global_position = at[0]
	cam.look_at(at[1], Vector3.UP)


## Parks player `p`'s car on the ground under where its camera looks (so
## traffic gathers there as it would in play).
func _park(p: LocalPlayer, at: Array) -> void:
	var look: Vector3 = at[1]
	var from: Vector3 = at[0]
	var spot := from.lerp(look, 0.35)
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 60.0, spot + Vector3.DOWN * 120.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var f := look - from
	f.y = 0.0
	var xf := Transform3D(Basis.looking_at(f.normalized() if f.length() > 0.1 else Vector3.FORWARD, Vector3.UP),
		(hit["position"] as Vector3) + Vector3.UP * (p.vehicle.ride_height() + 0.2))
	p.vehicle.teleport(xf)


## Averages over `frames`: [gpu ms (all viewports), frame ms, draw calls, primitives].
func _measure(frames: int) -> Array:
	var rids: Array[RID] = [tools.get_viewport().get_viewport_rid()]
	if game.split:
		for v in game.split.views:
			rids.append(v.get_viewport_rid())
	for r in rids:
		RenderingServer.viewport_set_measure_render_time(r, true)
	await wait(8)
	var gpu := 0.0
	var cpu := 0.0
	var main := 0.0
	var calls := 0
	var prims := 0
	var frame_times: Array[float] = []
	var last := Time.get_ticks_usec()
	for k in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		last = now
		for r in rids:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(r)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(r)
		cpu += RenderingServer.get_frame_setup_time_cpu()
		main += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	frame_times.sort()
	var ft := 0.0
	for t in frame_times:
		ft += t
	return [gpu / frames, ft / frames, calls / frames, prims / frames, frame_times[int(frames * 0.95)], cpu / frames, main / frames]


func _report(line: String) -> void:
	print(line)
	_lines.append(line)


func bench() -> void:
	var g := game
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	g.traffic.set_enabled(true)
	var levels := [GraphicsQuality.LOW, GraphicsQuality.MEDIUM, GraphicsQuality.HIGH]
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			levels.clear()
			for l in arg.split("=")[1].split(","):
				levels.append(int(l))
		if arg.begins_with("--views="):
			only = arg.split("=")[1].split(",")
	if OS.get_cmdline_user_args().has("--no-trims"):
		GraphicsQuality.split_trims = false
	var size := tools.get_viewport().get_visible_rect().size
	_report("SPLITBENCH window %dx%d, GPU: %s" % [size.x, size.y, RenderingServer.get_video_adapter_name()])
	var scen := _scenarios()
	var results := {}
	for split in [false, true]:
		if split and not g.is_split():
			await join(-1, 1)
			g.players[1].ensure_driving()
		g.ensure_driving()
		for level: int in levels:
			Settings.set_value("graphics", level)
			for s: Array in scen:
				if not only.is_empty() and not only.has(s[0]):
					continue
				for p in g.players:
					p.set_process(true)
				_park(g.players[0], s[1])
				if split:
					_park(g.players[1], s[2])
				await wait_s(5.0)  # traffic fills in, trees and LODs settle
				_cams_off()
				_aim(g.players[0], s[1])
				if split:
					_aim(g.players[1], s[2])
				var st: Array = await _measure(90)
				results["%s/%d/%s" % [s[0], level, split]] = st
				_report("SPLITBENCH %-13s %-6s %-6s gpu %6.2f ms  render cpu %5.2f ms  frame %6.2f ms (p95 %6.2f)  %5d calls %8d prims" % [
					s[0], ["low", "medium", "high", "ultra"][level], "split" if split else "single", st[0], st[5], st[1], st[4], st[2], st[3]])
				if level == GraphicsQuality.MEDIUM:
					await shot("bench_%s_%s" % [s[0], "split" if split else "single"])
				for p in g.players:
					for c: Camera3D in [p.camera, p.foot_camera, p.flight_camera]:
						c.set_process(true)
			# A drive: player 1 up the avenue, player 2 along the highway.
			var st2: Array = await _drive(split)
			results["drive/%d/%s" % [level, split]] = st2
			_report("SPLITBENCH %-13s %-6s %-6s gpu %6.2f ms  render cpu %5.2f ms  frame %6.2f ms (p95 %6.2f)  %5d calls" % [
				"drive", ["low", "medium", "high", "ultra"][level], "split" if split else "single", st2[0], st2[5], st2[1], st2[4], st2[2]])
	# Summary: split vs single, and a Steam Deck estimate (iGPU / 1.6).
	_report("")
	_report("SUMMARY (GPU ms, iGPU; Deck estimate = iGPU / 1.6; fps = 1000 / Deck ms)")
	_report("  render CPU = culling and draw calls per frame on this CPU (a Deck's Zen 2 is roughly")
	_report("  2-2.5x slower per thread); scripts and physics cost the same with one or two players.")
	for level: int in levels:
		for name in ["centre", "city_city", "city_highway", "country", "fly_city", "drive"]:
			var a: Variant = results.get("%s/%d/false" % [name, level])
			var b: Variant = results.get("%s/%d/true" % [name, level])
			if a == null or b == null:
				continue
			var deck_single: float = a[0] / 1.6
			var deck_split: float = b[0] / 1.6
			var cpu_a: float = a[5] if a.size() > 5 else 0.0
			var cpu_b: float = b[5] if b.size() > 5 else 0.0
			_report("  %-6s %-13s single %6.2f  split %6.2f  (x%.2f)   Deck GPU ~%5.1f ms (%3.0f fps) -> ~%5.1f ms (%3.0f fps)   render CPU %4.1f -> %4.1f ms" % [
				["low", "medium", "high", "ultra"][level], name, a[0], b[0], b[0] / maxf(a[0], 0.01),
				deck_single, 1000.0 / maxf(deck_single, 1.0), deck_split, 1000.0 / maxf(deck_split, 1.0), cpu_a, cpu_b])
	var f := FileAccess.open(dir.path_join("splitbench.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
	Settings.set_value("graphics", GraphicsQuality.HIGH)


## Cameras glide along roads, 0.5 m a frame for 400 frames (their cars ride
## along, so traffic and LODs move with them). [gpu, frame, calls, prims, p95 frame]
func _drive(split: bool) -> Array:
	var g := game
	_cams_off()
	var hw: PackedVector3Array = g.world.roads.highway.points
	var cum := PackedFloat32Array([0.0])
	for i in range(1, hw.size()):
		cum.append(cum[i - 1] + hw[i].distance_to(hw[i - 1]))
	var hw_at := func(dist: float) -> Vector3:
		var dd := fposmod(dist, cum[cum.size() - 1])
		for i in range(1, hw.size()):
			if cum[i] >= dd:
				return hw[i - 1].lerp(hw[i], (dd - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001))
		return hw[0]
	var c1 := g.players[0].view_camera()
	var car1 := g.players[0].vehicle
	car1.freeze = true
	var c2: Camera3D = g.players[1].view_camera() if split else null
	var car2: Vehicle = g.players[1].vehicle if split else null
	if car2:
		car2.freeze = true
	var start2 := cum[cum.size() - 1] * 0.3
	var place := func(k: int) -> void:
		var z := -20.0 - k * 0.5
		c1.global_position = Vector3(2.4, 2.4, z)
		c1.look_at(Vector3(2.4, 1.6, z - 40.0), Vector3.UP)
		car1.global_transform = Transform3D(Basis.IDENTITY, Vector3(2.4, 0.6, z - 8.0))
		if c2:
			var p: Vector3 = hw_at.call(start2 + k * 0.5)
			var ahead: Vector3 = hw_at.call(start2 + k * 0.5 + 30.0)
			var behind: Vector3 = hw_at.call(start2 + k * 0.5 - 8.0)
			c2.global_position = behind + Vector3.UP * 2.6
			c2.look_at(ahead + Vector3.UP * 1.0, Vector3.UP)
			car2.global_transform = Transform3D(Basis.looking_at((ahead - p).normalized(), Vector3.UP), p + Vector3.UP * 0.7)
	place.call(0)
	await wait_s(4.0)
	var rids: Array[RID] = [tools.get_viewport().get_viewport_rid()]
	if g.split:
		for v in g.split.views:
			rids.append(v.get_viewport_rid())
	var gpu := 0.0
	var cpu := 0.0
	var main := 0.0
	var calls := 0
	var frame_times: Array[float] = []
	var last := Time.get_ticks_usec()
	var n := 400
	for k in n:
		place.call(k)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		last = now
		for r in rids:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(r)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(r)
		cpu += RenderingServer.get_frame_setup_time_cpu()
		main += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	car1.freeze = false
	if car2:
		car2.freeze = false
	for p in g.players:
		for c: Camera3D in [p.camera, p.foot_camera, p.flight_camera]:
			c.set_process(true)
	frame_times.sort()
	var ft := 0.0
	for t in frame_times:
		ft += t
	return [gpu / n, ft / n, calls / n, 0, frame_times[int(n * 0.95)], cpu / n, main / n]
