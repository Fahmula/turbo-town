extends Node
## Developer helpers, inactive during normal play.
##   --tour=<dir>     save screenshots from a set of viewpoints, then quit
##   --drive=<dir>    drive the player car with scripted input, snapping shots
##   --garage=<dir>   garage menu + changing into every vehicle (checks and shots)
##   --menus=<dir>    title/pause/settings/controls menus driven by input (checks and shots)
##   --lanes=<dir>    traffic passing a parked player, horn reactions, highway lane changes
##   --junction=<dir> the signalized highway/avenue junction: turns used, crashes, jams
##   --stunts=<dir>   air, flips, rolls, spins, drift, near miss, wipeout -> combos and records
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
		elif arg.begins_with("--uturn="):
			_mode = "uturn"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--stunts="):
			_mode = "stunts"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--corner="):
			_mode = "corner"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--junction="):
			_mode = "junction"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--lanes="):
			_mode = "lanes"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--menus="):
			_mode = "menus"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--garage="):
			_mode = "garage"
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
	elif _mode == "uturn":
		await _uturn(game)
	elif _mode == "garage":
		await _garage(game)
	elif _mode == "menus":
		await _menus(game)
	elif _mode == "lanes":
		await _lanes(game)
	elif _mode == "junction":
		await _junction(game)
	elif _mode == "corner":
		await _corner(game)
	elif _mode == "stunts":
		await _stunts(game)
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
				print("  LOST at t=%.0f pos=%s: %s (%s)" % [t, d.vehicle.global_position.round(), d.lost_reason, d.vehicle.display_name])
				await _photo_vehicle(game, d.vehicle, "lost_%d" % int(t))
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
		if int(t * 120) % 600 == 0:
			print("  t=%.0f traffic cars=%d player=%s speed=%.0f" % [t, tm.drivers.size(), v.global_position.round(), v.speed_kmh])
		if int(t * 60) % 240 == 0 and shots < 10:
			shots += 1
			await _shot("rampage_%d" % shots)
	_release()
	# Back off and check that nearby traffic gets going again.
	var near := {}
	for d in tm.drivers:
		if d.vehicle.global_position.distance_to(v.global_position) < 15.0:
			near[d] = d.vehicle.global_position
	Input.action_press("brake")
	await _wait(120)
	Input.action_release("brake")
	await _wait(600)
	for d in near:
		if is_instance_valid(d) and is_instance_valid(d.vehicle):
			print("  after release: %s moved %.0f m (state %s, blocker '%s')" % [d.vehicle.display_name,
				d.vehicle.global_position.distance_to(near[d]), ["DRIVING", "STUNNED", "LOST"][d.state], d.blocker])
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
	# Family photo: park them side by side in the plaza.
	var x := -60.0
	for d in drivers:
		d.set_physics_process(false)
		var v := d.vehicle
		v.throttle_input = 0.0
		v.brake_input = 1.0
		v.steer_input = 0.0
		v.teleport(Transform3D(Basis(Vector3.UP, -0.5), Vector3(x, 0.15 + v.wheel_radius() + 0.1, -50)))
		x += 5.5
	await _wait(90)
	var views := [
		["family_front", Vector3(-38, 3.5, -64), Vector3(-44, 1.2, -50)],
		["family_rear", Vector3(-52, 3.5, -36), Vector3(-44, 1.2, -50)],
	]
	for view in views:
		cam.global_position = view[1]
		cam.look_at(view[2], Vector3.UP)
		await _wait(3)
		await _shot(view[0])


## A small car drives into the south avenue dead end (by the stunt park
## gate) and must U-turn back north.
func _uturn(game: Game) -> void:
	var tm := game.traffic
	tm.set_enabled(false)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(40, 0.8, 330)))
	await _wait(10)
	var d := tm.spawn_near(tm.car_scenes[1], Vector3(-1.8, 0, 270))
	var t := 0.0
	var min_z := INF
	var max_z := -INF
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var z := d.vehicle.global_position.z
		max_z = maxf(max_z, z)
		if max_z > 300.0:
			min_z = minf(min_z, z)
	var ok := max_z > 300.0 and min_z < 280.0 and d.state == TrafficDriver.State.DRIVING
	print("UTURN %s: reached z=%.0f, came back to z=%.0f, state=%s blocker='%s'" % [
		"PASS" if ok else "FAIL", max_z, min_z, ["DRIVING", "STUNNED", "LOST"][d.state], d.blocker])


