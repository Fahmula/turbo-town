extends RefCounted
## The --flight=<dir> dev test (run from DevTools): the plane flown through
## the player's own controls (Input actions, like a gamepad would), with
## pass/fail checks and screenshots:
##   take-off from the runway, cruise with the stick let go, banking and
##   levelling, a level turn, a loop, an aileron roll, a stall and its
##   recovery, R in the air, teleporting while flying, the island boundary,
##   an autopilot approach and landing, getting out and back in, a crash, and
##   swapping between the plane and a car in the garage.

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


## Sets the flight controls like a gamepad: power / slow 0..1, pitch and
## roll -1..1 (+ = nose up, + = bank right).
func stick(power: float, slow: float, pitch: float, roll: float) -> void:
	_axis("fly_power", power)
	_axis("fly_slow", slow)
	_axis("fly_nose_up", maxf(pitch, 0.0))
	_axis("fly_nose_down", maxf(-pitch, 0.0))
	_axis("fly_bank_right", maxf(roll, 0.0))
	_axis("fly_bank_left", maxf(-roll, 0.0))


func _axis(action: String, v: float) -> void:
	if v > 0.001:
		# Analog strength (< 1: the controller takes it as a stick, not a key).
		Input.action_press(action, minf(v, 0.98))
	else:
		Input.action_release(action)


func release() -> void:
	for a in ACTIONS:
		Input.action_release(a)


## Back over the island's south side, flying north (room for a manoeuvre).
func reposition(a: Aircraft, height := 200.0) -> void:
	a.place_in_flight(Vector3(0.0, height, 350.0), Vector3.FORWARD)
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)


func plane() -> Aircraft:
	return game.vehicle as Aircraft


func telemetry(label: String, a: Aircraft) -> void:
	if game.vehicle != a:
		print("  !! the player's vehicle changed")
	print("  %s: %.0f km/h  alt %.0f m  climb %.1f  bank %.0f  aoa %.1f  thr %.2f  ground %s  pos (%.0f, %.0f, %.0f)" % [
		label, a.speed_kmh, a.altitude, rad_to_deg(a.climb_angle), rad_to_deg(a.bank), rad_to_deg(a.aoa), a.throttle,
		a.on_ground, a.global_position.x, a.global_position.y, a.global_position.z])


func fly(seconds: float, power: float, slow: float, pitch: float, roll: float, label := "", every := 1.0) -> void:
	var t := 0.0
	var next := 0.0
	stick(power, slow, pitch, roll)
	while t < seconds:
		await tick()
		t += dt()
		if label != "" and t >= next:
			next += every
			telemetry("%s t=%.1f" % [label, t], plane())


func run() -> void:
	Settings.set_value("assists", true)
	Settings.set_value("flight_invert", false)
	var index := VehicleCatalog.index_of_id("plane")
	game.change_vehicle(index)
	await tools._wait(30)
	var a := plane()
	check(a != null, "the garage's plane is the player's vehicle")
	if a == null:
		return
	check(game.possession.driving() and game.possession.kind_of(a) == Controllable.PLANE, "sitting in it, with the plane rig")
	check(game.flight_controller.aircraft == a and game.controller.vehicle == null, "flight controls have the plane, car controls have nothing")
	check(game.flight_camera.current, "the flight camera is showing")
	check(game.hud.flying and not game.stunts.enabled, "HUD in flying mode, stunt scoring off")
	check(a.on_ground and absf(a.global_position.z - MapLayout.RUNWAY_A.z) < 2.0, "on the runway (%s)" % a.global_position)
	await shot("01_runway")

	await _take_off(a)
	await _cruise(a)
	await _turns(a)
	await _loop(a)
	await _roll(a)
	await _stall(a)
	await _help_button(a)
	await _teleports(a)
	await _boundary(a)
	await _landing(a)
	await _out_and_in(a)
	await _crash(a)
	await _garage_swap()
	release()
	print("FLIGHT: %d checks, %d failed" % [checks, fails])


