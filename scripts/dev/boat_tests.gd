extends RefCounted
## The --boat=<dir> dev test (run from DevTools): the speedboat driven
## through the player's own controls (Input actions, like a gamepad), with
## pass/fail checks and screenshots:
##   the marked boat spots and the marina are deep enough, picking it in the
##   garage (it goes on the water), floating level at rest, speeding up onto
##   the plane, top speed, turns that lean in, a power slide, coasting to a
##   stop, backing up, the help button, righting itself upside down, running
##   up a beach and back, teleports, the island's edge, getting out at sea
##   (refused) and at the marina, the parked boats, fuel at the marina, a
##   car picked out at sea, split-screen riding along, and the cost.

const ACTIONS := ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "reset_vehicle"]

var tools: Node
var game: Game
var dir := ""
var fails := 0
var checks := 0


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


func tick() -> void:
	await tools.get_tree().physics_frame


func dt() -> float:
	return tools.get_physics_process_delta_time()


func _axis(action: String, v: float) -> void:
	if v > 0.001:
		Input.action_press(action, minf(v, 0.98))
	else:
		Input.action_release(action)


## Throttle 0..1, brake 0..1, steer -1..1 (+ = right), slide.
func pad(gas: float, brake: float, steer: float, slide := false) -> void:
	_axis("accelerate", gas)
	_axis("brake", brake)
	_axis("steer_right", maxf(steer, 0.0))
	_axis("steer_left", maxf(-steer, 0.0))
	if slide:
		Input.action_press("handbrake")
	else:
		Input.action_release("handbrake")


func release() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func boat() -> Boat:
	return game.vehicle as Boat


func heading_of(b: Boat) -> float:
	var f := -b.global_basis.z
	return atan2(-f.x, -f.z)


func pitch_deg(b: Boat) -> float:
	return rad_to_deg(asin(clampf((-b.global_basis.z).y, -1.0, 1.0)))


func telemetry(label: String, b: Boat) -> void:
	print("  %s: %.0f km/h  fwd %.1f  y %+.2f  pitch %+.1f  bank %+.1f  wet %.2f  rpm %.0f  bite %.2f  gear %d  pos (%.0f, %.0f)" % [
		label, b.speed_kmh, b.forward_speed, b.global_position.y - MapLayout.SEA_LEVEL, pitch_deg(b), rad_to_deg(b.bank),
		b.wet, b.engine_rpm, b.prop_bite, b.gear, b.global_position.x, b.global_position.z])


func drive(seconds: float, gas: float, brake: float, steer: float, slide := false, label := "", every := 1.0) -> void:
	var t := 0.0
	var next := 0.0
	pad(gas, brake, steer, slide)
	while t < seconds:
		await tick()
		t += dt()
		if label != "" and t >= next:
			next += every
			telemetry("%s t=%.1f" % [label, t], boat())


## Puts the boat on open water off the south coast, heading west (away from
## the jump ramp), stopped.
func reposition(b: Boat, at := Vector3(0.0, 0.0, 680.0), dir3 := Vector3.LEFT) -> void:
	release()
	b.teleport(Transform3D(Basis.looking_at(dir3, Vector3.UP), Vector3(at.x, MapLayout.SEA_LEVEL + 0.05, at.z)))
	game.snap_camera()
	await drive(2.5, 0.0, 0.0, 0.0)


func run() -> void:
	Settings.set_value("assists", true)
	Settings.set_value("fuel", true)
	game.teleport_to(0)
	await tools._wait(30)
	if game.possession.driving():
		game.possession.exit()
		await tools._wait(240)
	await _spots()
	await _garage()
	var b := boat()
	if b == null:
		print("BOAT: %d checks, %d failed" % [checks, fails])
		return
	await _float(b)
	await _speed(b)
	await _turns(b)
	await _slide(b)
	await _stop_and_reverse(b)
	await _help(b)
	await _beach(b)
	await _ramp(b)
	await _teleports(b)
	await _edge(b)
	await _no_exit_at_sea(b)
	await _marina(b)
	b = boat()
	await _fuel(b)
	await _car_at_sea(b)
	await _crash(boat())
	await _ride_along(boat())
	await _night(boat())
	release()
	print("BOAT: %d checks, %d failed" % [checks, fails])


# --- The water ----------------------------------------------------------------

func _spots() -> void:
	print("-- boat spots and the marina")
	var space := game.get_world_3d().direct_space_state
	for s: Vector4 in MapLayout.BOAT_SPOTS:
		var d := Boat.water_depth(space, Vector3(s.x, 0.0, s.y))
		check(d >= Boat.SPOT_DEPTH, "boat spot (%.0f, %.0f): %.1f m deep" % [s.x, s.y, d])
	for berth: Vector2 in MapLayout.MARINA_BERTHS:
		var d := Boat.water_depth(space, Vector3(berth.x, 0.0, berth.y))
		check(d >= 1.6, "marina berth (%.0f, %.0f): %.1f m deep" % [berth.x, berth.y, d])
	var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(MapLayout.MARINA_X, 5.0, -228.0), Vector3(MapLayout.MARINA_X, -5.0, -228.0), 1))
	check(not deck.is_empty() and absf((deck["position"] as Vector3).y - MapLayout.MARINA_DECK) < 0.05, "the pontoon's deck is just above the water")
	var parked := 0
	for n in game.world.find_children("*", "Prop", true, false):
		if (n as Prop).drive_scene.ends_with("boat.tscn"):
			parked += 1
	check(parked == MapLayout.MARINA_BERTHS.size(), "%d speedboats tied up in the marina" % parked)


