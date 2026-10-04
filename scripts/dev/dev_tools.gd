extends Node
## Developer helpers, inactive during normal play.
##   --tour=<dir>     save screenshots from a set of viewpoints, then quit
##   --drive=<dir>    drive the player car with scripted input, snapping shots
##   --garage=<dir>   garage menu, customising, changing into every vehicle (checks and shots)
##   --onfoot=<dir>   the player character: walking, getting in and out of every kind of
##                    vehicle, traffic and parked cars, exits by walls, damage, the garage,
##                    teleports, being bumped by a car, leak check (checks and shots)
##   --onfootbench    cost of the character: draw calls / CPU / GPU with it shown and
##                    hidden, physics time with and without it, walking (window)
##   --charsheet=<dir> the character from fixed cameras (front, 3/4, side, game camera,
##                    face) in day / sunset / night, plus each animation sampled over time
##   --perfsweep=<dir> GPU cost of each High-only effect, Medium/Low, grass and trees, in heavy
##                    views and while driving (run it on a weak GPU: --gpu-index 0 = the iGPU)
##   --wheels=<dir>   every rim, rim colour, tyre and tyre stripe in the garage's wheel view,
##                    plus custom wheels on a few vehicles and on the road (shots for review)
##   --menus=<dir>    title/pause/settings/controls menus driven by input (checks and shots)
##   --lanes=<dir>    traffic passing a parked player, horn reactions, highway lane changes
##   --junction=<dir> the signalized highway/avenue junction: turns used, crashes, jams
##   --stunts=<dir>   air, flips, rolls, spins, drift, near miss, wipeout -> combos and records
##   --map=<dir>      minimap and big map screenshots
##   --races=<dir>    an autopilot drives every race (times -> medal reference), checks the flow
##   --park=<dir>     loop-the-loop and wall-ride bowl driven by an autopilot
##   --trail=<dir>    drive the mountain trail to the summit
##   --landmarks=<dir> drive through the tunnel, over the bridge, down the runway (+ shots)
##   --night=<dir>    sunset / night / cycle: lights switch, screenshots
##   --damage=<dir>   crash tests: parts falling off, broken lights/glass, pull, repair
##   --replay=<dir>   pausing freezes everything, instant replay, slow-motion crash cam
##   --megakit=<dir>  the Downtown City MegaKit experiment: every building has
##                    collision, a far proxy and an occluder; facades are where
##                    their colliders are; a car driven into a facade stops and
##                    dents; the chase camera stays out of the buildings; the
##                    character can't walk into them (checks and shots)
##   --scenery=<dir>  fixed views of the city and the north bridge at day /
##                    sunset / night and Low / High, plus draw calls, primitives
##                    and GPU time per view (--views=a,b limits the views,
##                    --quick shoots day on High only, --profile hides one family
##                    of meshes at a time and prints what it cost, --stress
##                    renders at 2x resolution so fill costs dominate,
##                    --traffic-on keeps traffic running for the shots)
## Add --graphics=<0-3> (low, medium, high, ultra) to run any of them at that quality.
## Example:
##   godot --path . -- --tour=/tmp/shots

var _dir := ""
var _mode := ""
## --vehicle=<catalog id>: start the test in that vehicle (e.g. --damage on the bus).
var _vehicle_id := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicle=") and not arg.contains("res://"):
			_vehicle_id = arg.split("=")[1]
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
		elif arg == "--spawncheck":
			_mode = "spawncheck"
			_dir = OS.get_user_data_dir()
		elif arg.begins_with("--damage="):
			_mode = "damage"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--replay="):
			_mode = "replay"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--night="):
			_mode = "night"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--landmarks="):
			_mode = "landmarks"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--trail="):
			_mode = "trail"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--park="):
			_mode = "park"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--races="):
			_mode = "races"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--map="):
			_mode = "map"
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
		elif arg.begins_with("--onfoot="):
			_mode = "onfoot"
			_dir = arg.split("=")[1]
		elif arg == "--onfootbench":
			_mode = "onfootbench"
			_dir = OS.get_user_data_dir()
		elif arg.begins_with("--charsheet="):
			_mode = "charsheet"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--wheels="):
			_mode = "wheels"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--perfsweep="):
			_mode = "perfsweep"
			_dir = arg.split("=")[1]
		elif arg == "--bench":
			_mode = "bench"
			_dir = OS.get_user_data_dir()
		elif arg.begins_with("--fx="):
			_mode = "fx"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--scenery="):
			_mode = "scenery"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--megakit="):
			_mode = "megakit"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--lookdev="):
			_mode = "lookdev"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--audio="):
			_mode = "audio"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--mixpanel="):
			_mode = "mixpanel"
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
		VehicleAudio.quit_quietly(get_tree())
		return
	# Automatic crash cams would pause the other tests mid-crash.
	Settings.set_value("crash_cam", _mode == "replay")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--graphics="):
			Settings.set_value("graphics", clampi(int(arg.split("=")[1]), 0, 3))
	if _vehicle_id != "":
		var vi := VehicleCatalog.index_of_id(_vehicle_id)
		if vi < 0:
			push_error("dev tools: unknown vehicle id '%s'" % _vehicle_id)
		else:
			game.change_vehicle(vi, null, false)
			await _wait(30)
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
	elif _mode == "onfoot":
		await _onfoot(game)
	elif _mode == "onfootbench":
		await _onfootbench(game)
	elif _mode == "charsheet":
		await _charsheet(game)
	elif _mode == "wheels":
		await _wheels(game)
	elif _mode == "perfsweep":
		await _perfsweep(game)
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
	elif _mode == "map":
		await _map(game)
	elif _mode == "races":
		await _races(game)
	elif _mode == "park":
		await _park(game)
	elif _mode == "trail":
		await _trail(game)
	elif _mode == "landmarks":
		await _landmarks(game)
	elif _mode == "night":
		await _night(game)
	elif _mode == "damage":
		await _damage(game)
	elif _mode == "replay":
		await _replay(game)
	elif _mode == "spawncheck":
		await _spawncheck(game)
	elif _mode == "scenery":
		await _scenery(game)
	elif _mode == "megakit":
		await _megakit(game)
	elif _mode == "lookdev":
		await _lookdev(game)
	elif _mode == "audio":
		await _audio(game)
	elif _mode == "mixpanel":
		await _mixpanel(game)
	else:
		await _drive(game)
	VehicleAudio.quit_quietly(get_tree())


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
				_on_driver_impact(d, func(dd: TrafficDriver, st: float, p: Vector3) -> void:
					if st > 9000.0:
						impacts[0] += 1
						if true:
							var other := ""
							for o in tm.vehicles:
								if is_instance_valid(o) and o != dd.vehicle and o.global_position.distance_to(dd.vehicle.global_position) < 7.0:
									var od := tm.driver_of(o)
									other += " %s(%.0fkmh%s)" % [o.display_name, o.speed_kmh, (" lc%.1f" % od._lc_offset) if od else " player"]
							print("  CRASH %.0f %s at %s %.0fkmh lane %d lc %.1f blocker '%s' near:%s" % [st, dd.vehicle.display_name,
								p.round(), dd.vehicle.speed_kmh, dd.current_lane().id if dd.current_lane() else -1, dd._lc_offset, dd.blocker, other]))
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
		(d.vehicle.get_node("Effects") as Node).set_physics_process(false)
		(d.vehicle.get_node("Body") as Node).set_physics_process(false)
		(d.vehicle.get_node("Damage") as Node).set_physics_process(false)
	await _measure("18 cars, effects/body/damage off", 5.0)
	for d in tm.drivers:
		d.vehicle.set_physics_process(false)
	await _measure("18 cars, all scripts off", 5.0)
	await _bench_spawns(game)
	await _bench_render(game)
	await _bench_drive(game)


## Draw calls and render time from the chase camera on the highway, with and
## without traffic.
func _bench_render(game: Game) -> void:
	if DisplayServer.get_name() == "headless":
		return  # nothing is drawn
	var tm := game.traffic
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for on in [false, true]:
		tm.set_enabled(on)
		game.teleport_to(1)
		await _wait_s(4.0)
		var calls := 0
		var objs := 0
		var gpu := 0.0
		var cpu := 0.0
		for k in 120:
			await RenderingServer.frame_post_draw
			calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
		print("BENCH render traffic %-5s %d cars: %d draw calls, %d objects, gpu %.2f ms, cpu %.2f ms" % [
			str(on), tm.drivers.size(), calls / 120, objs / 120, gpu / 120.0, cpu / 120.0])


