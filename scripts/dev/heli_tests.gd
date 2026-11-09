extends RefCounted
## The --heli=<dir> dev test (run from DevTools): the helicopter flown through
## the player's own controls (Input actions, like a gamepad would), with
## pass/fail checks and screenshots:
##   picking it in the garage (it stands beside you), the rotor spooling up,
##   take-off, holding a hover, forward flight and stopping, turning on the
##   spot and banked turns, flying backward, climbing and sinking, a flip and
##   a roll, R in the air, teleporting while flying and to the helipad, the
##   island boundary, a soft landing, getting out and back in, a replay, the
##   parked helicopter on the helipad, a crash, garage swaps (in the air too),
##   assists off, and the controls page.

const ACTIONS := ["fly_power", "fly_slow", "fly_nose_up", "fly_nose_down", "fly_bank_left", "fly_bank_right", "fly_trick"]

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


## The controls like a gamepad: up / down 0..1, fwd -1..1 (+ = forward),
## turn -1..1 (+ = right).
func stick(up: float, down: float, fwd: float, turn: float) -> void:
	_axis("fly_power", up)
	_axis("fly_slow", down)
	_axis("fly_nose_down", maxf(fwd, 0.0))
	_axis("fly_nose_up", maxf(-fwd, 0.0))
	_axis("fly_bank_right", maxf(turn, 0.0))
	_axis("fly_bank_left", maxf(-turn, 0.0))


func _axis(action: String, v: float) -> void:
	if v > 0.001:
		# Analog strength (< 1: the controller takes it as a stick, not a key).
		Input.action_press(action, minf(v, 0.98))
	else:
		Input.action_release(action)


func release() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func heli() -> Helicopter:
	return game.vehicle as Helicopter


func telemetry(label: String, h: Helicopter) -> void:
	if game.vehicle != h:
		print("  !! the player's vehicle changed")
	var b := h.global_basis
	var tilt := rad_to_deg(acos(clampf(b.y.y, -1.0, 1.0)))
	print("  %s: %.0f km/h  fwd %.1f  vs %.1f  alt %.1f  tilt %.0f  bank %.0f  hdg %.0f  rotor %.2f  thr %.2f  ground %s  pos (%.0f, %.0f, %.0f)" % [
		label, h.speed_kmh, h.linear_velocity.dot(h.heading_dir()), h.vertical_speed, h.altitude, tilt, rad_to_deg(h.bank),
		rad_to_deg(h.heading), h.rotor, h.throttle, h.on_ground, h.global_position.x, h.global_position.y, h.global_position.z])


func fly(seconds: float, up: float, down: float, fwd: float, turn: float, label := "", every := 1.0) -> void:
	var t := 0.0
	var next := 0.0
	stick(up, down, fwd, turn)
	while t < seconds:
		await tick()
		t += dt()
		if label != "" and t >= next:
			next += every
			telemetry("%s t=%.1f" % [label, t], heli())


## Hovering over open country south of the city, nose north.
func reposition(h: Helicopter, height := 120.0) -> void:
	h.place_in_flight(Vector3(0.0, height, 380.0), Vector3.FORWARD)
	await fly(1.5, 0.0, 0.0, 0.0, 0.0)


func run() -> void:
	Settings.set_value("assists", true)
	Settings.set_value("flight_invert", false)
	game.teleport_to(0)
	await tools._wait(30)
	if game.possession.driving():
		game.possession.exit()
		await tools._wait(240)
	var index := VehicleCatalog.index_of_id("helicopter")
	check(index >= 0, "the helicopter is in the garage's list")
	game.change_vehicle(index)
	await tools._wait(5)
	var h := heli()
	check(h != null, "the garage's helicopter is the player's vehicle")
	if h == null:
		return
	check(game.possession.driving() and game.possession.kind_of(h) == Controllable.HELI, "sitting in it, with the helicopter rig")
	check(game.heli_controller.heli == h and game.controller.vehicle == null and game.flight_controller.vehicle == null,
		"helicopter controls have it, car and plane controls have nothing")
	check(game.heli_camera.current, "the helicopter camera is showing")
	check(game.hud.flying and game.hud.heli and not game.stunts.enabled, "HUD in helicopter mode, stunt scoring off")
	var city: Vector3 = (game.world.spawn_points[0]["xform"] as Transform3D).origin
	print("  placed at %s (city centre %s)" % [h.global_position, city])
	check(h.global_basis.y.y > 0.98 and h.global_position.distance_to(city) < 60.0, "standing upright beside the player in the city")
	await _take_off(h)
	await _hover(h)
	await _forward(h)
	await _turns(h)
	await _back_and_vertical(h)
	await _up_down_while_moving(h)
	await _tricks(h)
	await _help_button(h)
	await _teleports(h)
	await _boundary(h)
	await _landing(h)
	await _out_and_in(h)
	await _replay(h)
	await _parked_heli()
	h = heli()
	await _crash(h)
	await _garage_swaps()
	await _assists_off()
	release()
	game.menu.show_page("controls_heli")
	await tools._wait(5)
	await shot("18_controls_heli")
	game.menu.close()
	print("HELI: %d checks, %d failed" % [checks, fails])