func _take_off(a: Aircraft) -> void:
	print("-- take-off")
	var start := a.global_position
	var lift_off := Vector3.ZERO
	var lift_speed := 0.0
	var t := 0.0
	var airborne := 0.0
	stick(1.0, 0.0, 0.0, 0.0)
	while t < 30.0:
		await tick()
		t += dt()
		var pull := 0.6 if a.speed_kmh > 80.0 and a.altitude < 30.0 else 0.0
		stick(1.0, 0.0, pull, 0.0)
		if not a.on_ground:
			airborne += dt()
			if lift_off == Vector3.ZERO:
				lift_off = a.global_position
				lift_speed = a.speed_kmh
		else:
			airborne = 0.0
		if is_equal_approx(fmod(t, 1.0), 0.0) or int(t * 120.0) % 120 == 0:
			telemetry("t=%.1f" % t, a)
		if t > 4.0 and t < 4.01:
			await shot("02_take_off_roll")
		if a.altitude > 60.0:
			break
	var roll_dist := Vector2(lift_off.x - start.x, lift_off.z - start.z).length()
	check(lift_off != Vector3.ZERO, "lifted off (at %.0f km/h, after %.0f m)" % [lift_speed, roll_dist])
	check(roll_dist < 200.0, "lift-off inside the runway (%.0f of 222 m)" % roll_dist)
	check(a.altitude > 60.0 and t < 30.0, "climbed to 60 m in %.1f s" % t)
	await shot("03_climb_out")
	# Let go of everything right after the climb: it must not stall.
	var slowest := INF
	t = 0.0
	while t < 8.0:
		stick(0.0, 0.0, 0.0, 0.0)
		await tick()
		t += dt()
		slowest = minf(slowest, a.airspeed)
	check(slowest > 22.0 and a.stall_warning < 0.6, "let go after take-off: no stall (slowest %.0f km/h)" % (slowest * 3.6))
	# The rest happens over the middle of the island (the runway points out to sea).
	a.place_in_flight(Vector3(0.0, 180.0, 350.0), Vector3.FORWARD)
	await tick()


func _cruise(a: Aircraft) -> void:
	print("-- cruise, stick let go")
	await fly(3.0, 0.0, 0.0, 0.0, 0.0)
	var alt0 := a.global_position.y
	await fly(10.0, 0.0, 0.0, 0.0, 0.0, "cruise", 2.0)
	check(a.airspeed > 33.0 and a.airspeed < 62.0, "cruises on its own at %.0f km/h" % a.speed_kmh)
	check(absf(a.climb_angle) < deg_to_rad(6.0), "the climb eases toward level (%.1f°)" % rad_to_deg(a.climb_angle))
	check(absf(rad_to_deg(a.bank)) < 3.0, "wings level (%.1f°)" % rad_to_deg(a.bank))
	print("  height change in 10 s: %.1f m" % (a.global_position.y - alt0))
	await shot("04_cruise")


func _turns(a: Aircraft) -> void:
	print("-- bank and let go")
	await reposition(a)
	await fly(3.0, 0.0, 0.0, 0.0, 1.0)
	var banked := rad_to_deg(a.bank)
	check(banked > 50.0 and banked < 72.0, "full stick banks right and holds it (%.0f°)" % banked)
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)
	check(absf(rad_to_deg(a.bank)) < 6.0, "wings level themselves again (%.1f°)" % rad_to_deg(a.bank))
	print("-- level turn (half stick)")
	await reposition(a)
	var alt0 := a.global_position.y
	var heading0 := _heading(a)
	var t := 0.0
	while t < 8.0:
		stick(0.0, 0.0, 0.0, 0.6)
		await tick()
		t += dt()
	var turned := rad_to_deg(absf(angle_difference(heading0, _heading(a))))
	check(turned > 30.0, "turned %.0f° in 8 s" % turned)
	check(absf(a.global_position.y - alt0) < 20.0, "kept its height in the turn (%.1f m)" % (a.global_position.y - alt0))
	await shot("05_turn")
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)


func _heading(a: Aircraft) -> float:
	var v := a.linear_velocity
	return atan2(v.x, -v.z)


