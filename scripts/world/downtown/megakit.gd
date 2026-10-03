@tool
class_name MegaKit
extends RefCounted
## Runtime side of the Downtown City MegaKit experiment: the converted modules
## (MegaKitLibrary), the one shared material (megakit.gdshader), building
## palettes, and Batch, which merges many module instances into ONE mesh
## surface (one draw call per building).
##
## Kit conventions (Quaternius): metres, a 2 m bay and 3 m floors; a wall
## module's outside face is at z = 0 facing +Z, its local x runs along the
## wall (-1..1 for a 2 m module), y = 0 at its foot. Corner pieces wrap
## round toward -Z.

const LIBRARY_PATH := "res://assets/models/megakit/megakit_modules.res"

## Tint slots (CUSTOM0.g), recoloured per building by a palette.
enum { SLOT_BRICK, SLOT_BRICK_ALT, SLOT_TRIM, SLOT_TRIM_DARK, SLOT_ACCENT, SLOT_METAL, SLOT_ROOF, SLOT_FIXED }
## Texture layers (CUSTOM0.r): slices of megakit_albedo / megakit_nrm.
enum { LAYER_BRICK, LAYER_TRIM, LAYER_METAL, LAYER_ORNAMENT, LAYER_SLATE, LAYER_ASPHALT, LAYER_CONCRETE, LAYER_SOIL }

## Building palettes: per slot [sRGB colour, recolour strength 0-1]; a slot
## left out keeps the kit's colour (strength 0). Row 0 is the kit's own look
## (streets and props use it). ART_BIBLE.md §0c lists them.
const PALETTES: Array[Dictionary] = [
	# 0 kit default: red brick, cream stone, charcoal / bottle-green paint.
	{SLOT_BRICK_ALT: [Color(0.66, 0.42, 0.33), 0.55], SLOT_TRIM_DARK: [Color(0.17, 0.17, 0.18), 0.9],
		SLOT_ACCENT: [Color(0.2, 0.33, 0.25), 0.85]},
	# 1 red brick, cream limestone, black iron.
	{SLOT_BRICK_ALT: [Color(0.7, 0.5, 0.4), 0.5], SLOT_TRIM_DARK: [Color(0.13, 0.13, 0.14), 0.95],
		SLOT_ACCENT: [Color(0.14, 0.15, 0.16), 0.9], SLOT_METAL: [Color(0.11, 0.11, 0.12), 0.8]},
	# 2 dark brown brick, white trim, bottle green.
	{SLOT_BRICK: [Color(0.36, 0.25, 0.2), 0.85], SLOT_BRICK_ALT: [Color(0.5, 0.36, 0.28), 0.8],
		SLOT_TRIM: [Color(0.86, 0.84, 0.78), 0.75], SLOT_TRIM_DARK: [Color(0.16, 0.26, 0.2), 0.9],
		SLOT_ACCENT: [Color(0.18, 0.31, 0.23), 0.9], SLOT_METAL: [Color(0.14, 0.2, 0.16), 0.85]},
	# 3 buff brick, brownstone trim, oxblood.
	{SLOT_BRICK: [Color(0.72, 0.6, 0.45), 0.85], SLOT_BRICK_ALT: [Color(0.8, 0.7, 0.55), 0.8],
		SLOT_TRIM: [Color(0.46, 0.31, 0.25), 0.8], SLOT_TRIM_DARK: [Color(0.36, 0.13, 0.11), 0.9],
		SLOT_ACCENT: [Color(0.4, 0.14, 0.12), 0.9], SLOT_METAL: [Color(0.2, 0.12, 0.1), 0.8]},
	# 4 deep red brick, warm grey stone, navy.
	{SLOT_BRICK: [Color(0.5, 0.22, 0.17), 0.7], SLOT_BRICK_ALT: [Color(0.62, 0.36, 0.28), 0.7],
		SLOT_TRIM: [Color(0.66, 0.64, 0.6), 0.75], SLOT_TRIM_DARK: [Color(0.15, 0.2, 0.3), 0.9],
		SLOT_ACCENT: [Color(0.16, 0.23, 0.36), 0.9], SLOT_METAL: [Color(0.13, 0.16, 0.22), 0.8]},
	# 5 painted cream brick, dark green.
	{SLOT_BRICK: [Color(0.82, 0.78, 0.68), 0.8], SLOT_BRICK_ALT: [Color(0.76, 0.72, 0.62), 0.8],
		SLOT_TRIM: [Color(0.9, 0.88, 0.82), 0.6], SLOT_TRIM_DARK: [Color(0.17, 0.25, 0.2), 0.9],
		SLOT_ACCENT: [Color(0.19, 0.3, 0.23), 0.9], SLOT_METAL: [Color(0.15, 0.2, 0.17), 0.85]},
	# 6 brownstone throughout (Back Bay rowhouse), black paint.
	{SLOT_BRICK: [Color(0.45, 0.3, 0.24), 0.9], SLOT_BRICK_ALT: [Color(0.5, 0.34, 0.27), 0.9],
		SLOT_TRIM: [Color(0.5, 0.35, 0.28), 0.85], SLOT_TRIM_DARK: [Color(0.12, 0.12, 0.13), 0.95],
		SLOT_ACCENT: [Color(0.13, 0.13, 0.14), 0.9], SLOT_METAL: [Color(0.1, 0.1, 0.11), 0.8]},
	# 7 orange-red brick, cream, ochre storefronts.
	{SLOT_BRICK: [Color(0.66, 0.36, 0.24), 0.6], SLOT_BRICK_ALT: [Color(0.76, 0.52, 0.38), 0.6],
		SLOT_TRIM_DARK: [Color(0.2, 0.17, 0.14), 0.9], SLOT_ACCENT: [Color(0.62, 0.45, 0.18), 0.85],
		SLOT_METAL: [Color(0.17, 0.15, 0.13), 0.8]},
	# 8 grey-brown brick, white stone, charcoal.
	{SLOT_BRICK: [Color(0.46, 0.4, 0.36), 0.85], SLOT_BRICK_ALT: [Color(0.58, 0.52, 0.47), 0.8],
		SLOT_TRIM: [Color(0.88, 0.87, 0.83), 0.7], SLOT_TRIM_DARK: [Color(0.18, 0.18, 0.19), 0.9],
		SLOT_ACCENT: [Color(0.22, 0.22, 0.24), 0.9], SLOT_METAL: [Color(0.13, 0.13, 0.14), 0.8]},
]