func _take_off(h: Helicopter) -> void:
	print("-- rotor start and take-off")
	await tools._wait(10)
	check(h.rotor < 0.5, "the rotor starts slowly (%.2f)" % h.rotor)
	check(game.hud._hint.visible and game.hud._hint.text.begins_with("Starting"), "the HUD says the rotor is starting ('%s')" % game.hud._hint.text)
	await shot("01_rotor_starting")
	# Holding up straight away: it stays down until the rotor is up to speed.
	var t := 0.0
	var lifted_at := -1.0
	stick(1.0, 0.0, 0.0, 0.0)
	while t < 12.0:
		await tick()
		t += dt()
		if lifted_at < 0.0 and h.altitude > 0.5:
			lifted_at = t
			telemetry("lift-off", h)
		if lifted_at > 0.0 and t > lifted_at + 2.5:
			break
	check(lifted_at > 1.5, "no lift-off on a slow rotor (lifted after %.1f s)" % lifted_at)
	check(lifted_at > 0.0 and lifted_at < 6.0, "lifts off once the rotor is up (%.1f s)" % lifted_at)
	check(h.altitude > 10.0, "climbing: %.0f m" % h.altitude)
	await shot("02_take_off")


func _hover(h: Helicopter) -> void:
	print("-- hover, everything let go")
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	var alt0 := h.global_position.y
	var pos0 := h.global_position
	var worst := 0.0
	var t := 0.0
	stick(0.0, 0.0, 0.0, 0.0)
	while t < 6.0:
		await tick()
		t += dt()
		worst = maxf(worst, absf(h.global_position.y - alt0))
	telemetry("hover", h)
	check(worst < 1.0, "holds its height (moved at most %.2f m)" % worst)
	var drift := Vector2(h.global_position.x - pos0.x, h.global_position.z - pos0.z).length()
	check(drift < 1.5 and h.airspeed < 0.6, "stays put (drifted %.2f m, %.2f m/s)" % [drift, h.airspeed])
	check(h.global_basis.y.y > 0.995, "level")
	await shot("03_hover")


