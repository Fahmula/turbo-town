class_name CarLod
extends RefCounted
## Cheap cars from afar (ART_BIBLE.md §27): parked-car props and traffic. A
## car is ~25 surfaces (body, bumpers, four wheels, several materials each),
## and every one is a draw call in the camera pass and again in each shadow
## split it falls in. `fit_prop` / `fit_vehicle` give the car two children:
## * "FarLod": its parts merged into one mesh with one shared material
##   (car_far.gdshader; looks baked into the vertices, paint, grime and lamp
##   states per car through instance uniforms), shown beyond NEAR instead of
##   the real parts;
## * "ShadowLod": the same merge without the see-through glass, which casts
##   the car's shadow at every distance (the real parts cast none).
## So a far car is one draw call per pass and a near one costs one per shadow
## split. The merges are built once per car type and shared: `prebuild` makes
## a batch of types at load, the slow part (LODs) on worker threads.
## Traffic: the merge is the car at rest (wheels straight and still, no body
## lean), which doesn't show at 40 m. VehicleBodyVisual sends its lamp states,
## paint and grime to the far mesh (add_far_lod). A damaged car shows its real
## parts at every distance (dents, lost bumpers, broken lamps) until it's
## repaired, and a traffic car the player takes loses all this (unfit_vehicle).

## Real parts out to here, the merged mesh beyond (swapping back and forth
## only once the distance moves this far past it, so it never flickers).
const NEAR := 40.0
const MARGIN := 4.0
const FAR_SHADER := preload("res://assets/shaders/vehicle/car_far.gdshader")

## Looks of the parts whose runtime shaders differ from the imported material
## (VehicleBodyVisual swaps them): [sRGB albedo, roughness, metallic]. Glass is
## opaque from afar, darkened for the cabin behind it. Lamps: _lamp_look.
const LOOKS := {
	"Trim": [Color(0.133, 0.137, 0.149), 0.6, 0.0],
	"Glass": [Color(0.14, 0.17, 0.21), 0.05, 0.0],
}
const LAMPS := {"Headlight": 0, "TailLight": 1, "ReverseLight": 2}
## Parked props' grime line (they're never dirty; the paint shader's default).
const PROP_DIRT_TOP := 0.3

## scene path -> [far mesh, shadow mesh]
static var _meshes := {}
static var _material: ShaderMaterial


## A parked-car prop: merged beyond NEAR, drawn out to `end_range`.
static func fit_prop(prop: Prop, end_range: float) -> void:
	var sel := _parts(prop, true)
	if (sel[0] as Array).is_empty():
		return
	var paint := prop.paint if prop.paint != Color.TRANSPARENT else Color(0.5, 0.5, 0.5)
	var lod := _fit(prop, sel[0], sel[1], PROP_DIRT_TOP, end_range, 1)
	for gi: GeometryInstance3D in lod:
		gi.set_instance_shader_parameter("paint_color", paint)
		gi.set_instance_shader_parameter("paint_metallic", PaintPalette.metallic_of(paint))
		gi.set_instance_shader_parameter("lights", 0.0)  # parked: lamps off


## A traffic car (call once it's in the tree; again for a reused one).
static func fit_vehicle(v: Vehicle) -> void:
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	if body == null:
		return
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if v.has_node("FarLod"):
		_set_active(v, dmg == null or dmg.total_damage <= 0.0)
		return
	var sel := _parts(v, true)
	if (sel[0] as Array).is_empty():
		return
	var lod := _fit(v, sel[0], sel[1], body.dirt_top, 0.0, Vehicle.VISUAL_LAYER)
	body.add_far_lod(lod[0])
	if dmg:
		var on_damage := func(total: float) -> void: _set_active(v, total <= 0.0)
		dmg.damage_changed.connect(on_damage)
		v.set_meta("lod_on_damage", on_damage)
		_set_active(v, dmg.total_damage <= 0.0)