func _photo_vehicle(game: Game, v: Vehicle, name: String) -> void:
	var cam := game.camera
	var was := cam.is_processing()
	cam.set_process(false)
	var cp := v.global_position
	var back := v.global_basis.z
	back.y = 0.0
	back = back.normalized()
	cam.global_position = cp + back * 9.0 + Vector3.UP * 6.0 + v.global_basis.x * 3.0
	cam.look_at(cp - back * 3.0, Vector3.UP)
	await _wait(2)
	await _shot(name)
	cam.global_position = cp + Vector3(0.5, 18.0, 0.5)
	cam.look_at(cp, Vector3.FORWARD)
	await _wait(2)
	await _shot(name + "_top")
	cam.set_process(was)


## Sends an input action through the real input pipeline (press + release).
func _tap(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _wait(3)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


## Player and every system that follows it agree on which vehicle is driven.
func _check_wiring(game: Game, label: String) -> void:
	var v := game.vehicle
	var players := 0
	for child in game.get_children():
		if child is Vehicle:
			players += 1
	_check(players == 1, "%s: one player vehicle in the scene (%d)" % [label, players])
	_check(game.controller.vehicle == v and game.camera.target == v and game.hud.vehicle == v,
		"%s: controller, camera and HUD follow the new vehicle" % label)
	_check(game.traffic.player == v and game.traffic.vehicles.count(v) == 1,
		"%s: traffic knows the new player vehicle" % label)


func _garage(game: Game) -> void:
	var tm := game.traffic
	game.teleport_to(0)
	await _wait(60)

	# 1) The menu, driven with the real input actions.
	var old := game.vehicle
	await _tap("change_vehicle")
	await _wait(20)
	_check(game.picker.is_open and get_tree().paused, "V opens the garage and pauses")
	await _shot("garage_0")
	for i in 4:
		await _tap("menu_right")
		await _wait(15)
		await _shot("garage_%d" % (i + 1))
	for i in 3:
		await _tap("menu_down")
	await _wait(10)
	await _shot("garage_paint")
	var want_color := VehicleCatalog.COLORS[game.picker.color_index]
	_check(game.picker.index == 4, "four steps right reach the bus")
	await _tap("menu_accept")
	await _wait(10)
	_check(not game.picker.is_open and not get_tree().paused, "accept closes the garage and unpauses")
	_check(not is_instance_valid(old), "old car is freed")
	_check(game.vehicle.display_name == "Bus", "now driving the %s" % game.vehicle.display_name)
	_check((game.vehicle.get_node("Body") as VehicleBodyVisual).paint_color == want_color, "paint colour applied")
	_check_wiring(game, "after garage")
	await _wait(60)
	_check(game.vehicle.global_basis.y.y > 0.95 and game.vehicle.linear_velocity.length() < 2.0,
		"bus settles calmly (up %.2f, speed %.1f)" % [game.vehicle.global_basis.y.y, game.vehicle.linear_velocity.length()])

	# Cancel leaves everything alone.
	var bus := game.vehicle
	await _tap("change_vehicle")
	await _wait(5)
	await _tap("menu_left")
	await _tap("menu_back")
	await _wait(5)
	_check(game.vehicle == bus and not get_tree().paused and not game.picker.is_open, "Esc/B backs out without changing")

	# 2) Drive every vehicle for a bit and photograph the cameras.
	for i in VehicleCatalog.count():
		game.teleport_to(0)
		await _wait(10)
		game.change_vehicle(i, VehicleCatalog.COLORS[(i * 3) % VehicleCatalog.COLORS.size()])
		await _wait(5)
		var v := game.vehicle
		_check_wiring(game, v.display_name)
		var t := 0.0
		var start := v.global_position
		while t < 7.0:
			var pos := v.global_position
			var local := v.global_basis.inverse() * (Vector3(pos.x + 30.0, pos.y, 3.0) - pos)
			_set_axis(clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0))
			_set_pedals(t > 0.5 and v.speed_kmh < 60.0, false)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("  %s drove %.0f m, %.0f km/h, upright %.2f" % [v.display_name, v.global_position.distance_to(start), v.speed_kmh, v.global_basis.y.y])
		var id: String = VehicleCatalog.ENTRIES[i]["id"]
		await _shot("drive_%s_chase" % id)
		game.camera.mode = ChaseCamera.Mode.HOOD
		await _wait(3)
		await _shot("drive_%s_hood" % id)
		game.camera.mode = ChaseCamera.Mode.FAR
		await _wait(3)
		await _shot("drive_%s_far" % id)
		game.camera.mode = ChaseCamera.Mode.CHASE
		_release()

	# 3) No room (a wall right in front): falls back to the spawn point.
	game.change_vehicle(0, Color.RED)
	await _wait(5)
	var spot := Transform3D(Basis.IDENTITY, Vector3(-20, 0.8, -20))
	game.vehicle.teleport(spot)
	await _wait(30)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 0.5)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = game.vehicle.global_position + Vector3(0, 1.0, -3.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.change_vehicle(4, Color.YELLOW)
	var sp: Transform3D = game.world.spawn_points[game.spawn_index]["xform"]
	_check(game.vehicle.global_position.distance_to(sp.origin) < 3.0, "blocked spot: bus goes to the spawn point instead")
	wall.queue_free()

	# 4) A traffic car in the way is removed instead.
	tm.set_enabled(false)
	await _wait(5)
	game.change_vehicle(0, Color.RED)
	var d := tm.spawn_near(VehicleCatalog.scene(1), Vector3(-1.8, 0, 200))
	await _wait(30)
	var tv := d.vehicle
	var lane_fwd := -tv.global_basis.z
	game.vehicle.teleport(Transform3D(tv.global_basis, tv.global_position + lane_fwd * 6.0 + Vector3.UP * 0.3))
	d.set_physics_process(false)
	tv.linear_velocity = Vector3.ZERO
	await _wait(30)
	var here := game.vehicle.global_position
	game.change_vehicle(4, Color.YELLOW)
	await _wait(5)
	_check(not is_instance_valid(tv) or tv.is_queued_for_deletion(), "traffic car overlapping the bus was removed")
	_check(game.vehicle.global_position.distance_to(here) < 1.5, "bus placed where the car was")
	await _wait(60)
	_check(game.vehicle.linear_velocity.length() < 2.0, "no physics explosion (speed %.1f)" % game.vehicle.linear_velocity.length())

	# 5) The choice is saved to disk and restored.
	Settings.persist = true
	Settings.path = _dir.path_join("settings_test.cfg")
	game._save_choice(2, VehicleCatalog.COLORS[6])
	Settings.persist = false
	Settings.set_value("vehicle", "sports_car")  # in memory only
	game.change_vehicle(0, Color.RED)
	Settings.load_file()
	game._load_choice()
	game.teleport_to(0)
	await _wait(10)
	_check(game.vehicle.display_name == "Van" and (game.vehicle.get_node("Body") as VehicleBodyVisual).paint_color == VehicleCatalog.COLORS[6],
		"saved choice (purple van) restored")
	_check_wiring(game, "after load")
	# A settings file from before the Settings autoload ([player] section).
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("player", "vehicle", "box_truck")
	old_cfg.set_value("player", "paint", VehicleCatalog.COLORS[3])
	old_cfg.save(Settings.path)
	Settings.load_file()
	_check(Settings.get_value("vehicle") == "box_truck" and Settings.get_value("paint") == VehicleCatalog.COLORS[3], "old garage settings file migrated")


func _menus(game: Game) -> void:
	var tm := game.traffic
	await _wait(30)
	# Title screen (dev runs normally skip it).
	game._enter_title()
	await _wait(90)
	_check(game.state == Game.State.TITLE and game.menu.page == "title" and not game.controller.enabled, "title screen shown, car input off")
	_check(game.title_camera.current, "title camera orbits the car")
	await _shot("menu_title")
	# DRIVE! has focus: accept starts driving.
	await _tap("ui_accept")
	await _wait(5)
	_check(game.state == Game.State.DRIVING and game.controller.enabled and game.camera.current and not game.menu.visible, "DRIVE! starts the game")

	# Pause menu with Esc, settings page via focus navigation.
	await _tap("pause")
	await _wait(5)
	_check(game.state == Game.State.PAUSED and get_tree().paused and game.menu.page == "pause", "Esc opens the pause menu")
	await _shot("menu_pause")
	await _tap("ui_down")
	await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(5)
	_check(game.menu.page == "settings", "down, down, accept opens settings")
	await _shot("menu_settings")
	# First row (traffic) is focused: right = Busy.
	var before := tm.max_cars
	await _tap("ui_right")
	_check(Settings.get_value("traffic_density") == 2 and tm.max_cars == Settings.TRAFFIC_CARS[2], "traffic busy: %d -> %d cars" % [before, tm.max_cars])
	await _tap("ui_left")
	await _tap("ui_left")
	_check(Settings.get_value("traffic_density") == 0 and tm.max_cars == Settings.TRAFFIC_CARS[0], "traffic few")
	await _wait(5)
	_check(tm.drivers.size() <= Settings.TRAFFIC_CARS[0], "extra traffic removed (%d left)" % tm.drivers.size())
	await _tap("ui_right")
	# Graphics row: go Low, screenshot, back to High.
	await _tap("ui_down")
	await _tap("ui_left")
	await _tap("ui_left")
	_check(Settings.get_value("graphics") == 0 and game.get_viewport().scaling_3d_scale < 1.0, "graphics low applied")
	await _tap("ui_cancel")
	await _tap("ui_cancel")
	await _wait(20)
	await _shot("graphics_low")
	await _tap("pause")
	await _tap("ui_down")
	await _tap("ui_down")
	await _tap("ui_accept")
	await _tap("ui_down")
	await _tap("ui_right")
	await _tap("ui_right")
	_check(Settings.get_value("graphics") == 2 and game.get_viewport().scaling_3d_scale == 1.0, "graphics high again")
	# Units row.
	await _tap("ui_down")
	await _tap("ui_right")
	_check(game.hud.speedometer.use_mph, "units switched to mph")
	await _tap("ui_left")
	# Back to the pause menu, then the controls page.
	await _tap("ui_cancel")
	_check(game.menu.page == "pause", "back returns to the pause menu")
	await _tap("ui_down")
	await _tap("ui_down")
	await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(5)
	_check(game.menu.page == "controls", "controls page")
	await _shot("menu_controls")
	await _tap("ui_cancel")
	await _tap("ui_cancel")
	await _wait(5)
	_check(game.state == Game.State.DRIVING and not get_tree().paused, "back twice resumes driving")
	# Records page (with a made-up combo so it has something to show).
	Records.add_combo(4321, "Bus", "BACKFLIP, HUGE AIR 3.1s, PERFECT LANDING")
	await _tap("pause")
	for i in 4:
		await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(5)
	_check(game.menu.page == "records", "records page")
	await _shot("menu_records")
	await _tap("ui_cancel")
	await _tap("ui_cancel")
	await _wait(5)

	# Garage from the pause menu, cancelled, returns to the pause menu.
	await _tap("pause")
	await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(10)
	_check(game.state == Game.State.GARAGE and game.picker.is_open, "garage from the pause menu")
	await _tap("menu_back")
	await _wait(5)
	_check(game.state == Game.State.PAUSED and game.menu.page == "pause", "cancelling the garage returns to the pause menu")
	# Main menu, then garage from the title: picking drives off.
	for i in 5:
		await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(10)
	_check(game.state == Game.State.TITLE and not get_tree().paused, "MAIN MENU goes back to the title screen")
	game.open_garage()
	await _wait(5)
	await _tap("menu_right")
	await _tap("menu_accept")
	await _wait(10)
	_check(game.state == Game.State.DRIVING and game.vehicle.display_name == "Sedan", "garage from the title: picking starts driving")
	# Rumble with no gamepad connected must be harmless.
	game.controller.rumble(1.0, 1.0, 0.2)
	game.vehicle.impact.emit(50000.0, game.vehicle.global_position, Vector3.UP)
	_check(true, "rumble without a gamepad")


## Distance of `v` from the centre of `lane` (m, + = right of it).
func _lane_side(lane: TrafficNetwork.Lane, v: Vehicle, hint: float) -> float:
	var s := lane.project(v.global_position, hint, 30.0)
	var right := lane.dir_at(s).cross(Vector3.UP).normalized()
	return (v.global_position - lane.point_at(s)).dot(right)


## Puts the player car on `lane` at `s`, facing along it, and stops it.
func _park_player(game: Game, lane: TrafficNetwork.Lane, s: float, side := 0.0) -> void:
	var dir := lane.dir_at(s)
	dir.y = 0.0
	var right := dir.normalized().cross(Vector3.UP)
	game.vehicle.teleport(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP),
		lane.point_at(s) + right * side + Vector3.UP * (game.vehicle.ride_height() + 0.1)))