func _forward(h: Helicopter) -> void:
	print("-- forward flight")
	await reposition(h)
	var alt0 := h.global_position.y
	var max_tilt := 0.0
	var t := 0.0
	stick(0.0, 0.0, 1.0, 0.0)
	var to100 := -1.0
	var leaned := -1.0
	while t < 16.0:
		await tick()
		t += dt()
		var tilt := rad_to_deg(acos(clampf(h.global_basis.y.y, -1.0, 1.0)))
		max_tilt = maxf(max_tilt, tilt)
		if leaned < 0.0 and tilt > 20.0:
			leaned = t
		if to100 < 0.0 and h.speed_kmh > 100.0:
			to100 = t
		if is_equal_approx(t, 6.0) or (t > 6.0 and t < 6.01):
			await shot("04_forward")
	telemetry("forward", h)
	var nose_down := h.global_basis.z.y   # +: the nose (-z) points down
	check(h.speed_kmh > 170.0 and h.speed_kmh < 215.0, "full stick: %.0f km/h" % h.speed_kmh)
	check(to100 > 3.0 and to100 < 10.0, "0-100 km/h in %.1f s" % to100)
	# Not a snap: the nose goes down over most of a second (owner, 2026-11-09).
	check(leaned > 0.5 and leaned < 1.5, "leans in smoothly (20° after %.2f s)" % leaned)
	check(nose_down > 0.25 and max_tilt < 34.0, "nose down while flying fast (lean %.0f°, most %.0f°)" % [rad_to_deg(asin(nose_down)), max_tilt])
	check(absf(h.global_position.y - alt0) < 6.0, "kept its height (%.1f m)" % (h.global_position.y - alt0))
	print("-- let go: stops")
	t = 0.0
	var stopped := -1.0
	var max_back := 0.0
	var level := -1.0
	var flared := -1.0
	stick(0.0, 0.0, 0.0, 0.0)
	while t < 20.0:
		await tick()
		t += dt()
		max_back = maxf(max_back, -h.global_basis.z.y)
		if level < 0.0 and h.global_basis.z.y < 0.0:
			level = t
		if flared < 0.0 and -h.global_basis.z.y > sin(deg_to_rad(20.0)):
			flared = t
		if stopped < 0.0 and h.airspeed < 1.0:
			stopped = t
			break
	telemetry("stopped", h)
	check(stopped > 0.0 and stopped < 16.0, "slows to a hover by itself (%.1f s)" % stopped)
	check(max_back > 0.2, "flares nose-up to stop (%.0f°)" % rad_to_deg(asin(max_back)))
	check(level > 0.4 and flared > level + 0.4, "and the nose comes up smoothly (level after %.2f s, 20° up after %.2f s)" % [level, flared])
	check(absf(h.global_position.y - alt0) < 8.0, "still at its height (%.1f m)" % (h.global_position.y - alt0))


func _turns(h: Helicopter) -> void:
	print("-- turn on the spot")
	await reposition(h)
	var hdg0 := h.heading
	await fly(2.0, 0.0, 0.0, 0.0, 1.0)
	var turned := rad_to_deg(angle_difference(h.heading, hdg0))
	check(turned > 120.0 and turned < 220.0, "full stick right turns it %.0f° in 2 s (to the right)" % turned)
	await fly(1.0, 0.0, 0.0, 0.0, 0.0)
	var hdg1 := h.heading
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)
	check(absf(rad_to_deg(angle_difference(hdg1, h.heading))) < 3.0, "stops turning when let go")
	print("-- banked turn at speed")
	await reposition(h)
	await fly(10.0, 0.0, 0.0, 1.0, 0.0)
	var alt0 := h.global_position.y
	hdg0 = h.heading
	var most_bank := 0.0
	var t := 0.0
	stick(0.0, 0.0, 1.0, 0.7)
	while t < 8.0:
		await tick()
		t += dt()
		most_bank = maxf(most_bank, rad_to_deg(h.bank))
		if t > 4.0 and t < 4.01:
			await shot("05_banked_turn")
	telemetry("turning", h)
	turned = rad_to_deg(absf(angle_difference(hdg0, h.heading)))
	var v := h.linear_velocity
	var slip := rad_to_deg(absf(angle_difference(atan2(-v.x, -v.z), h.heading)))
	check(turned > 60.0, "turned %.0f° in 8 s at %.0f km/h" % [turned, h.speed_kmh])
	check(most_bank > 15.0 and most_bank < 60.0, "leaned into the turn (%.0f°)" % most_bank)
	check(slip < 15.0, "goes where the nose points (%.0f° off)" % slip)
	check(absf(h.global_position.y - alt0) < 10.0, "kept its height in the turn (%.1f m)" % (h.global_position.y - alt0))
	await fly(6.0, 0.0, 0.0, 0.0, 0.0)


func _back_and_vertical(h: Helicopter) -> void:
	print("-- backward, up, down")
	await reposition(h)
	await fly(4.0, 0.0, 0.0, -1.0, 0.0)
	var back := h.linear_velocity.dot(h.heading_dir())
	check(back < -5.0 and back > -12.0, "stick back flies backward (%.1f m/s)" % back)
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	await fly(4.0, 1.0, 0.0, 0.0, 0.0)
	check(h.vertical_speed > 7.0, "full up climbs at %.1f m/s" % h.vertical_speed)
	await fly(4.0, 0.0, 1.0, 0.0, 0.0)
	check(h.vertical_speed < -5.0, "full down sinks at %.1f m/s" % h.vertical_speed)
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	check(absf(h.vertical_speed) < 0.5, "let go: holds its height again (%.2f m/s)" % h.vertical_speed)