func _garage() -> void:
	print("-- the garage (on foot in the city)")
	var index := VehicleCatalog.index_of_id("boat")
	check(index >= 0, "the speedboat is in the garage's list")
	game.change_vehicle(index)
	await tools._wait(5)
	var b := boat()
	check(b != null, "the garage's boat is the player's vehicle")
	if b == null:
		return
	check(game.possession.driving() and game.possession.kind_of(b) == Controllable.VEHICLE and game.controller.vehicle == b,
		"sitting in it, with the car's controls")
	await drive(2.0, 0.0, 0.0, 0.0)
	var space := game.get_world_3d().direct_space_state
	var d := Boat.water_depth(space, b.global_position)
	print("  placed at (%.0f, %.1f, %.0f), %.1f m deep" % [b.global_position.x, b.global_position.y, b.global_position.z, d])
	check(b.floating() and d >= 1.0, "it's on the water")
	check(game.camera.current and game.camera.target == b, "the chase camera follows it")
	check(not game.hud.flying, "the HUD in driving mode")
	await shot("01_garage_on_the_water")
	check(not VehicleCatalog.is_special(VehicleCatalog.index_of_id("sedan")) and VehicleCatalog.is_special(index), "the boat isn't remembered as the start vehicle")


func _float(b: Boat) -> void:
	print("-- floating")
	await reposition(b)
	await drive(3.0, 0.0, 0.0, 0.0)
	telemetry("at rest", b)
	var y := b.global_position.y - MapLayout.SEA_LEVEL
	check(absf(y) < 0.1, "floats on its water line (%+.2f m)" % y)
	check(absf(pitch_deg(b)) < 2.5 and absf(rad_to_deg(b.bank)) < 2.0, "level (pitch %.1f, roll %.1f)" % [pitch_deg(b), rad_to_deg(b.bank)])
	check(b.linear_velocity.length() < 0.2, "lying still (%.2f m/s)" % b.linear_velocity.length())
	await shot("02_floating")


func _speed(b: Boat) -> void:
	print("-- full throttle")
	var t := 0.0
	var t50 := -1.0
	var max_pitch := -99.0
	var min_wet := 9.0
	pad(1.0, 0.0, 0.0)
	while t < 16.0:
		await tick()
		t += dt()
		if t50 < 0.0 and b.speed_kmh >= 50.0:
			t50 = t
		max_pitch = maxf(max_pitch, pitch_deg(b))
		if t > 8.0:
			min_wet = minf(min_wet, b.wet)
		if fmod(t, 2.0) < dt():
			telemetry("gas t=%.0f" % t, b)
		if absf(t - 4.0) < dt() * 0.5:
			await shot("03_onto_the_plane")
	telemetry("flat out", b)
	check(t50 > 2.0 and t50 < 7.0, "0-50 km/h in %.1f s" % t50)
	check(b.speed_kmh > 68.0 and b.speed_kmh < 95.0, "top speed %.0f km/h" % b.speed_kmh)
	check(max_pitch > 3.0 and max_pitch < 14.0, "bow up on the way onto the plane (%.1f deg)" % max_pitch)
	check(pitch_deg(b) > -1.0 and pitch_deg(b) < 7.0, "planing trim %.1f deg" % pitch_deg(b))
	check(min_wet < 0.85, "planing: less of the hull in the water (%.2f)" % min_wet)
	check(b.engine_rpm > b.redline_rpm * 0.75, "engine near the top (%.0f rpm)" % b.engine_rpm)
	await shot("04_flat_out")


func _turns(b: Boat) -> void:
	print("-- turns")
	await reposition(b)
	await drive(6.0, 1.0, 0.0, 0.0)
	var h0 := heading_of(b)
	var max_bank := 0.0
	var t := 0.0
	pad(1.0, 0.0, 1.0)
	while t < 3.0:
		await tick()
		t += dt()
		max_bank = maxf(max_bank, rad_to_deg(b.bank))
		if absf(t - 1.5) < dt() * 0.5:
			await shot("05_turning_right")
	telemetry("right turn", b)
	var turned := rad_to_deg(wrapf(h0 - heading_of(b), -PI, PI))
	check(turned > 70.0, "full right at speed turns right (%.0f deg in 3 s)" % turned)
	check(max_bank > 4.0 and max_bank < 25.0, "leans into the turn (%.1f deg)" % max_bank)
	check(b.speed_kmh > 35.0, "keeps going (%.0f km/h)" % b.speed_kmh)
	await drive(2.0, 1.0, 0.0, 0.0)
	h0 = heading_of(b)
	var min_bank := 0.0
	t = 0.0
	pad(1.0, 0.0, -1.0)
	while t < 3.0:
		await tick()
		t += dt()
		min_bank = minf(min_bank, rad_to_deg(b.bank))
	turned = rad_to_deg(wrapf(heading_of(b) - h0, -PI, PI))
	check(turned > 70.0 and min_bank < -4.0, "left too (%.0f deg, leaning %.1f)" % [turned, min_bank])
	await drive(2.0, 1.0, 0.0, 0.0)
	check(absf(rad_to_deg(b.bank)) < 3.0, "levels out when straight (%.1f)" % rad_to_deg(b.bank))