func _lanes(game: Game) -> void:
	var tm := game.traffic
	var cam := game.camera
	tm.set_enabled(false)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(40, 0.8, 330)))
	await _wait(10)

	# 1) A car passes the player parked in its lane (south avenue, northbound).
	var d := tm.spawn_near(VehicleCatalog.scene(1), Vector3(1.8, 0, 292))
	var lane := d.current_lane()
	var ps := d.lane_s() + 26.0
	print("  avenue lane %d length %.0f, car at s=%.0f, player at s=%.0f" % [lane.id, lane.length, d.lane_s(), ps])
	_park_player(game, lane, ps)
	var bumps := [0]
	game.vehicle.impact.connect(func(st: float, _p: Vector3, _n: Vector3) -> void:
		if st > 2000.0:
			bumps[0] += 1)
	var t := 0.0
	var passed := false
	var shot_taken := false
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(d):
			break
		if d.passes > 0 and not shot_taken and d.vehicle.global_position.distance_to(game.vehicle.global_position) < 5.0:
			shot_taken = true
			cam.set_process(false)
			var back := -lane.dir_at(ps)
			cam.global_position = game.vehicle.global_position + back * 14.0 + Vector3.UP * 7.0 + back.cross(Vector3.UP) * 4.0
			cam.look_at(game.vehicle.global_position, Vector3.UP)
			await _shot("lanes_bypass")
			cam.set_process(true)
		var ds := lane.project(d.vehicle.global_position, ps, 40.0)
		if ds > ps + 12.0 and absf(_lane_side(lane, d.vehicle, ds)) < 1.0:
			passed = true
			break
	_check(passed and bumps[0] == 0, "car passes the parked player (%.1fs, %d bumps, state %s, blocker '%s')" % [t, bumps[0], ["DRIVING", "STUNNED", "LOST"][d.state], d.blocker])
	tm._despawn(d)
	await _wait(5)

	# 2) Honk behind a car on a two-lane street: it pulls over and slows.
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(40, 0.8, 330)))
	d = tm.spawn_near(VehicleCatalog.scene(1), Vector3(1.8, 0, 300))
	lane = d.current_lane()
	await _wait(60)
	var follow := func(dd: TrafficDriver) -> void:
		var fwd := -dd.vehicle.global_basis.z
		game.vehicle.global_transform = Transform3D(dd.vehicle.global_basis, dd.vehicle.global_position - fwd * 10.0)
		game.vehicle.linear_velocity = dd.vehicle.linear_velocity
	follow.call(d)
	await get_tree().physics_frame
	var v_before := d.vehicle.forward_speed
	Input.action_press("horn")
	for i in 12:
		follow.call(d)
		await get_tree().physics_frame
	Input.action_release("horn")
	t = 0.0
	var max_side := 0.0
	while t < 3.5:
		follow.call(d)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_side = maxf(max_side, _lane_side(lane, d.vehicle, d.lane_s()))
	_check(max_side > 1.0 and d.vehicle.forward_speed < 6.0,
		"honk: car pulls over %.1f m and slows %.0f -> %.0f km/h" % [max_side, v_before * 3.6, d.vehicle.forward_speed * 3.6])
	await _shot("lanes_pull_over")
	tm._despawn(d)
	await _wait(5)

	# 3) Honk behind a car in the middle highway lane: it moves right.
	var hw_lane: TrafficNetwork.Lane = null
	for l in tm.network.lanes:
		if l.closed and l.lane_count == 3 and l.index == 1 and not l.reverse:
			hw_lane = l
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(290, 0.8, -60)))
	await _wait(5)
	d = tm.spawn_near(VehicleCatalog.scene(2), hw_lane.point_at(120.0))
	await _wait(120)
	var lc_before := d.lane_changes
	var middle := d.current_lane()
	follow.call(d)
	Input.action_press("horn")
	for i in 12:
		follow.call(d)
		await get_tree().physics_frame
	Input.action_release("horn")
	for i in 120:
		follow.call(d)
		await get_tree().physics_frame
	_check(d.lane_changes > lc_before and d.current_lane().id == middle.right_id,
		"honk on the highway: car moves a lane right (lane %d -> %d)" % [middle.id, d.current_lane().id])
	tm._despawn(d)

	# 4) Highway traffic for 90 s: lane changes happen, nobody crashes or gets lost.
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(290, 0.8, -60)))
	tm.set_enabled(true)
	await _wait(30)
	var crashes := [0]
	var lost := 0
	var watched := {}
	var total_changes := 0
	t = 0.0
	var next_shot := 20.0
	while t < 90.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var on_highway := 0
		for dr: TrafficDriver in tm.drivers:
			if not watched.has(dr):
				watched[dr] = dr.lane_changes
				dr.vehicle.impact.connect(func(st: float, _p: Vector3, _n: Vector3) -> void:
					if st > 9000.0:
						crashes[0] += 1)
			total_changes += dr.lane_changes - int(watched[dr])
			watched[dr] = dr.lane_changes
			if dr.current_lane() and dr.current_lane().lane_count == 3:
				on_highway += 1
			if dr.state == TrafficDriver.State.LOST and not dr.has_meta("counted"):
				dr.set_meta("counted", true)
				lost += 1
				print("  LOST %s at %s: %s" % [dr.vehicle.display_name, dr.vehicle.global_position.round(), dr.lost_reason])
				await _photo_vehicle(game, dr.vehicle, "lanes_lost_%d" % lost)
		if int(t * 120.0) % 1200 == 0:
			print("  t=%.0f highway cars %d, lane changes so far %d" % [t, on_highway, total_changes])
		if t > next_shot:
			next_shot += 25.0
			# Film a car that's changing lanes right now, if any.
			for dr: TrafficDriver in tm.drivers:
				if absf(dr._lc_offset) > 1.5 and dr.vehicle.global_position.distance_to(game.vehicle.global_position) < 250.0:
					await _photo_vehicle(game, dr.vehicle, "lanes_change_%d" % int(t))
					break
	print("  highway 90 s: %d cars seen, %d lane changes, %d crash impacts, %d lost" % [watched.size(), total_changes, crashes[0], lost])
	_check(total_changes >= 3 and crashes[0] == 0 and lost == 0, "highway lane changes without crashes")


