extends SceneTree
## Converts the Downtown City MegaKit modules (glTF, from the build cache
## made by tools/megakit/megakit_common.py) into one MegaKitLibrary resource:
##
##   python3 tools/megakit/megakit_common.py          # download + extract (once)
##   godot --headless --path . --import               # registers MegaKitLibrary
##   godot --headless --path . -s tools/megakit/build_megakit_modules.gd
##
## Output: assets/models/megakit/megakit_modules.res. For the vertex format
## see scripts/world/downtown/megakit_library.gd.
##
## Material -> (texture layer, tint slot, kind) is the MAT table below; the
## layers are the slices of tools/megakit/build_megakit_textures.py and the
## slots are MegaKit.SLOT_* (a building's palette colours each slot).

const SRC := "build/asset_sources/downtown_city_megakit/extracted/Exports/glTF (Godot)/"
const OUT := "res://assets/models/megakit/megakit_modules.res"

# Texture layers (slices of megakit_albedo / megakit_nrm).
const L_BRICK := 0
const L_TRIM := 1
const L_METAL := 2
const L_ORNAMENT := 3
const L_SLATE := 4
const L_ASPHALT := 5
const L_CONCRETE := 6
const L_SOIL := 7
# Tint slots (MegaKit.SLOT_*).
const S_BRICK := 0
const S_BRICK_ALT := 1
const S_TRIM := 2
const S_TRIM_DARK := 3
const S_ACCENT := 4
const S_METAL := 5
const S_ROOF := 6
const S_FIXED := 7
# Kinds.
const K_SOLID := 0
const K_WINDOW := 1
## Glass with nothing behind it in the kit (doors, transoms): kept, drawn as
## dark reflective glass (megakit.gdshader kind 3); dropping it would leave a
## hole into the hollow building.
const K_GLASS := 3

## material name -> [layer, slot, kind, room variant]; missing = dropped.
const MAT := {
	"MI_RedBrick": [L_BRICK, S_BRICK, K_SOLID, 0],
	"MI_RedBrick_Pale": [L_BRICK, S_BRICK_ALT, K_SOLID, 0],
	"MI_Trim": [L_TRIM, S_TRIM, K_SOLID, 0],
	"MI_Trim_Dark": [L_TRIM, S_TRIM_DARK, K_SOLID, 0],
	"MI_Trim_Green": [L_TRIM, S_ACCENT, K_SOLID, 0],
	"MI_Trim_MetalConcrete": [L_METAL, S_METAL, K_SOLID, 0],
	"MI_Ornaments": [L_ORNAMENT, S_FIXED, K_SOLID, 0],
	"MI_Roof_Slate": [L_SLATE, S_ROOF, K_SOLID, 0],
	"MI_Asphalt": [L_ASPHALT, S_FIXED, K_SOLID, 0],
	"MI_Concrete": [L_CONCRETE, S_FIXED, K_SOLID, 0],
	"MI_Dirt": [L_SOIL, S_FIXED, K_SOLID, 0],
	"MI_FakeInterior": [0, S_FIXED, K_WINDOW, 0],
	"MI_FakeInterior_1": [0, S_FIXED, K_WINDOW, 1],
	"MI_FakeInterior_2": [0, S_FIXED, K_WINDOW, 2],
	"MI_FakeInterior_3": [0, S_FIXED, K_WINDOW, 3],
	"MI_FakeInterior_4": [0, S_FIXED, K_WINDOW, 4],
}
const DECAL_MAT := "MI_StreetDecals"
## Never used: interior floors and ceilings.
const SKIP_PREFIX := ["Floor_"]
## Far LOD: modules this cheap are used as they are.
const FAR_KEEP_TRIS := 64
## Far LOD: dropped (small, behind frames, or not worth a proxy).
const FAR_DROP := ["Prop_ACUnit", "Door_1", "Door_2", "Door_3", "Prop_Drain", "Prop_ManholeCover", "Prop_Bollard",
	"Stairs_Rails_Metal", "Stairs_Rails_Metal_Straight_1", "Stairs_Rails_Metal_Straight_2"]
## Far LOD: use this cheaper module's mesh instead (dormers -> plain slope).
const FAR_SUBSTITUTE := {"Roof_SlateCornice_Window_1": "Roof_SlateCornice_Center", "Roof_Slate_Window_1": "Roof_Slate_Center"}