func _slide(b: Boat) -> void:
	print("-- power slide")
	await reposition(b)
	await drive(5.0, 1.0, 0.0, 0.0)
	var h0 := heading_of(b)
	var t := 0.0
	var max_slip := 0.0
	pad(1.0, 0.0, 1.0, true)
	while t < 2.5:
		await tick()
		t += dt()
		var v := b.linear_velocity
		var side := absf(v.dot(b.global_basis.x))
		max_slip = maxf(max_slip, side)
		if absf(t - 1.2) < dt() * 0.5:
			await shot("06_slide")
	var turned := rad_to_deg(wrapf(h0 - heading_of(b), -PI, PI))
	telemetry("slide", b)
	check(max_slip > 4.0, "slides sideways (%.1f m/s across)" % max_slip)
	check(turned > 80.0, "spins round quicker (%.0f deg in 2.5 s)" % turned)
	check(b.global_basis.y.y > 0.85, "stays upright")
	await drive(2.0, 0.0, 0.0, 0.0)


func _stop_and_reverse(b: Boat) -> void:
	print("-- coasting, stopping, backing up")
	await reposition(b)
	await drive(6.0, 1.0, 0.0, 0.0)
	var v0 := b.speed_kmh
	await drive(4.0, 0.0, 0.0, 0.0, false, "coast", 2.0)
	check(b.speed_kmh < v0 * 0.55, "the water slows it (%.0f -> %.0f km/h in 4 s)" % [v0, b.speed_kmh])
	var t := 0.0
	pad(0.0, 1.0, 0.0)
	while t < 8.0 and b.forward_speed > 0.3:
		await tick()
		t += dt()
	check(t < 8.0, "the brake (reverse thrust) stops it (%.1f s)" % t)
	await drive(5.0, 0.0, 1.0, 0.0, false, "reverse", 2.5)
	check(b.gear == -1 and b.forward_speed < -1.5, "backs up (%.1f m/s)" % b.forward_speed)
	check(b.forward_speed > -b.max_reverse_speed - 0.5, "slowly")
	await drive(2.0, 0.0, 0.0, 0.0)


func _help(b: Boat) -> void:
	print("-- help button and capsizing")
	await reposition(b)
	# Knocked on its side: Y puts it upright where it floats.
	b.global_transform = Transform3D(Basis(Vector3.FORWARD, 1.3) * b.global_basis, b.global_position)
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	await tick()
	var before := b.global_basis.y.y
	await tools._tap("reset_vehicle")
	check(before < 0.5 and b.global_basis.y.y > 0.98, "the help button sets it upright where it floats (up %.2f -> %.2f)" % [before, b.global_basis.y.y])
	await drive(2.0, 0.0, 0.0, 0.0)
	check(b.floating() and absf(b.global_position.y - MapLayout.SEA_LEVEL) < 0.12, "floating again")
	# Upside down: it rights itself after a moment.
	b.teleport(Transform3D(Basis(Vector3.FORWARD, PI) * b.global_basis, b.global_position + Vector3.UP * 0.6))
	await drive(1.0, 0.0, 0.0, 0.0)
	check(b.global_basis.y.y < 0.0, "capsized")
	await drive(0.6, 0.0, 0.0, 0.0)
	check(game.hud._hint.visible and game.hud._hint.text.begins_with("Upside down"), "the HUD says how to flip it ('%s')" % game.hud._hint.text)
	await drive(2.5, 0.0, 0.0, 0.0)
	check(b.global_basis.y.y > 0.95, "rights itself (assists on)")


func _beach(b: Boat) -> void:
	print("-- running up the beach")
	await reposition(b, Vector3(-470.0, 0.0, 34.0), Vector3.RIGHT)
	var t := 0.0
	pad(1.0, 0.0, 0.0)
	while t < 12.0 and b.floating():
		await tick()
		t += dt()
	var shore := b.global_position
	var speed := b.speed_kmh
	release()
	t = 0.0
	while t < 8.0 and b.stuck_time <= Boat.STRANDED_TIME + 0.2:
		await tick()
		t += dt()
	await tools._wait(3)
	telemetry("beached", b)
	var slid := Vector2(b.global_position.x - shore.x, b.global_position.z - shore.z).length()
	print("  left the water at %.0f km/h, slid %.1f m up the beach" % [speed, slid])
	var space := game.get_world_3d().direct_space_state
	check(not b.floating(), "ran aground on the beach")
	check(slid < 18.0, "the sand stops it a boat length or two up the beach (%.1f m)" % slid)
	check(b.global_basis.y.y > 0.8, "still upright")
	check(b.stuck_time > Boat.STRANDED_TIME and game.hud._hint.visible and game.hud._hint.text.begins_with("Stuck on land"),
		"the HUD says how to get back in ('%s')" % game.hud._hint.text)
	await shot("07_beached")
	await tools._tap("reset_vehicle")
	await drive(2.0, 0.0, 0.0, 0.0)
	var d := Boat.water_depth(space, b.global_position)
	check(b.floating() and d >= 1.0, "the help button puts it back in open water (%.1f m deep)" % d)
	check(not game.hud._hint.visible, "the hint goes away")