## Wall-clock cost of putting one traffic car on the road (and removing it).
func _bench_spawns(game: Game) -> void:
	var tm := game.traffic
	tm.set_enabled(false)
	await _wait(10)
	var probe := tm.spawn_near(tm.car_scenes[1], Vector3(-60, 0, 120))
	var lane: TrafficNetwork.Lane = probe._plan[0]["lane"]
	var s: float = probe._s
	tm._despawn(probe)
	await _wait(5)
	for scene in tm.car_scenes:
		var times: Array[float] = []
		for k in 4:
			var t0 := Time.get_ticks_usec()
			var d := tm._spawn(lane, s, scene)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			await _wait(3)
			var t1 := Time.get_ticks_usec()
			tm._despawn(d)
			times.append((Time.get_ticks_usec() - t1) / 1000.0)
			await _wait(3)
		print("BENCH spawn %-14s first %.2f ms, then %.2f / %.2f / %.2f ms (despawn %.2f ms)" % [
			scene.resource_path.get_file().get_basename(), times[0], times[2], times[4], times[6], times[3]])
	# Where the time goes, for one type.
	for k in 3:
		var t0 := Time.get_ticks_usec()
		var car := tm.car_scenes[1].instantiate() as Vehicle
		var t1 := Time.get_ticks_usec()
		var dmg := car.get_node("Damage")
		car.remove_child(dmg)
		tm.add_child(car)
		var t2 := Time.get_ticks_usec()
		car.add_child(dmg)
		var t3 := Time.get_ticks_usec()
		dmg.repair()
		var t4 := Time.get_ticks_usec()
		print("BENCH   instantiate %.2f, add (no damage) %.2f, damage _ready %.2f, repair %.2f ms" % [
			(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
		car.queue_free()
		await _wait(3)


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


## Calls `cb(driver, strength, position)` on impacts of `d`'s car while `d`
## still drives it (traffic cars are reused by other drivers later).
func _on_driver_impact(d: TrafficDriver, cb: Callable) -> void:
	var id := d.get_instance_id()
	var car := d.vehicle
	car.impact.connect(func(st: float, p: Vector3, _n: Vector3) -> void:
		var dd := instance_from_id(id) as TrafficDriver
		if dd != null and dd.vehicle == car:
			cb.call(dd, st, p))


## Presses and releases a gamepad button the way a real controller does
## (a joypad event, not an action), so the bindings themselves are tested.
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = pressed
		ev.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)
		await _wait(3)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


## Player and every system that follows it agree on which vehicle is driven.
func _check_wiring(game: Game, label: String) -> void:
	var v := game.vehicle
	var players := 0
	for child in game.get_children():
		if child is Vehicle and not game.left_vehicles.has(child):
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
	var p := game.picker
	await _tap("change_vehicle")
	await _wait(20)
	_check(p.is_open and get_tree().paused and p.tab == 0, "V opens the garage on the CAR tab and pauses")
	await _shot("garage_0")
	for i in 4:
		await _tap("menu_right")
		await _wait(15)
		await _shot("garage_%d" % (i + 1))
	_check(p.index == 4, "four steps right reach the bus")
	await _tap("menu_tab_next")
	_check(p.tab == 1, "Q/E (LB/RB) switch to the PAINT tab")
	for i in 3:
		await _tap("menu_right")
	await _wait(10)
	await _shot("garage_paint")
	var want_color: Color = p.loadout().get_value("paint")
	_check(want_color != Loadout.stock("bus").get_value("paint"), "left/right repaints the bus")
	await _tap("menu_tab_next")
	await _wait(40)
	_check(p.tab == 2, "next tab: WHEELS")
	await _shot("garage_wheels")
	await _tap("menu_right")  # rims: the next one after the bus's steelies
	var want_rims: String = p.loadout().get_value("rims")
	await _tap("menu_down")
	for i in 6:
		await _tap("menu_right")  # rim colour: stock -> gold
	await _tap("menu_down")
	await _tap("menu_right")  # tyres: heavy duty (the last) -> wraps to the first
	await _tap("menu_down")
	await _tap("menu_right")  # tyre stripe: none -> white wall
	await _wait(20)
	await _shot("garage_wheels_custom")
	var l := p.loadout()
	_check(want_rims != "steel" and l.get_value("rim_color") == "gold" and l.get_value("tyres") == PartsCatalog.TYRES[0]["id"]
		and l.get_value("tyre_stripe") == "whitewall", "up/down + left/right set rims, rim colour, tyres and stripe %s" % l.overrides())
	_check(WheelKit.is_fitted(p._car), "the turntable bus wears the new wheels")
	await _tap("menu_accept")
	await _wait(10)
	_check(not p.is_open and not get_tree().paused, "accept closes the garage and unpauses")
	_check(not is_instance_valid(old), "old car is freed")
	_check(game.vehicle.display_name == "Bus", "now driving the %s" % game.vehicle.display_name)
	_check((game.vehicle.get_node("Body") as VehicleBodyVisual).paint_color == want_color, "paint colour applied")
	_check_wheels(game.vehicle, want_rims, "gold", PartsCatalog.TYRES[0]["id"], "bus")
	_check(Loadout.saved("bus").values == game.loadout.values, "the bus setup is saved")
	_check_wiring(game, "after garage")
	await _wait(60)
	_check(game.vehicle.global_basis.y.y > 0.95 and game.vehicle.linear_velocity.length() < 2.0,
		"bus settles calmly (up %.2f, speed %.1f)" % [game.vehicle.global_basis.y.y, game.vehicle.linear_velocity.length()])

	# Backing out never swaps the vehicle, but keeps changes made to it.
	var bus := game.vehicle
	await _tap("change_vehicle")
	await _wait(5)
	await _tap("menu_left")
	await _tap("menu_back")
	await _wait(5)
	_check(game.vehicle == bus and not get_tree().paused and not p.is_open, "Esc/B backs out without changing")
	await _tap("change_vehicle")
	await _wait(5)
	await _tap("menu_tab_prev")
	_check(p.tab == 2, "tabs wrap round (CAR -> WHEELS)")
	await _tap("menu_right")
	var kept: String = p.loadout().get_value("rims")
	await _tap("menu_back")
	await _wait(5)
	var fl_rim := bus.get_node_or_null("WheelFL/Visual/Model/Rim") as Node3D
	_check(game.vehicle == bus and game.loadout.get_value("rims") == kept and fl_rim != null
		and fl_rim.scene_file_path == PartsCatalog.rim_scene(kept), "backing out keeps the new rims on the bus (%s)" % kept)
	# Calipers only behind open rims.
	game.loadout.set_value("rims", "dish")
	game.loadout.apply(bus)
	_check(bus.get_node_or_null("WheelFL/Caliper") == null, "closed rims: no caliper")
	game.loadout.set_value("rims", "sport5")
	game.loadout.apply(bus)
	_check(bus.get_node_or_null("WheelFL/Caliper") != null, "open rims: caliper on")
	# Surprise me, on the WHEELS tab.
	await _tap("change_vehicle")
	await _wait(5)
	await _tap("menu_tab_prev")
	var before := p.loadout().values.duplicate()
	await _tap("menu_extra")
	await _tap("menu_extra")
	_check(p.loadout().values != before, "X / (Y) surprises with a new wheel setup")
	await _tap("menu_back")
	await _wait(5)

	# 2) Drive every vehicle for a bit and photograph the cameras.
	for i in VehicleCatalog.count():
		game.teleport_to(0)
		await _wait(10)
		game.change_vehicle(i, _painted(i, VehicleCatalog.COLORS[(i * 3) % VehicleCatalog.COLORS.size()]))
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
	game.change_vehicle(0, _painted(0, Color.RED))
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
	game.change_vehicle(4, _painted(4, Color.YELLOW))
	var sp: Transform3D = game.world.spawn_points[game.spawn_index]["xform"]
	_check(game.vehicle.global_position.distance_to(sp.origin) < 3.0, "blocked spot: bus goes to the spawn point instead")
	wall.queue_free()

	# 4) A traffic car in the way is removed instead.
	tm.set_enabled(false)
	await _wait(5)
	game.change_vehicle(0, _painted(0, Color.RED))
	var d := tm.spawn_near(VehicleCatalog.scene(1), Vector3(-1.8, 0, 200))
	await _wait(30)
	var tv := d.vehicle
	var lane_fwd := -tv.global_basis.z
	game.vehicle.teleport(Transform3D(tv.global_basis, tv.global_position + lane_fwd * 6.0 + Vector3.UP * 0.3))
	d.set_physics_process(false)
	tv.linear_velocity = Vector3.ZERO
	await _wait(30)
	var here := game.vehicle.global_position
	game.change_vehicle(4, _painted(4, Color.YELLOW))
	await _wait(5)
	# Removed = freed, or put back in the traffic pool (out of the tree).
	_check(not is_instance_valid(tv) or tv.is_queued_for_deletion() or (not tv.is_inside_tree() and not tm.vehicles.has(tv)),
		"traffic car overlapping the bus was removed")
	_check(game.vehicle.global_position.distance_to(here) < 1.5, "bus placed where the car was")
	await _wait(60)
	_check(game.vehicle.linear_velocity.length() < 2.0, "no physics explosion (speed %.1f)" % game.vehicle.linear_velocity.length())

	# 5) The choice and each vehicle's setup are saved to disk and restored.
	Settings.persist = true
	Settings.path = _dir.path_join("settings_test.cfg")
	var van := Loadout.stock("van")
	van.set_value("paint", VehicleCatalog.COLORS[6])
	van.set_value("rims", "turbine")
	van.set_value("rim_color", "chrome")
	van.save()
	game._save_choice(2)
	Settings.persist = false
	Settings.set_value("vehicle", "sports_car")  # in memory only
	Settings.set_value("loadouts", {})
	game.change_vehicle(0)
	Settings.load_file()
	game._load_choice()
	game.teleport_to(0)
	await _wait(10)
	_check(game.vehicle.display_name == "Van" and (game.vehicle.get_node("Body") as VehicleBodyVisual).paint_color == VehicleCatalog.COLORS[6],
		"saved choice (purple van) restored")
	_check_wheels(game.vehicle, "turbine", "chrome", "heavy", "restored van")
	_check(Loadout.saved("sedan").overrides().is_empty(), "other vehicles stay stock")
	_check_wiring(game, "after load")
	# A settings file from before the Settings autoload ([player] section).
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("player", "vehicle", "box_truck")
	old_cfg.set_value("player", "paint", VehicleCatalog.COLORS[3])
	old_cfg.save(Settings.path)
	Settings.load_file()
	_check(Settings.get_value("vehicle") == "box_truck" and Loadout.saved("box_truck").get_value("paint") == VehicleCatalog.COLORS[3],
		"old garage settings file migrated")
	# One from before per-vehicle setups (0.6.x: one paint + stripes).
	var v06 := ConfigFile.new()
	v06.set_value("settings", "vehicle", "sports_car")
	v06.set_value("settings", "paint", VehicleCatalog.COLORS[5])
	v06.set_value("settings", "stripes", true)
	v06.save(Settings.path)
	Settings.load_file()
	var sc := Loadout.saved("sports_car")
	_check(sc.get_value("paint") == VehicleCatalog.COLORS[5] and sc.get_value("stripes") == true and sc.wheels_stock(),
		"0.6 paint and stripes became the sports car's setup")


## A stock setup for catalog entry `index` in paint `c` (snapped to the
## garage colours).
func _painted(index: int, c: Color) -> Loadout:
	var l := Loadout.stock(VehicleCatalog.ENTRIES[index]["id"])
	l.set_value("paint", c)
	return l


## `v` wears garage wheels: the rim and tyre models, the rim finish, a
## caliper exactly on open rims, the car's own tyre material, the wheel layer.
func _check_wheels(v: Vehicle, rims: String, finish: String, tyres: String, label: String) -> void:
	var problems: Array[String] = []
	var body := v.get_node("Body") as VehicleBodyVisual
	var open: bool = PartsCatalog.option("rims", rims)["open"]
	for w in v.wheels:
		var rim := w.get_node_or_null("Visual/Model/Rim") as Node3D
		var tyre := w.get_node_or_null("Visual/Model/Tyre") as Node3D
		if rim == null or tyre == null or rim.scene_file_path != PartsCatalog.rim_scene(rims) or tyre.scene_file_path != PartsCatalog.tyre_scene(tyres):
			problems.append("%s parts" % w.name)
			continue
		if (w.get_node_or_null("Caliper") != null) != open:
			problems.append("%s caliper" % w.name)
		for gi in w.find_children("*", "GeometryInstance3D", true, false):
			if (gi as GeometryInstance3D).layers != Vehicle.WHEEL_LAYER:
				problems.append("%s layer" % w.name)
				break
		var meshes := rim.find_children("*", "MeshInstance3D", true, false) + tyre.find_children("*", "MeshInstance3D", true, false)
		for node in meshes:
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				match String(mi.mesh.surface_get_material(i).resource_name):
					"Rim":
						var want: Color = PartsCatalog.option("rim_color", finish).get("color", Color.BLACK)
						if finish != "stock" and not (m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color.is_equal_approx(want)):
							problems.append("%s finish" % w.name)
					"Tire":
						if m != body._mats.get("tyre"):
							problems.append("%s tyre material" % w.name)
	_check(problems.is_empty(), "%s wears %s rims (%s) on %s tyres %s" % [label, rims, finish, tyres, ", ".join(problems)])


## Wheel parts gallery for review: every rim, rim colour, tyre and tyre
## stripe in the garage's wheel view, other vehicles with custom wheels, and
## a custom car on the road.
func _wheels(game: Game) -> void:
	game.teleport_to(0)
	await _wait(30)
	game.open_garage()
	await _wait(5)
	var p := game.picker
	p._set_tab(2)
	await _wait(60)
	for i in PartsCatalog.RIMS.size():
		p._set_slot("rims", i)
		await _wait(6)
		await _shot("rim_%02d_%s" % [i, PartsCatalog.RIMS[i]["id"]])
	p._set_slot("rims", 0)
	for i in PartsCatalog.RIM_COLORS.size():
		p._set_slot("rim_color", i)
		await _wait(6)
		await _shot("finish_%02d_%s" % [i, PartsCatalog.RIM_COLORS[i]["id"]])
	p._set_slot("rim_color", 0)
	for i in PartsCatalog.TYRES.size():
		p._set_slot("tyres", i)
		await _wait(6)
		await _shot("tyre_%02d_%s" % [i, PartsCatalog.TYRES[i]["id"]])
	p._set_slot("tyres", 0)
	for i in PartsCatalog.TYRE_STRIPES.size():
		p._set_slot("tyre_stripe", i)
		await _wait(6)
		await _shot("stripe_%02d_%s" % [i, PartsCatalog.TYRE_STRIPES[i]["id"]])
	p._set_slot("tyre_stripe", 0)
	# Other vehicles: their stock wheels, then a custom set.
	var custom := {"sedan": ["star5", "black", "sport"], "van": ["ten", "silver", "road"],
		"pickup": ["twist", "gunmetal", "allterrain"], "monster_truck": ["turbine", "chrome", "offroad"]}
	for id: String in custom:
		p._set_tab(0)
		p.index = VehicleCatalog.index_of_id(id)
		p._show_vehicle()
		p._set_tab(2)
		await _wait(50)
		await _shot("vehicle_%s_stock" % id)
		var parts: Array = custom[id]
		p._set_slot("rims", PartsCatalog.index_of("rims", parts[0]))
		p._set_slot("rim_color", PartsCatalog.index_of("rim_color", parts[1]))
		p._set_slot("tyres", PartsCatalog.index_of("tyres", parts[2]))
		await _wait(6)
		await _shot("vehicle_%s_custom" % id)
	# A custom sports car on the road.
	p._set_tab(0)
	p.index = 0
	p._show_vehicle()
	p._set_slot("rims", PartsCatalog.index_of("rims", "star5"))
	p._set_slot("rim_color", PartsCatalog.index_of("rim_color", "gold"))
	p._set_slot("tyre_stripe", PartsCatalog.index_of("tyre_stripe", "red"))
	p._set_tab(2)
	await _wait(40)
	await _shot("garage_custom_sports")
	await _tap("menu_accept")
	await _wait(20)
	_check_wheels(game.vehicle, "star5", "gold", "sport", "sports car")
	Input.action_press("accelerate")
	await _wait_s(2.5)
	_release()
	await _wait_s(1.0)
	await _shot("road_custom_chase")
	game.camera.mode = ChaseCamera.Mode.FAR
	await _wait(5)
	await _shot("road_custom_far")
	game.camera.mode = ChaseCamera.Mode.CHASE


func _menus(game: Game) -> void:
	var tm := game.traffic
	await _wait(30)
	# With a gamepad only (real joypad events): A presses the focused button,
	# B goes back, Start pauses, the D-pad moves between buttons.
	game._enter_title()
	await _wait(30)
	await _pad(JOY_BUTTON_A)
	await _wait(5)
	_check(game.state == Game.State.DRIVING, "gamepad A on DRIVE! starts the game")
	await _pad(JOY_BUTTON_START)
	await _wait(5)
	_check(game.state == Game.State.PAUSED and game.menu.page == "pause", "gamepad Start opens the pause menu")
	for i in 3:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _wait(5)
	_check(game.menu.page == "settings", "gamepad D-pad down + A opens settings")
	await _pad(JOY_BUTTON_B)
	await _wait(5)
	_check(game.menu.page == "pause", "gamepad B goes back to the pause menu")
	await _pad(JOY_BUTTON_B)
	await _wait(5)
	_check(game.state == Game.State.DRIVING and not get_tree().paused, "gamepad B resumes driving")
	# Garage from the pause menu with the pad: A opens it, B backs out, B resumes.
	await _pad(JOY_BUTTON_START)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _wait(10)
	_check(game.state == Game.State.GARAGE and game.picker.is_open, "gamepad A opens the garage from the pause menu")
	await _pad(JOY_BUTTON_B)
	await _wait(10)
	_check(game.state == Game.State.PAUSED and game.menu.page == "pause", "gamepad B leaves the garage, back to the pause menu")
	await _pad(JOY_BUTTON_B)
	await _wait(5)
	_check(game.state == Game.State.DRIVING, "gamepad B resumes driving again")

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
	for i in 3:
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
	for i in 3:
		await _tap("ui_down")
	await _tap("ui_accept")
	await _tap("ui_down")
	await _tap("ui_right")
	await _tap("ui_right")
	_check(Settings.get_value("graphics") == 2 and game.get_viewport().scaling_3d_scale == 1.0, "graphics high again")
	# Units row (below graphics and time of day).
	await _tap("ui_down")
	await _tap("ui_down")
	await _tap("ui_right")
	_check(game.hud.speedometer.use_mph, "units switched to mph")
	await _tap("ui_left")
	# Back to the pause menu, then the controls page.
	await _tap("ui_cancel")
	_check(game.menu.page == "pause", "back returns to the pause menu")
	for i in 4:
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
	for i in 5:
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
	await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(10)
	_check(game.state == Game.State.GARAGE and game.picker.is_open, "garage from the pause menu")
	await _tap("menu_back")
	await _wait(5)
	_check(game.state == Game.State.PAUSED and game.menu.page == "pause", "cancelling the garage returns to the pause menu")
	# Credits, then main menu, then garage from the title: picking drives off.
	for i in 6:
		await _tap("ui_down")
	await _tap("ui_accept")
	await _wait(5)
	_check(game.menu.page == "credits", "credits page")
	await _tap("ui_cancel")
	await _wait(5)
	# Back on the pause menu, focus is on RESUME again.
	for i in 7:
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
				_on_driver_impact(dr, func(ddr: TrafficDriver, st: float, p: Vector3) -> void:
					if st > 9000.0:
						crashes[0] += 1
						_log_crash(tm, ddr, st, p))
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
						_on_driver_impact(d, func(dd: TrafficDriver, st: float, p: Vector3) -> void:
							if st > 9000.0:
								crashes[0] += 1
								_log_crash(tm, dd, st, p))
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


func _map(game: Game) -> void:
	await _wait(10)
	var img := game.world_map.get_texture().get_image()
	var road := img.get_pixelv(WorldMap.to_uv(Vector3(0, 0, -75)) * WorldMap.SIZE)
	_check(img.get_width() == WorldMap.SIZE and road.v < 0.45, "world map drawn (road pixel %s)" % road)
	img.save_png(_dir.path_join("world_map.png"))
	for i in [0, 1, 2]:
		game.teleport_to(i)
		await _wait_s(1.5)
		game.hud.show_help_for(0.01)
		await _wait(5)
		await _shot("minimap_%d" % i)
	game.hud.toggle_big_map()
	await _wait(5)
	await _shot("big_map")
	game.hud.toggle_big_map()


## Drives the current race along its path: pure pursuit with a speed limit
## from how sharply the path turns ahead. Returns the finish time or -1.
func _autopilot_race(game: Game, max_kmh: float, time_limit: float) -> float:
	var rm := game.race
	var path: Array = rm.race["path"]
	var v := game.vehicle
	var finish := [-1.0]
	var on_finish := func(_r: Dictionary, t: float, _m: int, _b: bool) -> void: finish[0] = t
	rm.finished.connect(on_finish)
	var idx := 0
	var t := 0.0
	var stuck := 0.0
	var respawns := 0
	while finish[0] < 0.0 and t < time_limit and rm.is_active():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var pos := v.global_position
		# Advance along the path.
		while idx < path.size() - 1 and Vector2(path[idx].x - pos.x, path[idx].z - pos.z).length() < 9.0 + v.forward_speed * 0.3:
			idx += 1
		var target: Vector3 = path[idx]
		var local := v.global_basis.inverse() * (target - pos)
		_set_axis(clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0))
		# Slow for sharp turns in the next ~45 m.
		var want := max_kmh
		var a: Vector3 = target - pos
		var d := 0.0
		for k in range(idx, mini(idx + 12, path.size() - 1)):
			var seg: Vector3 = path[k + 1] - path[k]
			d += seg.length()
			if d > 45.0 + v.forward_speed:
				break
			var ang := rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(seg.x, seg.z)))
			want = minf(want, lerpf(max_kmh, 32.0, clampf(absf(ang) / 85.0, 0.0, 1.0)))
		if rm.phase == RaceManager.Phase.COUNTDOWN:
			_set_pedals(false, false)
		else:
			_set_pedals(v.speed_kmh < want, v.speed_kmh > want + 12.0)
		stuck = stuck + dt if v.speed_kmh < 4.0 and rm.phase == RaceManager.Phase.RACING else 0.0
		if stuck > 4.0 or v.global_basis.y.y < 0.3:
			stuck = 0.0
			respawns += 1
			if respawns <= 2:
				print("      stuck at %s (gate %d, path %d/%d, up %.2f)" % [pos.round(), rm.next_cp, idx, path.size(), v.global_basis.y.y])
				await _photo_vehicle(game, v, "race_stuck_%s_%d" % [rm.race["id"], respawns])
			game.respawn()
			# Pick the path point nearest the respawn spot.
			var best := INF
			for k in path.size():
				var dd: float = (path[k] as Vector3).distance_to(v.global_position)
				if dd < best:
					best = dd
					idx = k
	_release()
	rm.finished.disconnect(on_finish)
	print("    %s: %s, %d respawns" % [rm.race.get("name", "race"), "finished %.1fs" % finish[0] if finish[0] >= 0 else "NOT finished", respawns])
	return finish[0]


func _races(game: Game) -> void:
	var rm := game.race
	game.traffic.set_enabled(false)
	await _wait_s(0.5)
	# Teleporting onto a start circle must not start a race; driving in does.
	game.vehicle.teleport(rm.races[0]["start"])
	await _wait_s(1.0)
	_check(not rm.is_active(), "teleporting into a start circle doesn't start a race")
	var st: Transform3D = rm.races[0]["start"]
	game.vehicle.teleport(Transform3D(st.basis, st.origin + st.basis.z * 18.0))
	await _wait_s(0.5)
	# Driving straight through doesn't start it...
	Input.action_press("accelerate")
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_release()
	_check(not rm.is_active(), "driving through a start circle doesn't start a race")
	# ...stopping in it does.
	game.vehicle.teleport(Transform3D(st.basis, st.origin + st.basis.z * 18.0))
	await _wait_s(0.5)
	t = 0.0
	while game.vehicle.global_position.distance_to(st.origin) > 3.0 and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_set_pedals(game.vehicle.speed_kmh < 12.0, false)
	Input.action_release("accelerate")
	Input.action_press("brake")
	await _wait_s(0.6)
	Input.action_release("brake")
	t = 0.0
	while not rm.is_active() and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_release()
	_check(rm.is_active() and rm.phase == RaceManager.Phase.COUNTDOWN and not game.controller.enabled, "stopping in the circle starts the countdown")
	await _wait_s(0.5)
	await _shot("race_countdown")
	await _wait_s(3.0)
	_check(rm.phase == RaceManager.Phase.RACING and game.controller.enabled, "GO: racing, controls back")
	rm.end_race()
	await _wait_s(0.5)
	var caps := {"city": 85.0, "highway": 150.0, "mountain": 85.0, "dirt": 80.0, "beach": 100.0}
	var times := {}
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--race-only="):
			only = arg.split("=")[1]
	for i in rm.races.size():
		var r: Dictionary = rm.races[i]
		if only != "" and r["id"] != only:
			continue
		rm.start(i)
		await _wait_s(0.1)
		var shot_at := 12.0
		var ft := await _autopilot_race(game, caps.get(r["id"], 90.0), 240.0)
		times[r["id"]] = ft
		_check(ft > 0.0, "%s completed by the autopilot (%.1fs, %d gates)" % [r["name"], ft, (r["checkpoints"] as Array).size()])
		await _wait_s(1.0)
	var line := ""
	for k in times:
		line += "\"%s\": %.1f, " % [k, times[k]]
	print("  reference times: { %s}" % line)
	_check(not Records.best_times.is_empty(), "best times recorded (%s)" % str(Records.best_times))