func _initialize() -> void:
	var dir := DirAccess.open(SRC)
	if dir == null:
		push_error("No kit at %s: run python3 tools/megakit/megakit_common.py first" % SRC)
		quit(1)
		return
	var lib := MegaKitLibrary.new()
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".gltf"):
			names.append(f.get_basename())
	names.sort()
	var dropped := {}
	var total_tris := 0
	for n in names:
		if SKIP_PREFIX.any(func(p: String) -> bool: return n.begins_with(p)):
			continue
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(SRC + n + ".gltf", st) != OK:
			push_error("cannot read " + n)
			continue
		var scene := doc.generate_scene(st)
		var solid := _Acc.new()
		var decal := _Acc.new()
		var has_interior := false
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m0 := mi.mesh.surface_get_material(si)
				if m0 and m0.resource_name.begins_with("MI_FakeInterior"):
					has_interior = true
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var xf := _global_xform(mi, scene)
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				var mname := mat.resource_name if mat else ""
				var arrays := mesh.surface_get_arrays(s)
				if mname == DECAL_MAT:
					decal.add(arrays, xf, [0, S_FIXED, K_SOLID, 0])
				elif mname == "MI_Glass" and not has_interior:
					solid.add(arrays, xf, [0, S_FIXED, K_GLASS, 0])
				elif MAT.has(mname):
					solid.add(arrays, xf, MAT[mname])
				else:
					dropped[mname] = dropped.get(mname, 0) + 1
		scene.free()
		if solid.count() > 0:
			lib.meshes[n] = solid.mesh()
			lib.bounds[n] = (lib.meshes[n] as ArrayMesh).get_aabb()
			total_tris += solid.indices.size() / 3
		if decal.count() > 0:
			lib.decals[n] = decal.mesh()
			if not lib.bounds.has(n):
				lib.bounds[n] = (lib.decals[n] as ArrayMesh).get_aabb()
	var far_tris := 0
	for n: String in lib.meshes:
		var m: ArrayMesh = lib.meshes[n]
		var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if n.begins_with("Building_"):
			continue
		if n in FAR_DROP:
			lib.far[n] = null
		elif FAR_SUBSTITUTE.has(n):
			lib.far[n] = lib.meshes[FAR_SUBSTITUTE[n]]
		elif tris > FAR_KEEP_TRIS:
			lib.far[n] = _far_proxy(m.surface_get_arrays(0))
		if lib.far.has(n) and lib.far[n] != null:
			far_tris += ((lib.far[n] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("megakit: %d far proxies (%d triangles)" % [lib.far.size(), far_tris])
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("megakit: %d modules (%d with markings), %d triangles, dropped surfaces %s -> %s (%s)" % [
		lib.meshes.size(), lib.decals.size(), total_tris, dropped, OUT, error_string(err)])
	quit(0 if err == OK else 1)


## A far-LOD stand-in for a module (kit local space: outside face at z = 0,
## facing +Z). With fake-interior windows: one backing quad over the module
## face in its dominant material, and the window quads pulled just in front
## of it (they keep their UVs, so the same room shows). Otherwise: the
## module's bounding box (no back face) in its dominant material.
func _far_proxy(a: Array) -> ArrayMesh:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var cu: PackedByteArray = a[Mesh.ARRAY_CUSTOM0]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var aabb := AABB(v[0], Vector3.ZERO)
	var area := {}  # "layer,slot" -> area
	var best_uv := {}  # "layer,slot" -> [area of biggest face, its centroid UV]
	var has_window := false
	var min_clean := 1.0
	var out := _Acc.new()
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		aabb = aabb.expand(v[i0]).expand(v[i1]).expand(v[i2])
		var kind := cu[i0 * 4 + 2]
		var nrm := (v[i1] - v[i0]).cross(v[i2] - v[i0])
		var ar := nrm.length() * 0.5
		if kind == K_WINDOW:
			has_window = true
			continue
		var key := "%d,%d" % [cu[i0 * 4], cu[i0 * 4 + 1]]
		var front := ar > 1e-6 and (nrm / (ar * 2.0)).dot(Vector3.BACK) < -0.7
		var w := ar * (3.0 if front else 1.0)
		area[key] = area.get(key, 0.0) + w
		if not best_uv.has(key) or ar > best_uv[key][0]:
			best_uv[key] = [ar, (uv[i0] + uv[i1] + uv[i2]) / 3.0]
		if v[i0].y < aabb.position.y + 0.05:
			min_clean = minf(min_clean, col[i0].g)
	var key_best := ""
	for k: String in area:
		if key_best == "" or area[k] > area[key_best]:
			key_best = k
	if key_best == "":
		key_best = "%d,%d" % [L_BRICK, S_BRICK]
		best_uv[key_best] = [0.0, Vector2(0.5, 0.5)]
	var ls := key_best.split(",")
	var layer := int(ls[0])
	var slot := int(ls[1])
	var flat_uv: Vector2 = best_uv[key_best][1]
	var lo := aabb.position
	var hi := aabb.end
	var quad := func(p: Array, clean_lo: float) -> void:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var pv := PackedVector3Array(p)
		var n := (pv[1] - pv[0]).cross(pv[2] - pv[0]).normalized()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for q in pv:
			uvs.append(Vector2((q.x + q.z) * 0.5, -q.y * 0.5) if layer == L_BRICK else flat_uv)
			var g := clean_lo if q.y < lo.y + 0.01 else 1.0
			cols.append(Color(1.0, g, g, 1.0))
		arr[Mesh.ARRAY_VERTEX] = pv
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n, n])
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
		out.add(arr, Transform3D.IDENTITY, [layer, slot, K_SOLID, 0])
	if has_window:
		# Backing quad over the face, then the windows just in front.
		quad.call([Vector3(lo.x, lo.y, 0.0), Vector3(hi.x, lo.y, 0.0), Vector3(hi.x, hi.y, 0.0), Vector3(lo.x, hi.y, 0.0)], min_clean)
		var wv := PackedInt32Array()
		var wi := PackedInt32Array()
		var remap := {}
		for t in range(0, idx.size(), 3):
			if cu[idx[t] * 4 + 2] != K_WINDOW:
				continue
			for j in 3:
				var src := idx[t + j]
				if not remap.has(src):
					remap[src] = wv.size()
					wv.append(src)
				wi.append(remap[src])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var pv := PackedVector3Array()
		var nv := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var cols := PackedColorArray()
		var tag := [0, S_FIXED, K_WINDOW, 0]
		for si in wv:
			var p := v[si]
			pv.append(Vector3(p.x, p.y, 0.004))
			nv.append(Vector3.BACK)
			uvs.append(uv[si])
			uv2s.append(Vector2(0.5, 0.5))
			cols.append(Color.WHITE)
			tag = [cu[si * 4], cu[si * 4 + 1], K_WINDOW, cu[si * 4 + 3]]
		arr[Mesh.ARRAY_VERTEX] = pv
		arr[Mesh.ARRAY_NORMAL] = nv
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = wi
		out.add(arr, Transform3D.IDENTITY, tag)
	else:
		# Box: front, top, bottom and both ends (the back is against the wall).
		quad.call([Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], min_clean)
		quad.call([Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)], 1.0)
		quad.call([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)], 1.0)
		quad.call([Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)], min_clean)
		quad.call([Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z)], min_clean)
	return out.mesh()