func _loop(a: Aircraft) -> void:
	print("-- loop")
	await reposition(a, 220.0)
	await fly(4.0, 1.0, 0.0, -0.15, 0.0)   # dive a little for speed
	var alt0 := a.global_position.y
	var pitched := 0.0
	var t := 0.0
	var top_shot := false
	var min_alt := INF
	while t < 16.0 and pitched < TAU:
		stick(1.0, 0.0, 1.0, 0.0)
		await tick()
		t += dt()
		pitched += (a.global_basis.inverse() * a.angular_velocity).x * dt()
		min_alt = minf(min_alt, a.altitude)
		if not top_shot and pitched > PI:
			top_shot = true
			telemetry("loop top", a)
			await shot("06_loop_top")
	check(pitched >= TAU * 0.98, "looped the loop in %.1f s (%.0f°)" % [t, rad_to_deg(pitched)])
	check(min_alt > 15.0, "never near the ground (lowest %.0f m)" % min_alt)
	print("  height after the loop: %+.0f m" % (a.global_position.y - alt0))
	await fly(5.0, 0.0, 0.0, 0.0, 0.0)


func _roll(a: Aircraft) -> void:
	print("-- barrel roll (trick + stick)")
	await reposition(a)
	await fly(2.0, 1.0, 0.0, 0.3, 0.0)
	var rolled := 0.0
	var t := 0.0
	Input.action_press("fly_trick")
	while t < 5.0 and rolled < TAU:
		stick(1.0, 0.0, 0.0, 1.0)
		await tick()
		t += dt()
		rolled += -(a.global_basis.inverse() * a.angular_velocity).z * dt()
	Input.action_release("fly_trick")
	check(rolled >= TAU * 0.98, "rolled all the way round in %.1f s" % t)
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)
	check(absf(rad_to_deg(a.bank)) < 8.0 and a.global_basis.y.y > 0.8, "upright again after the roll")


func _stall(a: Aircraft) -> void:
	print("-- stall")
	await reposition(a, 250.0)
	var warned := 0.0
	var max_yaw := 0.0
	var t := 0.0
	while t < 14.0:
		stick(0.0, 1.0, 1.0, 0.0)
		await tick()
		t += dt()
		warned = maxf(warned, a.stall_warning)
		max_yaw = maxf(max_yaw, absf(a.angular_velocity.y))
	telemetry("stalled", a)
	check(warned > 0.6, "stall warning (%.2f)" % warned)
	check(max_yaw < 1.0 and a.global_basis.y.y > 0.5, "no spin: upright, yaw rate at most %.2f rad/s" % max_yaw)
	await shot("07_stall")
	await fly(8.0, 1.0, 0.0, -0.2, 0.0)
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)
	check(a.airspeed > 33.0, "recovered: %.0f km/h" % a.speed_kmh)


func _help_button(a: Aircraft) -> void:
	print("-- R in the air")
	await reposition(a)
	Input.action_press("fly_trick")
	await fly(1.5, 0.0, 0.0, 0.0, 1.0)
	Input.action_release("fly_trick")
	a.reset_upright()
	await tick()
	check(absf(rad_to_deg(a.bank)) < 1.0 and absf(a.climb_angle) < 0.02, "levelled out")
	check(absf(a.airspeed - a.cruise_speed) < 2.0 and not a.on_ground, "at cruise speed, still flying")
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)


func _teleports(a: Aircraft) -> void:
	print("-- teleport while flying")
	game.teleport_to(0)
	await tick()
	var city: Vector3 = (game.world.spawn_points[0]["xform"] as Transform3D).origin
	check(not a.on_ground and a.global_position.y > city.y + 80.0, "over the City Center at %.0f m" % a.global_position.y)
	await fly(4.0, 0.0, 0.0, 0.0, 0.0)
	await shot("08_over_the_city")
	game.flight_camera.mode = FlightCamera.Mode.COCKPIT
	await fly(1.0, 0.0, 0.0, 0.0, 0.0)
	await shot("09_cockpit")
	game.flight_camera.mode = FlightCamera.Mode.CHASE


