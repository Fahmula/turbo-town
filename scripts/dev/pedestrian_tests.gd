extends "res://scripts/dev/split_tests.gd"
## The pedestrians dev test (run from DevTools):
##   --peds=<dir>     the sidewalk network (built, every walking line clear of
##                    walls, poles and props), people around City Center (how
##                    many, how varied, on the ground, walking), waiting for
##                    the lights and crossing on the zebra (drivers stop for
##                    them), saying hi on foot (prompt, wave, a speech bubble),
##                    a honk (wave) and three (dance), a stunt (cheer), a car
##                    coming at them (they hop aside), a car bumping them
##                    (they tumble, get up and walk back), a player on foot
##                    can't walk through them, the Pedestrians setting (Off /
##                    Busy), night; shots of all of it and a line-up of every
##                    look (checks and shots)
##   --pedbench       what they cost in the city centre: draw calls, render
##                    CPU, GPU and the game's own frame time with pedestrians
##                    Off, Normal and Busy (A/B, three rounds; run with
##                    --gpu-index 0 --graphics=1: the Deck stand-in)
## Run with --fixed-fps 60.


func p() -> LocalPlayer:
	return game.players[0]


func pm() -> PedestrianManager:
	return game.pedestrians


func press(k: Key, frames := 4) -> void:
	key(k, true)
	await wait(frames)
	key(k, false)
	await wait(4)


func _on_foot(at: Vector3, face: Vector3) -> void:
	var xf := Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), at + Vector3.UP * 0.05)
	p().possession.start_on_foot(xf)
	p().foot_camera.snap()
	await wait(10)


func _in_car(at: Vector3, face: Vector3) -> void:
	p().possession.start_in_vehicle(p().vehicle)
	var v := p().vehicle
	v.teleport(Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), at + Vector3.UP * (v.ride_height() + 0.1)))
	v.linear_velocity = Vector3.ZERO
	p().camera.snap()
	await wait(6)


## A fresh pedestrian of `look` standing still at `at`, facing `face`.
func _person(at: Vector3, face: Vector3, look := "") -> Pedestrian:
	var ped := pm().spawn_at(at, look)
	ped.global_position = Vector3(at.x, pm().network.ground_y(at.x, at.z), at.z)
	ped.facing = Pedestrian._yaw_of(face)
	ped.rotation.y = ped.facing
	ped._pause(30.0)
	ped.pose.look_weight = 0.0
	return ped


## Stage a scene: nobody else comes or goes.
## Holds the on-foot camera still at `at`, looking at `target` (staged shots).
func _pin_camera(at: Vector3, target: Vector3) -> void:
	var cam := p().foot_camera
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.global_position = at
	cam.look_at(target)
	await wait(2)


func _free_camera() -> void:
	p().foot_camera.set_process(true)
	p().foot_camera.set_physics_process(true)


func _clear() -> void:
	pm().managing = false
	for ped in pm().active.duplicate():
		pm()._despawn(ped)