func _ramp(b: Boat) -> void:
	print("-- a jump ramp")
	var r: Vector4 = MapLayout.BOAT_RAMPS[2]
	var face := Vector3(r.z, 0.0, r.w).normalized()
	var lip := Vector3(r.x, 0.0, r.y)
	await reposition(b, lip - face * 90.0, face)
	var t := 0.0
	var max_air := 0.0
	var top := -99.0
	# (Lambdas copy the locals they use: an array is shared.)
	var landed := [0.0]
	var landed_cb := func(air: float) -> void: landed[0] = air
	b.landed.connect(landed_cb)
	var hits := []
	var hit_cb := func(strength: float, pos: Vector3, _n: Vector3) -> void: hits.append([strength, b.global_transform.affine_inverse() * pos, b.speed_kmh])
	b.impact.connect(hit_cb)
	pad(1.0, 0.0, 0.0)
	while t < 10.0:
		await tick()
		t += dt()
		max_air = maxf(max_air, b.airtime)
		top = maxf(top, b.global_position.y - MapLayout.SEA_LEVEL)
		if b.airtime > 0.3 and absf(b.airtime - 0.45) < dt() * 0.6:
			await shot("14_ramp_jump")
		if landed[0] > 0.0 and t > 1.0:
			break
	await drive(1.5, 0.6, 0.0, 0.0)
	b.landed.disconnect(landed_cb)
	b.impact.disconnect(hit_cb)
	for h: Array in hits:
		print("  impact %.0f N s at %s (%.0f km/h)" % [h[0], h[1], h[2]])
	telemetry("after the jump", b)
	print("  air %.2f s, up to %.1f m over the water" % [max_air, top])
	check(max_air > 0.6, "flies off the ramp (%.2f s in the air)" % max_air)
	check(top > 2.5, "high over the water (%.1f m)" % top)
	check(landed[0] > 0.5, "lands back on the water (a splash, %.2f s of air)" % landed[0])
	check(b.floating() and b.global_basis.y.y > 0.9, "upright and floating after the landing")
	check(game.stunts.enabled, "stunt scoring is on for boats")
	var dmg := b.get_node("Damage") as VehicleDamage
	check(dmg.total_damage == 0.0, "a clean jump does no damage (%.0f%%)" % dmg.total_damage)
	check(game._crash_wait < 0.0 and game.state == Game.State.DRIVING, "and no crash replay")
	# The jump again, as an instant replay.
	check(game.start_replay(), "P plays the replay")
	check(game.state == Game.State.REPLAY, "replaying")
	await tools._wait(90)
	await shot("14b_replay")
	game.replay.stop()
	await tools._wait(5)
	check(game.state == Game.State.DRIVING and game.camera.current and game.possession.driving(), "back at the helm after the replay")
	await drive(2.0, 0.0, 0.0, 0.0)
	check(b.floating() and absf(b.global_position.y - MapLayout.SEA_LEVEL) < 0.3, "still floating after the replay")


func _teleports(b: Boat) -> void:
	print("-- teleports")
	for want: String in ["Stunt Park", "Harbour", "Lighthouse"]:
		var i := -1
		for k in game.world.spawn_points.size():
			if game.world.spawn_points[k]["name"] == want:
				i = k
		if i < 0:
			check(false, "a teleport called %s" % want)
			continue
		game.teleport_to(i)
		await drive(1.5, 0.0, 0.0, 0.0)
		var place := (game.world.spawn_points[i]["xform"] as Transform3D).origin
		var spot := Boat.nearest_boat_spot(b, place)
		print("  %s: boat at (%.0f, %.0f), place (%.0f, %.0f)" % [want, b.global_position.x, b.global_position.z, place.x, place.z])
		check(game.possession.driving() and b.floating() and game.vehicle == b, "%s: still in the boat, on the water" % want)
		var near := false
		for s: Vector4 in MapLayout.BOAT_SPOTS:
			if Vector2(s.x, s.y).distance_to(Vector2(b.global_position.x, b.global_position.z)) < 20.0:
				near = true
		check(near and not spot.is_empty(), "%s: at the boat spot nearest the place" % want)
		check(game.p1._lost_timer == 0.0, "%s: not 'lost at sea'" % want)
	await shot("08_teleport_lighthouse")


