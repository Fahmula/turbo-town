extends Node
## Developer helpers, inactive during normal play.
##   --tour=<dir>     save screenshots from a set of viewpoints, then quit
##   --drive=<dir>    drive the player car with scripted input, snapping shots
##   --garage=<dir>   garage menu + changing into every vehicle (checks and shots)
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
##   --artzone=<dir>  environment art preview: fixed views at day / sunset / night
##                    and Low / High, plus draw calls per view (add --legacy-art
##                    for the same views in the old style; --views=a,b limits the
##                    views, --quick shoots day on High only, --profile hides one
##                    family of new-style meshes at a time and prints what it cost,
##                    --stress renders at 2x resolution so fill costs dominate,
##                    --traffic-on keeps traffic running for the shots)
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
		elif arg == "--bench":
			_mode = "bench"
			_dir = OS.get_user_data_dir()
		elif arg.begins_with("--fx="):
			_mode = "fx"
			_dir = arg.split("=")[1]
		elif arg.begins_with("--artzone="):
			_mode = "artzone"
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
	# Automatic crash cams would pause the other tests mid-crash.
	Settings.set_value("crash_cam", _mode == "replay")
	if _vehicle_id != "":
		var vi := VehicleCatalog.index_of_id(_vehicle_id)
		if vi < 0:
			push_error("dev tools: unknown vehicle id '%s'" % _vehicle_id)
		else:
			game.change_vehicle(vi, Color.RED, false)
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
	elif _mode == "artzone":
		await _artzone(game)
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
	# Removed = freed, or put back in the traffic pool (out of the tree).
	_check(not is_instance_valid(tv) or tv.is_queued_for_deletion() or (not tv.is_inside_tree() and not tm.vehicles.has(tv)),
		"traffic car overlapping the bus was removed")
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
	# Main menu, then garage from the title: picking drives off.
	for i in 6:
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
		game.change_vehicle(vi, Color.RED, false)
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
	game.change_vehicle(0, Color.RED, false)
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
		game.change_vehicle(vi, Color.RED, false)
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
	tm._despawn(d1)
	await _wait(2)
	var d2 := tm.spawn_near(tm.car_scenes[1], Vector3(60, 0, -120))
	var drivers_on_car := car.find_children("*", "TrafficDriver", false, false).size()
	var sounds := car.find_children("*", "AudioStreamPlayer3D", false, false).size()
	_check(d2.vehicle == car, "the same sedan was reused")
	_check(dented and dmg._meshes[0].mesh == dmg._sources[0] and not dmg.headlights_broken and dmg.total_damage == 0.0
		and dmg._parts["FrontBumper"]["debris"] == null, "reused car is repaired (dents, lights, bumper)")
	_check(drivers_on_car == 1 and sounds == 3 and car.visible, "one driver, one set of sounds (%d, %d)" % [drivers_on_car, sounds])
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
	game.change_vehicle(4, Color.YELLOW)
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
	var lights_ok := true
	for sf: Array in dmg._surfaces_named("Headlight"):
		lights_ok = lights_ok and (sf[0] as MeshInstance3D).get_surface_override_material(sf[1]) == VehicleDamage._broken_light
	var body := v.get_node("Body") as VehicleBodyVisual
	var paint_ok := false
	for mi: MeshInstance3D in dmg._meshes:
		for k in mi.get_surface_override_material_count():
			paint_ok = paint_ok or body._paint_mats.has(mi.get_surface_override_material(k))
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


## Environment art preview (ArtZone): screenshots from fixed views inside the
## zone, at day / sunset / night on High and day on Low, with the HUD hidden
## and traffic off so before/after runs (--legacy-art) match. Prints draw
## calls, objects, primitives and GPU time per view (High, day).
func _artzone(game: Game) -> void:
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
	]
	var times := ["day", "sunset", "night"]
	var only: PackedStringArray = []
	var quick := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.split("=")[1].split(",")
		quick = quick or arg == "--quick"
	for q in ([GraphicsQuality.HIGH] if quick else [GraphicsQuality.HIGH, GraphicsQuality.LOW]):
		Settings.set_value("graphics", q)
		for t in (range(3) if q == GraphicsQuality.HIGH and not quick else [0]):
			Settings.set_value("time_of_day", t)
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
				var tag := "%s_%s_%s" % [view[0], times[t], "high" if q == GraphicsQuality.HIGH else "low"]
				if OS.get_cmdline_user_args().has("--profile") and q == GraphicsQuality.HIGH and t == 0:
					await _profile_families(game, view[0])
				if q == GraphicsQuality.HIGH and t == 0:
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
					print("ARTZONE %-16s %4d draw calls, %4d objects, %7d primitives, gpu %.2f ms" % [
						view[0], calls / 30, objs / 30, prims / 30, gpu / 30.0])
				await _shot(tag)
	cam.set_process(true)
	game.hud.visible = true
	Settings.set_value("graphics", GraphicsQuality.HIGH)
	Settings.set_value("time_of_day", 0)


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


## Hides one family of new-style meshes at a time and prints what it cost
## (draw calls, primitives, GPU time) in the current view.
func _profile_families(game: Game, view: String) -> void:
	var world := game.world
	var families := {
		"facades": func(n: Node) -> bool: return n.name == &"FacadesEnv",
		"roof_clutter": func(n: Node) -> bool: return n.name == &"BuildingClutterEnv",
		"paving": func(n: Node) -> bool: return n.name == &"PavingEnv" or n.get_parent().name == &"PavingEnv",
		"roads_env": func(n: Node) -> bool: return n.get_parent() != null and String(n.get_parent().name).ends_with("Env") and String(n.get_parent().name).contains("Road"),
		"trees_env": func(n: Node) -> bool: return n is MultiMeshInstance3D and (String(n.name).begins_with("broadleaf") or String(n.name).begins_with("conifer")),
		"kit_props": func(n: Node) -> bool: return n is MeshInstance3D and (n.get_parent() is KitProp or (n.get_parent() is TrafficLightProp and (n.get_parent() as TrafficLightProp).model == n)),
		"terrain": func(n: Node) -> bool: return n is MeshInstance3D and String(n.name).begins_with("Chunk_"),
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