func _park(game: Game) -> void:
	var st := game.stunts
	var cam := game.camera
	game.traffic.set_enabled(false)
	var tricks: Array[String] = []
	st.trick.connect(func(n: String, _p: int) -> void: tricks.append(n))
	var has := func(prefix: String) -> bool:
		for n in tricks:
			if n.begins_with(prefix):
				return true
		return false
	for vi in [0, 1, 6, 5]:  # sports car, sedan, buggy, pickup
		tricks.clear()
		game.change_vehicle(vi, null, false)
		var v := game.vehicle
		v.teleport(Transform3D(Basis.looking_at(Vector3.BACK), Vector3(StuntParkBuilder.LOOP_X, 0.6 + v.ride_height(), StuntParkBuilder.LOOP_Z - 62.0)))
		await _wait_s(0.5)
		var t := 0.0
		var max_y := 0.0
		var shot := false
		while t < 14.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var pos := v.global_position
			# Aim at the loop's centre line a bit ahead of the nearest point
			# (straight lines before and after it).
			var ahead_pt: Vector3
			var lp := StuntParkBuilder.loop_points()
			if pos.z < StuntParkBuilder.LOOP_Z - 2.0 and max_y < 2.0:
				ahead_pt = Vector3(StuntParkBuilder.LOOP_X, pos.y, pos.z + 12.0)
			else:
				var best := 0
				var bd := INF
				for k in lp.size():
					var dd := lp[k].distance_squared_to(pos)
					if dd < bd and (k > lp.size() / 2 or max_y < 8.0):
						bd = dd
						best = k
				if best + 6 < lp.size():
					ahead_pt = lp[best + 6]
				else:
					ahead_pt = lp[lp.size() - 1] + Vector3(0, 0, 12)
			var local := v.global_basis.inverse() * (ahead_pt - pos)
			_set_axis(clampf(atan2(local.x, -local.z) * 1.5, -1.0, 1.0))
			_set_pedals(v.speed_kmh < (92.0 if vi == 5 else 80.0), false)
			max_y = maxf(max_y, pos.y)
			if pos.y > 11.0 and not shot:
				shot = true
				cam.set_process(false)
				cam.global_position = Vector3(StuntParkBuilder.LOOP_X - 30.0, 8.0, StuntParkBuilder.LOOP_Z + 4.0)
				cam.look_at(Vector3(StuntParkBuilder.LOOP_X + 4.0, 7.5, StuntParkBuilder.LOOP_Z + 4.0), Vector3.UP)
				await _shot("park_loop_%d" % vi)
				cam.set_process(true)
			if pos.z > StuntParkBuilder.LOOP_Z + 30.0 and max_y > 11.0:
				break
		_release()
		await _wait_s(1.2)
		var exit_ok := v.global_position.z > StuntParkBuilder.LOOP_Z + 15.0 and v.global_basis.y.y > 0.9
		_check(max_y > 12.0 and exit_ok and has.call("LOOP"), "%s loops the loop (top %.1f m, tricks %s, end %s up %.2f)" % [v.display_name, max_y, ", ".join(tricks), v.global_position.round(), v.global_basis.y.y])

	# Wall ride: circle the bowl high on the wall.
	tricks.clear()
	game.change_vehicle(0, null, false)
	var v := game.vehicle
	var c := StuntParkBuilder.BOWL_CENTER
	var c3 := Vector3(c.x, 0, c.y)
	v.teleport(Transform3D(Basis.looking_at(Vector3.BACK), Vector3(c.x, 0.6 + v.ride_height(), c.y - 40.0)))
	await _wait_s(0.5)
	var t := 0.0
	var max_tilt := 0.0
	var shot := false
	while t < 16.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var pos := v.global_position
		var rel := Vector3(pos.x - c3.x, 0, pos.z - c3.z)
		var target: Vector3
		if t < 3.0:
			target = c3 + Vector3(0, 0, 3)
		else:
			# Circle anticlockwise (seen from above) at a radius near the wall.
			var ang := atan2(rel.z, rel.x) - 0.5
			target = c3 + Vector3(cos(ang), 0, sin(ang)) * 15.5 + Vector3.UP * 5.0
		var local := v.global_basis.inverse() * (target - pos)
		_set_axis(clampf(atan2(local.x, -local.z) * 1.6, -1.0, 1.0))
		_set_pedals(v.speed_kmh < 70.0, false)
		max_tilt = maxf(max_tilt, absf(v.global_basis.x.y))
		if absf(v.global_basis.x.y) > 0.8 and not shot:
			shot = true
			cam.set_process(false)
			cam.global_position = c3 + Vector3(0, 22, 0)
			cam.look_at(pos, Vector3.FORWARD)
			await _shot("park_wallride")
			cam.set_process(true)
	_release()
	await _wait_s(1.5)
	_check(has.call("WALL RIDE"), "wall ride in the bowl (max tilt %.2f, tricks %s)" % [max_tilt, ", ".join(tricks)])


func _trail(game: Game) -> void:
	game.traffic.set_enabled(false)
	var road := game.world.roads.find_road("MountainTrail")
	var path := road.points
	for vi in [6, 5]:  # buggy, pickup
		game.change_vehicle(vi, null, false)
		var v := game.vehicle
		var dir := path[3] - path[0]
		dir.y = 0.0
		v.teleport(Transform3D(Basis.looking_at(dir.normalized()), path[0] + Vector3.UP * (v.ride_height() + 0.3)))
		await _wait_s(0.5)
		var idx := 0
		var t := 0.0
		var stuck := 0.0
		var shots := 0
		while idx < path.size() - 2 and t < 120.0:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			var pos := v.global_position
			while idx < path.size() - 1 and Vector2(path[idx].x - pos.x, path[idx].z - pos.z).length() < 7.0:
				idx += 1
			var local := v.global_basis.inverse() * (path[mini(idx + 1, path.size() - 1)] - pos)
			_set_axis(clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0))
			# Slow for the hairpins coming up.
			var want := 40.0
			var a0 := path[mini(idx + 1, path.size() - 1)] - path[idx]
			var a1 := path[mini(idx + 6, path.size() - 1)] - path[mini(idx + 3, path.size() - 1)]
			if Vector2(a0.x, a0.z).angle_to(Vector2(a1.x, a1.z)) > 0.5 or absf(Vector2(a0.x, a0.z).angle_to(Vector2(a1.x, a1.z))) > 0.5:
				want = 18.0
			_set_pedals(v.speed_kmh < want, v.speed_kmh > want + 8.0)
			stuck = stuck + dt if v.speed_kmh < 3.0 else 0.0
			if stuck > 6.0:
				break
			if idx > shots * (path.size() / 3) + 10 and shots < 3:
				await _shot("trail_%d_%d" % [vi, shots])
				shots += 1
		_release()
		var top := v.global_position
		print("    %s: reached point %d/%d at %s in %.0fs" % [v.display_name, idx, path.size(), top.round(), t])
		_check(idx >= path.size() - 3, "%s drives the mountain trail to the top (%.0f m up)" % [v.display_name, top.y])


## Prints who a traffic car hit (for the traffic tests' crash counts).
func _log_crash(tm: TrafficManager, d: TrafficDriver, st: float, p: Vector3) -> void:
	if not is_instance_valid(d):
		return
	var other := ""
	for o in tm.vehicles:
		if is_instance_valid(o) and o != d.vehicle and o.global_position.distance_to(d.vehicle.global_position) < 8.0:
			var od := tm.driver_of(o)
			other += " %s(%.0fkmh%s)" % [o.display_name, o.speed_kmh, (" lc%.1f %s" % [od._lc_offset, ["D", "S", "L"][od.state]]) if od else " player"]
	var hit: Object = d.vehicle.last_impact_collider
	var hit_name: String = String((hit as Node).name) if hit is Node else str(hit)
	print("  CRASH %.0f %s hit '%s' at %s %.0fkmh lane %d lc %.1f age %.1fs blocker '%s' near:%s" % [st, d.vehicle.display_name, hit_name,
		p.round(), d.vehicle.speed_kmh, d.current_lane().id if d.current_lane() else -1, d._lc_offset, d.age, d.blocker, other])


## Spawns traffic cars one by one and reports any impact in their first second.
func _spawncheck(game: Game) -> void:
	var tm := game.traffic
	tm.set_enabled(false)
	game.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	await _wait_s(0.5)
	var bad := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 60:
		var pick := tm.network.random_spawn(rng)
		if pick.is_empty():
			continue
		var scene: PackedScene = tm.car_scenes[k % tm.car_scenes.size()]
		var d := tm._spawn(pick["lane"], pick["s"], scene)
		var v := d.vehicle
		var hits: Array[String] = []
		var frame := [0]
		v.impact.connect(func(st: float, p: Vector3, _n: Vector3) -> void:
			hits.append("f%d %.0f vs %s at %s (car at %s)" % [frame[0], st, (v.last_impact_collider as Node).name if v.last_impact_collider is Node else "?", p.round(), v.global_position.round()]))
		var y0 := v.global_position.y
		var lane_id := d.current_lane().id
		var lane_len := d.current_lane().length
		for f in 120:
			frame[0] = f
			await get_tree().physics_frame
			if not is_instance_valid(d):
				break
		if not is_instance_valid(d):
			# Spawned too far from the player and tidied away: fine unless it crashed.
			if not hits.is_empty():
				print("  (freed) %s lane %d: %s" % [scene.resource_path.get_file(), lane_id, ", ".join(hits)])
				bad += 1
			continue
		if not hits.is_empty() or d.state != TrafficDriver.State.DRIVING:
			bad += 1
			print("  %s on lane %d (len %.0f, s %.0f): %s state %s  dy %.2f blocker '%s'" % [v.display_name, lane_id, lane_len,
				pick["s"], ", ".join(hits), ["D", "S", "L"][d.state], v.global_position.y - y0, d.blocker])
		tm._despawn(d)
		for w in int(OS.get_environment("GAPF") if OS.get_environment("GAPF") != "" else "1"):
			await get_tree().physics_frame
	_check(bad == 0, "clean spawns (%d bad of 60)" % bad)

	# Removed cars wait in a pool and come back as good as new.
	await _wait(2)
	_check(tm.pooled_count() > 0, "removed cars wait in the pool (%d)" % tm.pooled_count())
	var d1 := tm.spawn_near(tm.car_scenes[1], Vector3(-60, 0, 120))
	var car := d1.vehicle
	var dmg := car.get_node("Damage") as VehicleDamage
	await _wait_s(0.5)
	dmg._dent(0, car.global_transform * Vector3(0.5, 0.5, -2.0), 0.3, 1.0)
	dmg._break_headlights()
	dmg._detach("FrontBumper")
	var dented := dmg._meshes[0].mesh != dmg._sources[0]
	var players_before := car.get_node("Audio").find_children("*", "AudioStreamPlayer3D", false, false).size()
	tm._despawn(d1)
	await _wait(2)
	var d2 := tm.spawn_near(tm.car_scenes[1], Vector3(60, 0, -120))
	var drivers_on_car := car.find_children("*", "TrafficDriver", false, false).size()
	# One VehicleAudio (traffic detail), with as many players as before: reuse
	# mustn't stack up sounds.
	var audios := car.find_children("*", "VehicleAudio", false, false)
	var players := (audios[0] as Node).find_children("*", "AudioStreamPlayer3D", false, false).size() if audios.size() == 1 else -1
	var sounds_ok := audios.size() == 1 and (audios[0] as VehicleAudio).detail == VehicleAudio.Detail.LITE and players == players_before
	_check(d2.vehicle == car, "the same sedan was reused")
	_check(dented and dmg._meshes[0].mesh == dmg._sources[0] and not dmg.headlights_broken and dmg.total_damage == 0.0
		and dmg._parts["FrontBumper"]["debris"] == null, "reused car is repaired (dents, lights, bumper)")
	_check(drivers_on_car == 1 and sounds_ok and car.visible, "one driver, one set of sounds (%d drivers, %d sound players, %d before)" % [
		drivers_on_car, players, players_before])
	await _wait_s(3.0)
	_check(is_instance_valid(d2) and d2.state == TrafficDriver.State.DRIVING and car.speed_kmh > 10.0,
		"reused car drives off (%.0f km/h)" % car.speed_kmh)


## Drives straight from `from` towards `to` (both on the ground) at up to
## `kmh`; returns the closest the car got to `to` and whether it stayed upright.
func _drive_line(game: Game, from: Vector3, to: Vector3, kmh: float, seconds: float, shot := "") -> Array:
	var v := game.vehicle
	var dir := to - from
	dir.y = 0.0
	v.teleport(Transform3D(Basis.looking_at(dir.normalized()), from + Vector3.UP * (v.ride_height() + 0.4)))
	await _wait_s(0.4)
	var t := 0.0
	var best := INF
	var worst_up := 1.0
	var shot_done := shot == ""
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var pos := v.global_position
		var local := v.global_basis.inverse() * (to - pos)
		_set_axis(clampf(atan2(local.x, -local.z) * 2.0, -1.0, 1.0))
		_set_pedals(v.speed_kmh < kmh, false)
		best = minf(best, Vector2(pos.x - to.x, pos.z - to.z).length())
		worst_up = minf(worst_up, v.global_basis.y.y)
		if not shot_done and t > seconds * 0.4:
			shot_done = true
			await _shot(shot)
		if best < 6.0:
			break
	_release()
	return [best, worst_up]


func _landmarks(game: Game) -> void:
	game.traffic.set_enabled(false)
	await _wait_s(0.3)
	# Tunnel: north to south along the avenue.
	var r := await _drive_line(game, Vector3(1.8, 0.0, 160.0), Vector3(1.8, 0.0, 245.0), 60.0, 14.0, "landmark_tunnel")
	_check(r[0] < 6.0 and r[1] > 0.9, "drives through the tunnel (closest %.1f m)" % r[0])
	# Bridge: beach to the islet.
	var east := Vector3(MapLayout.BRIDGE_EAST_X + 25.0, 0.0, 0.0)
	east.y = game.world.terrain.height_at(east.x, 0.0)
	var west := Vector3(MapLayout.ISLET_CENTER.x + 16.0, 0.0, 0.0)
	r = await _drive_line(game, east, west, 50.0, 20.0, "landmark_bridge")
	var on_islet := game.vehicle.global_position.y > MapLayout.SEA_LEVEL + 1.0
	_check(r[0] < 6.0 and on_islet and r[1] > 0.9, "drives over the bridge to the islet (closest %.1f m, y %.1f)" % [r[0], game.vehicle.global_position.y])
	# Runway: full length at speed.
	r = await _drive_line(game, MapLayout.RUNWAY_A + Vector3(10, 0, 0), MapLayout.RUNWAY_B - Vector3(15, 0, 0), 150.0, 20.0, "landmark_runway")
	_check(r[0] < 6.0 and r[1] > 0.9, "runway end to end (closest %.1f m)" % r[0])
	# Harbour: out along a pier.
	var pz := (MapLayout.HARBOR_QUAY_A.z + MapLayout.HARBOR_QUAY_B.z) * 0.5
	r = await _drive_line(game, Vector3(MapLayout.HARBOR_QUAY_A.x + 8.0, MapLayout.HARBOR_QUAY_A.y, pz), Vector3(MapLayout.HARBOR_QUAY_A.x - 55.0, MapLayout.HARBOR_QUAY_A.y, pz), 30.0, 14.0, "landmark_pier")
	_check(r[0] < 6.0 and game.vehicle.global_position.y > 0.0, "drives out onto a pier (closest %.1f m)" % r[0])
	# A few views.
	var cam := game.camera
	cam.set_process(false)
	var views := [
		["view_airfield", MapLayout.APRON_CENTER + Vector3(-60, 30, 70), MapLayout.APRON_CENTER + Vector3(30, 0, 20)],
		["view_tunnel", Vector3(40, 18, 165), Vector3(0, 4, 205)],
		["view_harbor", MapLayout.HARBOR_QUAY_A + Vector3(-90, 30, 30), MapLayout.HARBOR_QUAY_A + Vector3(-20, 0, -40)],
		["view_lighthouse", Vector3(-440, 20, 60), Vector3(-500, 5, 0)],
	]
	for vw in views:
		cam.global_position = vw[1]
		cam.look_at(vw[2], Vector3.UP)
		await _wait(3)
		await _shot(vw[0])
	cam.set_process(true)


func _night(game: Game) -> void:
	var dn := game.day_night
	var cam := game.camera
	var lamps := get_tree().get_nodes_in_group("night_lights")
	_check(lamps.size() > 10, "%d night lights in the world" % lamps.size())
	game.teleport_to(0)
	await _wait_s(1.0)
	Settings.set_value("time_of_day", 1)
	await _wait(10)
	await _shot("sunset_city")
	_check(not dn.is_night, "sunset is still daylight")
	Settings.set_value("time_of_day", 2)
	await _wait(10)
	var lamp := lamps[0] as Node3D
	var lights := game.vehicle.get_node_or_null("Headlights") as Node3D
	_check(dn.is_night and lamp.visible and lights != null and lights.visible, "night: lamps and headlights on")
	# Drive a little so the headlights sweep the street.
	Input.action_press("accelerate")
	await _wait_s(2.0)
	_release()
	await _wait_s(1.0)
	await _shot("night_city")
	game.change_vehicle(4, _painted(4, Color.YELLOW))
	await _wait(10)
	var bus_lights := game.vehicle.get_node_or_null("Headlights") as Node3D
	_check(bus_lights != null and bus_lights.visible, "headlights follow a vehicle change")
	await _shot("night_bus")
	cam.set_process(false)
	cam.global_position = Vector3(-420, 25, 60)
	cam.look_at(Vector3(-528, 12, 0), Vector3.UP)
	await _wait_s(1.0)
	await _shot("night_lighthouse")
	cam.global_position = Vector3(-60, 90, 260)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await _wait(5)
	await _shot("night_overview")
	cam.set_process(true)
	# Cycle: time moves and lights go off in the morning.
	Settings.set_value("time_of_day", 3)
	dn.hour = 5.5
	await _wait(5)
	var t := 0.0
	while dn.is_night and t < 60.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		dn.hour += get_physics_process_delta_time() * 0.5  # fast-forward
	_check(not dn.is_night and not lamp.visible, "morning: lights off again (hour %.1f)" % dn.hour)
	Settings.set_value("time_of_day", 0)


## Drives (or reverses) the player car into a temporary wall at `kmh`.
func _ram_wall(game: Game, kmh: float, backwards := false) -> void:
	var v := game.vehicle
	var start := Vector3(345, 0, -110)
	start.y = game.world.terrain.height_at(start.x, start.z)
	# Move it without teleport(): that counts as a reset and repairs the car.
	v.global_transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * (v.ride_height() + 0.3))
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO
	v.reset_physics_interpolation()
	await _wait_s(0.8)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 1)
	cs.shape = box
	wall.add_child(cs)
	game.add_child(wall)
	var dz := 40.0 if backwards else -40.0
	wall.global_position = start + Vector3(0, 2.0, dz)
	var t := 0.0
	var key := "brake" if backwards else "accelerate"
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if v.speed_kmh < kmh:
			Input.action_press(key)
		else:
			Input.action_release(key)
		# Steer at the wall (a damaged car pulls to one side).
		var local := v.global_basis.inverse() * (wall.global_position - v.global_position)
		var ang := atan2(local.x, -local.z) if not backwards else -atan2(local.x, local.z)
		_set_axis(clampf(ang * 2.0, -1.0, 1.0))
		if v.global_position.distance_to(wall.global_position) < 3.5 + v.body_length() * 0.5:
			break
	_release()
	await _wait_s(1.2)
	wall.queue_free()