func run() -> void:
	var g := game
	var m := pm()
	check(m != null, "the game has a PedestrianManager")
	if m == null:
		return
	var net := m.network
	print("network: ", net.report())
	var crossings := 0
	var signalled := 0
	for e in net.edges:
		if e.kind == PedestrianNetwork.Kind.CROSSING:
			crossings += 1
			if e.signal_id >= 0:
				signalled += 1
	check(net.edges.size() > 200 and crossings >= 40, "a sidewalk network with crossings (%d edges, %d crossings)" % [net.edges.size(), crossings])
	check(signalled == crossings, "every crossing is at a junction with lights (%d of %d)" % [signalled, crossings])
	await _check_clear()

	# --- City Center: how many, how varied, on the ground, walking ---
	g.teleport_to(0)
	await wait_s(4.0)
	var want := m.max_peds
	check(m.active.size() >= int(want * 0.8), "people around City Center (%d of %d)" % [m.active.size(), want])
	var looks := {}
	var heights := []
	for ped in m.active:
		looks[ped.who["look"]] = true
		heights.append(ped.who["height"])
	heights.sort()
	check(looks.size() >= 5, "different people (%d looks: %s)" % [looks.size(), ", ".join(looks.keys())])
	check(heights.size() > 2 and heights[-1] - heights[0] > 0.12, "different heights (%.2f-%.2f m)" % [heights[0] if heights else 0.0, heights[-1] if heights else 0.0])
	var off_ground := 0
	for ped in m.active:
		var gy := net.ground_y(ped.global_position.x, ped.global_position.z)
		if ped.state in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.WAIT] and absf(ped.global_position.y - gy) > 0.06:
			off_ground += 1
	check(off_ground == 0, "everyone on the ground (%d floating or sunk)" % off_ground)
	var start := {}
	for ped in m.active:
		start[ped] = ped.global_position
	await wait_s(3.0)
	var moved := 0
	for ped in m.active:
		if start.has(ped) and ped.global_position.distance_to(start[ped]) > 1.5:
			moved += 1
	check(moved >= int(m.active.size() * 0.5), "people walking (%d of %d moved)" % [moved, m.active.size()])

	# A street view on foot.
	var walkway := Vector3(-110.0, 0.15, -9.0)
	await _on_foot(walkway, Vector3(1, 0, 0))
	await wait_s(2.0)
	var seen := 0
	for ped in m.active:
		if ped.lod_seen and ped.lod_dist < 70.0:
			seen += 1
	check(seen >= 3, "people in view along the street (%d)" % seen)
	await shot("01_sidewalk")

	# --- Crossing on the lights ---
	await _crossing_check()

	# --- Say hi ---
	_clear()
	var spot := Vector3(-120.0, 0.15, -8.8)
	var ped := _person(spot, Vector3(-1, 0, 0), "dress_f")
	await _on_foot(spot + Vector3(-1.6, 0, 0), Vector3(1, 0, 0))
	await wait(20)
	var it := p().possession.interactable
	check(it != null and it.prompt(p().character) == "Say hi", "\"Say hi\" next to someone (%s)" % (it.prompt(p().character) if it else "no prompt"))
	await press(KEY_F)
	await wait(10)
	check(ped.greeted_count == 1 and ped.state == Pedestrian.State.GREET, "they stop and wave")
	check(ped.speaking(), "a speech bubble (\"%s\")" % (ped._bubble.text if ped._bubble else ""))
	await wait(30)
	check(ped.pose.active and ped.pose.gesture == PedestrianPose.Gesture.WAVE, "the wave is on (head and arm IK)")
	await _pin_camera(spot + Vector3(-0.6, 1.5, 3.2), spot + Vector3(-0.8, 1.2, 0.0))
	await shot("03_say_hi")
	_free_camera()
	await wait_s(3.5)
	check(ped.state in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.WAIT], "then they carry on (%s)" % Pedestrian.State.keys()[ped.state])

	# --- A player on foot can't walk through them ---
	_clear()
	ped = _person(spot, Vector3(0, 0, 1), "tee_shorts_heavy")
	await _on_foot(spot + Vector3(-2.5, 0, 0), Vector3(1, 0, 0))
	var closest := INF
	key(KEY_W, true)
	for k in 90:
		await tools.get_tree().physics_frame
		closest = minf(closest, Vector2(p().character.global_position.x - ped.global_position.x,
			p().character.global_position.z - ped.global_position.z).length())
	key(KEY_W, false)
	check(closest > Pedestrian.RADIUS + 0.2, "walking into someone stops at them (closest %.2f m)" % closest)

	# --- Honks: one waves, three dance ---
	_clear()
	g.traffic.set_enabled(false)
	await wait(5)
	var a := _person(spot, Vector3(0, 0, 1), "tee_jeans_f")
	var b := _person(spot + Vector3(3.0, 0, 0), Vector3(0, 0, 1), "long_skirt_f")
	await _in_car(spot + Vector3(1.5, -0.15, 12.0), Vector3(0, 0, -1))
	await press(KEY_E, 6)
	await wait(10)
	check(a.horn_reactions >= 1 and a.state == Pedestrian.State.REACT, "a honk: they wave")
	await wait_s(2.6)
	for k in 3:
		await press(KEY_E, 5)
	await wait(20)
	check(a.dance_count >= 1 and b.dance_count >= 1, "three honks: they dance")
	await wait_s(1.0)
	await shot("04_dance")
	await wait_s(5.0)

	# --- A stunt: cheering ---
	var cheers_before := a.cheer_count + b.cheer_count
	p().stunts.combo_banked.emit(800, 1)
	await wait(15)
	check(a.cheer_count + b.cheer_count > cheers_before, "a stunt nearby: they cheer")
	await wait_s(0.8)
	await shot("05_cheer")
	await wait_s(3.0)

	# --- A car coming at them: they hop aside ---
	_clear()
	var d := _person(spot + Vector3(0, 0, 0), Vector3(1, 0, 0), "jacket_m")
	d._resume()
	d.walk_speed = 0.01
	var v := p().vehicle
	await _in_car(spot + Vector3(-14.0, -0.15, 0.0), Vector3(1, 0, 0))
	v.linear_velocity = Vector3(9.0, 0, 0)
	var hopped := false
	for k in 90:
		await tools.get_tree().physics_frame
		v.linear_velocity.x = 9.0
		hopped = hopped or d.state == Pedestrian.State.DODGE
		if hopped:
			break
	check(d.dodged_count >= 1, "a car heading at them: they hop out of the way")
	await wait(4)
	await shot("06_dodge")
	v.linear_velocity = Vector3.ZERO
	await wait_s(2.0)
	check(d.knocked_count == 0, "and it missed them")

	# --- A car that bumps them: tumble, up again, back to the sidewalk ---
	_clear()
	var k2 := _person(spot, Vector3(0, 0, 1), "tee_jeans_m")
	await _in_car(spot + Vector3(-3.2, -0.15, 0.0), Vector3(1, 0, 0))
	v.linear_velocity = Vector3(8.0, 0, 0)
	var knocked := false
	for k in 40:
		await tools.get_tree().physics_frame
		knocked = knocked or k2.knocked_count > 0
		if knocked:
			break
	check(knocked, "a car bumping them knocks them over")
	await wait(10)
	await shot("07_tumble")
	v.linear_velocity = Vector3.ZERO
	await wait_s(5.0)
	check(k2.state not in [Pedestrian.State.KNOCKED, Pedestrian.State.DODGE], "they get back up (%s)" % Pedestrian.State.keys()[k2.state])
	await wait_s(6.0)
	var gy := net.ground_y(k2.global_position.x, k2.global_position.z)
	check(k2.state in [Pedestrian.State.WALK, Pedestrian.State.CROSS, Pedestrian.State.WAIT] and gy > 0.1,
		"and walk back to the sidewalk (%s, %.2f m up)" % [Pedestrian.State.keys()[k2.state], gy])
	g.traffic.set_enabled(true)

	# --- The setting ---
	pm().managing = true
	Settings.set_value("pedestrians", 0)
	await wait(10)
	check(m.active.size() == 0, "Pedestrians Off takes everyone away")
	g.teleport_to(0)
	Settings.set_value("pedestrians", 3)
	await wait_s(4.0)
	check(m.active.size() >= Settings.PEDESTRIAN_COUNTS[3] - 4, "Busy fills the sidewalks (%d of %d)" % [m.active.size(), Settings.PEDESTRIAN_COUNTS[3]])
	await _on_foot(walkway, Vector3(1, 0, 0))
	await wait_s(1.5)
	await shot("08_busy")
	g.day_night.set_mode(2)
	await wait_s(1.0)
	await shot("09_night")
	g.day_night.set_mode(0)
	Settings.set_value("pedestrians", 2)

	await _lineup()
	print("pedestrians: %d/%d ok (%d failed)" % [checks - fails, checks, fails])
	if fails > 0:
		push_error("pedestrians test failed (%d/%d)" % [fails, checks])


