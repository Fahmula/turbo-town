extends "res://scripts/dev/split_tests.gd"
## Where the draw calls go (run from DevTools):
##   --drawcalls=<dir>  in heavy city views and along a city drive: draw calls
##                      split into the camera pass and the shadow passes, what
##                      each family of the world costs (hidden one at a time;
##                      props by type), a census of meshes / surfaces / shadow
##                      casters per family, the surfaces of each traffic car
##                      type, and what-ifs (fewer shadow splits, families that
##                      stop casting shadows). The world is paused while a view
##                      is measured, so moving traffic doesn't blur the numbers.
##                      Results go to stdout and drawcalls.txt.
##   add --graphics=<0-3> for the quality (default Medium, the Deck setting),
##   --views=a,b to limit the views (drive = the city drive), --no-traffic to
##   leave traffic off.
## Run with a window; --gpu-index 0 --resolution 1280x800 is the Deck proxy.

const VIEWS := [
	["downtown_street", Vector3(9.0, 2.4, 2.0), Vector3(42.0, 3.0, 2.0)],
	["avenue_chase", Vector3(2.4, 2.4, -30.0), Vector3(2.4, 1.4, -62.0)],
	["intersection", Vector3(10.0, 1.7, -60.0), Vector3(-6.0, 1.2, -80.0)],
	["aerial", Vector3(95.0, 70.0, 15.0), Vector3(-10.0, 0.0, -110.0)],
]

var _vp: RID
var _sun: DirectionalLight3D