func _global_xform(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Accumulates surfaces into one megakit-format surface.
class _Acc:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedByteArray()
	var indices := PackedInt32Array()

	func count() -> int:
		return verts.size()

	func add(arrays: Array, xf: Transform3D, tag: Array) -> void:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var nv := v.size()
		var base := verts.size()
		verts.append_array(xf * v)
		var nb := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		var nn := nb * n
		for i in nn.size():
			nn[i] = nn[i].normalized()
		normals.append_array(nn)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.size() != nv:
			uv.resize(nv)
		uvs.append_array(uv)
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		if uv2.size() != nv:
			# No bevel UVs: point at the flat middle of the corner-normal map.
			uv2 = PackedVector2Array()
			uv2.resize(nv)
			uv2.fill(Vector2(0.5, 0.5))
		uv2s.append_array(uv2)
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if col.size() != nv:
			col = PackedColorArray()
			col.resize(nv)
			col.fill(Color.WHITE)
		colors.append_array(col)
		var c := PackedByteArray([tag[0], tag[1], tag[2], tag[3]])
		for i in nv:
			custom.append_array(c)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(nv)
			for i in nv:
				idx[i] = i
		for i in idx.size():
			indices.append(idx[i] + base)

	func mesh() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_TEX_UV2] = uv2s
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_CUSTOM0] = custom
		a[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {},
			Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return m