func _damage(game: Game) -> void:
	game.traffic.set_enabled(false)
	await _wait_s(0.3)
	var v := game.vehicle
	var dmg := v.get_node("Damage") as VehicleDamage
	var lost: Array[String] = []
	dmg.part_lost.connect(func(n: String) -> void: lost.append(n))
	await _ram_wall(game, 55.0, true)
	await _ram_wall(game, 55.0, true)
	await _shot("damage_rear")
	_check(dmg.taillights_broken, "rear crash: tail lights broken (rear %.2f)" % dmg.rear_damage)
	_check(lost.has("REAR BUMPER") or lost.has("SPOILER"), "rear parts fell off (%s)" % str(lost))
	await _ram_wall(game, 75.0)
	await _shot("damage_front")
	_check(dmg.headlights_broken and v.damage_power < 0.95, "front crash: headlights broken, power %.2f" % v.damage_power)
	_check(lost.has("FRONT BUMPER"), "front bumper fell off (%s)" % str(lost))
	for k in 3:
		await _ram_wall(game, 70.0)
	_check(dmg.glass_broken and dmg.total_damage > 55.0, "glass cracked at %.0f%% damage" % dmg.total_damage)
	# Later dents keep the broken lights and the paint.
	var body := v.get_node("Body") as VehicleBodyVisual
	var lights_ok := body.front_lights_broken()
	for sf: Array in dmg._surfaces_named("Headlight"):
		var lm := (sf[0] as MeshInstance3D).get_active_material(sf[1]) as ShaderMaterial
		lights_ok = lights_ok and lm != null and float(lm.get_shader_parameter("broken")) > 0.5
	var paint_ok := false
	for mi: MeshInstance3D in dmg._meshes:
		for k in mi.get_surface_override_material_count():
			paint_ok = paint_ok or mi.get_surface_override_material(k) == body.paint()
	_check(lights_ok and paint_ok, "dents keep broken lights and paint (lights %s, paint %s)" % [lights_ok, paint_ok])
	# Smashed front makes the car smoke and pull.
	_check(v.damage_power <= 0.6 and dmg._smoke.emitting, "engine smoking, power %.2f, pull %.2f" % [v.damage_power, v.damage_steer_bias])
	var cam := game.camera
	await _wait_s(0.5)
	cam.set_process(false)
	cam.global_position = v.global_position + Vector3(6, 3, -6)
	cam.look_at(v.global_position + Vector3.UP * 0.5, Vector3.UP)
	await _wait(3)
	await _shot("damage_wreck")
	cam.set_process(true)
	# Repair (R) restores everything.
	v.reset_upright()
	await _wait_s(0.5)
	var parts_back := true
	for pn: String in dmg._parts:
		var p: Dictionary = dmg._parts[pn]
		parts_back = parts_back and p["debris"] == null and (p["mesh"] as MeshInstance3D).visible
	_check(dmg.total_damage == 0.0 and not dmg.headlights_broken and not dmg.glass_broken and v.damage_power == 1.0 and parts_back,
		"repair restores parts, lights, glass and power")
	# Damage on a traffic car that's then removed: its debris tidies up safely.
	game.traffic.set_enabled(true)
	await _wait_s(1.0)
	_check(true, "no errors")


func _replay(game: Game) -> void:
	var v := game.vehicle
	Settings.set_value("crash_cam", false)  # until part 3
	# 1) Pausing freezes the car: no drift, and no kick when the game resumes.
	game.teleport_to(4)
	await _wait_s(1.5)
	var parked := v.global_position
	await _tap("pause")
	_check(game.state == Game.State.PAUSED, "pause menu open")
	await _wait(240)
	_check(v.global_position.distance_to(parked) < 0.05, "parked car stays put while paused (%.2f m)" % v.global_position.distance_to(parked))
	game._enter_driving()
	await _wait_s(0.5)
	_check(v.linear_velocity.length() < 0.5 and v.global_position.distance_to(parked) < 0.2,
		"no kick on resume (moved %.2f m, %.2f m/s)" % [v.global_position.distance_to(parked), v.linear_velocity.length()])
	# Same while driving.
	var hw := game.world.roads.highway
	game.teleport_to(1)
	await _wait_s(0.5)
	Input.action_press("accelerate")
	await _wait_s(4.0)
	var kmh := v.speed_kmh
	game._enter_pause()
	await _wait(240)
	game._enter_driving()
	await _wait_s(0.1)
	Input.action_release("accelerate")
	_check(absf(v.speed_kmh - kmh) < 6.0 and v.angular_velocity.length() < 1.5,
		"driving: same speed after a pause (%.0f -> %.0f km/h, spin %.2f)" % [kmh, v.speed_kmh, v.angular_velocity.length()])

	# 2) Instant replay while driving along the highway with traffic around.
	var rp := game.replay
	Input.action_press("accelerate")
	await _wait_s(5.0)
	await _tap("instant_replay")
	Input.action_release("accelerate")
	_check(game.state == Game.State.REPLAY and get_tree().paused and rp._camera.current and rp._overlay.visible,
		"P: replay playing, game paused, replay camera on")
	# The live state when the replay started, and the state right after it.
	var live: Transform3D = rp._restore[0][1]
	var live_speed: float = (rp._restore[0][2] as Vector3).length() * 3.6
	var others := {}
	for r: Array in rp._restore.slice(1):
		others[r[0]] = r[1]
	var after := {}
	rp.finished.connect(func() -> void:
		after["pos"] = v.global_position
		after["kmh"] = v.linear_velocity.length() * 3.6
		var ok := true
		for o in others:
			if is_instance_valid(o) and (not o.visible or o.global_position.distance_to((others[o] as Transform3D).origin) > 0.01):
				ok = false
		after["traffic"] = ok, CONNECT_ONE_SHOT)
	await _wait_real(1.5)
	await _shot("replay_instant")
	_check(v.global_position.distance_to(live.origin) > 15.0, "car shown back in time (%.0f m behind)" % v.global_position.distance_to(live.origin))
	var moved := 0
	for o in others:
		if is_instance_valid(o) and o.visible and o.global_position.distance_to((others[o] as Transform3D).origin) > 1.0:
			moved += 1
	_check(moved > 0, "traffic replayed too (%d cars)" % moved)
	await _wait_real(2.0)
	await _shot("replay_instant_2")
	await _tap("menu_accept")
	_check(game.state == Game.State.DRIVING and not get_tree().paused and game.camera.current, "Enter/A skips back to driving")
	_check((after["pos"] as Vector3).distance_to(live.origin) < 0.01 and absf(float(after["kmh"]) - live_speed) < 0.1,
		"car back exactly where it was (%.3f m, %.1f -> %.1f km/h)" % [(after["pos"] as Vector3).distance_to(live.origin), live_speed, after["kmh"]])
	_check(after["traffic"], "traffic back where it was")
	# A replay left to play out ends by itself.
	await _wait_s(1.0)
	game.start_replay()
	var t0 := Time.get_ticks_msec()
	while game.state == Game.State.REPLAY and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	_check(game.state == Game.State.DRIVING, "replay ends on its own (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))

	# The car drives on smoothly after a replay (empty road, gas held throughout).
	game.traffic.set_enabled(false)
	game.teleport_to(1)
	await _wait_s(0.5)
	Input.action_press("accelerate")
	await _wait_s(4.0)
	var before := [v.speed_kmh, v.global_position]
	game.start_replay()
	await _wait_real(1.0)
	game.replay.stop()
	var resumed := v.global_position
	await _wait_s(0.5)
	_check(v.speed_kmh >= float(before[0]) - 1.0 and v.angular_velocity.length() < 0.5 and resumed.distance_to(before[1]) < 0.01,
		"drives on smoothly after a replay (%.0f -> %.0f km/h, spin %.2f)" % [before[0], v.speed_kmh, v.angular_velocity.length()])
	Input.action_release("accelerate")

	# 3) Crash cam: a big crash plays back in slow motion.
	Settings.set_value("crash_cam", true)
	await _wait_s(0.5)
	var got_cam := [false]
	var watch := func() -> void:
		if game.state == Game.State.REPLAY:
			got_cam[0] = true
	get_tree().process_frame.connect(watch)
	_ram_wall.call(game, 75.0)
	var t1 := Time.get_ticks_msec()
	while game.state != Game.State.REPLAY and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
	_check(game.state == Game.State.REPLAY and rp._title.text == "CRASH CAM" and rp._speed < 0.5, "big crash: slow-motion crash cam")
	await _wait_real(2.5)
	await _shot("replay_crash")
	await _wait_real(2.0)
	await _shot("replay_crash_2")
	t1 = Time.get_ticks_msec()
	while game.state == Game.State.REPLAY and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
	_check(game.state == Game.State.DRIVING, "crash cam ends by itself (%.1f s)" % ((Time.get_ticks_msec() - t1) / 1000.0))
	await _wait_s(2.0)
	# Another crash straight after doesn't show it again.
	got_cam[0] = false
	await _ram_wall(game, 75.0)
	await _wait_s(1.5)
	_check(not got_cam[0], "no second crash cam straight away")
	# And it can be switched off.
	game._last_crash_cam = -INF
	Settings.set_value("crash_cam", false)
	await _ram_wall(game, 75.0)
	await _wait_s(1.5)
	_check(not got_cam[0], "crash cam setting off: no crash cam")
	get_tree().process_frame.disconnect(watch)
	Settings.set_value("crash_cam", true)


## Waits `seconds` of real time (game time stands still in a replay).
func _wait_real(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await get_tree().process_frame


## Screenshots from fixed views of the city spine and the north bridge (where
## the environment upgrade was previewed), at day / sunset / night on High and
## day on Low, with the HUD hidden and traffic off so runs compare. Prints draw
## calls, objects, primitives and GPU time per view (High, day).
func _scenery(game: Game) -> void:
	var tm := game.traffic
	var with_traffic := OS.get_cmdline_user_args().has("--traffic-on")
	tm.set_enabled(with_traffic)
	game.hud.visible = false
	var cam := game.camera
	var v := game.vehicle
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var north := Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	var east := Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	# [name, camera position, look at, player car transform (or null), also on Low]
	var views := [
		["avenue_chase", Vector3(2.4, 2.4, -30.0), Vector3(2.4, 1.4, -62.0), Transform3D(north, Vector3(2.4, 0.6, -38.0)), true],
		["intersection", Vector3(10.0, 1.7, -60.0), Vector3(-6.0, 1.2, -80.0), null, true],
		["sidewalk", Vector3(-3.6, 1.6, -92.0), Vector3(-9.0, 4.0, -140.0), null, false],
		["downtown_street", Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0), Transform3D(east, Vector3(16.0, 0.6, 2.0)), true],
		["downtown_up", Vector3(4.0, 1.5, -3.0), Vector3(38.0, 28.0, 30.0), null, false],
		["plaza", Vector3(-28.0, 2.0, -3.0), Vector3(-42.0, 2.0, -40.0), null, false],
		["park", Vector3(38.0, 1.7, -77.0), Vector3(36.0, 3.0, -120.0), null, false],
		["overpass_under", Vector3(2.5, 1.8, -212.0), Vector3(0.0, 6.0, -255.0), null, true],
		["overpass_deck", Vector3(-45.0, 11.5, -244.0), Vector3(20.0, 9.6, -244.5), null, true],
		["hill_junction", Vector3(6.0, 3.5, -280.0), Vector3(25.0, 6.0, -322.0), null, false],
		["aerial", Vector3(95.0, 70.0, 15.0), Vector3(-10.0, 0.0, -110.0), null, true],
		["aerial_overpass", Vector3(60.0, 32.0, -185.0), Vector3(0.0, 5.0, -258.0), null, false],
		# Downtown (MegaKit experiment) close-ups: the spawn, eye level on the
		# sidewalks, a corner, looking up a facade, the plaza edge, the car park.
		["dt_spawn", Vector3(-117.5, 2.6, 3.0), Vector3(-85.0, 1.8, 3.0), Transform3D(east, Vector3(-110.0, 0.6, 3.0)), true],
		["dt_spawn_walk", Vector3(-121.0, 1.7, -7.5), Vector3(-80.0, 5.0, -1.0), null, false],
		["dt_corner", Vector3(-63.0, 1.7, 8.5), Vector3(-82.0, 7.0, -10.0), null, false],
		["dt_facade", Vector3(4.0, 1.7, 8.2), Vector3(22.0, 4.5, 7.6), null, false],
		["dt_look_up", Vector3(14.0, 1.6, -7.8), Vector3(18.0, 24.0, -11.0), null, false],
		["dt_plaza_edge", Vector3(-40.0, 1.8, -12.0), Vector3(-52.0, 8.0, 20.0), null, false],
		["dt_avenue_south", Vector3(2.4, 2.4, -6.0), Vector3(2.4, 3.0, 45.0), null, false],
		["dt_car_park", Vector3(-95.0, 2.2, 14.0), Vector3(-140.0, 7.0, 62.0), null, false],
	]
	# --cams=px,py,pz,lx,ly,lz;... : extra views named cam0, cam1... (camera
	# position, look-at point), e.g. close-ups for a visual review.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cams="):
			var k := 0
			for c in arg.split("=")[1].split(";"):
				var f := c.split_floats(",")
				if f.size() == 6:
					views.append(["cam%d" % k, Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), null, true])
					k += 1
	# Chase-style views at the teleport spots outside the city (spawn_beach,
	# spawn_dirt_fields, spawn_mountain_top...): nature, terrain and landmarks.
	for sp: Dictionary in game.world.spawn_points.slice(2):
		var xf: Transform3D = sp["xform"]
		var fwd := -xf.basis.z
		views.append(["spawn_" + String(sp["name"]).to_lower().replace(" ", "_"),
			xf.origin - fwd * 7.5 + Vector3.UP * 2.6, xf.origin + fwd * 25.0 + Vector3.UP * 1.0, xf, false])
	var times := ["day", "sunset", "night"]
	var only: PackedStringArray = []
	var quick := false
	# --hours=6.4,9,18.2: shoot these clock times (day/night cycle) instead.
	var hours: PackedFloat64Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.split("=")[1].split(",")
		if arg.begins_with("--hours="):
			for h in arg.split("=")[1].split(","):
				hours.append(float(h))
		quick = quick or arg == "--quick" or not hours.is_empty()
	if not hours.is_empty():
		times.clear()
		for h in hours:
			times.append("h%05.2f" % h)
	# --ultra: the "high" shots use Ultra (the full PC look) instead;
	# --medium: the Steam Deck preset instead.
	var top := GraphicsQuality.ULTRA if OS.get_cmdline_user_args().has("--ultra") else GraphicsQuality.HIGH
	if OS.get_cmdline_user_args().has("--medium"):
		top = GraphicsQuality.MEDIUM
	for q in ([top] if quick else [top, GraphicsQuality.LOW]):
		Settings.set_value("graphics", q)
		for t in (range(hours.size()) if not hours.is_empty() else (range(3) if q == top and not quick else [0])):
			if hours.is_empty():
				Settings.set_value("time_of_day", t)
			else:
				game.day_night.cycling = false
				game.day_night.hour = hours[t]
				game.day_night._apply()
			for view: Array in views:
				if q == GraphicsQuality.LOW and not view[4]:
					continue
				if not only.is_empty() and not only.has(view[0]):
					continue
				cam.set_process(true)
				if view[3] != null:
					v.teleport(view[3])
				else:
					v.teleport(Transform3D(north, Vector3(2.4, 0.6, -38.0)))
				await _wait(20)
				if with_traffic:
					await _wait_s(6.0)  # let traffic fill in around the player
				cam.set_process(false)
				cam.global_position = view[1]
				cam.look_at(view[2], Vector3.UP)
				if OS.get_cmdline_user_args().has("--stress"):
					# Render at 2x resolution so per-pixel (fill) costs dominate the GPU time.
					get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
					get_viewport().scaling_3d_scale = 2.0
				await _wait(12)
				var tag := "%s_%s_%s" % [view[0], times[t], "high" if q == top else "low"]
				if OS.get_cmdline_user_args().has("--profile") and q == top and t == 0:
					await _profile_families(game, view[0])
				if q == top and t == 0:
					var calls := 0
					var objs := 0
					var prims := 0
					var gpu := 0.0
					for k in 30:
						await RenderingServer.frame_post_draw
						calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
						objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
						prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
						gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
					print("SCENERY %-16s %4d draw calls, %4d objects, %7d primitives, gpu %.2f ms" % [
						view[0], calls / 30, objs / 30, prims / 30, gpu / 30.0])
				await _shot(tag)
	cam.set_process(true)
	game.hud.visible = true
	Settings.set_value("graphics", GraphicsQuality.HIGH)
	Settings.set_value("time_of_day", 0)


