extends Node
## Developer helpers, inactive during normal play.
##   --tour=<dir>     save screenshots from a set of viewpoints, then quit
##   --drive=<dir>    drive the player car with scripted input, snapping shots
## Example:
##   godot --path . -- --tour=/tmp/shots

var _dir := ""
var _mode := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour="):
			_mode = "tour"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--drive="):
			_mode = "drive"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--traffic="):
			_mode = "traffic"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--rampage="):
			_mode = "rampage"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--showcase="):
			_mode = "showcase"
			_dir = arg.split("=")[1]
		elif arg == "--bench":
			_mode = "bench"
			_dir = OS.get_user_data_dir()
		elif arg.begins_with("--fx="):
			_mode = "fx"
			_dir = arg.split("=")[1]
	if _mode == "":
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dir.path_join(name + ".png"))
	print("shot: ", name)


func _run() -> void:
	await _wait(20)
	var game := get_tree().current_scene as Game
	if game == null:
		push_error("dev tools: main scene is not Game")
		get_tree().quit()
		return
	if _mode == "tour":
		await _tour(game)
	elif _mode == "fx":
		await _fx(game)
	elif _mode == "traffic":
		await _traffic(game)
	elif _mode == "bench":
		await _bench(game)
	elif _mode == "rampage":
		await _rampage(game)
	elif _mode == "showcase":
		await _showcase(game)
	else:
		await _drive(game)
	get_tree().quit()


func _tour(game: Game) -> void:
	for i in game.world.spawn_points.size():
		game.teleport_to(i)
		await _wait(90)
		await _shot("spawn_%d" % i)
	var cam := game.camera
	game.teleport_to(0)
	for m in [ChaseCamera.Mode.FAR, ChaseCamera.Mode.HOOD]:
		cam.mode = m
		cam.snap()
		await _wait(40)
		await _shot("cam_mode_%d" % m)
	cam.mode = ChaseCamera.Mode.CHASE
	cam.set_process(false)
	var views := [
		["overview", Vector3(330, 260, 330), Vector3(0, 0, 0)],
		["overpass_north", Vector3(70, 22, -190), Vector3(0, 6, -250)],
		["city_street", Vector3(-30, 2.5, 7), Vector3(40, 6, 3)],
		["city_aerial", Vector3(-120, 70, 120), Vector3(0, 0, 0)],
		["stunt_park", Vector3(-40, 45, 280), Vector3(20, 0, 420)],
		["mountain", Vector3(-40, 70, -260), Vector3(0, 30, -480)],
		["highway_corner", Vector3(260, 18, 300), Vector3(150, 0, 220)],
		["gas_station", Vector3(170, 10, 10), Vector3(200, 2, -32)],
		["gantry", Vector3(240, 4, 230), Vector3(250, 6, 150)],
	]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		await _wait(8)
		await _shot(v[0])