func _edge(b: Boat) -> void:
	print("-- the island's edge")
	b.teleport(Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(0.0, MapLayout.SEA_LEVEL + 0.05, 880.0)))
	game.snap_camera()
	var t := 0.0
	var turned := false
	pad(1.0, 0.0, 0.0)
	while t < 25.0:
		await tick()
		t += dt()
		if b.turning_back:
			turned = true
		var out := Vector2(b.global_position.x, b.global_position.z)
		var nose := -b.global_basis.z
		if turned and Vector2(nose.x, nose.z).dot(-out.normalized()) > 0.8:
			break
	var r := Vector2(b.global_position.x, b.global_position.z).length()
	telemetry("edge", b)
	check(turned and game.hud.turning_back, "far out, it turns back toward the island (HUD says so)")
	check(r < 1000.0 and r > 850.0, "and doesn't go much further out (%.0f m from the middle)" % r)
	var nose := -b.global_basis.z
	check(Vector2(nose.x, nose.z).dot(-Vector2(b.global_position.x, b.global_position.z).normalized()) > 0.8, "now pointing home")
	release()


func _no_exit_at_sea(b: Boat) -> void:
	print("-- getting out at sea")
	await reposition(b)
	game.possession.exit()
	await drive(1.0, 0.0, 0.0, 0.0)
	check(game.possession.driving() and game.vehicle == b, "can't get out at sea")
	check(game.hud._toast.visible and game.hud._toast.text.contains("pier"), "the toast says where to go ('%s')" % game.hud._toast.text)


func _marina(b: Boat) -> void:
	print("-- the marina")
	var pos := game.possession
	# Alongside the middle finger, bow out to sea.
	var fz: float = MapLayout.MARINA_FINGERS[1]
	var at := Vector3(-428.6, MapLayout.SEA_LEVEL + 0.05, fz - MapLayout.MARINA_FINGER_WIDTH * 0.5 - 0.45 - b.body_half_width)
	await reposition(b, at, Vector3.LEFT)
	await shot("09_marina_alongside")
	check(pos.exit(), "F gets out at the marina")
	var t := 0.0
	while t < 5.0 and not pos.on_foot():
		await tick()
		t += dt()
	check(pos.on_foot(), "on foot")
	var c := game.character
	var feet := c.global_position
	print("  stood at (%.1f, %.2f, %.1f)" % [feet.x, feet.y, feet.z])
	check(absf(feet.y - MapLayout.MARINA_DECK) < 0.15, "standing on the pontoon (%.2f)" % feet.y)
	check(feet.distance_to(b.global_position) < 5.0, "beside the boat (%.1f m)" % feet.distance_to(b.global_position))
	await drive(3.0, 0.0, 0.0, 0.0)
	check(absf(c.global_position.y - MapLayout.MARINA_DECK) < 0.15 and game.p1._lost_timer == 0.0, "still on the pontoon, dry")
	var drift := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
	check(drift < 1.0, "the boat stays moored (moved %.2f m)" % drift)
	await shot("10_on_the_pontoon")
	var entry := b.get_node("Entry") as VehicleEntry
	check(entry.prompt(c) == "Get in the speedboat", "prompt: '%s'" % entry.prompt(c))
	check(pos.enter(b), "gets back in")
	t = 0.0
	while t < 4.0 and (not pos.driving() or game.camera_blend.blending):
		await tick()
		t += dt()
	check(pos.driving() and game.vehicle == b, "back at the helm")
	# Over to a parked one: out, walk to the second berth's boat.
	pos.exit()
	t = 0.0
	while t < 5.0 and not pos.on_foot():
		await tick()
		t += dt()
	var berth: Vector2 = MapLayout.MARINA_BERTHS[1]
	var finger: float = MapLayout.MARINA_FINGERS[2]
	c.place(Transform3D(Basis.IDENTITY, Vector3(berth.x + 0.5, MapLayout.MARINA_DECK + 0.02, finger)))
	await tools._wait(20)
	pos._update_interactable()
	var it := pos.interactable
	print("  by the parked boat: '%s'" % (it.prompt(c) if it else ""))
	check(it is ParkedCarEntry and it.prompt(c) == "Get in the speedboat", "a parked speedboat: 'Get in the speedboat'")
	await shot("11_parked_boats")
	if it:
		it.interact(c)
	t = 0.0
	while t < 5.0 and (not pos.driving() or game.camera_blend.blending):
		await tick()
		t += dt()
	var nb := boat()
	check(pos.driving() and nb != null and nb != b, "driving the parked boat")
	if nb:
		check(nb.floating() and nb.global_basis.y.y > 0.98, "it floats where it was tied up")
		check(Vector2(nb.global_position.x - berth.x, nb.global_position.z - berth.y).length() < 0.5, "in its berth")
		await drive(4.0, 0.7, 0.0, 0.0)
		check(nb.global_position.x < berth.x - 8.0, "and goes out to sea (bow first)")
		await shot("12_leaving_the_marina")
	check(game.p1.left_vehicles.has(b) or is_instance_valid(b), "the first boat stays where it was left")