## The MegaKit downtown experiment (DowntownBlock): see the header.
func _megakit(game: Game) -> void:
	game.traffic.set_enabled(false)
	await _wait_s(0.5)
	var world := game.world
	var downtown := world.find_child("Downtown", true, false)
	_check(downtown != null, "downtown built")
	if downtown == null:
		return
	var near := 0
	var far := 0
	var shadow := 0
	for n in downtown.find_children("Building_*", "MeshInstance3D", true, false):
		if String(n.name).ends_with("_Far"):
			far += 1
		elif String(n.name).ends_with("_Shadow"):
			shadow += 1
		else:
			near += 1
	var occluders := downtown.find_children("*", "OccluderInstance3D", true, false).size()
	_check(near >= 30 and far == near and shadow == near and occluders == near,
		"%d buildings: %d far proxies, %d shadow proxies, %d occluders" % [near, far, shadow, occluders])
	_check(bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")), "occlusion culling is on")

	# Facades along the avenue (z = 0) are where their colliders are: rays at
	# chest height from the road hit a building within the facade band.
	var space := world.get_world_3d().direct_space_state
	var hits := 0
	var tries := 0
	var hit_x := 1e9
	# South of the avenue: blocks (1, 2) and (2, 2); north: (2, 1) (the
	# plaza is north-west of the centre).
	for side: float in [1.0, -1.0]:
		var x := -64.0 if side > 0.0 else 6.0
		while x < 70.0:
			if absf(fmod(absf(x) + 37.5, 75.0) - 37.5) > 32.0:  # skip the cross streets
				x += 5.0
				continue
			tries += 1
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1.2, side * 2.0), Vector3(x, 1.2, side * 14.0))
			var r := space.intersect_ray(q)
			if not r.is_empty() and absf(absf(r["position"].z) - 10.5) < 0.6:
				hits += 1
				# The crash lane needs nothing on the sidewalk in front of the
				# facade (tree pits, bollards): a ray at bumper height and a
				# car-wide strip either side must reach the building too.
				var clear := side > 0.0
				for dx: float in [-1.1, 0.0, 1.1]:
					var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x + dx, 0.45, 2.0), Vector3(x + dx, 0.45, 14.0)))
					clear = clear and not low.is_empty() and absf(low["position"].z - 10.5) < 0.6
				if clear and absf(x - 20.0) < absf(hit_x - 20.0):
					hit_x = x
			x += 5.0
	_check(tries > 0 and hits >= tries * 0.7, "facade colliders on the avenue: %d / %d rays hit the facade band (alleys and gaps excepted)" % [hits, tries])

	# Drive into a south facade at about 45 km/h.
	var v := game.vehicle
	var dmg := v.get_node("Damage") as VehicleDamage
	if hit_x > 1e8:
		hit_x = 20.0
	v.teleport(Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(hit_x, 0.6, -5.0)))
	await _wait_s(1.0)
	var t := 0.0
	var max_z := -1e9
	var max_speed := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if v.speed_kmh < 45.0 and v.global_position.z < 6.0:
			Input.action_press("accelerate")
		else:
			Input.action_release("accelerate")
		max_z = maxf(max_z, v.global_position.z + v.body_length() * 0.5)
		max_speed = maxf(max_speed, v.speed_kmh)
	_release()
	await _wait_s(0.5)
	await _shot("megakit_crash")
	_check(max_z < 10.5 + 0.6, "car stopped at the facade (front reached z %.2f, facade 10.5, top speed %.0f km/h)" % [max_z, max_speed])
	_check(dmg.total_damage > 0.02, "car dented by the building (damage %.2f)" % dmg.total_damage)
	_check(v.speed_kmh < 8.0, "car no longer moving through the wall (%.1f km/h)" % v.speed_kmh)
	# The chase camera stays outside every building collider.
	var cam_p := game.camera.global_position
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = cam_p
	var inside := space.intersect_point(pq)
	var in_building := false
	for h: Dictionary in inside:
		if h["collider"] is StaticBody3D and String((h["collider"] as Node).name) == "Buildings":
			in_building = true
	_check(not in_building, "chase camera outside the buildings after the crash (%s)" % cam_p.snapped(Vector3.ONE * 0.1))

	# On foot: walk straight at a facade; the character stops at it.
	game.teleport_to(0)
	await _wait_s(1.0)
	if game.possession.driving():
		await _tap("interact")
		await _wait_mode(game, Possession.Mode.ON_FOOT, 6.0)
	var ch := game.character
	if game.possession.on_foot():
		ch.place(Transform3D(Basis.IDENTITY, _ground(game, Vector3(hit_x + 1.0, 1.0, 8.0))))
		game.foot_camera.yaw = PI
		await _wait_s(0.5)
		_foot_push(game, Vector3.BACK, 1.0)
		await _wait_s(3.0)
		_foot_release()
		await _wait_s(0.3)
		var cz := ch.global_position.z
		_check(cz < 10.5 - 0.2, "character stopped at the facade (z %.2f)" % cz)
		await _shot("megakit_onfoot_wall")
	else:
		_check(false, "could not get out of the vehicle for the on-foot check")


## Render cost of one view: averages over `frames`.
func _render_stats(frames: int) -> Array:
	var vp_rid := get_viewport().get_viewport_rid()
	var calls := 0
	var prims := 0
	var gpu := 0.0
	for k in frames:
		await RenderingServer.frame_post_draw
		calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	return [calls / frames, prims / frames, gpu / frames]


## Steam Deck tuning: GPU time in a few heavy views on High, with each
## High-only effect turned off in turn, on Medium and Low, without grass or
## trees; then along a 300 m drive (SDFGI re-voxelises as the camera moves,
## so moving costs more than standing). Results go to stdout and perf.txt.
## --views=a,b limits the views, --configs=a,b the settings tried.
func _perfsweep(game: Game) -> void:
	game.traffic.set_enabled(false)
	game.hud.visible = false
	var vp := get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var world := game.world
	var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := world.get_node("Sun") as DirectionalLight3D
	var grass: Array[Node] = world.find_children("*", "GrassField", true, false)
	var trees := world.find_child("Trees", true, false) as Node3D
	# MegaKit downtown families: the buildings (near, far, shadow proxy) and
	# the street dressing (kit props, markings, signs, clutter, glow, yards).
	var kit: Array[Node] = world.find_children("Building_*", "GeometryInstance3D", true, false)
	var dressing: Array[Node] = []
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Props_") or nm.begins_with("Markings_") or nm in ["ShopSigns", "Clutter", "ShopLight", "Yard"]:
			dressing.append(n)
	var hide := func(nodes: Array, on: bool) -> void:
		for n in nodes:
			if n is Node3D:
				(n as Node3D).visible = not on
	var configs := [
		["high", func() -> void: pass],
		["-sdfgi", func() -> void: env.sdfgi_enabled = false],
		["-ssil", func() -> void: env.ssil_enabled = false],
		["-ssr", func() -> void: env.ssr_enabled = false],
		["-volfog", func() -> void: env.volumetric_fog_enabled = false],
		["-ssao", func() -> void: env.ssao_enabled = false],
		["-softsun", func() -> void: sun.light_angular_distance = 0.0],
		["-glow", func() -> void: env.glow_enabled = false],
		["-msaa", func() -> void: vp.msaa_3d = Viewport.MSAA_DISABLED],
		["-grass", func() -> void: hide.call(grass, true)],
		["-trees", func() -> void: hide.call([trees], true)],
		["-kit", func() -> void: hide.call(kit, true)],
		["-dressing", func() -> void: hide.call(dressing, true)],
		["med-kit", func() -> void:
			Settings.set_value("graphics", GraphicsQuality.MEDIUM)
			hide.call(kit, true)],
		["med-trees", func() -> void:
			Settings.set_value("graphics", GraphicsQuality.MEDIUM)
			hide.call([trees], true)],
		["med-dress", func() -> void:
			Settings.set_value("graphics", GraphicsQuality.MEDIUM)
			hide.call(dressing, true)],
		["fsr80", func() -> void:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.8],
		["-treeshadow", func() -> void:
			for mmi in trees.find_children("*", "GeometryInstance3D", true, false):
				(mmi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF],
		["shadow2048", func() -> void: RenderingServer.directional_shadow_atlas_set_size(2048, true)],
		["-shadows", func() -> void: sun.shadow_enabled = false],
		["-probe", func() -> void:
			var probe := game.vehicle.get_node_or_null("Reflection") as Node3D
			if probe:
				probe.visible = false],
		["ultra", func() -> void: Settings.set_value("graphics", GraphicsQuality.ULTRA)],
		["medium", func() -> void: Settings.set_value("graphics", GraphicsQuality.MEDIUM)],
		["low", func() -> void: Settings.set_value("graphics", GraphicsQuality.LOW)],
	]
	var views := [
		["downtown_street", Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0)],
		["avenue_chase", Vector3(2.4, 2.4, -30.0), Vector3(2.4, 1.4, -62.0)],
		["park", Vector3(38.0, 1.7, -77.0), Vector3(36.0, 3.0, -120.0)],
		["aerial", Vector3(95.0, 70.0, 15.0), Vector3(-10.0, 0.0, -110.0)],
		["hill_junction", Vector3(6.0, 3.5, -280.0), Vector3(25.0, 6.0, -322.0)],
		["dt_spawn", Vector3(-117.5, 2.6, 3.0), Vector3(-85.0, 1.8, 3.0)],
		["dt_avenue_south", Vector3(2.4, 2.4, -6.0), Vector3(2.4, 3.0, 45.0)],
	]
	var only_views: PackedStringArray = []
	var only_configs: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only_views = arg.split("=")[1].split(",")
		if arg.begins_with("--configs="):
			only_configs = arg.split("=")[1].split(",")
	var reset := func() -> void:
		hide.call(grass, false)
		hide.call([trees], false)
		hide.call(kit, false)
		hide.call(dressing, false)
		# After un-hiding: the preset decides which kit shadow proxies show.
		Settings.set_value("graphics", GraphicsQuality.HIGH)
		GraphicsQuality.apply(GraphicsQuality.HIGH, vp, world)
		var probe := game.vehicle.get_node_or_null("Reflection") as Node3D
		if probe:
			probe.visible = true
	var lines: PackedStringArray = []
	var cam := game.camera
	cam.set_process(false)
	for view: Array in views:
		if not only_views.is_empty() and not only_views.has(view[0]):
			continue
		cam.global_position = view[1]
		cam.look_at(view[2], Vector3.UP)
		var base := 0.0
		for c: Array in configs:
			if not only_configs.is_empty() and not only_configs.has(c[0]):
				continue
			reset.call()
			(c[1] as Callable).call()
			await _wait(45)  # SDFGI and the LOD settle
			var st: Array = await _render_stats(45)
			if c[0] == "high":
				base = st[2]
			var line := "PERF %-16s %-9s %6.2f ms  (%+6.2f vs high)  %4d calls %8d prims" % [view[0], c[0], st[2], st[2] - base, st[0], st[1]]
			print(line)
			lines.append(line)
	# Driving: 300 m up the avenue and under the highway, 0.5 m a frame.
	for c: Array in configs:
		if not (c[0] in ["high", "-ssil", "-probe", "ultra", "medium"]):
			continue
		if not only_configs.is_empty() and not only_configs.has(c[0]):
			continue
		reset.call()
		(c[1] as Callable).call()
		cam.global_position = Vector3(2.4, 2.4, -20.0)
		cam.look_at(Vector3(2.4, 1.6, -60.0), Vector3.UP)
		# The player's car rides along 8 m ahead, so its reflection probe
		# recaptures as it would in play.
		var car := game.vehicle
		car.freeze = true
		car.global_transform = Transform3D(Basis.IDENTITY, Vector3(2.4, 0.6, -28.0))
		await _wait(45)
		var times: Array[float] = []
		for k in 600:
			cam.global_position.z -= 0.5
			car.global_position.z -= 0.5
			await RenderingServer.frame_post_draw
			times.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
		times.sort()
		var avg := 0.0
		for t in times:
			avg += t
		avg /= times.size()
		var line := "PERF drive            %-9s avg %6.2f ms  p95 %6.2f ms  max %6.2f ms" % [c[0], avg, times[int(times.size() * 0.95)], times[times.size() - 1]]
		print(line)
		lines.append(line)
	reset.call()
	var f := FileAccess.open(_dir.path_join("perf.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")


## Hides one family of meshes at a time and prints what it cost
## (draw calls, primitives, GPU time) in the current view.
func _profile_families(game: Game, view: String) -> void:
	var world := game.world
	var families := {
		"facades": func(n: Node) -> bool: return n.name == &"Facades",
		"roof_clutter": func(n: Node) -> bool: return n.name == &"Clutter",
		"paving": func(n: Node) -> bool: return n.get_parent() != null and n.get_parent().name == &"Paving",
		"roads": func(n: Node) -> bool: return n.get_parent() != null and String(n.get_parent().name) in ["CityRoads", "Highway", "CountryRoads"],
		"trees": func(n: Node) -> bool: return n is MultiMeshInstance3D and (String(n.name).begins_with("broadleaf") or String(n.name).begins_with("conifer")),
		"kit_props": func(n: Node) -> bool: return n is MeshInstance3D and (n.get_parent() is KitProp or (n.get_parent() is TrafficLightProp and (n.get_parent() as TrafficLightProp).model == n)),
		"terrain": func(n: Node) -> bool: return n is MeshInstance3D and String(n.name).begins_with("Chunk_"),
		"kit_buildings": func(n: Node) -> bool: return String(n.name).begins_with("Building_"),
		"kit_dressing": func(n: Node) -> bool: return String(n.name) in ["ShopSigns", "Clutter", "ShopLight", "Yard"] or String(n.name).begins_with("Props_") or String(n.name).begins_with("Markings_"),
		"parked_cars": func(n: Node) -> bool:
			var a := n.get_parent()
			for i in 5:
				if a == null:
					return false
				if a is RigidBody3D and String(a.name).begins_with("Parked"):
					return n is GeometryInstance3D
				a = a.get_parent()
			return false,
		"traffic_signals_lamps": func(n: Node) -> bool: return n is MeshInstance3D and (n.get_parent() is TrafficLightProp or String(n.get_parent().name).begins_with("StreetLamp")),
		"sky_off": func(n: Node) -> bool: return false,
	}
	var base: Array = await _render_stats(40)
	print("PROFILE %-16s all            %4d calls %8d prims %.2f ms" % [view, base[0], base[1], base[2]])
	var meshes := world.find_children("*", "GeometryInstance3D", true, false)
	for fam: String in families:
		var hidden: Array[GeometryInstance3D] = []
		for n in meshes:
			if (families[fam] as Callable).call(n) and (n as GeometryInstance3D).visible:
				(n as GeometryInstance3D).visible = false
				hidden.append(n)
		var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
		var bg := env.background_mode
		if fam == "sky_off":
			env.background_mode = Environment.BG_COLOR
		await _wait(3)
		var st: Array = await _render_stats(40)
		print("PROFILE %-16s -%-13s %+5d calls %+8d prims %+.2f ms (%d nodes)" % [view, fam, st[0] - base[0], st[1] - base[1], st[2] - base[2], hidden.size()])
		for n in hidden:
			n.visible = true
		env.background_mode = bg
		await _wait(3)


## Fixed-camera portraits of every vehicle for comparing the vehicle look
## before and after a change (ART_BIBLE.md §30). The car stands on a sunny
## avenue; cameras sit around it at distances scaled to its size.
##   --vehicles=a,b      catalog ids (default: all)
##   --views=a,b         front34, rear34, side, wheel, chase, lamps (default: all)
##   --times=day,sunset,night (default: all three)
##   --damaged           also a smashed pass (dents, broken lights and glass)
func _lookdev(game: Game) -> void:
	game.traffic.set_enabled(false)
	game.hud.visible = false
	var cam := game.camera
	var args := OS.get_cmdline_user_args()
	var ids: Array = VehicleCatalog.ENTRIES.map(func(e: Dictionary) -> String: return e["id"])
	var views := ["front34", "rear34", "side", "wheel", "chase", "lamps"]
	var times := ["day", "sunset", "night"]
	var damaged := args.has("--damaged")
	for arg in args:
		if arg.begins_with("--vehicles="):
			ids = Array(arg.split("=")[1].split(","))
		elif arg.begins_with("--views="):
			views = Array(arg.split("=")[1].split(","))
		elif arg.begins_with("--times="):
			times = Array(arg.split("=")[1].split(","))
	# A believable paint per vehicle (metallics included).
	var paints := {"sports_car": 0, "sedan": 10, "van": 9, "box_truck": 9, "bus": 6, "pickup": 11, "buggy": 2, "monster_truck": 7}
	var spot := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(2.4, 0.6, -38.0))
	for id: String in ids:
		var vi := VehicleCatalog.index_of_id(id)
		if vi < 0:
			continue
		# Parts knocked off the previous car in its smashed pass.
		for n in game.get_children():
			if n is RigidBody3D and String(n.name).begins_with("Debris"):
				n.queue_free()
		game.change_vehicle(vi, _painted(vi, VehicleCatalog.COLORS[paints.get(id, 0)]), false)
		var v := game.vehicle
		v.teleport(spot.translated(Vector3.UP * v.ride_height()))
		await _wait_s(1.5)
		game.controller.set_physics_process(false)
		for pass_i in (2 if damaged else 1):
			if pass_i == 1:
				_smash_for_photo(v)
				await _wait_s(0.3)
			for t: String in times:
				Settings.set_value("time_of_day", ["day", "sunset", "night"].find(t))
				await _wait(8)
				for view: String in views:
					await _lookdev_view(game, v, view, "%s_%s%s_%s" % [id, view, "_smashed" if pass_i == 1 else "", t])
		game.controller.set_physics_process(true)
		v.brake_input = 0.0
	cam.set_process(true)
	game.hud.visible = true
	Settings.set_value("time_of_day", 0)


func _lookdev_view(game: Game, v: Vehicle, view: String, shot: String) -> void:
	var cam := game.camera
	cam.set_process(false)
	var l := v.body_length()
	var w := v.body_half_width
	var h := v.body_top
	var c := v.global_position + v.global_basis.y * h * 0.45
	var at := c
	var local := Vector3.ZERO
	v.auto_reverse = false
	v.brake_input = 0.0
	v.gear = 1
	match view:
		"front34":
			local = Vector3(-w - l * 0.32, h * 0.8 + 0.4, -l * 0.72)
		"rear34":
			local = Vector3(w + l * 0.32, h * 0.8 + 0.5, l * 0.72)
		"side":
			local = Vector3(w + l * 0.85, h * 0.55 + 0.3, 0.0)
		"wheel":
			var wheel := v.get_node("WheelFL") as VehicleWheel
			at = (wheel.get_node("Visual") as Node3D).global_position
			local = v.global_basis.inverse() * (at - v.global_position) + Vector3(-0.75 - wheel.radius * 2.2, 0.15, -0.55)
		"chase":
			local = Vector3(0.0, 1.9 + h * 0.5, l * 0.5 + 5.0)
			at = v.global_transform * Vector3(0.0, h * 0.6, -l)
		"lamps":
			# Rear three-quarter with the brake lights on (reverse gear shows reverse lamps).
			local = Vector3(-w - l * 0.3, h * 0.6 + 0.4, l * 0.85)
			v.brake_input = 1.0
	cam.global_position = v.global_transform * local
	cam.look_at(at, Vector3.UP)
	await _wait(6)
	await _shot(shot)