func _drive(game: Game) -> void:
	var v := game.vehicle
	var hw := game.world.roads.highway
	# 1) Highway lap on autopilot (inner lane), logging height vs terrain.
	game.teleport_to(1)
	await _wait(30)
	var t := 0.0
	var min_clear := INF
	var max_speed := 0.0
	var fps_sum := 0.0
	var frames := 0
	while t < 75.0:
		var pos := v.global_position
		var target := _lookahead(hw.points, pos, 28.0, -6.5)
		var local := v.global_basis.inverse() * (target - pos)
		var steer := clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0)
		_set_axis(steer)
		var want := 105.0 if absf(steer) < 0.25 else 75.0
		_set_pedals(v.speed_kmh < want, v.speed_kmh > want + 15.0)
		var ground := game.world.terrain.height_at(pos.x, pos.z)
		min_clear = minf(min_clear, pos.y - ground)
		max_speed = maxf(max_speed, v.speed_kmh)
		fps_sum += Engine.get_frames_per_second()
		frames += 1
		if frames % 600 == 0:
			print("  hwy t=%.0f pos=(%.0f, %.1f, %.0f) speed=%.0f" % [t, pos.x, pos.y, pos.z, v.speed_kmh])
		if frames % 900 == 0:
			await _shot("hwy_%d" % (frames / 900))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("HIGHWAY: min clearance over terrain %.2f, max speed %.0f, avg fps %.0f" % [min_clear, max_speed, fps_sum / frames])
	_release()

	# 2) Stunt park: straight over the medium kicker and the table top.
	game.teleport_to(2)
	await _wait(30)
	t = 0.0
	var max_air := 0.0
	while t < 12.0:
		_set_pedals(v.speed_kmh < 70.0, false)
		max_air = maxf(max_air, v.airtime)
		if int(t * 60) % 90 == 0 and t > 2.0:
			await _shot("park_%d" % int(t))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("PARK: max air %.2f s, end pos %s, upright %.2f" % [max_air, v.global_position, v.global_basis.y.y])
	_release()

	# 3) City: east along the avenue, across the highway junction into the fields.
	game.teleport_to(0)
	await _wait(30)
	t = 0.0
	min_clear = INF
	while t < 20.0:
		var pos := v.global_position
		var local := v.global_basis.inverse() * (Vector3(pos.x + 30.0, pos.y, 3.0) - pos)
		_set_axis(clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0))
		_set_pedals(v.speed_kmh < 90.0, false)
		min_clear = minf(min_clear, pos.y - game.world.terrain.height_at(pos.x, pos.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("CITY->FIELDS: end pos %s speed %.0f min clearance %.2f upright %.2f" % [v.global_position, v.speed_kmh, min_clear, v.global_basis.y.y])
	await _shot("city_east_end")
	_release()

	# 4) Mountain jump.
	game.teleport_to(3)
	await _wait(30)
	t = 0.0
	max_air = 0.0
	while t < 10.0:
		_set_pedals(v.speed_kmh < 80.0, false)
		max_air = maxf(max_air, v.airtime)
		if int(t * 60) % 120 == 0 and t > 1.0:
			await _shot("mountain_%d" % int(t))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("MOUNTAIN: max air %.2f s, end pos %s" % [max_air, v.global_position])
	_release()


func _set_axis(steer: float) -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.02:
		Input.action_press("steer_right", steer)
	elif steer < -0.02:
		Input.action_press("steer_left", -steer)


func _set_pedals(gas: bool, brake: bool) -> void:
	if gas:
		Input.action_press("accelerate")
	else:
		Input.action_release("accelerate")
	if brake:
		Input.action_press("brake")
	else:
		Input.action_release("brake")


func _release() -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)


## Point `ahead` metres further along a closed polyline from the nearest point,
## shifted sideways by `offset` (negative = left of travel direction).
func _lookahead(pts: PackedVector3Array, pos: Vector3, ahead: float, offset: float) -> Vector3:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	var n := pts.size()
	var i := best
	var acc := 0.0
	while acc < ahead:
		acc += pts[i].distance_to(pts[(i + 1) % n])
		i = (i + 1) % n
	var dir := (pts[(i + 1) % n] - pts[i]).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	return pts[i] + right * offset


func _fx(game: Game) -> void:
	var v := game.vehicle
	# Drift in the stunt park.
	game.teleport_to(2)
	await _wait(30)
	game.world.get_node("Props")  # (warm-up)
	v.teleport(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-60, 0.6, 330)))
	await _wait(10)
	var t := 0.0
	while t < 7.0:
		_set_pedals(t < 3.5 or t > 4.2, false)
		if t > 3.5:
			_set_axis(-1.0)
		if t > 3.5 and t < 4.3:
			Input.action_press("handbrake")
		else:
			Input.action_release("handbrake")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if absf(t - 4.6) < 0.005 or absf(t - 5.6) < 0.005 or absf(t - 6.8) < 0.005:
			await _shot("drift_%.1f" % t)
	_release()
	# Crash into a building at speed.
	v.teleport(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-140, 0.6, 72)))
	await _wait(10)
	t = 0.0
	var shot_taken := false
	v.impact.connect(func(st: float, _p: Vector3, _n: Vector3) -> void: print("  crash impact %.0f, damage %.0f" % [st, (v.get_node("Damage") as VehicleDamage).total_damage]))
	while t < 7.0:
		_set_pedals(true, false)
		_set_axis(-1.0 if (t > 3.2 and t < 3.7) else 0.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not shot_taken and v.speed_kmh < 20.0 and t > 2.0:
			shot_taken = true
			await _shot("crash_moment")
	_release()
	await _wait(60)
	var cam := game.camera
	cam.set_process(false)
	var c := v.global_position
	for k in 3:
		var ang := k * TAU / 3.0 + 0.4
		cam.global_position = c + Vector3(cos(ang) * 5.5, 2.2, sin(ang) * 5.5)
		cam.look_at(c + Vector3.UP * 0.5, Vector3.UP)
		await _wait(4)
		await _shot("dent_%d" % k)
	cam.set_process(true)


## Parks the player and watches the traffic for a while, logging health stats.
func _traffic(game: Game) -> void:
	var tm := game.traffic
	# Park the player in the plaza, out of the traffic lanes.
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-20, 0.8, -20)))
	var impacts := [0]
	var seen := {}
	var t := 0.0
	var cam := game.camera
	var views := [
		["t_intersection", Vector3(28, 26, 28), Vector3(0, 0, 0)],
		["t_street", Vector3(-60, 7, 20), Vector3(-10, 1, -8)],
		["t_highway", Vector3(275, 25, -120), Vector3(250, 0, -40)],
		["t_junction", Vector3(215, 30, 40), Vector3(250, 0, 0)],
	]
	var view_i := 0
	var log_t := 0.0
	var speed_sum := 0.0
	var speed_n := 0
	var lost_seen := {}
	var follow: TrafficDriver = null
	var follow_shots := 0
	while t < 150.0:
		for d in tm.drivers:
			if d.state == TrafficDriver.State.LOST and not lost_seen.has(d):
				lost_seen[d] = true
				print("  LOST at t=%.0f pos=%s: %s" % [t, d.vehicle.global_position.round(), d.lost_reason])
		# Follow an AI car with the camera between the fixed views.
		if t > 5.0 and t < 18.0:
			if follow == null or not is_instance_valid(follow):
				for d in tm.drivers:
					if d.state == TrafficDriver.State.DRIVING and d.vehicle.global_position.distance_to(game.vehicle.global_position) < 200.0:
						follow = d
						cam.set_target(d.vehicle)
						break
			if follow and int(t * 10) % 25 == 0 and follow_shots < 5 and absf(t * 10 - round(t * 10)) < 0.05:
				follow_shots += 1
				await _shot("t_follow_%d" % follow_shots)
		elif follow != null:
			cam.set_target(game.vehicle)
			follow = null
		for d in tm.drivers:
			if not seen.has(d):
				seen[d] = true
				d.vehicle.impact.connect(func(st: float, _p: Vector3, _n: Vector3) -> void:
					if st > 9000.0:
						impacts[0] += 1)
			if d.state == TrafficDriver.State.DRIVING:
				speed_sum += d.vehicle.speed_kmh
				speed_n += 1
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		log_t += dt
		if log_t >= 10.0:
			log_t = 0.0
			var lost := 0
			var stunned := 0
			var stopped := 0
			for d in tm.drivers:
				if d.state == TrafficDriver.State.LOST:
					lost += 1
				elif d.state == TrafficDriver.State.STUNNED:
					stunned += 1
				elif d.vehicle.speed_kmh < 3.0:
					stopped += 1
			print("  t=%3.0f cars=%d driving_avg=%.0fkmh stopped=%d stunned=%d lost=%d spawned_total=%d crashes=%d fps=%.0f phys=%.1fms proc=%.1fms" % [
				t, tm.drivers.size(), speed_sum / maxf(speed_n, 1), stopped, stunned, lost, seen.size(), impacts[0], Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			speed_sum = 0.0
			speed_n = 0
			var why := {}
			for d in tm.drivers:
				if d.state == TrafficDriver.State.DRIVING and d.vehicle.speed_kmh < 25.0:
					var key := d.blocker.split(" ")[0] if d.blocker != "" else "(free/curve)"
					why[key] = why.get(key, 0) + 1
			print("       slow cars limited by: ", why)
		if t > 20.0 + view_i * 25.0 and view_i < views.size():
			var v: Array = views[view_i]
			cam.set_process(false)
			cam.global_position = v[1]
			cam.look_at(v[2], Vector3.UP)
			await _wait(3)
			await _shot(v[0])
			cam.set_process(true)
			view_i += 1
	print("TRAFFIC: spawned %d cars, %d crash impacts" % [seen.size(), impacts[0]])


func _measure(label: String, seconds: float) -> void:
	var t := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		n += 1
	var per_tick := float(Time.get_ticks_usec() - t0) / n / 1000.0
	print("BENCH %-30s %.2f ms per physics tick (wall clock, %d ticks)" % [label, per_tick, n])


func _bench(game: Game) -> void:
	var tm := game.traffic
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-20, 0.8, -20)))
	tm.set_enabled(false)
	await _wait(30)
	await _measure("no traffic", 5.0)
	await _measure("no traffic again", 5.0)
	game.vehicle.set_physics_process(false)
	await _measure("no traffic, player script off", 3.0)
	game.vehicle.set_physics_process(true)
	tm.set_enabled(true)
	await _wait(120)
	await _measure("18 cars driving", 8.0)
	for d in tm.drivers:
		d.set_physics_process(false)
		d.vehicle.throttle_input = 0.0
		d.vehicle.brake_input = 1.0
	await _wait(60)
	await _measure("18 cars, drivers paused", 5.0)
	for d in tm.drivers:
		d.vehicle.set_physics_process(false)
		(d.vehicle.get_node("Effects") as Node).set_physics_process(false)
		(d.vehicle.get_node("Body") as Node).set_physics_process(false)
	await _measure("18 cars, all scripts off", 5.0)