func _junction(game: Game) -> void:
	var tm := game.traffic
	var cam := game.camera
	var p := Vector3(MapLayout.HIGHWAY_HALF_EXTENT, 0, 0)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, p + Vector3(32, 0.8, 30)))
	await _wait(60)
	# Which junction connectors get used.
	var moves := {}
	for lane in tm.network.lanes:
		if lane.connector and lane.points[0].distance_to(p) < 40.0:
			var a := lane.dir_at(0.0)
			var b := lane.dir_at(lane.length)
			var kind: String = ["straight", "right", "left", "uturn"][TrafficNetwork._turn_kind(a, b)]
			var from_hwy := absf(a.z) > absf(a.x)
			moves[lane.id] = ("highway " if from_hwy else "avenue ") + kind
	var used := {}
	var seen_on := {}
	var crashes := [0]
	var lost := 0
	var t := 0.0
	var feed := 0.0
	var shot_i := 0
	cam.set_process(false)
	while t < 150.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		feed -= dt
		if feed <= 0.0:
			feed = 6.0
			# Keep cars coming from both avenues towards the junction.
			var hl := TrafficNetwork.HIGHWAY_OFFSETS
			for q in [p + Vector3(-45, 0, 1.8), p + Vector3(45, 0, -1.8),
					p + Vector3(-hl[2], 0, -80), p + Vector3(hl[2], 0, 80),
					p + Vector3(-hl[0], 0, -90), p + Vector3(hl[0], 0, 90)]:
				var clear := true
				for v in tm.vehicles:
					if is_instance_valid(v) and v.global_position.distance_to(q) < 14.0:
						clear = false
				if clear:
					var d := tm.spawn_near(tm.car_scenes[tm._rng.randi() % 3], q)
					if d:
						d.vehicle.impact.connect(func(st: float, _p: Vector3, _n: Vector3) -> void:
							if st > 9000.0:
								crashes[0] += 1)
		for d: TrafficDriver in tm.drivers:
			var lane := d.current_lane()
			if lane and moves.has(lane.id):
				if seen_on.get(d) != lane.id:
					seen_on[d] = lane.id
					used[moves[lane.id]] = used.get(moves[lane.id], 0) + 1
			if d.state == TrafficDriver.State.LOST and not d.has_meta("counted") and d.vehicle.global_position.distance_to(p) < 80.0:
				d.set_meta("counted", true)
				lost += 1
				print("  LOST %s at %s: %s" % [d.vehicle.display_name, d.vehicle.global_position.round(), d.lost_reason])
		if t > 20.0 + shot_i * 40.0:
			cam.global_position = p + Vector3(-40, 45, 40)
			cam.look_at(p, Vector3.UP)
			await _shot("junction_aerial_%d" % shot_i)
			cam.global_position = p + Vector3(-36, 4, 14)
			cam.look_at(p + Vector3(0, 1, -4), Vector3.UP)
			await _shot("junction_street_%d" % shot_i)
			shot_i += 1
	cam.set_process(true)
	var keys := used.keys()
	keys.sort()
	for k in keys:
		print("  %-18s %d" % [k, used[k]])
	print("  junction 150 s: %d crash impacts, %d lost nearby" % [crashes[0], lost])
	_check(used.size() >= 5 and crashes[0] == 0 and lost == 0, "junction: %d kinds of moves, no crashes or jams" % used.size())