static var _library: MegaKitLibrary
static var _material: ShaderMaterial
static var _decal_material: ShaderMaterial
## Module name -> its surface arrays (decoding a mesh is slow; do it once).
static var _arrays := {}
static var _decal_arrays := {}
static var _far_arrays := {}


static func library() -> MegaKitLibrary:
	if _library == null:
		_library = load(LIBRARY_PATH) as MegaKitLibrary
	return _library


static func has_module(module: String) -> bool:
	return library().meshes.has(module)


static func arrays(module: String) -> Array:
	if not _arrays.has(module):
		var m: ArrayMesh = library().meshes.get(module)
		_arrays[module] = m.surface_get_arrays(0) if m else []
	return _arrays[module]


## Far-LOD arrays of a module: its proxy, [] to drop it, or its own arrays
## when it is cheap (MegaKitLibrary.far).
static func far_arrays(module: String) -> Array:
	if not _far_arrays.has(module):
		var lib := library()
		if lib.far.has(module):
			var m: ArrayMesh = lib.far[module]
			_far_arrays[module] = m.surface_get_arrays(0) if m else []
		else:
			_far_arrays[module] = arrays(module)
	return _far_arrays[module]


static func decal_arrays(module: String) -> Array:
	if not _decal_arrays.has(module):
		var m: ArrayMesh = library().decals.get(module)
		_decal_arrays[module] = m.surface_get_arrays(0) if m else []
	return _decal_arrays[module]


static func bounds(module: String) -> AABB:
	return library().bounds.get(module, AABB())


## The shared material of every kit mesh.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/megakit.gdshader")
		_material.set_shader_parameter("albedo_tex", load("res://assets/textures/megakit/megakit_albedo.jpg"))
		_material.set_shader_parameter("nrm_tex", load("res://assets/textures/megakit/megakit_nrm.png"))
		_material.set_shader_parameter("detail_tex", load("res://assets/textures/megakit/megakit_detail.png"))
		_material.set_shader_parameter("room_tex", load("res://assets/textures/megakit/megakit_rooms.jpg"))
		_material.set_shader_parameter("cover_tex", load("res://assets/textures/megakit/megakit_covers.png"))
		_material.set_shader_parameter("palette_tex", _palette_texture())
	return _material


static func decal_material() -> ShaderMaterial:
	if _decal_material == null:
		_decal_material = ShaderMaterial.new()
		_decal_material.shader = load("res://assets/shaders/megakit_decal.gdshader")
		_decal_material.set_shader_parameter("decal_tex", load("res://assets/textures/megakit/megakit_decals.png"))
		_decal_material.render_priority = 1
	return _decal_material