## Dents, broken lights and cracked glass without driving into anything.
func _smash_for_photo(v: Vehicle) -> void:
	var dmg := v.get_node("Damage") as VehicleDamage
	var w := v.body_half_width
	var hits := [
		[Vector3(-w * 0.8, 0.35, -v.body_front * 0.92), 0.28, 1.0],
		[Vector3(w * 1.05, 0.45, 0.2), 0.1, 0.8],
		[Vector3(w * 0.7, 0.4, v.body_rear * 0.95), 0.2, 0.9],
	]
	for hit: Array in hits:
		var p: Vector3 = v.global_transform * (hit[0] as Vector3)
		for m in dmg._meshes.size():
			dmg._dent(m, p, hit[1], hit[2], 0.8, 0.9)
	dmg.total_damage = 75.0
	dmg.front_left = 0.9
	dmg._break_headlights()
	dmg._break_taillights()
	dmg._break_glass(v.global_transform * Vector3(-w * 0.5, v.body_top * 0.7, -0.3))
	if dmg._parts.has("FrontBumper"):
		dmg._detach("FrontBumper")
	dmg._update_driving()


# --------------------------------------------------------------- audio test --

var _audio_log: Array[String] = []
var _audio_events: Array[String] = []
var _audio_t := 0.0
## While set, every physics tick advances _audio_t and samples its state.
var _audio_watch: VehicleAudio
var _audio_seen := {}


func _physics_process(dt: float) -> void:
	if _audio_watch == null or not is_instance_valid(_audio_watch):
		return
	_audio_t += dt
	var st := _audio_state(_audio_watch)
	for k: String in st:
		if st[k] is bool:
			_audio_seen[k] = bool(_audio_seen.get(k, false)) or st[k]
		else:
			_audio_seen[k] = maxf(float(_audio_seen.get(k, 0.0)), float(st[k]))


## Drives a scripted session and records what the game sounds like
## (AudioEffectRecord on the master bus -> <dir>/session.wav), with a state
## log (<dir>/session.csv: engine rpm/load, active voices, layer levels) and
## the times of deliberate one-shots (<dir>/events.txt) so
## tools/audio/check_recording.py can tell clicks from crashes. Then checks
## the traffic voice budget. Run with --audio-driver Dummy so nothing plays
## out loud (the dummy driver still mixes).
##   --vehicle=<id> to test another vehicle
## The dev audio mix panel (AudioMixPanel): opens with F8 while driving,
## doesn't take the controls, its sliders change the buses at once, saving
## writes only the changed values. Shots: <dir>/panel_*.png.
func _mixpanel(game: Game) -> void:
	var panel := get_node_or_null("/root/AudioMixPanel")
	_check(panel != null and panel.has_method("toggle") and not panel.is_open(), "panel autoload present, closed")
	if panel == null:
		return
	var v := game.vehicle
	var start := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(2.4, 0.6, 140.0))
	v.teleport(start.translated(Vector3.UP * v.ride_height()))
	await _wait_s(0.5)
	var f8 := InputEventKey.new()
	f8.physical_keycode = KEY_F8
	f8.pressed = true
	Input.parse_input_event(f8)
	await _wait(2)
	_check(panel.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "F8 opens it (mouse / touch free)")
	Input.action_press("accelerate", 1.0)
	await _wait_s(3.0)
	Input.action_release("accelerate")
	var kmh := v.linear_velocity.length() * 3.6
	_check(kmh > 25.0, "still drives with the panel open (%.0f km/h)" % kmh)
	var rows: Dictionary = panel._rows
	(rows["engine.volume_db"].slider as HSlider).value = 5.0
	(rows["skid.treble_db"].slider as HSlider).value = -12.0
	var engine_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Engine"))
	var shelf := AudioMix._fx("Skid", "treble") as AudioEffectFilter
	_check(is_equal_approx(engine_db, 5.0) and absf(40.0 * log(shelf.gain) / log(10.0) + 12.0) < 0.01,
		"sliders apply at once (engine %.1f dB, skid shelf %.1f dB)" % [engine_db, 40.0 * log(shelf.gain) / log(10.0)])
	var path := _dir.path_join("mix_test.cfg")
	AudioMix._save(path, true)
	var cfg := ConfigFile.new()
	cfg.load(path)
	var prof := AudioMix.profile()
	_check(cfg.get_value(prof, "engine.volume_db", 0.0) == 5.0 and cfg.get_section_keys(prof).size() == 2,
		"save keeps only what changed (%s)" % ", ".join(cfg.get_section_keys(prof)))
	await _wait_s(0.5)
	await _shot("panel_open")
	for c in panel.find_children("*", "Button", true, false):
		if (c as Button).text.begins_with("+ Engine"):
			(c as Button).pressed.emit()
	await _wait(3)
	await _shot("panel_engine")
	AudioMix.set_profile("deck")
	panel._sync()
	var eq_on := AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(&"Engine"), 0)
	_check(AudioMix.profile() == "deck" and eq_on, "profile switch applies the deck values (engine EQ on)")
	AudioMix.reset_profile()
	AudioMix.set_profile(prof)
	AudioMix.reset_profile()
	Input.parse_input_event(f8.duplicate())
	await _wait(2)
	_check(not panel.is_open(), "F8 closes it")


func _audio(game: Game) -> void:
	game.traffic.set_enabled(false)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	# --stems: each mix bus recorded too (after its effects, before its
	# fader), <dir>/stem_<bus>.wav, for checking the mix category by category.
	var stems := {}
	if "--stems" in OS.get_cmdline_user_args():
		for bus in ["Engine", "Tyres", "Surface", "Skid", "Impacts", "Environment", "Signals", "Traffic", "TrafficEngine"]:
			var r := AudioEffectRecord.new()
			AudioServer.add_bus_effect(AudioServer.get_bus_index(StringName(bus)), r)
			stems[bus] = r
		# Each stem's faders down to the master (for the analysis).
		var faders := []
		for bus: String in stems:
			var idx := AudioServer.get_bus_index(StringName(bus))
			var total := 0.0
			while idx > 0:
				total += AudioServer.get_bus_volume_db(idx)
				idx = AudioServer.get_bus_index(AudioServer.get_bus_send(idx))
			faders.append("%s=%.1f" % [bus, total])
		print("MIXFADERS %s %s" % [AudioMix.profile(), " ".join(faders)])
	var v := game.vehicle
	var audio := v.get_node("Audio") as VehicleAudio
	_check(audio != null and audio.detail == VehicleAudio.Detail.FULL and audio.profile != null, "player has FULL vehicle audio with a profile")
	# A long straight: the avenue north of the city centre.
	var start := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(2.4, 0.6, 140.0))
	v.teleport(start.translated(Vector3.UP * v.ride_height()))
	await _wait_s(0.5)
	rec.set_recording_active(true)
	for r: AudioEffectRecord in stems.values():
		r.set_recording_active(true)
	_audio_t = 0.0
	_audio_seen = {}
	_audio_watch = audio
	VehicleAudio.on_shot = func(path: String, _pos: Vector3) -> void:
		_audio_events.append("%.2f shot %s" % [_audio_t, path.get_file()])
	VehicleAudio.on_voice = func(path: String, what: String) -> void:
		_audio_events.append("%.2f voice %s %s" % [_audio_t, what, path.get_file()])
	audio.start_engine()
	_audio_events.append("0.00 startup")
	var phases := [
		[3.0, "idle", {}],
		[9.0, "full throttle", {"accelerate": 1.0}],
		[13.0, "coast", {}],
		[16.5, "brake", {"brake": 1.0}],
		[18.0, "idle", {}],
		[19.2, "horn", {"horn": 1.0}],
		[21.0, "throttle", {"accelerate": 1.0}],
		[23.5, "handbrake slide", {"accelerate": 0.6, "handbrake": 1.0, "steer_right": 1.0}],
		[26.0, "recover", {"brake": 1.0}],
	]
	for ph: Array in phases:
		var keys: Dictionary = ph[2]
		_audio_events.append("%.2f phase %s" % [_audio_t, ph[1]])
		for k: String in keys:
			Input.action_press(k, keys[k])
		while _audio_t < float(ph[0]):
			await get_tree().physics_frame
		for k: String in keys:
			Input.action_release(k)
	_check(bool(_audio_seen.get("engine_on", false)) and float(_audio_seen.get("engine", 0)) <= 4.0,
		"engine layers play, at most 4 at once (max %d)" % int(_audio_seen.get("engine", 0)))
	var rp: AudioStreamPlayer3D = audio._loops.get("roll")
	_check(_audio_seen.get("roll", false), "tyre roll plays while moving%s" % ("" if _audio_seen.get("roll", false) else
		" (player %s)" % ("missing" if rp == null else "playing=%s paused=%s starting=%s db=%.0f stream=%s inside=%s" % [rp.playing,
		rp.stream_paused, rp.get_meta("starting", false), rp.volume_db, rp.stream, rp.is_inside_tree()])))
	_check(_audio_seen.get("squeal", false), "tyre squeal plays in the handbrake slide")
	_check(_audio_seen.get("horn", false), "horn plays while held")
	_check(not _audio_seen.get("bad", false), "no NaN/inf levels")
	# Gravel: the dirt fields.
	v.teleport(game.world.spawn_points[4]["xform"])
	_audio_events.append("%.2f teleport dirt" % _audio_t)
	await _wait_s(0.6)
	_audio_events.append("%.2f phase gravel" % _audio_t)
	Input.action_press("accelerate")
	_audio_seen["gravel"] = false
	await _wait_s(4.0)
	Input.action_release("accelerate")
	_check(_audio_seen.get("gravel", false), "gravel roll plays on the dirt fields")
	# A crash: shots must fire.
	_audio_events.append("%.2f phase crash run" % _audio_t)
	var shots := [0]
	var first := [true]
	v.impact.connect(func(_s: float, _p: Vector3, _n: Vector3) -> void:
		shots[0] += 1
		if first[0]:
			first[0] = false
			_audio_events.append("%.2f impact" % _audio_t))
	_audio_seen["shot"] = false
	# _ram_wall moves the car without snapping the camera: the camera catching
	# up dips the level for a moment (like a teleport).
	_audio_events.append("%.2f teleport ram" % _audio_t)
	await _ram_wall(game, 55.0)
	_check(shots[0] > 0 and _audio_seen.get("shot", false), "crash plays impact sounds (%d impacts)" % shots[0])
	# Pausing (menus) silences vehicle sound.
	await _wait_s(1.0)
	get_tree().paused = true
	await _wait_s(0.3)
	var playing := 0
	for p in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		var pl := p as AudioStreamPlayer3D
		if pl.playing and not pl.stream_paused and pl.can_process():
			playing += 1
	var level := AudioServer.get_bus_peak_volume_left_db(0, 0)
	get_tree().paused = false
	_check(playing == 0 and level < -50.0, "paused game is silent (%d players running, master %.0f dB)" % [playing, level])
	_audio_watch = null
	VehicleAudio.on_shot = Callable()
	VehicleAudio.on_voice = Callable()
	rec.set_recording_active(false)
	for bus: String in stems:
		var r: AudioEffectRecord = stems[bus]
		r.set_recording_active(false)
		var stem := r.get_recording()
		if stem:
			stem.save_to_wav(_dir.path_join("stem_%s.wav" % bus))
		var bi := AudioServer.get_bus_index(StringName(bus))
		AudioServer.remove_bus_effect(bi, AudioServer.get_bus_effect_count(bi) - 1)
	var wav := rec.get_recording()
	if wav:
		wav.save_to_wav(_dir.path_join("session.wav"))
	var f := FileAccess.open(_dir.path_join("session.csv"), FileAccess.WRITE)
	f.store_string("t,rpm,load,gear,speed,skid,voices,engine_layers,engine_gain_db\n" + "\n".join(_audio_log) + "\n")
	f = FileAccess.open(_dir.path_join("events.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_audio_events) + "\n")
	print("AUDIO player car: at most %d voices playing, recorded %.1f s" % [int(_audio_seen.get("voices", 0)), _audio_t])
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	await _audio_traffic(game)


## Samples one vehicle's audio state; logs it to the CSV 20 times a second.
func _audio_state(audio: VehicleAudio) -> Dictionary:
	var voices := 0
	var engine := 0
	var engine_db := -80.0
	var bad := false
	for p in audio.find_children("*", "AudioStreamPlayer3D", false, false):
		var pl := p as AudioStreamPlayer3D
		if pl.playing and not pl.stream_paused:
			voices += 1
			if not is_finite(pl.volume_db) or not is_finite(pl.pitch_scale):
				bad = true
	for pl in audio._on + audio._off:
		if pl.playing and not pl.stream_paused and pl.volume_db > -60.0:
			engine += 1
			engine_db = maxf(engine_db, pl.volume_db)
	var on := func(k: String) -> bool:
		var p: AudioStreamPlayer3D = audio._loops.get(k)
		return p != null and p.playing and not p.stream_paused
	var shot := false
	for p in audio._shots:
		shot = shot or p.playing
	var v := audio.vehicle
	var dt := get_physics_process_delta_time()
	if int(_audio_t * 20.0) != int((_audio_t - dt) * 20.0):
		_audio_log.append("%.2f,%.0f,%.2f,%d,%.1f,%.2f,%d,%d,%.1f" % [_audio_t, v.engine_rpm, v.engine_load, v.gear,
			v.linear_velocity.length() * 3.6, v.get_skid_amount(), voices, engine, engine_db])
	return {"voices": voices, "engine": engine, "engine_on": engine > 0, "squeal": on.call("squeal"), "horn": on.call("horn"),
		"roll": on.call("roll"), "gravel": on.call("gravel"), "shot": shot, "bad": bad}


## Traffic: voices stay within the budget and pass-bys are heard.
func _audio_traffic(game: Game) -> void:
	var tm := game.traffic
	game.vehicle.teleport(Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(-6.0, 0.8, -60.0)))
	tm.set_enabled(true)
	await _wait_s(8.0)
	var director := AudioDirector.instance
	var max_voiced := 0
	var max_players := 0
	var t := 0.0
	while t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		max_voiced = maxi(max_voiced, director.voiced_count() if director else 99)
		var players := 0
		for d in tm.drivers:
			for p in d.vehicle.get_node("Audio").find_children("*", "AudioStreamPlayer3D", false, false):
				if (p as AudioStreamPlayer3D).playing and not (p as AudioStreamPlayer3D).stream_paused:
					players += 1
		max_players = maxi(max_players, players)
	_check(director != null and max_voiced <= AudioDirector.MAX_VOICES, "traffic engine voices within budget (%d cars, at most %d voiced, budget %d)" % [
		tm.drivers.size(), max_voiced, AudioDirector.MAX_VOICES])
	_check(max_players <= AudioDirector.MAX_VOICES * 3 + 6, "traffic players playing at once: %d" % max_players)


## Driving down the city avenue at 80 km/h (the player's reflection probe
## re-captures every 14 m): render CPU/GPU time and draw calls with the
## probe on and off. Then, with traffic, the game's CPU use (all threads,
## from /proc on Linux) with vehicle sound on and with every vehicle's
## sound stopped: what the sound costs.
func _bench_drive(game: Game) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	game.traffic.set_enabled(false)
	for probe_on in [true, false]:
		var probe := game.vehicle.get_node_or_null("Reflection")
		if probe and not probe_on:
			probe.free()
		elif probe == null and probe_on:
			game._fit_reflection()
		_drive_line(game, Vector3(2.4, 0.0, 150.0), Vector3(2.4, 0.0, -260.0), 80.0, 14.0)
		await _wait_s(3.0)
		var st := await _frame_stats(300)
		print("BENCH drive probe %-3s %4d draw calls (max %d), cpu %.2f ms (peak %.2f), gpu %.2f ms (peak %.2f), car at %.0f km/h" % [
			"on" if probe_on else "off", st[0], st[5], st[1], st[2], st[3], st[4], game.vehicle.speed_kmh])
		await _wait_s(4.0)
	game._fit_reflection()
	# Sound cost, with traffic around.
	game.traffic.set_enabled(true)
	game.teleport_to(0)
	await _wait_s(8.0)
	for sound_on in [true, false]:
		var audios := get_tree().root.find_children("Audio", "VehicleAudio", true, false)
		for a in audios:
			(a as VehicleAudio).set_process(sound_on)
			if not sound_on:
				for p in (a as Node).find_children("*", "AudioStreamPlayer3D", false, false):
					(p as AudioStreamPlayer3D).stop()
		_drive_line(game, Vector3(2.4, 0.0, 150.0), Vector3(2.4, 0.0, -260.0), 60.0, 12.0)
		await _wait_s(1.0)
		var voices := 0
		for p in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
			if (p as AudioStreamPlayer3D).playing and not (p as AudioStreamPlayer3D).stream_paused:
				voices += 1
		var c0 := _cpu_seconds()
		var t0 := Time.get_ticks_usec()
		await _wait_s(8.0)
		var cpu := (_cpu_seconds() - c0) / ((Time.get_ticks_usec() - t0) / 1e6)
		print("BENCH sound %-3s %d players playing, game process cpu %.2f cores" % ["on" if sound_on else "off", voices, cpu])
	for a in get_tree().root.find_children("Audio", "VehicleAudio", true, false):
		(a as VehicleAudio).set_process(true)


## [draw calls, cpu ms, cpu peak, gpu ms, gpu peak, draw calls peak] over
## `frames` frames.
func _frame_stats(frames: int) -> Array:
	var vp := get_viewport().get_viewport_rid()
	var calls := 0
	var cpu := 0.0
	var gpu := 0.0
	var cpu_peak := 0.0
	var gpu_peak := 0.0
	var calls_peak := 0
	for k in frames:
		await RenderingServer.frame_post_draw
		var c_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		calls += c_calls
		calls_peak = maxi(calls_peak, c_calls)
		var c := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += c
		gpu += g
		cpu_peak = maxf(cpu_peak, c)
		gpu_peak = maxf(gpu_peak, g)
	return [calls / frames, cpu / frames, cpu_peak, gpu / frames, gpu_peak, calls_peak]


## This process's CPU time so far (user + system, all threads), Linux only.
func _cpu_seconds() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0.0
	# procfs files report size 0, so read the line rather than the "whole file".
	var parts := f.get_line().split(") ")[1].split(" ")
	# Fields 14 and 15 (utime, stime) are parts 11 and 12 after the comm field.
	return (float(parts[11]) + float(parts[12])) / 100.0


# --- On foot: the character and getting in and out of vehicles ---------------

const FOOT_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump", "interact"]


func _foot_release() -> void:
	for a: String in FOOT_ACTIONS:
		Input.action_release(a)


## Pushes the move stick toward world direction `dir` (0..1 strength),
## relative to the on-foot camera, like a player would.
func _foot_push(game: Game, dir: Vector3, strength := 1.0) -> void:
	var f := -game.foot_camera.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP)
	dir.y = 0.0
	var d := dir.normalized() * strength
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	var x := d.dot(r)
	var y := d.dot(f)
	if y > 0.01:
		Input.action_press("move_forward", y)
	elif y < -0.01:
		Input.action_press("move_back", -y)
	if x > 0.01:
		Input.action_press("move_right", x)
	elif x < -0.01:
		Input.action_press("move_left", -x)