## Flies `seconds` with the stick and triggers held and records the nose
## (degrees, + = down), the speed along the heading and its change (m/s²).
func _trace(h: Helicopter, seconds: float, up: float, down: float, fwd: float, label: String) -> Dictionary:
	var r := {"pmin": 999.0, "pmax": -999.0, "vmin": 999.0, "vmax": -999.0, "amax": 0.0}
	var t := 0.0
	var next := 0.0
	var v_last := h.linear_velocity.dot(h.heading_dir())
	stick(up, down, fwd, 0.0)
	while t < seconds:
		await tick()
		t += dt()
		var pitch := rad_to_deg(asin(clampf(h.global_basis.z.y, -1.0, 1.0)))
		var v := h.linear_velocity.dot(h.heading_dir())
		r.pmin = minf(r.pmin, pitch)
		r.pmax = maxf(r.pmax, pitch)
		r.vmin = minf(r.vmin, v)
		r.vmax = maxf(r.vmax, v)
		r.amax = maxf(r.amax, absf(v - v_last) / dt())
		v_last = v
		if t >= next:
			next += 0.25
			print("    %s t=%.2f  nose %+.0f°  fwd %.1f m/s  vs %+.1f" % [label, t, pitch, v, h.vertical_speed])
	r["end_v"] = v_last
	return r


## Up or down (the triggers) while flying forward or back: the nose keeps
## the lean the stick asked for, the speed doesn't surge (owner: "a little
## yo-yo", 2026-11-09).
func _up_down_while_moving(h: Helicopter) -> void:
	print("-- up and down while moving")
	await reposition(h, 160.0)
	var r := await _trace(h, 4.0, 0.98, 0.0, 1.0, "fwd+up")
	check(r.pmax < 32.0 and r.pmin > -3.0, "forward and up from a hover: the nose leans in, no fling (%.0f..%.0f°)" % [r.pmin, r.pmax])
	await reposition(h, 160.0)
	r = await _trace(h, 4.0, 0.0, 0.98, 1.0, "fwd+down")
	check(r.pmax < 32.0 and r.pmin > -3.0, "forward and down from a hover: the nose leans in, no fling (%.0f..%.0f°)" % [r.pmin, r.pmax])
	await reposition(h, 160.0)
	r = await _trace(h, 3.0, 0.0, 0.98, -1.0, "back+down")
	check(r.pmin > -32.0 and r.pmax < 3.0, "back and down: the nose comes up, no fling (%.0f..%.0f°)" % [r.pmin, r.pmax])
	check(r.vmin > -h.max_back_speed - 1.5, "and backward speed doesn't overshoot (%.1f m/s)" % r.vmin)
	await reposition(h, 160.0)
	r = await _trace(h, 3.0, 0.98, 0.0, -1.0, "back+up")
	check(r.pmin > -32.0 and r.pmax < 3.0, "back and up: the nose comes up, no fling (%.0f..%.0f°)" % [r.pmin, r.pmax])
	# At full speed, then down, let go of down, up, let go of up.
	# From the south coast, so 24 s of full speed and the four steps stay
	# inside the island's edge (beyond it the helicopter turns itself back).
	h.place_in_flight(Vector3(0.0, 200.0, 900.0), Vector3.FORWARD)
	await fly(24.0, 0.0, 0.0, 1.0, 0.0)
	var v0 := h.linear_velocity.dot(h.heading_dir())
	var p0 := rad_to_deg(asin(h.global_basis.z.y))
	print("    full speed: %.1f m/s, nose %.0f°" % [v0, p0])
	for step: Array in [["down", 0.0, 0.98], ["let go", 0.0, 0.0], ["up", 0.98, 0.0], ["let go", 0.0, 0.0]]:
		r = await _trace(h, 2.5, step[1], step[2], 1.0, "fast+" + step[0])
		check(r.pmax - p0 < 4.0 and p0 - r.pmin < 6.0, "full speed, %s: the nose stays put (%.0f..%.0f°, was %.0f°)" % [step[0], r.pmin, r.pmax, p0])
		check(r.vmax - v0 < 2.5 and v0 - r.vmin < 2.5 and r.amax < 4.0,
			"full speed, %s: no surge (%.1f..%.1f m/s, was %.1f; most %.1f m/s²)" % [step[0], r.vmin, r.vmax, v0, r.amax])
	check(not game.heli_controller.turning_back, "(still inside the island's edge: z %.0f)" % h.global_position.z)
	release()