## Each traffic vehicle laps part of the highway with forced lane changes,
## logging the worst body roll (looking for cars that tip over on their own).
func _corner(game: Game) -> void:
	var tm := game.traffic
	tm.set_enabled(false)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-20, 0.8, -20)))
	var lane0: TrafficNetwork.Lane = null
	for l in tm.network.lanes:
		if l.closed and l.lane_count == 3 and l.index == 0 and not l.reverse:
			lane0 = l
	for scene in tm.car_scenes:
		var start := lane0.point_at(lane0.closest_distance(Vector3(250, 0, 60)))
		var d := tm.spawn_near(scene, start)
		var v := d.vehicle
		var t := 0.0
		var worst_up := 1.0
		var worst_t := 0.0
		var max_speed := 0.0
		var flips := 0
		var next_change := 3.0
		while t < 40.0 and is_instance_valid(d):
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			game.vehicle.global_position = v.global_position + Vector3(0, 30, 0)  # keep it "near the player"
			game.vehicle.linear_velocity = Vector3.ZERO
			if v.global_basis.y.y < worst_up:
				worst_up = v.global_basis.y.y
				worst_t = t
			max_speed = maxf(max_speed, v.speed_kmh)
			if d.state == TrafficDriver.State.LOST:
				flips += 1
				print("    LOST at t=%.1f: %s (speed %.0f, lane %d, lc_offset %.1f)" % [t, d.lost_reason, v.speed_kmh, d.current_lane().id, d._lc_offset])
				break
			if t > next_change:
				next_change += 4.0
				d._lc_cooldown = 0.0
				if not d._change_lane(1, false):
					d._change_lane(-1, false)
		print("  %-15s worst up.y %.2f at t=%.1f, max %.0f km/h, lane changes %d%s" % [v.display_name, worst_up, worst_t, max_speed,
			d.lane_changes if is_instance_valid(d) else -1, " LOST" if flips else ""])
		if is_instance_valid(d):
			tm._despawn(d)
		await _wait(5)