## Walks the character toward `target` until within `stop` metres or `limit` s.
func _foot_walk_to(game: Game, target: Vector3, stop := 0.6, limit := 8.0) -> bool:
	var t := 0.0
	while t < limit:
		var to := target - game.character.global_position
		to.y = 0.0
		if to.length() < stop:
			_foot_release()
			return true
		_foot_push(game, to, 1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_foot_release()
	return false


## Average ground speed over `seconds` while pushing toward `dir`.
func _foot_speed(game: Game, dir: Vector3, strength: float, seconds: float, extra := "") -> float:
	if extra != "":
		Input.action_press(extra)
	_foot_push(game, dir, strength)
	await _wait_s(0.8)  # get up to speed
	var p0 := game.character.global_position
	await _wait_s(seconds)
	var p1 := game.character.global_position
	_foot_release()
	return Vector2(p1.x - p0.x, p1.z - p0.z).length() / seconds


## Does the character's capsule overlap anything solid at `feet`?
func _overlaps(game: Game, feet: Vector3, exclude: Array[RID] = []) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.95)
	q.collision_mask = 0b111
	q.exclude = exclude
	for hit in game.get_world_3d().direct_space_state.intersect_shape(q, 4):
		var col: Object = hit["collider"]
		if col is RigidBody3D and not (col is Vehicle) and (col as RigidBody3D).mass < 150.0:
			continue
		return true
	return false


## Waits until the Possession reaches `mode` (or `limit` seconds pass), then
## until the interact button works again.
func _wait_mode(game: Game, mode: Possession.Mode, limit := 4.0) -> bool:
	var t := 0.0
	while game.possession.mode != mode and t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if game.possession.mode == mode:
		await _wait_s(Possession.COOLDOWN + 0.05)
	return game.possession.mode == mode


## A vehicle of catalog `id` parked upright on the ground at `pos` facing `fwd`.
func _park_new(game: Game, id: String, pos: Vector3, fwd: Vector3) -> Vehicle:
	var car := VehicleCatalog.scene(VehicleCatalog.index_of_id(id)).instantiate() as Vehicle
	var space := game.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 5.0, pos + Vector3.DOWN * 10.0, 1))
	if not hit.is_empty():
		pos = hit["position"]
	var xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos + Vector3.UP * (car.ride_height() + 0.1))
	car.transform = xf
	var holder := game.get_node_or_null("TestVehicles")
	if holder == null:
		holder = Node3D.new()
		holder.name = "TestVehicles"
		game.add_child(holder)
	holder.add_child(car)
	car.teleport(xf)
	return car


func _ground(game: Game, p: Vector3) -> Vector3:
	var space := game.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 10.0, 1))
	return hit["position"] if not hit.is_empty() else p


func _wall(game: Game, center: Vector3, size: Vector3, yaw: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	wall.add_child(mi)
	game.add_child(wall)
	wall.global_transform = Transform3D(Basis(Vector3.UP, yaw), center)
	return wall


## Gets in (interact pressed), checks, drives forward for `seconds`, gets out
## (interact again) and checks the exit. Returns the vehicle driven.
func _enter_drive_exit(game: Game, v: Vehicle, label: String, seconds := 2.0, use_pad := false) -> void:
	var p := game.possession
	if use_pad:
		await _pad(JOY_BUTTON_B)
	else:
		await _tap("interact")
	var entered := await _wait_mode(game, Possession.Mode.IN_VEHICLE, 3.0)
	_check(entered and p.vehicle == v and game.vehicle == v, "%s: got in (%s)" % [label, "gamepad B" if use_pad else "F"])
	if not entered:
		return
	var c := Controllable.of(v)
	_check(game.controller.vehicle == v and game.foot_controller.character == null and c.controller == p,
		"%s: the player's vehicle controller drives it, nothing else" % label)
	_check(not game.character.visible and game.character.collision_layer == 0, "%s: character hidden, no collisions" % label)
	var audio := v.get_node_or_null("Audio") as VehicleAudio
	_check(audio == null or (audio.detail == VehicleAudio.Detail.FULL and audio.engine_running), "%s: full engine sound, engine running" % label)
	_check(game.traffic.player == v and game.hud.vehicle == v and game.camera.target == v, "%s: traffic, HUD and camera follow it" % label)
	await _wait_s(0.9)
	_check(game.camera.current, "%s: chase camera after the blend" % label)
	var p0 := v.global_position
	Input.action_press("accelerate")
	await _wait_s(seconds)
	Input.action_release("accelerate")
	var moved := v.global_position.distance_to(p0)
	_check(moved > 4.0, "%s: drives (%.1f m in %.1f s, %.0f km/h)" % [label, moved, seconds, v.speed_kmh])
	await _shot("onfoot_%s_driving" % label.to_snake_case())
	await _tap("interact")
	var out := await _wait_mode(game, Possession.Mode.ON_FOOT, 6.0)
	_check(out, "%s: got out (from %.0f km/h)" % [label, v.speed_kmh])
	if not out:
		return
	await _wait_s(0.5)
	var ch := game.character
	var d := ch.global_position.distance_to(v.global_position)
	_check(d < v.body_length() * 0.5 + 4.0, "%s: out next to it (%.1f m from its centre)" % [label, d])
	_check(not _overlaps(game, ch.global_position), "%s: standing clear of everything" % label)
	_check(ch.is_on_floor() and ch.visible, "%s: on the ground, visible" % label)
	_check(v.linear_velocity.length() < 1.0 and v.handbrake_input, "%s: parked, handbrake on" % label)
	_check(audio == null or (audio.detail == VehicleAudio.Detail.LITE and not audio.engine_running), "%s: engine off, quiet sound" % label)
	_check(game.controller.vehicle == null and game.foot_controller.character == ch and c.is_free(), "%s: controls back on the character" % label)
	await _wait_s(0.7)
	_check(game.foot_camera.current, "%s: on-foot camera after the blend" % label)


func _onfoot(game: Game) -> void:
	var p := game.possession
	var ch := game.character
	var tm := game.traffic
	tm.set_enabled(false)
	await _wait_s(1.0)

	# --- Start on foot ---
	_check(p.on_foot() and ch.visible and ch.state == PlayerCharacter.State.ACTIVE, "starts on foot")
	_check(game.foot_camera.current, "on-foot camera is showing")
	_check(game.controller.vehicle == null and game.foot_controller.character == ch, "only the character is controlled")
	_check(ch.global_position.distance_to(game.vehicle.global_position) < 4.0,
		"standing next to the vehicle (%.1f m)" % ch.global_position.distance_to(game.vehicle.global_position))
	_check(not game.hud.speedometer.visible and game.hud.minimap.target == ch and game.hud.minimap.car == game.vehicle,
		"HUD on foot: no speedometer, map follows the character and marks the vehicle")
	_check(tm.focus == ch, "traffic is centred on the character")
	await _shot("onfoot_spawn")

	# --- Teleport on foot: the vehicle comes along ---
	game.teleport_to(6)  # Airfield: a big flat apron
	await _wait_s(1.0)
	var car := game.vehicle
	_check(p.on_foot() and ch.global_position.distance_to(car.global_position) < 4.5, "teleport on foot: vehicle comes along, character beside it")
	_check(not _overlaps(game, ch.global_position), "teleport on foot: character clear of the vehicle")

	# --- Walk, run, sprint, jump: on the runway (long, flat, nothing on it yet) ---
	var away := Vector3.RIGHT
	ch.place(Transform3D(Basis.looking_at(away, Vector3.UP), _ground(game, Vector3(330.0, 1.0, 296.0))))
	game.foot_camera.yaw = atan2(-away.x, -away.z)
	game.foot_camera.snap()
	await _wait_s(0.5)
	game.foot_camera.yaw = atan2(-away.x, -away.z)
	var walk := await _foot_speed(game, away, 0.45, 1.5)
	var anim_walk := ch._current_anim
	_check(walk > 0.8 and walk < 2.2 and anim_walk == "walk", "gentle push walks (%.2f m/s, %s)" % [walk, anim_walk])
	_foot_push(game, -away, 1.0)
	await _wait_s(0.3)
	await _shot("onfoot_walk_turn")
	_foot_release()
	await _wait_s(0.4)
	var run := await _foot_speed(game, away, 1.0, 1.5)
	_check(run > 3.5 and run < 5.0 and ch._current_anim == "run", "full push runs (%.2f m/s, %s)" % [run, ch._current_anim])
	var slow := await _foot_speed(game, -away, 1.0, 1.5, "walk")
	_check(slow > 0.8 and slow < 2.0, "Ctrl walks (%.2f m/s)" % slow)
	_foot_push(game, away, 1.0)
	Input.action_press("sprint")
	await _wait_s(1.0)
	await _shot("onfoot_sprint")
	var sp0 := ch.global_position
	await _wait_s(1.0)
	var sprint := Vector2(ch.global_position.x - sp0.x, ch.global_position.z - sp0.z).length()
	_check(sprint > 5.5 and ch._current_anim == "sprint", "Shift sprints (%.2f m/s, %s)" % [sprint, ch._current_anim])
	_foot_release()
	await _wait_s(0.8)
	_check(ch.ground_speed < 0.3 and ch._current_anim == "idle", "stops and idles (%s)" % ch._current_anim)
	await _shot("onfoot_idle")
	# Gamepad: left stick moves, L3 click sprints until the stick is let go.
	game.foot_camera.yaw = atan2(-away.x, -away.z)
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = -1.0
	Input.parse_input_event(ev)
	await _pad(JOY_BUTTON_LEFT_STICK)
	await _wait_s(1.2)
	_check(ch.ground_speed > 5.5, "gamepad: stick + L3 sprints (%.1f m/s)" % ch.ground_speed)
	ev.axis_value = 0.0
	Input.parse_input_event(ev)
	await _wait_s(0.8)
	var y0 := ch.global_position.y
	await _tap("jump")
	await _wait_s(0.25)
	var rise := ch.global_position.y - y0
	await _shot("onfoot_jump")
	_check(rise > 0.3 and not ch.is_on_floor(), "jumps (%.2f m up after 0.25 s)" % rise)
	await _wait_s(1.2)
	_check(ch.is_on_floor(), "lands")

	# --- Walk to the vehicle, prompt, get in, drive, get out ---
	# From 6 m out to the side of the driver's door.
	var door := (car.get_node("Entry") as VehicleEntry).door_spot(car.global_position - car.global_basis.x * 5.0)
	var out_dir := (door - car.global_position) * Vector3(1, 0, 1)
	ch.place(Transform3D(Basis.IDENTITY, _ground(game, door + out_dir.normalized() * 6.0)))
	game.foot_camera.snap()
	await _wait_s(0.5)
	var reached := await _foot_walk_to(game, door, 0.9)
	await _wait_s(0.3)
	_check(reached and game.hud.prompt_text().begins_with("Get in the"), "walking up shows the prompt ('%s')" % game.hud.prompt_text())
	await _shot("onfoot_prompt")
	# Press, then watch every physics tick: walking to the door, the camera gliding.
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	var walked := false
	var glided := false
	for i in 240:
		await get_tree().physics_frame
		if p.mode == Possession.Mode.ENTERING:
			walked = walked or ch.state == PlayerCharacter.State.SCRIPTED
			glided = glided or game.camera_blend.current
		if p.mode != Possession.Mode.ON_FOOT:
			break
	press.pressed = false
	Input.parse_input_event(press)
	_check(walked and glided, "getting in: walks to the door, camera glides")
	await _shot("onfoot_entering")
	await _tap("interact")  # pressing again mid-way changes nothing
	while p.mode == Possession.Mode.ENTERING:
		await get_tree().physics_frame
	await _tap("interact")  # nor does mashing it right after getting in
	await _wait_s(0.2)
	_check(p.driving() and p.vehicle == car, "in the vehicle (presses while getting in and just after are ignored; mode %d)" % p.mode)
	await _wait_s(0.6)
	# Re-press out at once and get back in: covered below. Drive + exit:
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	(car.get_node("Entry") as VehicleEntry).interact(ch)
	await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	p.exit()
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	await _enter_drive_exit(game, car, "Sports Car", 3.0)
	await _shot("onfoot_out_of_car")
	# Getting out keeps the view's heading (no swing round): the on-foot camera
	# starts looking the way the chase camera looked.
	(car.get_node("Entry") as VehicleEntry).interact(ch)
	await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	await _wait_s(1.5)
	var chase_f := -game.camera.global_basis.z
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	var foot_f := -game.foot_camera.global_basis.z
	var turn := rad_to_deg(Vector2(chase_f.x, chase_f.z).angle_to(Vector2(foot_f.x, foot_f.z)))
	_check(absf(turn) < 35.0, "getting out keeps the view's heading (turned %.0f deg)" % turn)
	_check(not game.start_replay(), "no instant replay on foot")

	# --- Every vehicle type: get in with the gamepad, drive, get out ---
	# Along the runway (x 285..525, z 300), 35 m apart, facing down it.
	var fwd := Vector3.RIGHT
	var right := fwd.cross(Vector3.UP)
	var k := 0
	for id: String in ["sedan", "van", "pickup", "box_truck", "bus", "buggy", "monster_truck"]:
		var v := _park_new(game, id, Vector3(292.0 + 35.0 * k, 1.0, 300.0), fwd)
		k += 1
		await _wait_s(0.6)
		var entry := v.get_node("Entry") as VehicleEntry
		var door_l := entry.door_spot(v.global_position - right * 5.0)
		ch.place(Transform3D(Basis.IDENTITY, _ground(game, door_l - right * 3.0)))
		game.foot_camera.snap()
		await _wait_s(0.3)
		await _foot_walk_to(game, door_l, 0.8)
		await _wait_s(0.3)
		await _enter_drive_exit(game, v, v.display_name, 2.0, k % 2 == 1)
	_check(game.left_vehicles.size() <= Game.MAX_LEFT_VEHICLES + 1, "left vehicles kept in check (%d)" % game.left_vehicles.size())

	# --- Exits by walls ---
	var wcar := _park_new(game, "sedan", Vector3(360.0, 1.0, 250.0), fwd)
	await _wait_s(0.5)
	var wr := wcar.global_basis.x
	var hw := wcar.body_half_width
	var len := wcar.body_length() + 2.0
	var left_wall := _wall(game, wcar.global_position - wr * (hw + 0.35), Vector3(0.4, 3.0, len), atan2(fwd.x, fwd.z))
	ch.place(Transform3D(Basis.IDENTITY, _ground(game, wcar.global_position + wr * (hw + 1.0))))
	await _wait_s(0.3)
	(wcar.get_node("Entry") as VehicleEntry).interact(ch)
	await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	await _wait_s(0.3)
	var side := (ch.global_position - wcar.global_position).dot(wr)
	_check(side > hw, "wall on the driver's side: out on the passenger side (%.1f m right)" % side)
	_check(not _overlaps(game, ch.global_position), "wall on the driver's side: clear of the wall")
	await _shot("onfoot_exit_wall_left")
	var right_wall := _wall(game, wcar.global_position + wr * (hw + 0.35), Vector3(0.4, 3.0, len), atan2(fwd.x, fwd.z))
	(wcar.get_node("Entry") as VehicleEntry).interact(ch)
	await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	await _wait_s(0.3)
	var along := (ch.global_position - wcar.global_position).dot(-wcar.global_basis.z)
	_check(absf(along) > wcar.body_length() * 0.5 - 0.2 and not _overlaps(game, ch.global_position),
		"walls on both sides: out at the front or back (%.1f m along)" % along)
	await _shot("onfoot_exit_walls_both")
	# Boxed in front and back too: out on the roof (or not at all).
	var front_wall := _wall(game, wcar.global_position - wcar.global_basis.z * (wcar.body_front + 0.5), Vector3(hw * 2.0 + 1.2, 3.0, 0.4), atan2(fwd.x, fwd.z))
	var back_wall := _wall(game, wcar.global_position + wcar.global_basis.z * (wcar.body_rear + 0.5), Vector3(hw * 2.0 + 1.2, 3.0, 0.4), atan2(fwd.x, fwd.z))
	(wcar.get_node("Entry") as VehicleEntry).interact(ch)
	var boxed_in := await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	if not boxed_in:
		# Couldn't reach the car from the gap: put the player in directly.
		game.adopt_vehicle(wcar)
		p.start_in_vehicle(wcar)
	await _tap("interact")
	await _wait_s(1.0)
	var on_roof := p.on_foot() and ch.global_position.y > wcar.global_position.y + 0.3
	var stayed := p.driving()
	_check((on_roof and not _overlaps(game, ch.global_position)) or stayed, "boxed in: out onto the roof, or stays in (%s)" % ("roof" if on_roof else "stayed in" if stayed else "??"))
	await _shot("onfoot_exit_boxed_in")
	if p.driving():
		for w in [left_wall, right_wall, front_wall, back_wall]:
			w.queue_free()
		await _wait_s(0.2)
		await _tap("interact")
		await _wait_mode(game, Possession.Mode.ON_FOOT)
	else:
		for w in [left_wall, right_wall, front_wall, back_wall]:
			w.queue_free()
	await _wait_s(1.0)

	# --- Overturned vehicle: get out, then flip it back over ---
	(wcar.get_node("Entry") as VehicleEntry).interact(ch)
	await _wait_mode(game, Possession.Mode.IN_VEHICLE)
	wcar.global_transform = Transform3D(wcar.global_basis.rotated(wcar.global_basis.z, PI), wcar.global_position + Vector3.UP * 1.2)
	wcar.reset_physics_interpolation()
	await _wait_s(2.0)
	await _tap("interact")
	var flipped_out := await _wait_mode(game, Possession.Mode.ON_FOOT, 5.0)
	await _wait_s(0.4)
	_check(flipped_out and not _overlaps(game, ch.global_position), "upside down: gets out clear of it")
	var fe := wcar.get_node("Entry") as VehicleEntry
	_check(fe.is_overturned() and fe.prompt(ch).begins_with("Flip"), "upside down: prompt offers to flip it ('%s')" % fe.prompt(ch))
	await _foot_walk_to(game, wcar.global_position, wcar.body_half_width + 0.9)
	await _wait_s(0.3)
	await _shot("onfoot_flip_prompt")
	await _tap("interact")
	await _wait_s(1.5)
	_check(not fe.is_overturned(), "flipping it puts it back on its wheels")

	# --- A damaged vehicle: crash it, get out, get back in, it still drives ---
	car = game.vehicle
	game.ensure_driving()
	await _ram_wall(game, 55.0)
	var dmg := car.get_node("Damage") as VehicleDamage
	var hurt := dmg.total_damage
	_check(hurt > 10.0, "crashed (%.0f%% damage)" % hurt)
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT, 5.0)
	await _wait_s(0.4)
	_check(p.on_foot() and not _overlaps(game, ch.global_position), "damaged: gets out")
	await _shot("onfoot_damaged_car")
	await _foot_walk_to(game, (car.get_node("Entry") as VehicleEntry).door_spot(ch.global_position), 0.8)
	await _enter_drive_exit(game, car, "Damaged " + car.display_name.to_lower(), 2.0)
	_check(dmg.total_damage >= hurt - 0.01, "damage stays (%.0f%%)" % dmg.total_damage)

	# --- Bumped by a moving car: knocked aside, unhurt, the car barely notices ---
	var bump := _park_new(game, "sedan", Vector3(300.0, 1.0, 290.0), fwd)
	await _wait_s(0.5)
	ch.place(Transform3D(Basis.IDENTITY, _ground(game, bump.global_position + fwd * 12.0)))
	await _wait_s(0.3)
	var knocked := [false]
	ch.knocked.connect(func(_s: float) -> void: knocked[0] = true, CONNECT_ONE_SHOT)
	bump.linear_velocity = fwd * 9.0
	var v_before := 9.0
	await _wait_s(1.6)
	_check(knocked[0], "a car driving into the character knocks it aside")
	_check(bump.linear_velocity.length() > v_before * 0.6 or bump.global_position.distance_to(ch.global_position) > 2.0,
		"the car isn't stopped dead by the character (%.1f m/s)" % bump.linear_velocity.length())
	await _wait_s(1.5)
	_check(ch.state == PlayerCharacter.State.ACTIVE and ch.is_on_floor() and not _overlaps(game, ch.global_position),
		"back on its feet, clear of the car")

	# --- A traffic car: it stops for the character, the player takes it over ---
	var lane: TrafficNetwork.Lane = null
	for l in tm.network.lanes:
		if not l.connector and l.length > 140.0 and l.speed < 16.0 and l.stops.is_empty():
			var curvy := false
			for kk in l.curv:
				curvy = curvy or kk > 0.01
			if not curvy:
				lane = l
				break
	_check(lane != null, "found a straight city lane")
	if lane:
		var start := lane.point_at(15.0)
		ch.place(Transform3D(Basis.IDENTITY, _ground(game, lane.point_at(75.0))))
		game.foot_camera.snap()
		await _wait_s(0.5)
		var d := tm.spawn_near(load("res://scenes/vehicles/sedan.tscn"), start)
		var tcar := d.vehicle
		var closest := INF
		var t := 0.0
		while t < 14.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			closest = minf(closest, tcar.global_position.distance_to(ch.global_position) - tcar.body_front)
			if t > 3.0 and tcar.linear_velocity.length() < 0.2:
				break
		await _wait_s(1.0)
		_check(closest > 0.5 and d.blocker == "pedestrian", "traffic stops for a person in the road (%.1f m short, waiting for '%s')" % [closest, d.blocker])
		await _shot("onfoot_traffic_stopped")
		await _wait_s(3.0)
		var tentry := tcar.get_node("Entry") as VehicleEntry
		await _foot_walk_to(game, tentry.door_spot(ch.global_position), 0.8)
		await _wait_s(0.3)
		_check(tentry.prompt(ch).begins_with("Get in"), "traffic car offers to get in ('%s')" % tentry.prompt(ch))
		await _enter_drive_exit(game, tcar, "Traffic sedan", 2.0)
		_check(tm.driver_of(tcar) == null and tcar.get_parent() == game and tcar.get_node_or_null("Driver") == null,
			"traffic car taken over: no AI driver left, it's the player's")
		_check(not tm.drivers.any(func(dd: TrafficDriver) -> bool: return dd.vehicle == tcar), "traffic no longer manages it")

	# --- A parked car in a lot: swapped for the real vehicle, driven ---
	game.teleport_to(0)
	await _wait_s(1.0)
	var best: ParkedCarEntry = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var pe := node as ParkedCarEntry
		if pe and pe.prop and pe.prompt(ch) != "":
			var dd := pe.prop.global_position.distance_to(ch.global_position)
			if dd < best_d:
				best_d = dd
				best = pe
	_check(best != null, "found a parked car (%.0f m away)" % best_d)
	if best:
		var prop := best.prop
		var px := prop.global_transform
		var spot := Vector3.INF
		for off: Vector3 in [Vector3(-2.0, 0, 0), Vector3(2.0, 0, 0), Vector3(0, 0, -3.6), Vector3(0, 0, 3.6)]:
			var cand := _ground(game, px * off)
			if not _overlaps(game, cand) and best.reach_distance(cand) < INF:
				spot = cand
				break
		_check(spot != Vector3.INF, "room to stand by the parked car")
		if spot != Vector3.INF:
			ch.place(Transform3D(Basis.IDENTITY, spot))
			game.foot_camera.snap()
			await _wait_s(0.5)
			_check(game.hud.prompt_text().begins_with("Get in"), "parked car prompt ('%s')" % game.hud.prompt_text())
			await _shot("onfoot_parked_prompt")
			var before := game.vehicle
			await _tap("interact")
			await _wait_mode(game, Possession.Mode.IN_VEHICLE, 3.0)
			var gone := not is_instance_valid(prop) or prop.is_queued_for_deletion() or not prop.is_inside_tree()
			_check(p.driving() and game.vehicle != before and gone, "parked car became a real vehicle and the player is in it")
			if p.driving():
				var pv := game.vehicle
				await _tap("interact")
				await _wait_mode(game, Possession.Mode.ON_FOOT)
				await _wait_s(0.3)
				await _enter_drive_exit(game, pv, "Parked car", 2.0)

	# --- The garage on foot: pick a vehicle, it's brought to you, you're in it ---
	_check(p.on_foot(), "on foot before the garage")
	game.open_garage()
	await _wait(10)
	game.picker.picked.emit(VehicleCatalog.index_of_id("pickup"))
	await _wait_s(0.5)
	_check(p.driving() and VehicleCatalog.id_of_vehicle(game.vehicle) == "pickup", "garage on foot: in the new pickup")
	_check(game.vehicle.global_position.distance_to(ch.global_position) < 8.0, "garage on foot: brought to where you stood")
	_check_wiring(game, "garage on foot")
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)

	# --- A race picked from the menu while on foot: in the vehicle at the start ---
	game._on_menu_action("race:0")
	await _wait_s(0.5)
	_check(p.driving() and game.race.is_active() and game.controller.vehicle == game.vehicle and game.camera.current,
		"race from on foot: driving, chase camera, race on")
	game.race.end_race()
	await _wait_s(0.3)
	await _tap("interact")
	await _wait_mode(game, Possession.Mode.ON_FOOT)
	_check(p.on_foot(), "out again after the race")

	# --- Fell in the sea on foot: back to the spawn point ---
	ch.place(Transform3D(Basis.IDENTITY, Vector3(-600, MapLayout.SEA_LEVEL - 3.0, 3)))
	await _wait_s(3.0)
	_check(p.on_foot() and ch.global_position.y > MapLayout.SEA_LEVEL,
		"fell in the sea: respawned on foot (mode %d, y %.1f, state %d, paused %s)" % [p.mode, ch.global_position.y, game.state, get_tree().paused])

	# --- Title screen -> PLAY! on foot ---
	game._enter_title()
	await _wait(5)
	game.menu.action.emit("drive")
	await _wait(5)
	_check(game.state == Game.State.DRIVING and p.on_foot() and game.foot_camera.current and game.foot_controller.enabled,
		"title -> PLAY: walking, on-foot camera (state %d, mode %d, cam %s)" % [game.state, p.mode, get_viewport().get_camera_3d().name])

	# --- Many times in and out: nothing piles up ---
	await _wait_s(0.5)
	var v0 := game.vehicle
	ch.place(Transform3D(Basis.IDENTITY, _ground(game, (v0.get_node("Entry") as VehicleEntry).door_spot(ch.global_position))))
	await _wait_s(0.5)
	game._tidy_left_vehicles()
	await _wait_s(0.5)
	var nodes0 := get_tree().get_node_count()
	var objs0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var players0 := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).size()
	for i in 12:
		await _tap("interact")
		await _wait_mode(game, Possession.Mode.IN_VEHICLE)
		await _wait_s(0.3)
		await _tap("interact")
		await _wait_mode(game, Possession.Mode.ON_FOOT)
		await _wait_s(0.3)
	await _wait_s(1.0)
	var nodes1 := get_tree().get_node_count()
	var objs1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var players1 := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).size()
	_check(nodes1 - nodes0 <= 4, "12 trips in and out: no more nodes (%d -> %d)" % [nodes0, nodes1])
	_check(objs1 - objs0 < 60.0, "12 trips: no more objects (%d -> %d)" % [objs0, objs1])
	_check(players1 <= players0 + 2, "12 trips: audio players steady (%d -> %d)" % [players0, players1])
	var controllers := 0
	for n in game.get_children():
		if n is PlayerVehicleController or n is PlayerCharacterController:
			controllers += 1
	_check(controllers == 2, "one vehicle controller and one character controller (%d)" % controllers)
	var chars := game.find_children("*", "PlayerCharacter", true, false).size()
	_check(chars == 1, "one character (%d)" % chars)