func bench() -> void:
	var g := game
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	g.hud.visible = false
	_vp = tools.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	var level: int = GraphicsQuality.MEDIUM
	var only: PackedStringArray = []
	var traffic := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--graphics="):
			level = clampi(int(arg.split("=")[1]), 0, 3)
		elif arg.begins_with("--views="):
			only = arg.split("=")[1].split(",")
		elif arg == "--no-traffic":
			traffic = false
	Settings.set_value("graphics", level)
	_sun = g.world.get_node("Sun") as DirectionalLight3D
	_report("DRAWCALLS GPU: %s, graphics %d, %s, traffic %s" % [RenderingServer.get_video_adapter_name(), level,
		str(tools.get_viewport().get_visible_rect().size), str(traffic)])
	_report("  sun shadows: mode %d (0 = orthogonal, 1 = 2 splits, 2 = 4 splits), max distance %.0f m" % [
		_sun.directional_shadow_mode, _sun.directional_shadow_max_distance])

	_car_census()
	_report("")
	_report("PROPS by type (whole map): count, surfaces each, shadow-casting surfaces each, visibility range end")
	var types := _prop_types()
	for t: String in types:
		var nodes: Array = types[t]
		_report("  %-18s %4d  %s" % [t, nodes.size(), _census([nodes[0]])])

	# Traffic fills in around the city spawn.
	g.traffic.set_enabled(traffic)
	g.teleport_to(0)
	await wait_s(8.0 if traffic else 1.0)

	var cam := g.camera
	for view: Array in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		cam.set_process(false)
		cam.global_position = view[1]
		cam.look_at(view[2], Vector3.UP)
		await wait(20)
		tools.get_tree().paused = true
		await wait(10)
		await _breakdown(view[0])
		await _what_ifs()
		await shot("drawcalls_%s" % view[0])
		tools.get_tree().paused = false
		cam.set_process(true)
		await wait(5)

	# Driving through the city at 80 km/h, as the --bench city drive does.
	if only.is_empty() or only.has("drive"):
		_report("")
		for c: Array in _configs():
			if not (c[0] in ["as is", "traffic old way", "parked+traffic old way"]):
				continue
			var undo: Callable = (c[1] as Callable).call()
			await _drive_stats(c[0])
			undo.call()

	var f := FileAccess.open(dir.path_join("drawcalls.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")


## --parkedlod=<dir>: parked cars of each type through a long lens, the real
## parts against the merged far mesh (CarLod), by day and night, and a
## walk-up from 70 m to 20 m across the switch; plus the merge's build time.
func parked_lod_shots() -> void:
	var g := game
	g.traffic.set_enabled(false)
	g.hud.visible = false
	var t0 := Time.get_ticks_usec()
	var cache: Dictionary = CarLod._meshes.duplicate()
	CarLod._meshes.clear()
	var picked := {}
	for c in g.world.get_node("Props").get_children():
		var p := c as Prop
		if p == null or not p.traffic_paint or picked.has(p.scene_file_path):
			continue
		picked[p.scene_file_path] = p
	for path: String in picked:
		var p: Prop = picked[path]
		var parts: Array[MeshInstance3D] = []
		for n in p.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh and mi.name != &"FarLod" and mi.name != &"ShadowLod" and mi.is_visible_in_tree():
				parts.append(mi)
		var t1 := Time.get_ticks_usec()
		var far: Mesh = CarLod._merge(p, parts, false, 0.3)
		var shadow: Mesh = CarLod._merge(p, parts, true, 0.3)
		print("PARKEDLOD %s: merged in %.1f ms, far %d verts / %d indices, shadow %d verts" % [path.get_file(),
			(Time.get_ticks_usec() - t1) / 1000.0, far.surface_get_array_len(0), far.surface_get_array_index_len(0),
			shadow.surface_get_array_len(0)])
	CarLod._meshes = cache
	print("PARKEDLOD all types merged in %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var cam := g.camera
	cam.set_process(false)
	var fov := cam.fov
	# Each car on its own open stretch of the avenue (x = 2.4), 70 m apart,
	# across the road; the camera looks along the road at it.
	g.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(40.0, 0.8, 300.0)))
	var space := g.world.get_world_3d().direct_space_state
	var k := 0
	for path: String in picked:
		var p: Prop = picked[path]
		p.freeze = true
		var at := Vector3(2.4, 50.0, -40.0 + 70.0 * k)
		var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 100.0)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		at.y = (hit["position"] as Vector3).y if hit else 0.15
		p.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), at)
		k += 1
	await wait(10)
	for hour_i in 2:
		Settings.set_value("time_of_day", 0 if hour_i == 0 else 2)
		await wait(20)
		for path: String in picked:
			var p: Prop = picked[path]
			var c := p.global_position + Vector3.UP * 0.8
			var dir := Vector3(0.12, 0.0, 1.0).normalized()
			var tag := "%s_%s" % [path.get_file().get_basename(), "day" if hour_i == 0 else "night"]
			# Long lens from 60 m, so the car fills the frame as it would at
			# ~6 m: from the road, and from above (as from a plane or a hill).
			cam.fov = 7.0
			for view: Array in [["", dir * 60.0 + Vector3.UP * 4.0], ["top_", dir * 40.0 + Vector3.UP * 45.0]]:
				cam.global_position = c + (view[1] as Vector3)
				cam.look_at(c, Vector3.UP)
				for mode in ["near", "far"]:
					_force(p, mode)
					await wait(8)
					await shot("%s_%s%s" % [tag, view[0], mode])
			_force(p, "auto")
			if hour_i == 0:
				# Walking up to it at a normal lens, across the switch.
				cam.fov = fov
				# In from 250 m and back out: the swap has hysteresis.
				var step := 0
				for d in [250.0, 70.0, 45.0, 41.0, 37.0, 30.0, 41.0, 45.0]:
					cam.global_position = c + dir * d + Vector3.UP * 2.0
					cam.look_at(c, Vector3.UP)
					await wait(6)
					await shot("%s_walk%d_%03d" % [tag, step, int(d)])
					step += 1
	# What each car adds to the camera pass at a distance (frustum culling only,
	# so hills in the way don't matter; the "objects" counter counts surfaces):
	# nothing past the range, the merged mesh alone far away, the real parts
	# alone up close.
	_vp = tools.get_viewport().get_viewport_rid()
	Settings.set_value("time_of_day", 0)
	_calm_weather()
	await wait(20)  # a bolt already in the air fades out
	cam.fov = 2.0
	for path: String in picked:
		var p: Prop = picked[path]
		var c := p.global_position + Vector3.UP * 0.8
		var parts := 0
		for n in p.find_children("*", "MeshInstance3D", true, false):
			if n.name != &"FarLod" and n.name != &"ShadowLod" and (n as MeshInstance3D).is_visible_in_tree():
				parts += (n as MeshInstance3D).mesh.get_surface_count()
		for d: float in [260.0, 100.0, 20.0]:
			cam.fov = 2.0 if d > 50.0 else 30.0  # the whole car in frame
			cam.global_position = c + Vector3(0.12, 0.0, 1.0).normalized() * d + Vector3.UP * 2.0
			cam.look_at(c, Vector3.UP)
			await wait(4)
			var with_car: Array = await _stats(4)
			p.visible = false
			await wait(4)
			var without: Array = await _stats(4)
			p.visible = true
			var objs: int = with_car[4] - without[4]
			var want := 0 if d > 220.0 else (1 if d > CarLod.NEAR else parts)
			check(objs == want, "%s at %.0f m draws %d surfaces in the camera pass (want %d)" % [path.get_file(), d, objs, want])
	cam.fov = fov
	cam.set_process(true)
	_restore_weather()
	Settings.set_value("time_of_day", 0)