func _boundary(a: Aircraft) -> void:
	print("-- the island's edge")
	a.place_in_flight(Vector3(900.0, 120.0, 0.0), Vector3.RIGHT)
	var t := 0.0
	var turned := false
	var warned := false
	while t < 40.0:
		stick(0.0, 0.0, 0.0, 0.0)
		await tick()
		t += dt()
		warned = warned or game.hud.turning_back
		if a.linear_velocity.x < -20.0:
			turned = true
			break
	check(turned, "turned back toward the island by itself (%.0f s, x %.0f)" % [t, a.global_position.x])
	check(warned, "the HUD said it's turning back")
	check(a.altitude > 60.0, "kept flying while it turned (%.0f m)" % a.altitude)


func _landing(a: Aircraft) -> void:
	print("-- approach and landing")
	var thr := MapLayout.RUNWAY_A + Vector3(30.0, 0.0, 0.0)
	a.place_in_flight(thr + Vector3(-700.0, 45.0, 0.0), Vector3.RIGHT, 34.0)
	var t := 0.0
	var touched := false
	var stopped := false
	var dmg := a.get_node("Damage") as VehicleDamage
	while t < 90.0:
		var p := a.global_position
		var dist := thr.x - p.x
		# Glide path: 4 degrees down to the threshold, on the centre line,
		# then power off and the stick let go (the assist settles it).
		var want_alt := maxf(dist, 0.0) * tan(deg_to_rad(4.0)) + 6.0
		var pitch := clampf((want_alt - a.altitude) * 0.04 - (a.vertical_speed + 2.0) * 0.06, -0.5, 0.5)
		# Heading east, right is +z: south of the line, bank left.
		var want_bank := clampf(-(p.z - thr.z) * 0.012 - a.linear_velocity.z * 0.03, -0.3, 0.3)
		var roll := clampf((want_bank - a.bank) * 2.5, -1.0, 1.0)
		var power := clampf((29.0 - a.airspeed) * 0.15 + 0.3, 0.0, 1.0)
		var slow := 0.0 if a.airspeed < 29.0 else 0.6
		if dist < 30.0 or a.altitude < 6.0:
			pitch = 0.0
			power = 0.0
			slow = 0.7
		if a.on_ground:
			touched = true
			roll = clampf((p.z - thr.z) * -0.1, -1.0, 1.0)
			slow = 1.0
		stick(power, slow, pitch, roll)
		await tick()
		t += dt()
		if int(t * 120.0) % 240 == 0:
			telemetry("approach t=%.0f" % t, a)
		if not touched and a.altitude < 10.0 and a.altitude > 9.9:
			await shot("10_short_final")
		if touched and a.airspeed < 0.5:
			stopped = true
			break
	var p2 := a.global_position
	check(touched, "touched down")
	check(stopped, "rolled to a stop")
	check(absf(p2.z - MapLayout.RUNWAY_A.z) < MapLayout.RUNWAY_WIDTH * 0.5 and p2.x < MapLayout.RUNWAY_B.x, "on the runway (%s)" % p2)
	check(dmg.total_damage < 10.0, "a gentle landing (damage %.0f)" % dmg.total_damage)
	await shot("11_landed")
	release()


func _out_and_in(a: Aircraft) -> void:
	print("-- get out and back in")
	var pos := game.possession
	check(pos.exit(), "F gets out on the runway")
	var t := 0.0
	while t < 5.0 and not pos.on_foot():
		await tick()
		t += dt()
	check(pos.on_foot(), "on foot beside the plane")
	var c := game.character
	var d := c.global_position.distance_to(a.global_position)
	check(d < 4.0, "standing %.1f m from the plane" % d)
	await tools._wait(30)
	await shot("12_on_foot")
	var entry := a.get_node("Entry") as VehicleEntry
	check(entry.prompt(c) == "Get in the plane", "prompt: '%s'" % entry.prompt(c))
	check(pos.enter(a), "gets back in")
	t = 0.0
	while t < 3.0 and not pos.driving():
		await tick()
		t += dt()
	await tools._wait(70)
	check(pos.driving() and game.flight_controller.aircraft == a and game.flight_camera.current, "flying rig again")
	# No getting out in the air.
	a.place_in_flight(a.global_position + Vector3.UP * 60.0, Vector3.RIGHT)
	await tick()
	pos.exit()
	await tick()
	check(pos.driving(), "can't get out while flying")