## Every walking line, sampled every half metre: a body-sized capsule there
## touches no wall, pole or prop.
func _check_clear() -> void:
	var net := pm().network
	var space := tools.get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.2
	q.shape = cap
	q.collision_mask = 0b101       # world, props
	var bad := 0
	var samples := 0
	var where: Array[String] = []
	for e in net.edges:
		var t := 0.0
		while t <= e.length:
			var pt: Vector3 = net.point_on(e, t, true)[0]
			q.transform = Transform3D(Basis.IDENTITY, pt + Vector3.UP * 1.0)
			samples += 1
			var hits := space.intersect_shape(q, 1)
			if not hits.is_empty():
				bad += 1
				if where.size() < 8:
					where.append("%s (%.1f, %.1f) %s" % [PedestrianNetwork.Kind.keys()[e.kind], pt.x, pt.z, (hits[0]["collider"] as Node).name])
			t += 0.5
	check(bad == 0, "walking lines clear of walls, poles and props (%d of %d samples blocked) %s" % [bad, samples, ", ".join(where)])


## Someone at a corner waits for the walk light, crosses on the zebra (in the
## drivers' walkers list) and reaches the far side.
func _crossing_check() -> void:
	var m := pm()
	var net := m.network
	# The north arm of the junction at (-75, 0): from the north-west block's
	# corner tip.
	var cross: PedestrianNetwork.Edge = null
	for e in net.edges:
		if e.kind == PedestrianNetwork.Kind.CROSSING and absf(e.pts[1].x + 75.0 + PedestrianNetwork.ZEBRA_REACH) < 0.1 \
				and absf(e.pts[1].z + PedestrianNetwork.ZEBRA) < 0.1:
			cross = e
	check(cross != null and cross.signal_id >= 0, "the crossing at (-75, 0) has lights")
	if cross == null:
		return
	_clear()
	var tip := net.points[cross.a]
	await _on_foot(tip + Vector3(-6.0, 0, -6.0), Vector3(1, 0, 1))
	var ped := m.spawn_at(tip, "tee_jeans_f")
	ped.edge = cross
	ped.from_a = true
	ped.s = 0.0
	ped.global_position = tip
	ped._set_state(Pedestrian.State.WAIT)
	var started := false
	var light_ok := true
	var listed := false
	var shot_taken := false
	for k in 60 * 40:
		await tools.get_tree().process_frame
		if ped.state == Pedestrian.State.CROSS:
			if not started:
				started = true
				light_ok = m.walk_light(cross)
			listed = listed or m.traffic.walkers.has(ped)
			if not shot_taken and ped.s > cross.length * 0.45:
				shot_taken = true
				await shot("02_crossing")
		elif started:
			break
	check(started and light_ok, "waits for the walk light, then crosses")
	check(listed, "drivers stop for them while they cross (in the walkers list)")
	check(started and ped.state != Pedestrian.State.CROSS and ped.global_position.distance_to(net.points[cross.b]) < 3.5,
		"reaches the far side (%.1f m from it)" % ped.global_position.distance_to(net.points[cross.b]))
	check(not m.traffic.walkers.has(ped), "and is off the drivers' list again")
	check(ped.knocked_count == 0, "nobody bumped into them on the way")