## --trafficlod=<dir>: one traffic car of each type standing on the avenue,
## brakes on: the real parts against CarLod's merged far mesh through a long
## lens by day and night, an indicator at night; checks of what each draws at
## 260 / 100 / 20 m, that a damaged car shows its real parts until repaired,
## and that a car the player takes loses the merged meshes.
func traffic_lod_shots() -> void:
	var g := game
	var tm := g.traffic
	tm.set_enabled(false)
	g.hud.visible = false
	# The player stays close by: traffic far from every player is removed
	# even with spawning off.
	g.vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-20.0, 0.8, -20.0)))
	await wait_s(0.5)
	var cars: Array[Vehicle] = []
	var k := 0
	for scene in tm.car_scenes:
		var d := tm.spawn_near(scene, Vector3(2.4, 0.0, -40.0 + 45.0 * k))
		k += 1
		if d == null:
			continue
		d.set_physics_process(false)
		d.vehicle.throttle_input = 0.0
		d.vehicle.brake_input = 1.0
		d.vehicle.linear_velocity = Vector3.ZERO
		cars.append(d.vehicle)
	await wait_s(2.0)
	for v in cars:
		check(v.has_node("FarLod") and v.has_node("ShadowLod"), "%s: traffic car has the merged meshes" % v.display_name)
		v.freeze = true
	_vp = tools.get_viewport().get_viewport_rid()
	var cam := g.camera
	cam.set_process(false)
	var fov := cam.fov
	for hour_i in 2:
		Settings.set_value("time_of_day", 0 if hour_i == 0 else 2)
		await wait(20)
		for v in cars:
			var c := v.global_position + Vector3.UP * 0.6
			var side := v.global_basis.x
			var back := v.global_basis.z
			var tag := "%s_%s" % [v.scene_file_path.get_file().get_basename(), "day" if hour_i == 0 else "night"]
			cam.fov = 7.0
			# Rear three-quarter (brake lights) and front three-quarter.
			for view: Array in [["rear_", (back * 0.96 + side * 0.28).normalized()], ["front_", (-back * 0.96 + side * 0.28).normalized()]]:
				cam.global_position = c + (view[1] as Vector3) * 60.0 + Vector3.UP * 5.0
				cam.look_at(c, Vector3.UP)
				for mode in ["near", "far"]:
					_force(v, mode)
					await wait(8)
					await shot("%s_%s%s" % [tag, view[0], mode])
			if hour_i == 1:
				# An indicator, caught while lit.
				var body := v.get_node("Body") as VehicleBodyVisual
				body.indicator = VehicleBodyVisual.Blinker.LEFT
				cam.global_position = c + (back * 0.96 - side * 0.28).normalized() * 60.0 + Vector3.UP * 5.0
				cam.look_at(c, Vector3.UP)
				for mode in ["near", "far"]:
					_force(v, mode)
					var t := 0
					while body._blink_out.x < 0.9 and t < 120:
						await wait(1)
						t += 1
					await wait(1)
					await shot("%s_blink_%s" % [tag, mode])
				body.indicator = VehicleBodyVisual.Blinker.OFF
			_force(v, "auto")
	Settings.set_value("time_of_day", 0)
	_calm_weather()
	await wait(20)  # a bolt already in the air fades out
	# What each car's meshes add to the camera pass ("objects" counts
	# surfaces; exhaust smoke and other effects aren't meshes and stay).
	for v in cars:
		var c := v.global_position + Vector3.UP * 0.6
		var near := 0
		for n in v.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh and mi.name != &"FarLod" and mi.name != &"ShadowLod" and mi.is_visible_in_tree():
				near += mi.mesh.get_surface_count()
		for d: float in [260.0, 100.0, 20.0]:
			cam.fov = 2.0 if d > 50.0 else 30.0
			cam.global_position = c + v.global_basis.z * d + Vector3.UP * 2.0
			cam.look_at(c, Vector3.UP)
			await wait(4)
			var with_car: Array = await _stats(4)
			var hidden: Array[MeshInstance3D] = []
			for n in v.find_children("*", "MeshInstance3D", true, false):
				if (n as MeshInstance3D).visible:
					(n as MeshInstance3D).visible = false
					hidden.append(n)
			await wait(4)
			var without: Array = await _stats(4)
			for mi in hidden:
				mi.visible = true
			var got: int = with_car[4] - without[4]
			var want := near if d < CarLod.NEAR else 1
			check(got == want, "%s at %.0f m draws %d surfaces in the camera pass (want %d)" % [v.display_name, d, got, want])
	cam.fov = fov
	cam.set_process(true)
	_restore_weather()
	# Damage shows the real parts at every distance; a repair brings it back.
	var v0 := cars[0]
	var dmg := v0.get_node("Damage") as VehicleDamage
	var far := v0.get_node("FarLod") as MeshInstance3D
	dmg.total_damage = 20.0
	dmg.damage_changed.emit(20.0)
	var body_mesh := v0.get_node("Body").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(not far.visible and body_mesh.visibility_parent.is_empty()
		and body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "damaged: real parts at every distance, casting shadows")
	dmg.repair()
	check(far.visible and not body_mesh.visibility_parent.is_empty()
		and body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "repaired: merged far mesh again")
	# A real crash (parts may come off while the far mesh is on).
	var v2 := cars[2]
	var dmg2 := v2.get_node("Damage") as VehicleDamage
	v2.freeze = false
	var errors_before := Engine.get_frames_drawn()
	for dir: Vector3 in [v2.global_basis.x, -v2.global_basis.x]:
		if dmg2.total_damage > 0.0:
			break
		v2.linear_velocity = dir * 26.0 + Vector3.UP * 0.5
		await wait_s(2.0)
	if dmg2.total_damage > 0.0:
		var bm2 := v2.get_node("Body").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		check(not (v2.get_node("FarLod") as Node3D).visible and bm2.visibility_parent.is_empty()
			and bm2.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"%s crashed (damage %.0f): real parts at every distance" % [v2.display_name, dmg2.total_damage])
	else:
		print("  (the %s missed everything; no crash check)" % v2.display_name)
	print("  crash test ran %d frames" % (Engine.get_frames_drawn() - errors_before))
	# The player takes a traffic car: no more merged meshes.
	var v1 := cars[1]
	check(tm.claim(v1), "claimed a traffic car")
	var bm := v1.get_node("Body").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(not v1.has_node("FarLod") and not v1.has_node("ShadowLod") and bm.visibility_parent.is_empty()
		and bm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and (v1.get_node("Body") as VehicleBodyVisual).far_lods.is_empty(), "claimed car: real parts only, casting shadows")
	print("TRAFFICLOD %d checks, %d failed" % [checks, fails])