## Player drives the wrong way down avenues into traffic.
func _rampage(game: Game) -> void:
	var tm := game.traffic
	var v := game.vehicle
	await _wait(60)
	var states := {}
	var t := 0.0
	var shots := 0
	v.teleport(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-140, 0.6, -1.6)))
	while t < 60.0:
		var pos := v.global_position
		# Hold the westbound (oncoming) lane of the z=0 avenue heading east; turn around at the ends.
		var dir_x := 1.0 if int(t / 20.0) % 2 == 0 else -1.0
		var lane_z := -1.6 * dir_x
		var target := Vector3(pos.x + 25.0 * dir_x, pos.y, lane_z)
		var local := v.global_basis.inverse() * (target - pos)
		_set_axis(clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0))
		_set_pedals(v.speed_kmh < 70.0 and absf(atan2(local.x, -local.z)) < 1.2, false)
		for d in tm.drivers:
			var key := "%s" % d.get_instance_id()
			var st := str(d.state)
			if states.get(key, "") != st:
				if st != "0" or states.has(key):
					print("  t=%.1f %s -> %s %s at %s" % [t, d.vehicle.name, ["DRIVING", "STUNNED", "LOST"][d.state], d.lost_reason, d.vehicle.global_position.round()])
				states[key] = st
				if d.lost_reason.begins_with("stuck"):
					var cam := game.camera
					cam.set_process(false)
					var cp := d.vehicle.global_position
					var back := d.vehicle.global_basis.z
					cam.global_position = cp + back * 7.0 + Vector3.UP * 4.0 + d.vehicle.global_basis.x * 3.0
					cam.look_at(cp - back * 3.0, Vector3.UP)
					await _wait(2)
					await _shot("stuck_%s" % d.vehicle.name)
					cam.global_position = cp - back * 9.0 + Vector3.UP * 3.0
					cam.look_at(cp, Vector3.UP)
					await _wait(2)
					await _shot("stuck_front_%s" % d.vehicle.name)
					cam.set_process(true)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if int(t * 60) % 240 == 0 and shots < 10:
			shots += 1
			await _shot("rampage_%d" % shots)
	_release()
	var counts := [0, 0, 0]
	for d in tm.drivers:
		counts[d.state] += 1
	print("RAMPAGE end: driving=%d stunned=%d lost=%d player damage=%.0f" % [counts[0], counts[1], counts[2], (v.get_node("Damage") as VehicleDamage).total_damage])