static func _palette_texture() -> ImageTexture:
	var img := Image.create(8, PALETTES.size(), false, Image.FORMAT_RGBA8)
	for row in PALETTES.size():
		var p: Dictionary = PALETTES[row]
		for slot in 8:
			var e: Array = p.get(slot, [Color.WHITE, 0.0])
			var c: Color = e[0]
			img.set_pixel(slot, row, Color(c.r, c.g, c.b, e[1]))
	return ImageTexture.create_from_image(img)


## A MeshInstance3D for a built mesh, coloured with palette `palette`.
static func instance(mesh: ArrayMesh, palette: int, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	mi.mesh = mesh
	mi.set_instance_shader_parameter("palette", palette)
	return mi


## Collects module instances and plain quads, then builds one surface.
class Batch:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedByteArray()
	var indices := PackedInt32Array()
	## Markings (decal material), kept apart.
	var decal: Batch
	## The far-LOD version of everything added (MegaKit.far_arrays), when
	## made with `with_far`.
	var far: Batch
	var rng := RandomNumberGenerator.new()
	var tris := 0

	func _init(seed_value := 1, with_far := false) -> void:
		rng.seed = seed_value
		if with_far:
			far = Batch.new(seed_value)

	func is_empty() -> bool:
		return verts.is_empty()

	## One kit module. Window rooms get a random variant (see megakit.gdshader).
	func add(module: String, xf: Transform3D, with_decal := true) -> void:
		var a := MegaKit.arrays(module)
		var k := rng.randi_range(0, 47)
		if not a.is_empty():
			_append(a, xf, k)
			if far != null:
				var fa := MegaKit.far_arrays(module)
				if not fa.is_empty():
					far._append(fa, xf, k)
		var d := MegaKit.decal_arrays(module) if with_decal else []
		if not d.is_empty():
			if decal == null:
				decal = Batch.new()
			decal._append(d, xf, 0)
		if a.is_empty() and d.is_empty():
			push_warning("MegaKit: no module " + module)

	func _append(a: Array, xf: Transform3D, k: int) -> void:
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(xf * v)
		var nb := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		normals.append_array(nb * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		if k != 0:
			uv = Transform2D(0.0, Vector2(4.0 * k, 0.0)) * uv
		uvs.append_array(uv)
		uv2s.append_array(a[Mesh.ARRAY_TEX_UV2])
		colors.append_array(a[Mesh.ARRAY_COLOR])
		custom.append_array(a[Mesh.ARRAY_CUSTOM0])
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var n := idx.size()
		var at := indices.size()
		indices.resize(at + n)
		for i in n:
			indices[at + i] = idx[i] + base
		tris += n / 3

	## A flat quad (corners counter-clockwise seen from the front) in one
	## texture layer: plain walls, roofs, paving. `uv` per corner; COLOR.g
	## per corner = clean (1) or grimy (0).
	func add_quad(p: Array[Vector3], uv: Array[Vector2], layer: int, slot: int, clean: Array[float] = [1.0, 1.0, 1.0, 1.0]) -> void:
		var base := verts.size()
		var n := (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		for i in 4:
			verts.append(p[i])
			normals.append(n)
			uvs.append(uv[i])
			uv2s.append(Vector2(0.5, 0.5))
			colors.append(Color(1.0, clean[i], clean[i], 1.0))
			custom.append_array(PackedByteArray([layer, slot, 0, 0]))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		tris += 2
		if far != null:
			far.add_quad(p, uv, layer, slot, clean)

	## The batch as a mesh; with `lods`, automatic LODs (index buffers over
	## the same vertices, so the kit's vertex data survives) like
	## MeshBuilder.with_lods.
	func build(lods := false) -> ArrayMesh:
		if verts.is_empty():
			return null
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_TEX_UV2] = uv2s
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_CUSTOM0] = custom
		a[Mesh.ARRAY_INDEX] = indices
		var flags := Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if lods:
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, MegaKit.material(), "", flags)
			im.generate_lods(25.0, 60.0, [])
			return im.get_mesh()
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
		m.surface_set_material(0, MegaKit.material())
		return m

	func build_decals() -> ArrayMesh:
		if decal == null or decal.is_empty():
			return null
		var m := decal.build()
		m.surface_set_material(0, MegaKit.decal_material())
		return m