## Rain (particles in a box round the camera, off under a roof) and lightning
## come and go as the camera moves, which would throw the surface counts off
## by one: clear weather while counting (a run with --weather=rain or storm).
func _calm_weather() -> void:
	if game.weather:
		game.weather.set_mode(Weather.Kind.CLEAR, true)


func _restore_weather() -> void:
	if game.weather:
		game.weather.set_mode(Settings.get_value("weather"), true)


## Shows only the real parts ("near"), only the merged mesh ("far"), or the
## normal distance switch ("auto"). The real parts follow the far mesh
## (visibility_parent), so only its range changes.
func _force(p: Node3D, mode: String) -> void:
	var far := p.get_node_or_null("FarLod") as MeshInstance3D
	if far == null:
		return
	if not far.has_meta("range"):
		far.set_meta("range", Vector2(far.visibility_range_begin, far.visibility_range_end))
	var r: Vector2 = far.get_meta("range")
	if mode == "auto":
		far.visibility_range_begin = r.x
		far.visibility_range_end = r.y
	elif mode == "far":
		far.visibility_range_begin = 0.0
		far.visibility_range_end = 0.0
	else:
		far.visibility_range_begin = 100000.0
		far.visibility_range_end = 0.0


## [camera-pass calls, shadow-pass calls, primitives, gpu ms, objects, render cpu ms]
## averaged over `frames`.
func _stats(frames: int) -> Array:
	var vis := 0
	var shd := 0
	var prims := 0
	var objs := 0
	var gpu := 0.0
	var cpu := 0.0
	for k in frames:
		await RenderingServer.frame_post_draw
		vis += RenderingServer.viewport_get_render_info(_vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		shd += RenderingServer.viewport_get_render_info(_vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		objs += RenderingServer.viewport_get_render_info(_vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
	return [vis / frames, shd / frames, prims / frames, gpu / frames, objs / frames, cpu / frames]


## Props grouped by their scene (lamp, parked car, bin...).
func _prop_types() -> Dictionary:
	var types := {}
	for c in game.world.get_node("Props").get_children():
		var t := c.scene_file_path.get_file().get_basename()
		if t == "":
			t = String(c.name)
		if not types.has(t):
			types[t] = []
		(types[t] as Array).append(c)
	return types


## The families: each child of the world (props split by type), the traffic
## cars and the player's car.
func _families() -> Dictionary:
	var fams := {}
	for c in game.world.get_children():
		if c.name == &"Props":
			var types := _prop_types()
			for t: String in types:
				fams["props/" + t] = types[t]
		elif c is Node3D or _has_geometry(c):
			fams[String(c.name)] = [c]
	var traffic: Array = []
	for d in game.traffic.drivers:
		if is_instance_valid(d) and is_instance_valid(d.vehicle):
			traffic.append(d.vehicle)
	fams["(traffic cars)"] = traffic
	fams["(player car)"] = [game.vehicle]
	return fams


func _has_geometry(n: Node) -> bool:
	return not n.find_children("*", "GeometryInstance3D", true, false).is_empty()


## Hides the geometry under `nodes`, adding what it hid to `hidden`.
func _hide(nodes: Array, hidden: Array) -> void:
	for n: Node in nodes:
		if n is Node3D:
			if (n as Node3D).visible:
				(n as Node3D).visible = false
				hidden.append(n)
		else:
			for c in n.get_children():
				_hide([c], hidden)


func _breakdown(view: String) -> void:
	var base: Array = await _stats(60)
	_report("")
	_report("VIEW %s: %d draw calls = %d camera + %d shadow, %d objects, %d prims, gpu %.2f ms, render cpu %.2f ms" % [
		view, base[0] + base[1], base[0], base[1], base[4], base[2], base[3], base[5]])
	var fams := _families()
	var rows: Array = []
	for fam: String in fams:
		var hidden: Array = []
		_hide(fams[fam], hidden)
		if hidden.is_empty():
			continue
		await wait(3)
		var st: Array = await _stats(20)
		for n: Node3D in hidden:
			n.visible = true
		await wait(3)
		var cam_d: int = base[0] - st[0]
		var shd_d: int = base[1] - st[1]
		if cam_d + shd_d < 3:
			continue
		rows.append([cam_d + shd_d, "  %-22s %5d calls (%4d camera, %4d shadow) %8d prims %+6.2f ms gpu %+6.2f ms cpu" % [
			fam, cam_d + shd_d, cam_d, shd_d, base[2] - st[2], base[3] - st[3], base[5] - st[5]]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r: Array in rows:
		_report(r[1])


## Each config sets something up and returns a Callable that undoes it.
func _configs() -> Array:
	var props := game.world.get_node("Props")
	var parked: Array = []
	var small: Array = []
	for t: String in _prop_types():
		if t.begins_with("parked_"):
			parked.append_array(_prop_types()[t])
		elif t in ["traffic_cone", "barrel", "crate", "bowling_pin", "hydrant", "street_bin", "bench", "signal_cabinet"]:
			small.append_array(_prop_types()[t])
	var traffic: Array = []
	for d in game.traffic.drivers:
		if is_instance_valid(d) and is_instance_valid(d.vehicle):
			traffic.append(d.vehicle)
	# Road decks that lie on the ground (the highway has elevated stretches).
	var ground_roads: Array = []
	for n in ["CityRoads", "CountryRoads", "Trails"]:
		var r := game.world.get_node("Roads").get_node_or_null(n)
		if r:
			ground_roads.append(r)
	return [
		["as is", func() -> Callable: return func() -> void: pass],
		["parked old way", func() -> Callable: return _parked_old_way(parked)],
		["traffic old way", func() -> Callable: return _traffic_old_way(traffic)],
		["parked+traffic old way", func() -> Callable:
			var a := _parked_old_way(parked)
			var b := _traffic_old_way(traffic)
			return func() -> void:
				a.call()
				b.call()],
		["2 splits", func() -> Callable: return _sun_mode(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, _sun.directional_shadow_max_distance)],
		["shadow 120 m", func() -> Callable: return _sun_mode(_sun.directional_shadow_mode, 120.0)],
		["props no shadow", func() -> Callable: return _no_shadow([props])],
		["parked no shadow", func() -> Callable: return _no_shadow(parked)],
		["small props no shadow", func() -> Callable: return _no_shadow(small)],
		["roads no shadow", func() -> Callable: return _no_shadow([game.world.get_node("Roads")])],
		["ground roads no shadow", func() -> Callable: return _no_shadow(ground_roads)],
		["traffic no shadow", func() -> Callable: return _no_shadow(traffic)],
		["parked hidden", func() -> Callable:
			var hidden: Array = []
			_hide(parked, hidden)
			return func() -> void:
				for n: Node3D in hidden:
					n.visible = true],
		["msaa off", func() -> Callable:
			var vp := tools.get_viewport()
			var old := vp.msaa_3d
			vp.msaa_3d = Viewport.MSAA_DISABLED
			return func() -> void: vp.msaa_3d = old],
		["2 splits + props no shadow", func() -> Callable:
			var a := _sun_mode(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, _sun.directional_shadow_max_distance)
			var b := _no_shadow([props])
			return func() -> void:
				a.call()
				b.call()],
		["parked+ground roads no shadow", func() -> Callable:
			var a := _no_shadow(parked)
			var b := _no_shadow(ground_roads)
			return func() -> void:
				a.call()
				b.call()],
		["2 splits+parked+roads no shadow", func() -> Callable:
			var a := _sun_mode(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, _sun.directional_shadow_max_distance)
			var b := _no_shadow(parked)
			var c := _no_shadow(ground_roads)
			return func() -> void:
				a.call()
				b.call()
				c.call()],
	]


## Parked cars as they were before CarLod: every real part drawn and
## casting shadows out to 200 m, no merged meshes.
func _parked_old_way(parked: Array) -> Callable:
	var changed: Array = []
	for p: Node in parked:
		var far := p.get_node_or_null("FarLod") as MeshInstance3D
		if far == null:
			continue
		for n in p.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			changed.append([mi, mi.visible, mi.visibility_parent, mi.visibility_range_end, mi.cast_shadow, mi.visibility_range_fade_mode])
			if mi.name == &"FarLod" or mi.name == &"ShadowLod":
				mi.visible = false
			elif mi.visible:
				mi.visibility_parent = NodePath()
				mi.visibility_range_end = Prop.PARKED_CAR_RANGE
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return func() -> void:
		for c: Array in changed:
			var mi := c[0] as MeshInstance3D
			mi.visible = c[1]
			mi.visibility_parent = c[2]
			mi.visibility_range_end = c[3]
			mi.cast_shadow = c[4]
			mi.visibility_range_fade_mode = c[5]


## Traffic as it was before CarLod: every real part drawn and casting shadows.
func _traffic_old_way(traffic: Array) -> Callable:
	var was: Array = []
	for v: Node3D in traffic:
		if is_instance_valid(v) and v.has_node("FarLod"):
			was.append([v, (v.get_node("FarLod") as Node3D).visible])
			CarLod._set_active(v, false)
	return func() -> void:
		for w: Array in was:
			if is_instance_valid(w[0]):
				CarLod._set_active(w[0], w[1])


func _sun_mode(mode: DirectionalLight3D.ShadowMode, dist: float) -> Callable:
	var old_mode := _sun.directional_shadow_mode
	var old_dist := _sun.directional_shadow_max_distance
	_sun.directional_shadow_mode = mode
	_sun.directional_shadow_max_distance = dist
	return func() -> void:
		_sun.directional_shadow_mode = old_mode
		_sun.directional_shadow_max_distance = old_dist


func _no_shadow(roots: Array) -> Callable:
	var changed: Array = []
	for r: Node in roots:
		var all := r.find_children("*", "GeometryInstance3D", true, false)
		if r is GeometryInstance3D:
			all.append(r)
		for n in all:
			var gi := n as GeometryInstance3D
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				changed.append([gi, gi.cast_shadow])
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return func() -> void:
		for c: Array in changed:
			if is_instance_valid(c[0]):
				(c[0] as GeometryInstance3D).cast_shadow = c[1]


## Each config against "as is", interleaved A/B for `rounds` rounds: the iGPU's
## clocks wander by a few ms, so only the median of back-to-back pairs means much.
func _what_ifs() -> void:
	var rounds := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			rounds = maxi(1, int(arg.split("=")[1]))
	_report("  what-ifs (median of %d back-to-back A/B pairs):" % rounds)
	for c: Array in _configs():
		if c[0] == "as is":
			continue
		var d_gpu: Array[float] = []
		var d_cpu: Array[float] = []
		var st: Array = []
		var base: Array = []
		for r in rounds:
			base = await _stats(24)
			var undo: Callable = (c[1] as Callable).call()
			await wait(6)
			st = await _stats(24)
			undo.call()
			await wait(6)
			d_gpu.append(st[3] - base[3])
			d_cpu.append(st[5] - base[5])
		d_gpu.sort()
		d_cpu.sort()
		_report("    %-30s %5d calls (%+5d: camera %+4d, shadow %+4d)  gpu %+.2f ms [%+.2f..%+.2f]  render cpu %+.2f ms" % [
			c[0], st[0] + st[1], (st[0] + st[1]) - (base[0] + base[1]), st[0] - base[0], st[1] - base[1],
			d_gpu[rounds / 2], d_gpu[0], d_gpu[rounds - 1], d_cpu[rounds / 2]])


## Meshes, surfaces, shadow-casting surfaces and the visibility range under
## `nodes` (visible ones only).
func _census(nodes: Array) -> String:
	var meshes := 0
	var multimeshes := 0
	var surfaces := 0
	var casters := 0
	var range_end := 0.0
	for root: Node in nodes:
		var all := root.find_children("*", "GeometryInstance3D", true, false)
		if root is GeometryInstance3D:
			all.append(root)
		for n in all:
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var s := 0
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				s = (gi as MeshInstance3D).mesh.get_surface_count()
				meshes += 1
			elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
				s = (gi as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
				multimeshes += 1
			else:
				continue
			surfaces += s
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += s
			range_end = maxf(range_end, gi.visibility_range_end)
	return "%d meshes, %d multimeshes, %d surfaces, %d casting shadows, range %s" % [
		meshes, multimeshes, surfaces, casters, ("%.0f m" % range_end) if range_end > 0.0 else "none"]


func _car_census() -> void:
	_report("")
	_report("TRAFFIC CARS (per car)")
	for scene in game.traffic.car_scenes:
		var car := scene.instantiate()
		tools.add_child(car)
		_report("  %-16s %s" % [scene.resource_path.get_file().get_basename(), _census([car])])
		tools.remove_child(car)
		car.queue_free()


func _drive_stats(label: String) -> void:
	var g := game
	# Same line as the --bench city drive: north up the avenue at 80 km/h.
	var done: Array = [false]
	var run := func() -> void:
		await tools._drive_line(g, Vector3(2.4, 0.0, 150.0), Vector3(2.4, 0.0, -260.0), 80.0, 14.0)
		done[0] = true
	run.call()
	await wait_s(3.0)
	var vis := 0
	var shd := 0
	var peak := 0
	var peak_shd := 0
	var gpu := 0.0
	var gpu_peak := 0.0
	var cpu := 0.0
	var n := 0
	while not done[0] and n < 600:
		await RenderingServer.frame_post_draw
		var v := RenderingServer.viewport_get_render_info(_vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var s := RenderingServer.viewport_get_render_info(_vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var gt := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		vis += v
		shd += s
		gpu += gt
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu_peak = maxf(gpu_peak, gt)
		if v + s > peak:
			peak = v + s
			peak_shd = s
		n += 1
	n = maxi(n, 1)
	_report("DRIVE %-28s %d cars: %5d calls avg (%d camera + %d shadow), peak %d (%d shadow), gpu %.2f ms (peak %.2f), render cpu %.2f ms, %d frames" % [
		label, g.traffic.drivers.size(), (vis + shd) / n, vis / n, shd / n, peak, peak_shd, gpu / n, gpu_peak, cpu / n, n])
	while not done[0]:
		await tools.get_tree().process_frame
	await wait_s(1.0)