## Takes it all off a car again (the player took it out of traffic).
static func unfit_vehicle(v: Vehicle) -> void:
	if not v.has_node("FarLod"):
		return
	_set_active(v, false)
	var dmg := v.get_node_or_null("Damage") as VehicleDamage
	if dmg and v.has_meta("lod_on_damage"):
		var cb: Callable = v.get_meta("lod_on_damage")
		if dmg.damage_changed.is_connected(cb):
			dmg.damage_changed.disconnect(cb)
		v.remove_meta("lod_on_damage")
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.far_lods.clear()
	for n in ["FarLod", "ShadowLod"]:
		var node := v.get_node(n)
		v.remove_child(node)
		node.queue_free()
	v.remove_meta("lod_parts")


## Builds the merged meshes of these vehicle / parked-car scenes ahead of
## their first fit (from spare copies outside the tree). The source meshes are
## read here; building the arrays and the LODs runs on worker threads.
static func prebuild(scenes: Array) -> void:
	var keys: Array[String] = []
	var jobs: Array = []  # [surfaces, for_shadow, dirt_top]
	for scene: PackedScene in scenes:
		if scene == null or _meshes.has(scene.resource_path) or keys.has(scene.resource_path):
			continue
		var root := scene.instantiate() as Node3D
		var sel := _parts(root, false) if root else [[], []]
		if not (sel[0] as Array).is_empty():
			var body := root.get_node_or_null("Body") as VehicleBodyVisual
			var dirt_top := body.dirt_top if body else PROP_DIRT_TOP
			var surfaces := _collect(root, sel[0])
			keys.append(scene.resource_path)
			jobs.append([surfaces, false, dirt_top])
			jobs.append([surfaces, true, dirt_top])
		if root:
			root.free()
	if jobs.is_empty():
		return
	var ims: Array[ImporterMesh] = []
	for j in jobs:
		ims.append(ImporterMesh.new())
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var job: Array = jobs[i]
		_build(ims[i], job[0], job[1], job[2]), jobs.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	for k in keys.size():
		_meshes[keys[k]] = [ims[k * 2].get_mesh(), ims[k * 2 + 1].get_mesh()]


## [merged, swapped]: the meshes that go into the merge, and the ones that
## swap with it (also calipers: the rims hide them from afar). A vehicle's are
## its body and wheel models; a prop's, all of its meshes. Outside the tree
## (prebuild), VehicleBodyVisual and Prop haven't hidden the optional racing
## stripes yet (never on traffic or parked cars), so they're left out by name.
static func _parts(root: Node3D, in_tree: bool) -> Array:
	var merged: Array[MeshInstance3D] = []
	var swapped: Array[MeshInstance3D] = []
	var body := root.get_node_or_null("Body") as VehicleBodyVisual if root is Vehicle else null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.name == &"FarLod" or mi.name == &"ShadowLod":
			continue
		if in_tree and not mi.is_visible_in_tree():
			continue
		if not in_tree and (mi.name == &"Stripes" or not _shown(mi, root)):
			continue
		if body == null:
			merged.append(mi)
			swapped.append(mi)
			continue
		var in_wheel := false
		var caliper := false
		var p := mi.get_parent()
		while p != root and p != null:
			in_wheel = in_wheel or p is VehicleWheel
			caliper = caliper or p.name == &"Caliper"
			p = p.get_parent()
		if body.is_ancestor_of(mi) or (in_wheel and not caliper):
			merged.append(mi)
			swapped.append(mi)
		elif caliper:
			swapped.append(mi)
	return [merged, swapped]