func _tricks(h: Helicopter) -> void:
	print("-- flip and roll")
	for kind: String in ["flip", "roll"]:
		await reposition(h, 150.0)
		var alt0 := h.global_position.y
		var spun := 0.0
		var t := 0.0
		Input.action_press("fly_trick")
		var shot_taken := false
		while t < 3.0:
			stick(0.0, 0.0, 1.0 if kind == "flip" else 0.0, 1.0 if kind == "roll" else 0.0)
			await tick()
			t += dt()
			var w := h.global_basis.inverse() * h.angular_velocity
			spun += absf(w.x if kind == "flip" else w.z) * dt()
			if not shot_taken and spun > PI * 0.9:
				shot_taken = true
				await shot("06_%s" % kind)
			if t > 0.3:
				Input.action_release("fly_trick")
		release()
		# The stick stayed forward after the flip: it flares to a stop first.
		await fly(5.0, 0.0, 0.0, 0.0, 0.0)
		telemetry("after the %s" % kind, h)
		check(spun > TAU * 0.95, "%s: all the way round (%.0f°)" % [kind, rad_to_deg(spun)])
		check(h.global_basis.y.y > 0.97, "%s: upright again" % kind)
		check(alt0 - h.global_position.y < 25.0, "%s: lost %.0f m" % [kind, alt0 - h.global_position.y])
	print("-- no tricks near the ground")
	h.place_in_flight(Vector3(0.0, 6.0, 380.0) + Vector3.UP * _ground_y(Vector3(0.0, 0.0, 380.0)), Vector3.FORWARD)
	await fly(1.0, 0.0, 0.0, 0.0, 0.0)
	Input.action_press("fly_trick")
	await fly(1.0, 0.0, 0.0, 0.0, 1.0)
	release()
	check(h.global_basis.y.y > 0.8 and h.trick_left <= 0.0, "too low: the trick button doesn't roll it")


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 300.0, p + Vector3.DOWN * 300.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _help_button(h: Helicopter) -> void:
	print("-- R in the air")
	await reposition(h)
	Input.action_press("fly_trick")
	await fly(0.5, 0.0, 0.0, 1.0, 1.0)
	release()
	h.reset_upright()
	await tick()
	check(h.global_basis.y.y > 0.999 and h.airspeed < 0.1 and not h.on_ground, "levelled out, hovering")
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)
	check(h.global_basis.y.y > 0.99 and h.airspeed < 1.0, "still hovering after it")


func _teleports(h: Helicopter) -> void:
	print("-- teleports while flying")
	game.teleport_to(0)
	await tick()
	var city: Vector3 = (game.world.spawn_points[0]["xform"] as Transform3D).origin
	check(not h.on_ground and h.global_position.y > city.y + 25.0 and h.global_position.y < city.y + 50.0,
		"hovering over the City Center at %.0f m" % (h.global_position.y - city.y))
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	await shot("07_over_the_city")
	game.heli_camera.mode = FlightCamera.Mode.COCKPIT
	await fly(1.0, 0.0, 0.0, 0.0, 0.0)
	await shot("08_cockpit")
	game.heli_camera.mode = FlightCamera.Mode.CHASE
	var air := -1
	for i in game.world.spawn_points.size():
		if game.world.spawn_points[i]["name"] == "Airfield":
			air = i
	game.teleport_to(air)
	await tools._wait(30)
	var pad := MapLayout.HELIPAD_A
	check(Vector2(h.global_position.x - pad.x, h.global_position.z - pad.z).length() < 1.0 and h.on_ground,
		"the Airfield teleport puts it on the helipad (%s)" % h.global_position)
	await shot("09_helipad")


func _boundary(h: Helicopter) -> void:
	print("-- the island's edge")
	h.place_in_flight(Vector3(940.0, 80.0, 0.0), Vector3.RIGHT)
	var t := 0.0
	var turned := false
	var warned := false
	while t < 30.0:
		stick(0.0, 0.0, 1.0, 0.0)
		await tick()
		t += dt()
		warned = warned or game.hud.turning_back
		if h.linear_velocity.x < -10.0:
			turned = true
			break
	check(turned, "turned back toward the island by itself (%.0f s, x %.0f)" % [t, h.global_position.x])
	check(warned, "the HUD said it's turning back")
	check(h.altitude > 40.0, "kept flying while it turned (%.0f m)" % h.altitude)
	release()