## Every look in a row, for look-dev.
func _lineup() -> void:
	_clear()
	game.traffic.set_enabled(false)
	await wait(10)
	var base := Vector3(-119.0, 0.15, -9.6)
	var looks := PedestrianLook.LOOKS
	for i in looks.size():
		var ped := _person(base + Vector3(i * 1.05, 0, 0), Vector3(0, 0, 1), looks[i]["name"])
		ped._pause(60.0)
		ped.pose.look_weight = 0.0
	await _on_foot(base + Vector3(3.7, 0, 5.4), Vector3(0, 0, -1))
	p().character.visible = false
	await wait(20)
	await _pin_camera(base + Vector3(3.7, 1.25, 5.0), base + Vector3(3.7, 0.95, 0.0))
	await wait(10)
	await shot("10_lineup")
	# Someone walking past, close up (feet, hems, the gait).
	_clear()
	var walker := pm().spawn_at(base + Vector3(-3.2, 0, 0.8), "long_skirt_f")
	walker.walk_speed = 1.35
	walker.lane = 0.0
	var near := pm().network.nearest(walker.global_position)
	walker.edge = near[0]
	walker.s = near[1]
	walker.from_a = (pm().network.point_on(walker.edge, walker.s, true)[1] as Vector3).x > 0.0
	if not walker.from_a:
		walker.s = walker.edge.length - walker.s
	await _pin_camera(base + Vector3(-1.0, 0.9, 4.0), base + Vector3(-1.0, 0.8, 0.0))
	for k in 6:
		await wait(8)
		await shot("11_walk_%d" % k)
	_free_camera()
	p().character.visible = true
	game.traffic.set_enabled(true)