func _crash(a: Aircraft) -> void:
	print("-- crash")
	var dmg := a.get_node("Damage") as VehicleDamage
	a.place_in_flight(MapLayout.RUNWAY_A + Vector3(80.0, 30.0, 60.0), Vector3(1, -0.6, 0).normalized(), 50.0)
	await fly(4.0, 1.0, 0.0, -0.6, 0.0)
	await shot("13_crash")
	await fly(2.0, 0.0, 0.0, 0.0, 0.0)
	check(dmg.total_damage > 20.0, "nose-dive into the ground dents it (damage %.0f)" % dmg.total_damage)
	check(is_finite(a.global_position.length()), "physics stayed sane")
	a.reset_upright()
	await tools._wait(10)
	check(dmg.total_damage == 0.0 and a.global_basis.y.y > 0.95, "R: upright and repaired")


func _garage_swap() -> void:
	print("-- garage: plane <-> car")
	var a := plane()
	a.place_in_flight(Vector3(0.0, 150.0, 200.0), Vector3.FORWARD)
	await tick()
	game.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	await tools._wait(20)
	var car := game.vehicle
	check(not (car is Aircraft) and game.possession.kind_of(car) == Controllable.VEHICLE, "now in a car")
	check(car.global_position.y < 20.0, "the car is on the ground, not in the sky (y %.0f)" % car.global_position.y)
	check(game.camera.current and not game.hud.flying, "chase camera and driving HUD")
	game.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await tools._wait(20)
	check(plane() != null and plane().on_ground and absf(plane().global_position.z - MapLayout.RUNWAY_A.z) < 2.0, "picking the plane puts it on the runway")


# --- --flightbench -------------------------------------------------------------

## GPU time, draw calls and primitives while flying over the island: the
## plane (frozen) moves along a fixed line across the city 1 m a frame
## (60 m/s at 60 fps) with the flight camera behind it, at three heights, on
## Medium, Low and High. Traffic is off so runs compare. Run it on the iGPU
## (--gpu-index 0) as a Steam Deck stand-in; results also go to perf.txt.
func bench() -> void:
	game.traffic.set_enabled(false)
	game.hud.visible = false
	game.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await tools._wait(30)
	var a := plane()
	a.freeze = true
	var vp := tools.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var lines: PackedStringArray = []
	for q: int in [GraphicsQuality.MEDIUM, GraphicsQuality.LOW, GraphicsQuality.HIGH]:
		Settings.set_value("graphics", q)
		for h: float in [60.0, 150.0, 300.0]:
			var basis := Basis.looking_at(Vector3.FORWARD, Vector3.UP)
			a.global_transform = Transform3D(basis, Vector3(-20.0, h, 420.0))
			a.reset_physics_interpolation()
			game.flight_camera.snap()
			await tools._wait(40)
			var times: Array[float] = []
			var calls := 0
			var prims := 0
			var frames := 420
			for k in frames:
				a.global_transform = Transform3D(basis, Vector3(-20.0, h, 420.0 - k * 2.0))
				await RenderingServer.frame_post_draw
				times.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
				calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			times.sort()
			var avg := 0.0
			for t in times:
				avg += t
			avg /= times.size()
			var line := "FLIGHTBENCH %-6s %3.0f m  gpu avg %6.2f ms  p95 %6.2f  max %6.2f   %5d calls %8d prims" % [
				Settings.GRAPHICS_LABELS[q], h, avg, times[int(times.size() * 0.95)], times[times.size() - 1],
				calls / frames, prims / frames]
			print(line)
			lines.append(line)
			if q == GraphicsQuality.MEDIUM:
				await shot("bench_%d_medium" % int(h))
	var f := FileAccess.open(dir.path_join("perf.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