func _landing(h: Helicopter) -> void:
	print("-- landing on the helipad")
	var pad := MapLayout.HELIPAD_A
	h.place_in_flight(pad + Vector3(0.0, 25.0, 0.0), Vector3.BACK)
	var dmg := h.get_node("Damage") as VehicleDamage
	var t := 0.0
	var touch_speed := 0.0
	var touched := false
	stick(0.0, 1.0, 0.0, 0.0)
	while t < 30.0:
		await tick()
		t += dt()
		if not touched and h.on_ground:
			touched = true
			touch_speed = -h.vertical_speed
			telemetry("touch-down", h)
		if touched and t > 0.0 and h.airspeed < 0.05:
			break
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)
	check(touched, "landed")
	check(touch_speed < 2.5, "softly (%.1f m/s at touch-down)" % touch_speed)
	check(dmg.total_damage < 3.0, "no damage (%.0f)" % dmg.total_damage)
	check(h.on_ground and h.grounded_wheels == 4 and h.airspeed < 0.1, "sitting on its skids")
	await shot("10_landed")
	# Let go on the ground: it stays down (no hopping).
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	check(h.on_ground and h.altitude < 0.2, "stays on the ground with nothing pressed")
	release()


func _out_and_in(h: Helicopter) -> void:
	print("-- get out and back in")
	var pos := game.possession
	check(pos.exit(), "F gets out on the helipad")
	var t := 0.0
	while t < 5.0 and not pos.on_foot():
		await tick()
		t += dt()
	check(pos.on_foot(), "on foot beside the helicopter")
	var c := game.character
	var d := c.global_position.distance_to(h.global_position)
	check(d < 4.0, "standing %.1f m from it" % d)
	await tools._wait(60)
	check(not h.engine_running and h.rotor < 1.0, "engine off: the rotor winds down (%.2f)" % h.rotor)
	await shot("11_on_foot")
	var entry := h.get_node("Entry") as VehicleEntry
	check(entry.prompt(c) == "Get in the helicopter", "prompt: '%s'" % entry.prompt(c))
	check(pos.enter(h), "gets back in")
	t = 0.0
	while t < 4.0 and (not pos.driving() or game.camera_blend.blending):
		await tick()
		t += dt()
	await tools._wait(5)
	check(pos.driving() and game.heli_controller.heli == h and game.heli_camera.current,
		"helicopter rig again (driving %s, controls %s, camera %s)" % [pos.driving(), game.heli_controller.heli == h, game.heli_camera.current])
	# No getting out in the air.
	h.place_in_flight(h.global_position + Vector3.UP * 30.0, Vector3.BACK)
	await tick()
	pos.exit()
	await tick()
	check(pos.driving(), "can't get out while flying")


func _replay(h: Helicopter) -> void:
	print("-- instant replay")
	await reposition(h)
	await fly(4.0, 0.3, 0.0, 0.8, 0.5)
	check(game.start_replay(), "P plays the replay")
	check(game.state == Game.State.REPLAY, "replaying")
	await tools._wait(90)
	await shot("12_replay")
	game.replay.stop()
	await tools._wait(5)
	check(game.state == Game.State.DRIVING and game.heli_camera.current, "back to flying with the helicopter camera")


func _parked_heli() -> void:
	print("-- the parked helicopter on the second helipad")
	release()
	var pos := game.possession
	var old := heli()
	old.teleport(game.helipad_start(old))
	var t := 0.0
	while t < 3.0 and not (old.on_ground and old.airspeed < 0.3):
		await tick()
		t += dt()
	check(old.on_ground, "teleported onto the helipad, it settles on its skids (%.1f s)" % t)
	pos.exit()
	t = 0.0
	while t < 5.0 and not pos.on_foot():
		await tick()
		t += dt()
	var prop: Prop = null
	for n in tools.get_tree().get_nodes_in_group(Interactable.GROUP):
		var e := n as ParkedCarEntry
		if e and e.prop and e.prop.drive_scene.ends_with("helicopter.tscn"):
			prop = e.prop
	check(prop != null, "there's a parked helicopter at the airfield")
	if prop == null:
		return
	check(prop.global_position.distance_to(MapLayout.HELIPAD_B) < 1.5, "on the second helipad")
	await shot("13_parked_heli")
	var at := prop.global_transform * Vector3(-1.9, 0.0, -0.4)
	game.character.place(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.1))
	await tools._wait(20)
	var it := Interactable.best_for(game.character, game.character.global_position)
	check(it != null and it.prompt(game.character) == "Get in the helicopter", "walking up to it: '%s'" % (it.prompt(game.character) if it else "nothing"))
	check(it != null and it.interact(game.character), "getting in")
	t = 0.0
	while t < 3.0 and not pos.driving():
		await tick()
		t += dt()
	await tools._wait(30)
	var h := heli()
	check(h != null and h != old and pos.driving(), "flying the parked helicopter now (the other one stays parked)")
	check(game.left_vehicles.has(old), "the first helicopter stays where it was left")
	await fly(9.0, 1.0, 0.0, 0.0, 0.0)
	check(h.altitude > 8.0, "it takes off (%.0f m)" % h.altitude)
	release()