func _fuel(b: Boat) -> void:
	print("-- fuel")
	var fuel := VehicleFuel.of(b)
	check(fuel != null and fuel.enabled, "the boat has a tank")
	if fuel == null:
		return
	var site := FuelSite.nearest_for(game.get_tree(), b, b.global_position)
	check(site != null and site.name == "MarinaFuel", "its nearest fuel is the marina's (%s)" % (site.name if site else "none"))
	var car_site: FuelSite = null
	for n in game.get_tree().get_nodes_in_group(FuelSite.GROUP):
		if n.name != "MarinaFuel" and (n as FuelSite).serves(b):
			car_site = n
	check(car_site == null, "no road or air pump serves a boat")
	if site:
		var sedan := VehicleCatalog.scene(VehicleCatalog.index_of_id("sedan")).instantiate() as Vehicle
		check(not site.serves(sedan), "the marina's pump doesn't serve cars")
		sedan.free()
	fuel.set_level(0.15)
	await drive(1.5, 0.3, 0.0, 0.0)
	check(game.hud._toast.text.contains("marina"), "low: '%s'" % game.hud._toast.text)
	check(game.p1.fuel_guide.site == site or game.p1.fuel_guide.vehicle == null, "the arrow points to the marina")
	# Back alongside the pontoon by the pump: get out to fill up.
	var fz: float = MapLayout.MARINA_FINGERS[0]
	await reposition(b, Vector3(-428.6, MapLayout.SEA_LEVEL + 0.05, fz + MapLayout.MARINA_FINGER_WIDTH * 0.5 + 0.45 + b.body_half_width), Vector3.LEFT)
	check(FuelSite.pump_near(game.get_tree(), b, b.global_position) != null, "the pump's hose reaches it in the first berth")
	await drive(1.0, 0.0, 0.0, 0.0)
	check(game.hud._prompt_label.text.contains("fill up"), "'%s'" % game.hud._prompt_label.text)
	fuel.set_level(0.0)
	await drive(0.5, 0.0, 0.0, 0.0)
	check(b.fuel_max_speed > 0.0, "empty: it crawls home")
	fuel.set_level(1.0)


func _car_at_sea(b: Boat) -> void:
	print("-- a car picked out at sea, then the boat again")
	await reposition(b)
	var sedan := VehicleCatalog.index_of_id("sedan")
	game.change_vehicle(sedan)
	await tools._wait(10)
	var car := game.vehicle
	check(car != null and not (car is Boat), "now in the sedan")
	await drive(2.0, 0.0, 0.0, 0.0)
	var space := game.get_world_3d().direct_space_state
	check(car.global_position.y > MapLayout.SEA_LEVEL and Boat.water_depth(space, car.global_position) < 0.05 and game.p1._lost_timer == 0.0,
		"on dry land, not in the sea (%.0f, %.1f, %.0f)" % [car.global_position.x, car.global_position.y, car.global_position.z])
	game.change_vehicle(VehicleCatalog.index_of_id("boat"))
	await tools._wait(10)
	var nb := boat()
	await drive(1.5, 0.0, 0.0, 0.0)
	check(nb != null and nb.floating() and Boat.water_depth(space, nb.global_position) >= 1.0, "and the boat goes on the nearest water")


