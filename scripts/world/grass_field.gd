class_name GrassField
extends Node3D
## 3D grass tufts around the camera (realism branch). GPU-driven: two rings of
## MultiMesh lattices (near: dense and small, far: sparse and bigger) follow
## the camera in whole lattice steps, and assets/shaders/grass.gdshader decides
## per slot whether a tuft grows there, from the terrain height and grass
## density textures TerrainBuilder bakes. No CPU work per frame beyond moving
## two nodes, no streaming hitches, no per-chunk draw calls beyond 4 sectors
## per ring (so frustum culling drops the ones behind the camera).
##
## High and Medium draw it; Low (Settings graphics == GraphicsQuality.LOW, the
## shader also clips everything when the global `quality` is 0) does not. It is also
## hidden when the camera is high above the ground (nothing within fade range).
## No shadows cast, no GI (alpha-tested cards would be voxelised by SDFGI).
## Cost: ring 0 = 3,600 slots x 12 tris, ring 1 = 4,700 x 4, ring 2 = 5,100 x 4
## (about 80k tris submitted, in 4 sectors per ring); only slots where a tuft
## grows draw anything.

## One entry per ring: lattice spacing (m), half size (m), fade-in and fade-out
## distances (start, end), tuft size (width, height m), cards and rows of the
## tuft mesh. Near: a dense carpet of small tufts. Far: sparse, bigger ones.
const RINGS := [
	{"spacing": 0.3, "half": 9.0, "fade_in": Vector2(0.0, 0.0), "fade_out": Vector2(4.5, 9.0), "size": Vector2(0.6, 0.42), "cards": 3, "rows": 2},
	{"spacing": 0.7, "half": 24.0, "fade_in": Vector2(4.0, 8.0), "fade_out": Vector2(16.0, 23.5), "size": Vector2(1.0, 0.62), "cards": 2, "rows": 1},
	{"spacing": 1.4, "half": 50.0, "fade_in": Vector2(14.0, 20.0), "fade_out": Vector2(36.0, 49.0), "size": Vector2(1.9, 0.85), "cards": 2, "rows": 1},
]
## The camera must be lower than this above the ground for tufts to show.
const MAX_CAMERA_HEIGHT := 55.0

var _terrain: TerrainBuilder
var _rings: Array[Node3D] = []
var _quality_poll := 0.0
var _enabled := true


func setup(terrain: TerrainBuilder) -> void:
	name = "Grass"
	if OS.get_cmdline_user_args().has("--no-grass"):  # for A/B timing
		visible = false
		return
	_terrain = terrain
	var tex := terrain.grass_textures()
	var shader := load("res://assets/shaders/grass.gdshader") as Shader
	var cards := load("res://assets/textures/terrain/grass_cards.png") as Texture2D
	var noise := load("res://assets/textures/terrain/grass_noise.png") as Texture2D
	var parks := TerrainBuilder.parks()
	var park_data := PackedVector4Array()
	for r in parks:
		park_data.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	while park_data.size() < 4:
		park_data.append(Vector4())
	for ring: Dictionary in RINGS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("cards", cards)
		mat.set_shader_parameter("noise", noise)
		mat.set_shader_parameter("heights", tex["heights"])
		mat.set_shader_parameter("mask", tex["mask"])
		mat.set_shader_parameter("t_half", terrain.half)
		mat.set_shader_parameter("t_cell", terrain.cell)
		mat.set_shader_parameter("t_n", terrain.n)
		mat.set_shader_parameter("spacing", ring["spacing"])
		mat.set_shader_parameter("fade_in", ring["fade_in"])
		mat.set_shader_parameter("fade_out", ring["fade_out"])
		mat.set_shader_parameter("tuft_size", ring["size"])
		mat.set_shader_parameter("parks", park_data)
		mat.set_shader_parameter("park_count", mini(parks.size(), 4))
		mat.set_shader_parameter("park_y", MapLayout.CURB_HEIGHT + 0.004)
		var mesh := _tuft_mesh(ring["cards"], ring["rows"])
		mesh.surface_set_material(0, mat)
		var holder := Node3D.new()
		holder.name = "Ring%d" % _rings.size()
		add_child(holder)
		_rings.append(holder)
		_add_sectors(holder, mesh, ring["spacing"], ring["half"])


## Unit tuft: `cards` crossed vertical quads (x in [-0.5, 0.5] along each
## card's own direction, y in [0, 1]) with `rows` vertical segments so the
## wind can bend them. COLOR.r = height fraction, UV = the card's texture.
func _tuft_mesh(cards: int, rows: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for c in cards:
		var a := PI * c / cards
		var dir := Vector3(cos(a), 0.0, sin(a))
		var base := verts.size()
		for r in rows + 1:
			var y := float(r) / rows
			for s in 2:
				var x := s - 0.5
				verts.append(dir * x + Vector3.UP * y)
				uvs.append(Vector2(float(s), 1.0 - y))
				cols.append(Color(y, 0.0, 0.0, 1.0))
		for r in rows:
			var i0 := base + r * 2
			idx.append_array([i0, i0 + 1, i0 + 3, i0, i0 + 3, i0 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Four quadrant MultiMeshes of the ring's lattice (offsets are whole multiples
## of the spacing, so the shader can read each slot's world cell).
func _add_sectors(holder: Node3D, mesh: ArrayMesh, spacing: float, half: float) -> void:
	var n := int(round(2.0 * half / spacing))
	var q := n / 2
	for qz in 2:
		for qx in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = q * q
			var buf := PackedFloat32Array()
			buf.resize(q * q * 12)
			var w := 0
			for j in q:
				var z := (qz * q + j - q) * spacing
				for i in q:
					var x := (qx * q + i - q) * spacing
					buf[w] = 1.0
					buf[w + 3] = x
					buf[w + 5] = 1.0
					buf[w + 7] = 0.0
					buf[w + 10] = 1.0
					buf[w + 11] = z
					w += 12
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Sector_%d_%d" % [qx, qz]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			# The shader moves tufts onto the terrain: cover its whole height range.
			mmi.custom_aabb = AABB(Vector3((qx - 1) * half, -12.0, (qz - 1) * half), Vector3(half, 80.0, half))
			holder.add_child(mmi)


func _process(delta: float) -> void:
	if _terrain == null or Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_quality_poll -= delta
	if _quality_poll <= 0.0:
		_quality_poll = 0.5
		_enabled = int(Settings.get_value("graphics")) > GraphicsQuality.LOW
	var p := cam.global_position
	var high := p.y - _terrain.height_at(p.x, p.z) > MAX_CAMERA_HEIGHT
	visible = _enabled and not high
	if not visible:
		return
	for i in RINGS.size():
		var s: float = RINGS[i]["spacing"]
		_rings[i].global_position = Vector3(roundf(p.x / s) * s, 0.0, roundf(p.z / s) * s)