func _crash(h: Helicopter) -> void:
	print("-- crash")
	var dmg := h.get_node("Damage") as VehicleDamage
	h.place_in_flight(MapLayout.RUNWAY_A + Vector3(80.0, 25.0, 0.0), Vector3.RIGHT, 30.0)
	Settings.set_value("assists", false)
	await fly(4.0, 0.0, 1.0, 1.0, 0.0)
	Settings.set_value("assists", true)
	await shot("14_crash")
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)
	check(dmg.total_damage > 15.0, "flying it into the ground dents it (damage %.0f)" % dmg.total_damage)
	check(is_finite(h.global_position.length()), "physics stayed sane")
	h.reset_upright()
	await tools._wait(10)
	check(dmg.total_damage == 0.0 and h.global_basis.y.y > 0.95, "R: upright and repaired")


func _garage_swaps() -> void:
	print("-- garage swaps")
	var h := heli()
	h.place_in_flight(Vector3(0.0, 120.0, 200.0), Vector3.FORWARD)
	await tick()
	game.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	await tools._wait(20)
	var car := game.vehicle
	check(not (car is Aircraft) and game.possession.kind_of(car) == Controllable.VEHICLE, "flying -> a car")
	check(car.global_position.y < 20.0 and game.camera.current and not game.hud.flying, "the car is on the ground, chase camera, driving HUD")
	game.change_vehicle(VehicleCatalog.index_of_id("helicopter"))
	await tools._wait(20)
	h = heli()
	check(h != null and h.on_ground and h.global_position.distance_to(car.global_position if is_instance_valid(car) else h.global_position) < 30.0,
		"car -> helicopter: it stands where the car was")
	game.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await tools._wait(20)
	var plane := game.vehicle as Aircraft
	plane.place_in_flight(Vector3(0.0, 150.0, 200.0), Vector3.FORWARD)
	await tick()
	var where := plane.global_position
	game.change_vehicle(VehicleCatalog.index_of_id("helicopter"))
	await tools._wait(10)
	h = heli()
	check(h != null and not h.on_ground and h.global_position.distance_to(where) < 60.0 and h.rotor > 0.99,
		"flying plane -> helicopter: it hovers where the plane was")
	check(game.heli_camera.current and game.hud.heli, "helicopter camera and HUD")
	await shot("15_swapped_in_the_air")


func _assists_off() -> void:
	print("-- assists off")
	var h := heli()
	Settings.set_value("assists", false)
	await tools._wait(2)
	check(not h.traction_control, "assists off")
	await reposition(h, 150.0)
	await fly(5.0, 0.0, 0.0, 1.0, 0.0, "pro", 1.0)
	var fast := h.airspeed
	check(fast > 15.0, "stick forward: leans and speeds up (%.0f km/h)" % (fast * 3.6))
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)
	check(h.airspeed > fast * 0.6, "let go: it keeps drifting (%.0f km/h)" % h.speed_kmh)
	await shot("16_assists_off")
	await fly(4.0, 0.0, 0.0, -1.0, 0.0)
	check(h.airspeed < fast, "leaning back slows it (%.0f km/h)" % h.speed_kmh)
	Settings.set_value("assists", true)
	await tools._wait(2)
	await fly(8.0, 0.0, 0.0, 0.0, 0.0)
	check(h.airspeed < 2.0 and h.global_basis.y.y > 0.99, "assists back on: hovering again")