## Into a pillar of the lighthouse bridge: dents, then the help button
## repairs it; and what a dent amidships costs.
func _crash(b: Boat) -> void:
	print("-- a crash")
	if b == null:
		return
	var dmg := b.get_node("Damage") as VehicleDamage
	await reposition(b, Vector3(-435.0, 0.0, -70.0), Vector3.BACK)
	pad(1.0, 0.0, 0.0)
	var t := 0.0
	var hit_at := 0.0
	while t < 10.0 and dmg.total_damage <= 0.0:
		await tick()
		t += dt()
		hit_at = maxf(hit_at, b.speed_kmh)
	await drive(1.0, 0.0, 0.0, 0.0)
	telemetry("after the pillar", b)
	check(dmg.total_damage > 0.0, "hits the bridge pillar (up to %.0f km/h): %.0f%% damage" % [hit_at, dmg.total_damage])
	check(b.floating() and b.global_basis.y.y > 0.5, "still afloat")
	await shot("16_crash")
	# A big dent amidships, timed: every mesh the dent pass looks at.
	var mid := b.global_transform * Vector3(b.body_half_width, 0.6, 0.0)
	var verts := 0
	for mi in dmg._meshes:
		var mesh := mi.mesh
		for k in mesh.get_surface_count():
			verts += (mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var t0 := Time.get_ticks_usec()
	for m in dmg._meshes.size():
		dmg._dent(m, mid, 0.3, 1.1, 0.8, 1.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  the boat's dentable meshes: %d, %d vertices; a full dent amidships %.2f ms" % [dmg._meshes.size(), verts, ms])
	check(ms < 8.0, "a dent amidships is cheap enough (%.2f ms)" % ms)
	await tools._tap("reset_vehicle")
	await drive(1.0, 0.0, 0.0, 0.0)
	check(dmg.total_damage == 0.0, "the help button repairs it")


## Two players: player 2 rides along in player 1's boat (on at the
## marina, can't get off at sea, comes along on player 1's teleport, gets
## off at the pontoon).
func _ride_along(b: Boat) -> void:
	print("-- two players: riding along")
	if b == null:
		return
	var st = preload("res://scripts/dev/split_tests.gd").new(tools, game, dir)
	var fz: float = MapLayout.MARINA_FINGERS[1]
	var at := Vector3(-428.6, MapLayout.SEA_LEVEL + 0.05, fz - MapLayout.MARINA_FINGER_WIDTH * 0.5 - 0.45 - b.body_half_width)
	await reposition(b, at, Vector3.LEFT)
	await st.join(0, 1)
	check(game.is_split(), "player 2 joins")
	if not game.is_split():
		return
	var p1 := game.players[0]
	var p2 := game.players[1]
	await tools._wait(20)
	var p2_car := p2.vehicle
	check(p2_car != null and not (p2_car is Boat) and p2_car.global_position.y > MapLayout.SEA_LEVEL - 0.3, "player 2's car isn't dropped in the sea")
	# Player 2 walks onto the finger beside the boat.
	p2.possession.leave_ride_now()
	if not p2.possession.on_foot():
		p2.possession.start_on_foot(Transform3D(Basis.IDENTITY, Vector3(at.x + 0.5, MapLayout.MARINA_DECK + 0.02, fz)))
	p2.character.place(Transform3D(Basis.IDENTITY, Vector3(at.x + 0.5, MapLayout.MARINA_DECK + 0.02, fz)))
	await tools._wait(10)
	var entry := VehicleEntry.of(b)
	check(entry.use_for(p2.character) == VehicleEntry.Use.RIDE, "by player 1's boat, player 2 can ride ('%s')" % entry.prompt(p2.character))
	check(p2.possession.ride_with(b), "player 2 gets in as a passenger")
	await drive(1.5, 0.0, 0.0, 0.0)
	check(p2.possession.riding() and p2.possession.ride == b, "riding in the boat")
	# Out to sea.
	b.teleport(Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(0.0, MapLayout.SEA_LEVEL + 0.05, 680.0)))
	await drive(1.5, 0.0, 0.0, 0.0)
	check(p2.possession.riding() and p2._lost_timer == 0.0, "player 2 rides out to sea (not 'lost at sea')")
	p2.possession.leave_ride()
	await drive(0.5, 0.0, 0.0, 0.0)
	check(p2.possession.riding(), "can't get off at sea")
	check(p2.hud._toast.text.contains("pier or a beach"), "player 2 is told why ('%s')" % p2.hud._toast.text)
	await shot("15_two_players_at_sea")
	# Player 1 teleports to the harbour: player 2 comes along.
	var harbour := -1
	for k in game.world.spawn_points.size():
		if game.world.spawn_points[k]["name"] == "Harbour":
			harbour = k
	p1.teleport_to(harbour)
	await drive(1.0, 0.0, 0.0, 0.0)
	check(p2.possession.riding() and p2.possession.ride == b and b.floating(), "player 2 comes along to the harbour")
	await reposition(b, at, Vector3.LEFT)
	check(p2.possession.leave_ride(), "at the pontoon player 2 gets off")
	var t := 0.0
	while t < 3.0 and not p2.possession.on_foot():
		await tick()
		t += dt()
	check(p2.possession.on_foot() and absf(p2.character.global_position.y - MapLayout.MARINA_DECK) < 0.2,
		"standing on the pontoon (%.2f)" % p2.character.global_position.y)
	game.remove_player()
	await tools._wait(20)
	check(not game.is_split() and game.vehicle == b and game.possession.driving(), "player 2 leaves; player 1 still at the helm")


func _night(b: Boat) -> void:
	print("-- night")
	if b == null:
		return
	await reposition(b, Vector3(-441.0, 0.0, -227.5), Vector3.RIGHT)
	game.day_night.cycling = false
	game.day_night.hour = 21.5
	game.day_night._apply()
	await drive(2.0, 0.0, 0.0, 0.0)
	game.p1._fit_headlights()
	var lights := b.get_node_or_null("Headlights") as Node3D
	check(lights != null and (lights.visible or not game.day_night.is_night), "the searchlight is on after dark")
	await shot("13_night_marina")


## --boatbench: what the boat's effects cost (wake, spray, rooster tail) while
## it circles at speed in open water: draw calls, render CPU and GPU with them
## shown and hidden, and the CPU of rebuilding the wake ribbon. Use
## --gpu-index 0 (the iGPU, a Deck stand-in) and --graphics=0..2.
func bench() -> void:
	var vp := tools.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	game.hud.visible = false
	game.traffic.set_enabled(false)
	game.teleport_to(0)
	await tools._wait(30)
	game.change_vehicle(VehicleCatalog.index_of_id("boat"))
	await tools._wait(10)
	var b := boat()
	if b == null:
		push_error("boatbench: no boat")
		return
	var fx := b.get_node("Effects") as BoatEffects
	await reposition(b)
	pad(1.0, 0.0, 0.45)
	await drive(8.0, 1.0, 0.0, 0.45)
	print("--- the boat's effects, graphics %s, %.0f km/h in a wide circle" % [Settings.GRAPHICS_LABELS[Settings.get_value("graphics")], b.speed_kmh])
	# Shown and hidden in turn, a second each, many times over (the circle
	# shows a different view every second; the averages see the same mix).
	var on := [0, 0.0, 0.0]
	var off := [0, 0.0, 0.0]
	for round in 10:
		for shown in [true, false]:
			fx._root.visible = shown
			fx.set_physics_process(shown)
			if not shown:
				for p in fx._root.find_children("*", "GPUParticles3D", true, false):
					(p as GPUParticles3D).emitting = false
			await tools._wait(15)
			var a: Array = await tools._frame_stats(60)
			var acc: Array = on if shown else off
			acc[0] += a[0]
			acc[1] += a[1]
			acc[2] += a[3]
	print("shown:  %d draw calls, render CPU %.2f ms, GPU %.2f ms" % [on[0] / 10, on[1] / 10.0, on[2] / 10.0])
	print("hidden: %d draw calls, render CPU %.2f ms, GPU %.2f ms" % [off[0] / 10, off[1] / 10.0, off[2] / 10.0])
	fx._root.visible = true
	fx.set_physics_process(true)
	await tools._wait(60)
	var n := 300
	var t0 := Time.get_ticks_usec()
	for i in n:
		fx._build_wake()
	var t1 := Time.get_ticks_usec()
	print("wake ribbon (%d points): %.3f ms per frame" % [fx._points.size(), (t1 - t0) / 1000.0 / n])
	release()
	game.hud.visible = true
	game.traffic.set_enabled(true)


## --boatshots=<dir>: screenshots for reviews (HUD hidden, a free camera):
## the marina from above, the boat planing with its wake, a ramp jump from
## the side, the garage, a sunset run.
func shots() -> void:
	game.traffic.set_enabled(false)
	game.teleport_to(0)
	await tools._wait(30)
	game.change_vehicle(VehicleCatalog.index_of_id("boat"))
	await tools._wait(10)
	var b := boat()
	if b == null:
		return
	game.hud.visible = false
	var cam := Camera3D.new()
	cam.far = 3000.0
	game.add_child(cam)
	var look := func(from: Vector3, at: Vector3, fov := 60.0) -> void:
		cam.global_position = from
		cam.look_at(at, Vector3.UP)
		cam.fov = fov
		cam.current = true
	# 1) The marina from above, the boat alongside the middle finger.
	var fz: float = MapLayout.MARINA_FINGERS[1]
	await reposition(b, Vector3(-428.6, 0.0, fz - MapLayout.MARINA_FINGER_WIDTH * 0.5 - 0.45 - b.body_half_width), Vector3.LEFT)
	look.call(Vector3(-452.0, 14.0, -206.0), Vector3(-426.0, -1.0, -228.0), 55.0)
	await tools._wait(20)
	await shot("show_01_marina")
	# 2) Planing in a wide turn, seen from behind and above.
	await reposition(b)
	await drive(7.0, 1.0, 0.0, 0.0)
	pad(1.0, 0.0, 0.35)
	for k in 90:
		await tick()
	var p := b.global_position
	var f := -b.global_basis.z
	var r := b.global_basis.x
	look.call(p - f * 16.0 + r * 9.0 + Vector3.UP * 6.0, p + f * 4.0, 50.0)
	await tools._wait(2)
	await shot("show_02_planing_wake")
	look.call(p + f * 14.0 - r * 6.0 + Vector3.UP * 2.0, p, 45.0)
	await tools._wait(2)
	await shot("show_03_coming_at_you")
	# 3) A ramp jump from the side.
	var rr: Vector4 = MapLayout.BOAT_RAMPS[2]
	var face := Vector3(rr.z, 0.0, rr.w).normalized()
	var lip := Vector3(rr.x, MapLayout.SEA_LEVEL, rr.y)
	await reposition(b, lip - face * 90.0, face)
	var side := face.cross(Vector3.UP)
	look.call(lip + face * 10.0 - side * 26.0 + Vector3.UP * 3.0, lip + face * 12.0 + Vector3.UP * 2.5, 55.0)
	pad(1.0, 0.0, 0.0)
	var t := 0.0
	var taken := false
	while t < 9.0:
		await tick()
		t += dt()
		if not taken and b.airtime > 0.5:
			taken = true
			await shot("show_04_ramp_jump")
	# 4) Sunset run along the west coast.
	game.day_night.cycling = false
	game.day_night.hour = 18.6
	game.day_night._apply()
	await reposition(b)
	await drive(6.0, 1.0, 0.0, 0.0)
	pad(1.0, 0.0, -0.25)
	for k in 60:
		await tick()
	p = b.global_position
	f = -b.global_basis.z
	r = b.global_basis.x
	look.call(p + f * 16.0 + r * 10.0 + Vector3.UP * 3.0, p, 50.0)
	await tools._wait(2)
	await shot("show_05_sunset")
	release()
	cam.current = false
	cam.queue_free()
	game.day_night.set_mode(0)
	game.hud.visible = true
	# 5) The garage.
	game.open_garage()
	await tools._wait(40)
	await shot("show_06_garage")
	game.picker.close()
	game._on_garage_cancelled()