## `node` and everything above it up to `root` is visible.
static func _shown(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n is Node3D and not (n as Node3D).visible:
			return false
		if n == root:
			return true
		n = n.get_parent()
	return true


## Adds FarLod and ShadowLod to `root` (merging `merged` first if this type
## isn't built yet) and hangs `swapped` on FarLod. Returns [far, shadow].
static func _fit(root: Node3D, merged: Array[MeshInstance3D], swapped: Array[MeshInstance3D],
		dirt_top: float, end_range: float, layers: int) -> Array:
	var key := root.scene_file_path
	if not _meshes.has(key):
		var surfaces := _collect(root, merged)
		_meshes[key] = [_mesh(surfaces, false, dirt_top), _mesh(surfaces, true, dirt_top)]
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = FAR_SHADER
	var far := _instance("FarLod", (_meshes[key] as Array)[0], root, layers)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.visibility_range_begin = NEAR
	far.visibility_range_begin_margin = MARGIN
	far.visibility_range_end = end_range
	far.visibility_range_end_margin = 20.0
	# The two versions match closely, so a clean swap (with hysteresis) reads
	# better than a dithered crossfade, which doubles the car for a moment.
	far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var shadow := _instance("ShadowLod", (_meshes[key] as Array)[1], root, layers)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.visibility_range_end = end_range + 20.0 if end_range > 0.0 else 0.0
	# What the real parts were, to put back when the car is damaged.
	var saved: Array = []
	for mi in swapped:
		saved.append([mi, mi.cast_shadow, mi.visibility_range_end, mi.visibility_range_end_margin,
			mi.visibility_range_fade_mode])
	root.set_meta("lod_parts", saved)
	_set_active(root, true)
	return [far, shadow]


## On: the real parts follow FarLod (HLOD) and cast no shadow. Off: they're
## drawn as they were, at every distance, and the merged meshes are hidden.
static func _set_active(root: Node3D, on: bool) -> void:
	var far := root.get_node_or_null("FarLod") as MeshInstance3D
	var shadow := root.get_node_or_null("ShadowLod") as MeshInstance3D
	if far == null or shadow == null or root.get_meta("lod_on", not on) == on:
		return
	root.set_meta("lod_on", on)
	far.visible = on
	shadow.visible = on
	for s: Array in root.get_meta("lod_parts", []):
		var mi := s[0] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		if on:
			# HLOD: the real parts show exactly when the far mesh is too close
			# to show, so wheels and body swap together on its distance.
			mi.visibility_range_end = 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi.visibility_parent = mi.get_path_to(far)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.visibility_parent = NodePath()
			mi.cast_shadow = s[1]
			mi.visibility_range_end = s[2]
			mi.visibility_range_end_margin = s[3]
			mi.visibility_range_fade_mode = s[4]


static func _instance(node_name: String, mesh: Mesh, root: Node3D, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _material
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	mi.layers = layers
	root.add_child(mi)
	return mi


## Where `node` sits in `root` with the car at rest: wheels straight, not
## spun, at their resting height (VehicleWheel.pose_at_rest), and no body
## lean (VehicleBodyVisual).
static func _rest_xform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n != null:
		var n3 := n as Node3D
		var t := n3.transform if n3 else Transform3D.IDENTITY
		if n3 is VehicleWheel or n3 is VehicleBodyVisual:
			t = Transform3D(Basis.IDENTITY, n3.position)
		elif n3 and n3.name == &"Visual" and n3.get_parent() is VehicleWheel and root is Vehicle:
			var w := n3.get_parent() as VehicleWheel
			t = Transform3D(Basis.IDENTITY, Vector3(w.track_offset, -w.rest_drop((root as Vehicle).mass / 4.0), 0.0))
		xf = t * xf
		n = n.get_parent()
	return xf


## One merged mesh of `parts` (in `root`'s space, at rest), right away.
static func _merge(root: Node3D, parts: Array[MeshInstance3D], for_shadow: bool, dirt_top: float) -> Mesh:
	return _mesh(_collect(root, parts), for_shadow, dirt_top)


static func _mesh(surfaces: Array, for_shadow: bool, dirt_top: float) -> Mesh:
	var im := ImporterMesh.new()
	_build(im, surfaces, for_shadow, dirt_top)
	return im.get_mesh()


## Reads what the merge needs from the scene (main thread): per surface
## [arrays, transform, role, see-through, sRGB albedo, roughness, metallic].
static func _collect(root: Node3D, parts: Array[MeshInstance3D]) -> Array:
	var out: Array = []
	for mi in parts:
		var xf := _rest_xform(mi, root)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			out.append([mi.mesh.surface_get_arrays(s), xf, String(mat.resource_name) if mat else "",
				mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
				mat.albedo_color if mat else Color(0.5, 0.5, 0.5), mat.roughness if mat else 0.5,
				mat.metallic if mat else 0.0])
	return out


## Builds one surface from `surfaces` into `im`, with LODs (plain data: safe
## on a worker thread). The far mesh leaves out the cabin (dark glass hides
## it); the shadow mesh leaves out the see-through glass, which casts no
## shadow on the real car either.
static func _build(im: ImporterMesh, surfaces: Array, for_shadow: bool, dirt_top: float) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for surf: Array in surfaces:
		var arr: Array = surf[0]
		var xf: Transform3D = surf[1]
		var role: String = surf[2]
		if (for_shadow and surf[3]) or (not for_shadow and role == "Interior"):
			continue
		var look: Array = LOOKS.get(role, [surf[4], surf[5], surf[6]])
		var albedo := (look[0] as Color).srgb_to_linear()
		var c := Color(albedo.r, albedo.g, albedo.b, look[1])
		var m := Vector2(look[2], 1.0 if role == "Paint" else 0.0)
		var nb := xf.basis.inverse().transposed()
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var su: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var lamp: int = LAMPS.get(role, -1)
		var base := verts.size()
		var n := sv.size()
		# Whole arrays at once where Godot can.
		verts.append_array(xf * sv)
		var sn2 := Transform3D(nb, Vector3.ZERO) * sn
		if not nb.is_conformal() or absf(nb.get_scale().x - 1.0) > 0.001:
			for i in n:
				sn2[i] = sn2[i].normalized()
		normals.append_array(sn2)
		if lamp >= 0:
			for i in n:
				var l := _lamp_look(lamp, su[i].x if i < su.size() else 0.0, sv[i].x < 0.0)
				colors.append(l[0])
				uv2.append(Vector2(l[1], 0.0))
				uv.append(Vector2(l[2], 0.0))
		else:
			var cs := PackedColorArray()
			cs.resize(n)
			cs.fill(c)
			colors.append_array(cs)
			var ms := PackedVector2Array()
			ms.resize(n)
			ms.fill(m)
			uv2.append_array(ms)
			if role == "Paint":
				# car_paint's grime falloff, from the part's own height.
				for i in n:
					var t := clampf((sv[i].y - dirt_top) / -0.6, 0.0, 1.0)
					uv.append(Vector2(0.0, t * t * (3.0 - 2.0 * t)))
			else:
				ms.fill(Vector2.ZERO)
				uv.append_array(ms)
		var si: Variant = arr[Mesh.ARRAY_INDEX]
		if si == null:
			for i in n:
				indices.append(base + i)
		else:
			var idx := si as PackedInt32Array
			var at := indices.size()
			indices.resize(at + idx.size())
			for i in idx.size():
				indices[at + i] = idx[i] + base
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Automatic LODs, like the imported models have, for the far views.
	im.generate_lods(25.0, 60.0, [])


## A lamp at one vertex, as vehicle_lamp.gdshader draws it unlit:
## [Color(linear lens, roughness), metallic, lamp code for car_far's glow].
## `u` is the vertex's UV.x, where body_kit tags the patch kind (vh_kind:
## 1 lamp, 2 DRL / position light, 3 indicator, 4 aux, 5 third brake light);
## `left` = the indicator on the car's left (object x < 0).
static func _lamp_look(lamp: int, u: float, left: bool) -> Array:
	var kind := maxf(floorf(u / 10.0 + 0.0005), 1.0)
	if kind > 2.5 and kind < 3.5:
		return [Color(0.62, 0.2, 0.012, 0.08), 0.0, 3.0 if left else 4.0]
	if lamp == 1:
		return [Color(0.16, 0.006, 0.006, 0.08), 0.0, 6.0 if kind < 1.5 else (7.0 if kind < 2.5 else 8.0)]
	if lamp == 2:
		return [Color(0.7, 0.7, 0.7, 0.12), 1.0, 9.0]
	return [Color(0.78, 0.79, 0.8, 0.1), 1.0, 1.0 if kind < 1.5 else (2.0 if kind < 2.5 else 5.0)]