func bench() -> void:
	var g := game
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	g.traffic.set_enabled(true)
	var size := tools.get_viewport().get_visible_rect().size
	_report("PEDBENCH window %dx%d, graphics %s, GPU: %s" % [size.x, size.y,
		Settings.GRAPHICS_LABELS[Settings.get_value("graphics")], RenderingServer.get_video_adapter_name()])
	var views := [
		["street on foot", Vector3(-110.0, 0.15, -9.0), Vector3(1, 0, 0), true],
		["junction by car", Vector3(-95.0, 0.0, 2.0), Vector3(1, 0, 0), false],
	]
	for view: Array in views:
		var rows := {}
		for round_i in 3:
			for level in [0, 2, 3]:
				Settings.set_value("pedestrians", level)
				g.teleport_to(0)
				if view[3]:
					await _on_foot(view[1], view[2])
				else:
					await _in_car(view[1], view[2])
				await wait_s(5.0)
				var t0 := pm()._cost_usec
				var f0 := Engine.get_process_frames()
				pm().cost_parts.clear()
				pm().profile = true
				var r := await _measure(240)
				pm().profile = false
				var frames := maxi(Engine.get_process_frames() - f0, 1)
				var own := (pm()._cost_usec - t0) / 1000.0 / frames
				if level == 3 and round_i == 2:
					var parts := []
					for part in pm().cost_parts:
						parts.append("%s %.3f" % [part, pm().cost_parts[part] / 1000.0 / frames])
					_report("    (%s, busy, ms per frame: %s)" % [view[0], ", ".join(parts)])
				var key_name: String = Settings.PEDESTRIAN_LABELS[level]
				var acc: Array = rows.get(key_name, [0.0, 0.0, 0.0, 0.0, 0.0, 0])
				acc[0] += r[2]
				acc[1] += r[5]
				acc[2] += r[0]
				acc[3] += r[6]
				acc[4] += own
				acc[5] = pm().active.size()
				rows[key_name] = acc
		for key_name in rows:
			var acc: Array = rows[key_name]
			_report("  %-16s %-6s %2d people: %5.0f draw calls, render CPU %.2f ms, GPU %.2f ms, game %.2f ms (pedestrians %.3f ms)" % [
				view[0], key_name, acc[5], acc[0] / 3.0, acc[1] / 3.0, acc[2] / 3.0, acc[3] / 3.0, acc[4] / 3.0])
	Settings.set_value("pedestrians", 2)
	if dir != "":
		var f := FileAccess.open(dir.path_join("pedbench.txt"), FileAccess.WRITE)
		f.store_string("\n".join(_lines))
