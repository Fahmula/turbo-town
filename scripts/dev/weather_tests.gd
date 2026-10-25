extends "res://scripts/dev/split_tests.gd"
## The weather dev test (run from DevTools):
##   --weather-test=<dir>  Clear / Cloudy / Rain / Thunderstorm / Changing:
##                         the menu's blend, the sky, sun and shadows, the
##                         ground soaking and drying, wet grip (braking
##                         distance dry and soaked), rain round the camera
##                         and none under the overpass, lightning (the
##                         ambient lifts and settles again), Changing moving
##                         on by itself, one rain per split-screen view,
##                         leak check (checks and shots)
## Uses the split-screen test's helpers.


func run() -> void:
	var g := game
	var w := g.weather
	var dn := g.day_night
	var sun := g.world.get_node("Sun") as DirectionalLight3D
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(1.0)
	g.ensure_driving()
	var kids_before := w.get_child_count()

	# --- Clear ------------------------------------------------------------------
	w.set_mode(Weather.Kind.CLEAR, true)
	await wait_s(0.3)
	check(w.clouds == 0.0 and w.rain == 0.0 and w.wet == 0.0, "clear: no clouds, rain or wet")
	check(VehicleWheel.weather_grip == 1.0, "clear: full grip")
	check(sun.shadow_enabled and is_equal_approx(sun.shadow_opacity, 1.0), "clear: sun shadows on")
	check(_rain_shown() == 0, "clear: no rain drawn")
	var clear_sun := sun.light_energy
	var clear_fog := (g.world.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_density

	# --- Rain from the menu (a few seconds' blend) -------------------------------
	Settings.set_value("weather", Weather.Kind.RAIN)
	await wait_s(1.0)
	check(w.clouds > 0.0 and w.clouds < 1.0, "the menu blends: clouds gathering (%.2f)" % w.clouds)
	await wait_s(6.0)
	check(is_equal_approx(w.clouds, 1.0) and is_equal_approx(w.rain, 0.6), "rain: overcast, raining (%.2f)" % w.rain)
	check(w.wet > 0.05 and w.wet < 0.5, "the ground is soaking (wet %.2f)" % w.wet)
	check(_rain_shown() == 1, "rain drawn round the camera")
	check(sun.light_energy < clear_sun * 0.35, "the sun is dimmed (%.2f -> %.2f)" % [clear_sun, sun.light_energy])
	check(not sun.shadow_enabled, "no sun shadows under a full overcast")
	var env := (g.world.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(env.fog_density > clear_fog * 2.0, "thicker haze (%.4f -> %.4f)" % [clear_fog, env.fog_density])
	await shot("rain_soaking")
	w.set_mode(Weather.Kind.RAIN, true)
	await wait_s(0.5)
	check(is_equal_approx(w.wet, 1.0) and is_equal_approx(VehicleWheel.weather_grip, 1.0 - Weather.WET_GRIP_LOSS), "soaked: grip %.2f" % VehicleWheel.weather_grip)
	await shot("rain_soaked")

	# --- Wet grip: braking from 90 km/h, dry and soaked ----------------------------
	w.set_mode(Weather.Kind.CLEAR, true)
	var dry := await _braking_distance()
	w.set_mode(Weather.Kind.RAIN, true)
	var soaked := await _braking_distance()
	check(soaked > dry * 1.03 and soaked < dry * 1.3, "braking from 90 km/h: %.1f m dry, %.1f m soaked (a little longer)" % [dry, soaked])

	# --- Under the overpass: no rain ---------------------------------------------------
	var cam := g.camera
	cam.set_process(false)
	var deck := _overpass_spot()
	check(deck != Vector3.INF, "found a spot under the overpass")
	if deck != Vector3.INF:
		cam.global_position = deck
		await wait_s(1.0)
		check(_rain_shown() == 0, "no rain under the overpass")
		cam.global_position = deck + Vector3(0.0, 0.0, 40.0)
		cam.look_at(deck + Vector3(0.0, 0.0, 80.0))
		await wait_s(1.0)
		check(_rain_shown() == 1, "rain again out in the open")
	cam.set_process(true)
	await wait_s(0.5)

	# --- Hood camera: drops fade out before the lens ---------------------------------
	g.teleport_to(0)
	await wait_s(1.0)
	cam.mode = ChaseCamera.Mode.HOOD
	await wait_s(1.5)
	await shot("rain_hood_cam")
	cam.mode = ChaseCamera.Mode.CHASE

	# --- Thunderstorm and lightning -----------------------------------------------
	w.set_mode(Weather.Kind.STORM, true)
	await wait_s(0.5)
	check(w.storm == 1.0 and w.rain == 1.0, "storm: full storm and downpour")
	var lightning: Lightning = w.get_node("Lightning")
	check(lightning.active, "lightning on in a storm")
	var base_ambient := env.ambient_light_energy
	var strikes := [0.0]
	var on_strike := func(d: float) -> void: strikes[0] = d
	lightning.struck.connect(on_strike)
	lightning._strike(0.0)
	await _bolt_shown(lightning)
	check(strikes[0] > 300.0, "a bolt strikes %.0f m away" % strikes[0])
	check(env.ambient_light_energy > base_ambient * 1.2, "the ambient light lifts (%.2f -> %.2f)" % [base_ambient, env.ambient_light_energy])
	await shot("storm_lightning")
	await wait_s(1.0)
	check(is_equal_approx(env.ambient_light_energy, base_ambient), "and settles again")
	lightning.struck.disconnect(on_strike)
	await shot("storm")
	g.teleport_to(0)
	dn.cycling = false
	dn.hour = 23.0
	dn._apply()
	await wait_s(1.0)
	await shot("storm_night")
	lightning._strike(0.0)
	await _bolt_shown(lightning)
	await shot("storm_night_lightning")
	dn.set_mode(0)

	# --- Drying, and Changing -----------------------------------------------------
	w.set_mode(Weather.Kind.RAIN, true)
	Settings.set_value("weather", Weather.Kind.CLEAR)
	await wait_s(8.0)
	check(w.rain == 0.0 and w.clouds < 0.6, "clearing up: rain stopped, clouds going")
	check(w.wet > 0.85 and w.wet < 1.0, "the ground dries slowly (wet %.2f)" % w.wet)
	w.set_mode(Weather.CHANGING, true)
	check(w.changing and w.kind == Weather.Kind.CLOUDY, "Changing starts cloudy")
	var before := w.kind
	w._stay_left = 0.0
	await wait(2)
	check(w.kind != before and (Weather.NEXT[before] as Array).has(w.kind), "Changing moves on by itself (to %s)" % Weather.Kind.keys()[w.kind])
	var c0 := w.clouds
	await wait_s(3.0)
	check(absf(w.clouds - c0) > 0.01 and absf(w.clouds - c0) < 0.2, "slowly (clouds %.2f -> %.2f)" % [c0, w.clouds])

	# --- Split-screen: one rain per view ---------------------------------------------
	w.set_mode(Weather.Kind.RAIN, true)
	await join(0, 1)
	await wait_s(1.0)
	var fx := w.find_children("*", "RainFx", false, false)
	check(fx.size() == 2 and _rain_shown() == 2, "split-screen: rain round both players")
	if fx.size() == 2:
		var a := (fx[0] as RainFx).get_child(0) as GPUParticles3D
		var b := (fx[1] as RainFx).get_child(0) as GPUParticles3D
		check(a.layers == Views.VIEW_LAYERS[0] and b.layers == Views.VIEW_LAYERS[1], "each drawn only in its own view")
	await shot("split_rain")
	g.remove_player()
	await wait_s(1.0)
	check(_rain_shown() == 1, "player 2 gone: one rain again")

	# --- Leaks ---------------------------------------------------------------------------
	w.set_mode(Weather.Kind.CLEAR, true)
	Settings.set_value("weather", Weather.Kind.CLEAR)
	await wait_s(0.5)
	check(w.get_child_count() <= kids_before + 2, "no stray weather nodes (%d -> %d)" % [kids_before, w.get_child_count()])
	print("WEATHER %d checks, %d failed" % [checks, fails])


## Waits (a few frames at most) until the bolt is drawn.
func _bolt_shown(lightning: Lightning) -> void:
	for i in 10:
		await wait(1)
		if lightning._bolt.visible:
			return


## How many RainFx are drawing rain now.
func _rain_shown() -> int:
	var n := 0
	for fx: RainFx in game.weather.find_children("*", "RainFx", false, false):
		if fx.visible:
			n += 1
	return n


## Braking distance (m) from 90 km/h to a stop, straight down the runway.
func _braking_distance() -> float:
	var g := game
	var v := g.vehicle
	# The controller zeroes the pedals even when disabled: stop it instead.
	g.controller.set_physics_process(false)
	var spot := -1
	for i in g.world.spawn_points.size():
		if String(g.world.spawn_points[i]["name"]).to_lower().contains("airfield"):
			spot = i
	g.teleport_to(maxi(spot, 0))
	await wait_s(1.0)
	var fwd := -v.global_basis.z
	v.throttle_input = 0.0
	for i in 3:
		# (Moving first: braking from a standstill would select reverse.)
		v.linear_velocity = fwd * 25.0
		await tools.get_tree().physics_frame
	v.brake_input = 1.0
	var start := v.global_position
	var t := 0.0
	while v.linear_velocity.length() > 0.3 and t < 10.0:
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()
	var d := start.distance_to(v.global_position)
	v.brake_input = 0.0
	g.controller.set_physics_process(true)
	return d


## A point 2 m above the ground under the overpass deck, with the deck
## found the way RainFx looks for roofs (Vector3.INF if none).
func _overpass_spot() -> Vector3:
	var space := game.world.get_world_3d().direct_space_state
	for x in range(-40, 40, 2):
		var top := Vector3(float(x), 40.0, -244.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 60.0, 1))
		if hit.is_empty() or hit["position"].y < 5.0:
			continue
		var from: Vector3 = hit["position"] + Vector3.DOWN * 1.5
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, 1))
		if ground.is_empty():
			continue
		var p: Vector3 = ground["position"] + Vector3.UP * 2.0
		var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * RainFx.ROOF_RAY, p + Vector3.UP * 2.5, 1))
		if not roof.is_empty():
			return p
	return Vector3.INF