## Drops the player car from `height` m over open ground (optionally upside down).
func _drop(game: Game, height: float, upside_down := false) -> void:
	var sp: Transform3D = game.world.spawn_points[4]["xform"]
	var b := sp.basis
	if upside_down:
		b = b.rotated(b.z, PI)
	game.vehicle.teleport(Transform3D(b, sp.origin + Vector3.UP * height))


## Holds `keys` until the stunt tracker's accumulated rotation on `axis`
## reaches `target` radians, then lets go (the car stops rotating by itself).
func _air_trick(game: Game, keys: Array, axis: int, target: float) -> void:
	var st := game.stunts
	for k in keys:
		Input.action_press(k)
	var t := 0.0
	while absf(st._rot[axis]) < target and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for k in keys:
		Input.action_release(k)


## Waits `seconds` of game (physics) time.
func _wait_s(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _wait_landed(game: Game) -> void:
	await _wait_s(0.2)  # get airborne first
	var t := 0.0
	while (game.vehicle.airtime > 0.0 or game.stunts._landing_check >= 0.0) and t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _wait(5)


func _stunts(game: Game) -> void:
	var st := game.stunts
	var tm := game.traffic
	tm.set_enabled(false)
	await _wait(10)
	var tricks: Array[String] = []
	var lost: Array[String] = []
	var banked: Array[int] = []
	st.trick.connect(func(n: String, _p: int) -> void: tricks.append(n))
	st.combo_lost.connect(func(r: String) -> void: lost.append(r))
	st.combo_banked.connect(func(p: int, _pl: int) -> void: banked.append(p))
	var has := func(prefix: String) -> bool:
		for n in tricks:
			if n.begins_with(prefix):
				return true
		return false

	# 1) Big air, no input: lands level by itself.
	_drop(game, 26.0)
	await _wait_landed(game)
	_check(has.call("BIG AIR") and has.call("PERFECT LANDING"), "big air + perfect landing (%s)" % ", ".join(tricks))

	# 2) Backflip: Space + S, then Space + W to stop the rotation.
	tricks.clear()
	_drop(game, 45.0)
	await _wait_s(0.3)
	await _air_trick(game, ["handbrake", "brake"], 0, TAU - 1.0)
	await _shot("stunt_backflip_air")
	await _wait_landed(game)
	_check(has.call("BACKFLIP"), "backflip (%s; lost %s)" % [", ".join(tricks), lost])

	# 3) Barrel roll: Space + D, then Space + A.
	tricks.clear()
	_drop(game, 45.0)
	await _wait_s(0.3)
	await _air_trick(game, ["handbrake", "steer_right"], 2, TAU - 1.0)
	await _wait_landed(game)
	_check(has.call("BARREL ROLL"), "barrel roll (%s; lost %s)" % [", ".join(tricks), lost])

	# 4) Spin: steering alone in the air.
	tricks.clear()
	_drop(game, 40.0)
	await _wait_s(0.3)
	await _air_trick(game, ["steer_left"], 1, PI - 0.4)
	await _wait_landed(game)
	_check(has.call("180 SPIN") or has.call("360 SPIN"), "air spin (%s)" % ", ".join(tricks))
	await _shot("stunt_combo")

	# Combo banks after a few quiet seconds.
	var before := st.score
	await _wait_s(4.0)
	_check(st.score > before and not banked.is_empty() and not Records.best_combos.is_empty(),
		"combo banked: +%d, best combo %d" % [st.score - before, Records.best_combos[0]["points"] if not Records.best_combos.is_empty() else 0])

	# 5) Wipeout: land on the roof after some air.
	tricks.clear()
	lost.clear()
	# (a trick first, so there's a combo to lose)
	_drop(game, 40.0)
	await _wait_s(0.3)
	await _air_trick(game, ["steer_left"], 1, PI - 0.4)
	await _wait_landed(game)
	_drop(game, 26.0)
	await _wait_s(1.2)
	game.vehicle.global_basis = game.vehicle.global_basis.rotated(game.vehicle.global_basis.z, PI)
	await _wait_s(4.0)
	_check(lost.has("WIPEOUT!"), "upside-down landing is a wipeout (%s)" % str(lost))
	game.vehicle.reset_upright()
	await _wait_s(2.0)

	# 6) Drift: handbrake turn at speed on the flat dirt.
	tricks.clear()
	var sp: Transform3D = game.world.spawn_points[4]["xform"]
	game.vehicle.teleport(sp)
	await _wait(30)
	Input.action_press("accelerate")
	var t := 0.0
	while game.vehicle.speed_kmh < 70.0 and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_press("steer_left")
	Input.action_press("handbrake")
	await _wait_s(0.5)
	Input.action_release("handbrake")
	t = 0.0
	while t < 3.0 and not has.call("DRIFT"):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		# Hold the slide: countersteer a little, keep the throttle on.
		if game.stunts._drift_time > 0.5:
			Input.action_release("steer_left")
	_release()
	await _wait_s(1.5)
	_check(has.call("DRIFT"), "drift (%s, best drift %.1fs)" % [", ".join(tricks), Records.best_drift])

	# 8) Steering all the way through a real ramp jump (what kids do) still
	#    lands on the wheels.
	for steer in ["steer_left", "steer_right"]:
		var ramp_sp: Transform3D = game.world.spawn_points[2]["xform"]
		game.vehicle.teleport(ramp_sp)
		await _wait_s(0.5)
		var max_air := 0.0
		var worst_up := 1.0
		t = 0.0
		Input.action_press("accelerate")
		while t < 12.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var v := game.vehicle
			max_air = maxf(max_air, v.airtime)
			if v.airtime > 0.1:
				Input.action_press(steer)
			else:
				Input.action_release(steer)
			if v.speed_kmh > 70.0:
				Input.action_release("accelerate")
			if t > 2.0:
				worst_up = minf(worst_up, v.global_basis.y.y)
		_release()
		_check(worst_up > 0.3, "%s held through park jumps: upright (worst up %.2f, max air %.1fs)" % [steer, worst_up, max_air])
	game.vehicle.teleport(game.world.spawn_points[4]["xform"])
	await _wait_s(1.0)

	# 7) Near miss: squeeze past an oncoming traffic car on a city street.
	tricks.clear()
	var d := tm.spawn_near(VehicleCatalog.scene(1), Vector3(-1.8, 0, 230))
	var lane := d.current_lane()
	var ps := d.lane_s() + 60.0
	var dir := -lane.dir_at(ps)
	dir.y = 0.0
	var right := dir.normalized().cross(Vector3.UP)
	# Player drives the other way, hugging the centre line.
	game.vehicle.teleport(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP),
		lane.point_at(ps) + right * (-3.6 + 1.3) + Vector3.UP * 0.6))
	await _wait(5)
	t = 0.0
	while t < 6.0 and not has.call("NEAR MISS"):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var v := game.vehicle
		Input.action_press("accelerate") if v.speed_kmh < 50.0 else Input.action_release("accelerate")
		var local := v.global_basis.inverse() * (v.global_position + dir * 20.0 - v.global_position)
		var side := (v.global_position - lane.point_at(ps)).dot(right) - (-3.6 + 1.3)
		_set_axis(clampf(-side * 0.4, -0.3, 0.3))
	_release()
	await _wait(30)
	_check(has.call("NEAR MISS"), "near miss (%s, total %d)" % [", ".join(tricks), Records.near_misses])
