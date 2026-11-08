class_name ParkedCarLod
extends RefCounted
## Cheap parked cars (ART_BIBLE.md §27). A parked-car prop is ~25 surfaces
## (body, bumpers, four wheels, each with several materials), and every one is
## a draw call in the camera pass and again in each shadow split it falls in.
## `fit` gives the prop:
## * "Far": its parts merged into one mesh with one shared material
##   (parked_far.gdshader; looks baked into the vertices, paint per car through
##   instance uniforms), shown beyond NEAR instead of the real parts;
## * "Shadow": the same merge without the see-through glass, which casts the
##   car's shadow at every distance (the real parts cast none).
## So a far car is one draw call per pass and a near one costs one per shadow
## split. The merged meshes are built once per car type and shared.

## Real parts out to here, the merged mesh beyond (swapping back and forth
## only once the distance moves this far past it, so it never flickers).
const NEAR := 40.0
const MARGIN := 4.0
const FAR_SHADER := preload("res://assets/shaders/vehicle/parked_far.gdshader")

## Looks of the parts whose runtime shaders differ from the imported material
## (VehicleBodyVisual swaps them): [sRGB albedo, roughness, metallic]. Glass is
## opaque from afar, darkened for the cabin behind it. Lamps: _lamp_look.
const LOOKS := {
	"Trim": [Color(0.133, 0.137, 0.149), 0.6, 0.0],
	"Glass": [Color(0.14, 0.17, 0.21), 0.05, 0.0],
}
const LAMPS := {"Headlight": 0, "TailLight": 1, "ReverseLight": 2}

## scene path -> [far mesh, shadow mesh]
static var _meshes := {}
static var _material: ShaderMaterial


static func fit(prop: Prop, end_range: float) -> void:
	var parts: Array[MeshInstance3D] = []
	for n in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and mi.is_visible_in_tree():
			parts.append(mi)
	if parts.is_empty():
		return
	var key := prop.scene_file_path
	if not _meshes.has(key):
		_meshes[key] = [_merge(prop, parts, false), _merge(prop, parts, true)]
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = FAR_SHADER
	var far := _instance("Far", (_meshes[key] as Array)[0], prop)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.visibility_range_begin = NEAR
	far.visibility_range_begin_margin = MARGIN
	far.visibility_range_end = end_range
	far.visibility_range_end_margin = 20.0
	# The two versions match closely, so a clean swap (with hysteresis) reads
	# better than a dithered crossfade, which doubles the car for a moment.
	far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for mi in parts:
		# HLOD: the real parts show exactly when the far mesh is too close to
		# show, so wheels and body swap together on the far mesh's distance.
		mi.visibility_range_end = 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.visibility_parent = mi.get_path_to(far)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow := _instance("Shadow", (_meshes[key] as Array)[1], prop)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.visibility_range_end = end_range + 20.0


static func _instance(node_name: String, mesh: Mesh, prop: Prop) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _material
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	prop.add_child(mi)
	var paint := prop.paint if prop.paint != Color.TRANSPARENT else Color(0.5, 0.5, 0.5)
	mi.set_instance_shader_parameter("paint_color", paint)
	mi.set_instance_shader_parameter("paint_metallic", PaintPalette.metallic_of(paint))
	return mi


## One surface from all of `parts` (in the prop's space). The far mesh leaves
## out the cabin (dark glass hides it); the shadow mesh leaves out the
## see-through glass, which casts no shadow on the real car either.
static func _merge(prop: Prop, parts: Array[MeshInstance3D], for_shadow: bool) -> Mesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var to_prop := prop.global_transform.affine_inverse()
	for mi in parts:
		var xf := to_prop * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var role := String(mat.resource_name) if mat else ""
			var see_through := mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			if (for_shadow and see_through) or (not for_shadow and role == "Interior"):
				continue
			var look: Array = LOOKS.get(role, [mat.albedo_color if mat else Color(0.5, 0.5, 0.5),
				mat.roughness if mat else 0.5, mat.metallic if mat else 0.0])
			var albedo := (look[0] as Color).srgb_to_linear()
			var c := Color(albedo.r, albedo.g, albedo.b, look[1])
			var m := Vector2(look[2], 1.0 if role == "Paint" else 0.0)
			var arr := mi.mesh.surface_get_arrays(s)
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var su: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var lamp: int = LAMPS.get(role, -1)
			var base := verts.size()
			var n := sv.size()
			# Whole arrays at once where Godot can (this runs at world build).
			verts.append_array(xf * sv)
			var sn2 := Transform3D(nb, Vector3.ZERO) * sn
			if not nb.is_conformal() or absf(nb.get_scale().x - 1.0) > 0.001:
				for i in n:
					sn2[i] = sn2[i].normalized()
			normals.append_array(sn2)
			if lamp >= 0:
				for i in n:
					var l := _lamp_look(lamp, su[i].x if i < su.size() else 0.0)
					colors.append(l[0])
					uv2.append(Vector2(l[1], 0.0))
					uv.append(l[2])
			else:
				var cs := PackedColorArray()
				cs.resize(n)
				cs.fill(c)
				colors.append_array(cs)
				var ms := PackedVector2Array()
				ms.resize(n)
				ms.fill(m)
				uv2.append_array(ms)
				ms.fill(Vector2.ZERO)
				uv.append_array(ms)
			var si = arr[Mesh.ARRAY_INDEX]
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
	# Automatic LODs, like the imported models have, for the far views.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## A parked car's lamp at one vertex, as vehicle_lamp.gdshader draws it with
## the lights off: [Color(linear lens, roughness), metallic, glow]. `u` is the
## vertex's UV.x, where body_kit tags the patch kind (vh_kind: 1 lamp, 2 DRL /
## position light, 3 indicator, 4 aux, 5 third brake light). Parked, the DRLs
## still glow (2.4) and the tail and position lights a little (0.25); glow.x
## is white (headlamp) light, glow.y red (tail), times the lens' average 0.8.
static func _lamp_look(lamp: int, u: float) -> Array:
	var kind := maxf(floorf(u / 10.0 + 0.0005), 1.0)
	if kind > 2.5 and kind < 3.5:
		return [Color(0.62, 0.2, 0.012, 0.08), 0.0, Vector2.ZERO]
	if lamp == 1:
		return [Color(0.16, 0.006, 0.006, 0.08), 0.0, Vector2(0.0, 0.25 * 0.8 if kind < 2.5 else 0.0)]
	if lamp == 2:
		return [Color(0.7, 0.7, 0.7, 0.12), 1.0, Vector2.ZERO]
	return [Color(0.78, 0.79, 0.8, 0.1), 1.0, Vector2(2.4 * 0.8 if kind > 1.5 and kind < 2.5 else 0.0, 0.0)]