## What the character costs: rendering (shown vs hidden, same view), physics
## (its script on vs off) and frame times while walking, in the city centre
## with normal traffic. Run with a window; add --gpu-index 0 for the iGPU.
func _onfootbench(game: Game) -> void:
	var ch := game.character
	var tm := game.traffic
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	game.hud.visible = false
	game.teleport_to(0)
	tm.set_enabled(true)
	await _wait_s(5.0)
	game.foot_camera.yaw = ch.facing
	await _wait(30)
	print("--- on foot, city centre, %d traffic cars, graphics %s" % [tm.drivers.size(), Settings.GRAPHICS_LABELS[Settings.get_value("graphics")]])
	# Rendering, shown vs hidden, with traffic off so the view stays the same.
	tm.set_enabled(false)
	await _wait_s(1.0)
	for round in 3:
		ch.visible = true
		await _wait(20)
		var a := await _frame_stats(240)
		ch.visible = false
		await _wait(20)
		var b := await _frame_stats(240)
		ch.visible = true
		print("character shown:  %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [a[0], a[1], a[3], a[4]])
		print("character hidden: %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [b[0], b[1], b[3], b[4]])
	tm.set_enabled(true)
	await _wait_s(4.0)
	# The character's own physics step (movement, kerbs, vehicle checks,
	# footsteps) and the interaction scan, timed directly: their physics is
	# switched off and the same calls are made from here, walking in circles
	# next to traffic.
	ch.set_physics_process(false)
	game.possession.set_physics_process(false)
	var parts := {"controller": 0, "character": 0, "scan": 0}
	var ticks := 0
	var t := 0.0
	while t < 6.0:
		_foot_push(game, Vector3(cos(t * 1.5), 0.0, sin(t * 1.5)), 1.0)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var t0 := Time.get_ticks_usec()
		game.foot_controller._physics_process(dt)
		var t1 := Time.get_ticks_usec()
		ch._physics_process(dt)
		var t2 := Time.get_ticks_usec()
		game.possession._physics_process(dt)
		var t3 := Time.get_ticks_usec()
		parts["controller"] += t1 - t0
		parts["character"] += t2 - t1
		parts["scan"] += t3 - t2
		ticks += 1
	_foot_release()
	ch.set_physics_process(true)
	game.possession.set_physics_process(true)
	var total: int = parts["controller"] + parts["character"] + parts["scan"]
	print("character + controller + interaction scan: %.3f ms per physics tick (%.2f ms per 60 fps frame); character %.3f, controller %.3f, scan %.3f" % [
		total / 1000.0 / ticks, total / 1000.0 / ticks * 2.0, parts["character"] / 1000.0 / ticks,
		parts["controller"] / 1000.0 / ticks, parts["scan"] / 1000.0 / ticks])
	tm.set_enabled(true)
	await _wait_s(4.0)
	# Walking and sprinting along the street.
	var fwd := Vector3(-sin(ch.facing), 0.0, -cos(ch.facing))
	_foot_push(game, fwd, 1.0)
	var w := await _frame_stats(300)
	Input.action_press("sprint")
	var r := await _frame_stats(300)
	_foot_release()
	print("walking/running: %d draw calls, render CPU %.2f ms (peak %.2f), GPU %.2f ms (peak %.2f)" % [w[0], w[1], w[2], w[3], w[4]])
	print("sprinting:       %d draw calls, render CPU %.2f ms (peak %.2f), GPU %.2f ms (peak %.2f)" % [r[0], r[1], r[2], r[3], r[4]])
	print("process frame: %.2f ms, physics frame %.2f ms (Performance monitors)" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])


## Average physics step time (ms) over `seconds`.
func _physics_ms(seconds: float) -> float:
	var t := 0.0
	var sum := 0.0
	var n := 0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1
	return sum / maxi(n, 1) * 1000.0


## Look-development shots of the character on the airfield apron (open, flat,
## neutral concrete): fixed cameras at three times of day, then every
## locomotion clip sampled at 8 points of its loop from the side.
func _charsheet(game: Game) -> void:
	var ch := game.character
	game.traffic.set_enabled(false)
	game.hud.visible = false
	game.teleport_to(6)
	await _wait_s(1.0)
	var pos := _ground(game, Vector3(360.0, 1.0, 250.0))
	ch.place(Transform3D(Basis.IDENTITY, pos))
	ch.set_physics_process(false)  # hold still where it's put
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 3000.0
	game.add_child(cam)
	cam.current = true
	var anim := ch._anim
	var views := {
		"front": [Vector3(0, 1.1, -4.2), Vector3(0, 0.95, 0)],
		"q3": [Vector3(2.8, 1.4, -3.2), Vector3(0, 0.95, 0)],
		"side": [Vector3(4.2, 1.1, 0), Vector3(0, 0.95, 0)],
		"back": [Vector3(0, 1.3, 4.2), Vector3(0, 0.95, 0)],
		"face": [Vector3(0.35, 1.68, -1.1), Vector3(0, 1.6, 0)],
		"game": [Vector3(0.0, 2.3, 3.6), Vector3(0.0, 1.45, -1.5)],
	}
	var times := ["day", "sunset", "night"]
	for t in times:
		game.day_night.set_mode(times.find(t))
		await _wait(10)
		anim.play(ch._clips["idle"], 0.0)
		anim.seek(0.6, true)
		anim.pause()
		for v: String in views:
			var setup: Array = views[v]
			cam.fov = 70.0 if v == "game" else 40.0
			cam.global_position = pos + setup[0]
			cam.look_at(pos + setup[1], Vector3.UP)
			await _wait(4)
			await _shot("char_%s_%s" % [t, v])
	game.day_night.set_mode(0)
	await _wait(10)
	cam.fov = 40.0
	cam.global_position = pos + Vector3(4.4, 1.0, 0)
	cam.look_at(pos + Vector3(0, 0.9, 0), Vector3.UP)
	for key in ["idle", "walk", "run", "sprint", "jump", "fall", "land"]:
		if not ch._clips.has(key):
			continue
		var clip: String = ch._clips[key]
		var length := anim.get_animation(clip).length
		anim.play(clip, 0.0)
		for k in 8:
			anim.seek(length * k / 8.0, true)
			anim.pause()
			await _wait(3)
			await _shot("anim_%s_%d" % [key, k])
	anim.play(ch._clips["idle"])
	ch.set_physics_process(true)
	cam.queue_free()