## One of each traffic vehicle in a convoy through the city, filmed.
func _showcase(game: Game) -> void:
	var tm := game.traffic
	tm.set_enabled(false)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-20, 0.8, -20)))
	await _wait(10)
	var drivers: Array[TrafficDriver] = []
	var i := 0
	for scene in tm.car_scenes:
		# Eastbound lane of the z = 75 street, spaced out behind each other.
		var d := tm.spawn_near(scene, Vector3(-60.0 - i * 16.0, 0, 76.8))
		if d:
			drivers.append(d)
		i += 1
	var cam := game.camera
	cam.set_process(false)
	var t := 0.0
	var shot_i := 0
	var shots := [
		[3.0, "convoy_side", Vector3(-70, 3, 90), Vector3(-80, 1.5, 76)],
		[6.0, "convoy_front", Vector3(-25, 4, 70), Vector3(-60, 1.5, 76)],
		[9.0, "convoy_follow", Vector3.ZERO, Vector3.ZERO],
		[14.0, "convoy_aerial", Vector3(10, 30, 110), Vector3(0, 0, 75)],
		[20.0, "convoy_turn", Vector3(-15, 18, 95), Vector3(0, 0, 75)],
	]
	while t < 26.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if shot_i < shots.size() and t >= shots[shot_i][0]:
			var sh: Array = shots[shot_i]
			if sh[1] == "convoy_follow" and drivers.size() > 0:
				var bus := drivers.back().vehicle as Vehicle
				cam.global_position = bus.global_transform * Vector3(-4.0, 4.5, 14.0)
				cam.look_at(bus.global_transform * Vector3(0, 1.0, -12.0), Vector3.UP)
			else:
				cam.global_position = sh[2]
				cam.look_at(sh[3], Vector3.UP)
			await _wait(2)
			await _shot(sh[1])
			shot_i += 1
	for d in drivers:
		print("  %s: state=%s pos=%s" % [d.vehicle.display_name, ["DRIVING", "STUNNED", "LOST"][d.state], d.vehicle.global_position.round()])
