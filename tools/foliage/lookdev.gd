extends SceneTree
## Tree look-dev sheet (a tool, not part of the game): lines the TreeKit
## variants up on a lawn under the game's sun and shoots them from several
## distances, with a 4.4 m car-sized box and a 1.8 m person for scale. Prints
## each mesh's triangle count and build time.
##
##   godot --path . --resolution 1280x800 -s tools/foliage/lookdev.gd -- \
##       --out=/tmp/lookdev --kinds=broadleaf_a,conifer_a,palm --lod=0 --views=lineup,close
##
## --time=day|sunset (sun angle), --lod=0|1|2, --views=lineup,close,under,back
## (back = the sun behind the crown, for translucency). Default kinds: all
## variants; for --lod=1 or 2 give species names (broadleaf, conifer, palm, shrub, hedge).

var _out := "/tmp/lookdev"
var _kinds: PackedStringArray = ["broadleaf_a", "broadleaf_b", "broadleaf_c", "conifer_a", "conifer_b", "palm", "shrub", "hedge"]
var _lod := 0
var _views: PackedStringArray = ["lineup", "close"]
var _time := "day"
var _cam: Camera3D
var _sun: DirectionalLight3D
var _placed := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.split("=")[1]
		elif arg.begins_with("--kinds="):
			_kinds = arg.split("=")[1].split(",")
		elif arg.begins_with("--lod="):
			_lod = int(arg.split("=")[1])
		elif arg.begins_with("--views="):
			_views = arg.split("=")[1].split(",")
		elif arg.begins_with("--time="):
			_time = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _run() -> void:
	root.msaa_3d = Viewport.MSAA_2X
	_build_scene()
	var x := 0.0
	var spacing := 16.0
	for k in _kinds:
		var t0 := Time.get_ticks_usec()
		var m := TreeKit.mesh(k, _lod)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("%-12s lod%d %6d tris %6d verts  built in %.1f ms" % [k, _lod, tris, (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), ms])
		_place(k, Vector3(x, 0, 0), 0.4)
		_placed[k] = Vector3(x, 0, 0)
		x += spacing
	# scale references next to the first tree
	_box(Vector3(_placed[_kinds[0]].x - 6.0, 0.7, 6.0), Vector3(1.8, 1.4, 4.4))
	_person(Vector3(_placed[_kinds[0]].x - 3.5, 0.9, 6.0))
	for i in 12:
		await process_frame
	var mid_x: float = (x - spacing) * 0.5
	for view in _views:
		match view:
			"lineup":
				await _shot("lineup_lod%d" % _lod, Vector3(mid_x, 4.0, 42.0 + (x - spacing) * 0.18), Vector3(mid_x, 4.0, 0.0))
			"grove":
				for gx in 3:
					for gz in 3:
						var kk: String = _kinds[(gx * 3 + gz) % _kinds.size()]
						_place(kk, Vector3(-200.0 + gx * 9.0 + (gz % 2) * 3.0, 0.0, 60.0 + gz * 8.0), 0.1 * (gx * 3 + gz))
				for i in 6:
					await process_frame
				await _shot("grove_lod%d" % _lod, Vector3(-190.0, 1.7, 100.0), Vector3(-190.0, 5.0, 70.0))
				await _shot("grove_high_lod%d" % _lod, Vector3(-175.0, 1.7, 55.0), Vector3(-190.0, 6.0, 70.0))
			"far":
				await _shot("far_lod%d" % _lod, Vector3(mid_x, 8.0, 180.0), Vector3(mid_x, 4.0, 0.0))
			"close", "under", "back":
				for k in _kinds:
					var p: Vector3 = _placed[k]
					var h: float = _height_of(k)
					if view == "close":
						await _shot("%s_close_lod%d" % [k, _lod], p + Vector3(0, minf(1.8, h * 0.6), 4.0 + h * 1.5), p + Vector3(0, h * 0.45, 0))
					elif view == "under":
						await _shot("%s_under_lod%d" % [k, _lod], p + Vector3(3.0, 1.7, 3.5), p + Vector3(0, h * 0.7, 0))
					else:
						# camera on the far side from the sun, looking into it through the crown
						var sun_dir := -_sun.global_basis.z
						var horiz := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
						await _shot("%s_back_lod%d" % [k, _lod], p - horiz * (10.0 + h * 0.4) + Vector3(0, 1.8, 0), p + Vector3(0, h * 0.55, 0))
	quit()


func _height_of(k: String) -> float:
	var name := k
	if TreeKit.SPECIES.has(k):
		name = TreeKit.SPECIES[k]["variants"][0]
	var v: Dictionary = TreeKit.VARIANTS[name]
	return float(v.get("height", 3.0))


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.239, 0.486, 0.788)
	sm.sky_horizon_color = Color(0.839, 0.89, 0.925)
	sm.ground_horizon_color = Color(0.839, 0.89, 0.925)
	sm.ground_bottom_color = Color(0.38, 0.38, 0.35)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.92)
	env.ambient_light_sky_contribution = 0.2
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.set("tonemap_agx_contrast", 1.4)
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.86, 0.92)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.95, 0.86)
	_sun.light_energy = 1.4
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.04
	_sun.shadow_blur = 1.2
	_sun.directional_shadow_max_distance = 260.0
	_sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0) if _time == "day" else Vector3(-12.0, -60.0, 0.0)
	if _time == "sunset":
		_sun.light_color = Color(1.0, 0.6, 0.35)
		_sun.light_energy = 1.2
	root.add_child(_sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.5, 0.23)
	gm.roughness = 0.95
	pm.material = gm
	root.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 2000.0
	root.add_child(_cam)
	_cam.current = true


func _place(kind: String, pos: Vector3, seed_v: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = TreeKit.mesh(kind, _lod)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.7), pos))
	mm.set_instance_custom_data(0, Color(0.0, seed_v, 0.5, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)


func _box(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.15, 0.12)
	bm.material = m
	mi.position = pos
	root.add_child(mi)


func _person(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.height = 1.8
	cm.radius = 0.25
	mi.mesh = cm
	mi.position = pos
	root.add_child(mi)


func _shot(shot_name: String, from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
	print("shot %s  (%d draw calls, %d primitives)" % [shot_name, calls, prims])
