@tool
class_name NatureBuilder
extends RefCounted
## Trees (TreeKit MultiMeshes + trunk colliders), rocks and the sea
## (ART_BIBLE.md §18-§19). Clouds are in the sky shader (sky.gdshader).

var _terrain: TerrainBuilder
var _rng := RandomNumberGenerator.new()
var _density := FastNoiseLite.new()


func _init(terrain: TerrainBuilder) -> void:
	_terrain = terrain
	_rng.seed = 99
	_density.seed = 5
	_density.frequency = 0.008


func build(parent: Node3D, city_tree_spots: Array[Vector3]) -> void:
	var root := Node3D.new()
	root.name = "Nature"
	parent.add_child(root)

	# Trees, shrubs and hedges: TreeScatter places them, TreeLod draws them,
	# TreeColliders gives the trunks colliders.
	var trees := TreeScatter.new(_terrain)
	trees.build(root, city_tree_spots)
	print("Trees: ", trees.stats)
	_add_rocks(root)
	_add_sea(root)


## Boulders (Poly Haven scans split and decimated by tools/blender/make_nature_rocks.py,
## textures from tools/textures/fetch_terrain.py): round the mountain, on the
## shores and scattered over the open hills. Merged into one mesh per 160 m
## chunk (two surfaces, one per rock set), sphere colliders. Falls back to the
## procedural boulders when the models are missing.
func _add_rocks(root: Node3D) -> void:
	var sets: Array[Dictionary] = []
	for key in ["a", "b"]:
		var scene := load("res://assets/models/nature/rocks_%s.glb" % key) as PackedScene
		if scene == null:
			_add_rocks_procedural(root)
			return
		var inst := scene.instantiate()
		var meshes: Array[Mesh] = []
		for n in inst.find_children("rock_*", "MeshInstance3D", true, false):
			meshes.append((n as MeshInstance3D).mesh)
		inst.free()
		var mat := ORMMaterial3D.new()
		mat.albedo_texture = load("res://assets/textures/terrain/rocks_%s_albedo.jpg" % key)
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/terrain/rocks_%s_normal.png" % key)
		mat.orm_texture = load("res://assets/textures/terrain/rocks_%s_orm.png" % key)
		sets.append({"meshes": meshes, "material": mat})

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var spots: Array[Dictionary] = []   # {set, mesh, xform, radius}
	# Round the mountain: a ring of boulders and a few clusters on its slopes.
	for k in 70:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(50.0, 175.0)
		var x := MapLayout.MOUNTAIN_CENTER.x + cos(ang) * dist
		var z := MapLayout.MOUNTAIN_CENTER.y + sin(ang) * dist
		_try_rock(spots, sets, rng, x, z, rng.randf_range(0.7, 1.9), 0.6)
		if rng.randf() < 0.25:
			for j in rng.randi_range(1, 2):
				_try_rock(spots, sets, rng, x + rng.randf_range(-4.0, 4.0), z + rng.randf_range(-4.0, 4.0), rng.randf_range(0.35, 0.9), 0.6)
	# Shores: rocks at the waterline, in small groups (walks every other terrain vertex).
	var step := _terrain.cell
	var hs := _terrain.heights
	var gn := _terrain.n
	var lo := MapLayout.SEA_LEVEL - 0.2
	for j in range(0, gn, 2):
		for i in range(0, gn, 2):
			var h := hs[j * gn + i]
			if h < lo or h > 0.5 or rng.randf() > 0.07:
				continue
			var x := -_terrain.half + i * step
			var z := -_terrain.half + j * step
			if _terrain.shore_factor(x, z) < 0.05:
				continue
			for k in rng.randi_range(1, 3):
				_try_rock(spots, sets, rng, x + rng.randf_range(-6.0, 6.0), z + rng.randf_range(-6.0, 6.0), rng.randf_range(0.35, 1.2), 0.8)
	var half := MapLayout.TERRAIN_HALF_SIZE - 10.0
	# Open hills outside the city: the odd boulder.
	for k in 400:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if absf(x) < 175.0 and absf(z) < 175.0:
			continue
		if Vector2(x, z).distance_to(MapLayout.FIELDS_CENTER) < 140.0:
			continue
		if _terrain.height_at(x, z) < 2.0 or rng.randf() > 0.08:
			continue
		_try_rock(spots, sets, rng, x, z, rng.randf_range(0.5, 1.5), 0.45)

	var body := StaticBody3D.new()
	body.name = "Rocks"
	# One merged mesh per chunk and rock set.
	var chunks := {}
	for sp in spots:
		var o: Vector3 = (sp["xform"] as Transform3D).origin
		var key := Vector3i(floori(o.x / 160.0), floori(o.z / 160.0), sp["set"])
		if not chunks.has(key):
			chunks[key] = SurfaceTool.new()
		(chunks[key] as SurfaceTool).append_from(sp["mesh"], 0, sp["xform"])
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = sp["radius"]
		cs.shape = sh
		cs.position = o + Vector3.UP * sh.radius * 0.7
		body.add_child(cs)
	for key: Vector3i in chunks:
		var st: SurfaceTool = chunks[key]
		var mesh := st.commit()
		mesh.surface_set_material(0, sets[key.z]["material"])
		var mi := MeshInstance3D.new()
		mi.name = "Rocks_%d_%d_%d" % [key.x, key.y, key.z]
		mi.mesh = mesh
		mi.visibility_range_end = 450.0
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		body.add_child(mi)
	root.add_child(body)


## Puts one boulder at (x, z) if the ground allows it (off roads, steep
## slopes and keep-clear spots); `max_slope` is the steepest ground it sits on.
func _try_rock(spots: Array[Dictionary], sets: Array[Dictionary], rng: RandomNumberGenerator, x: float, z: float, scale: float, max_slope: float) -> void:
	if _terrain.road_weight_at(x, z) > 0.01 or _keep_clear(x, z):
		return
	if _terrain.slope_at(x, z) > max_slope:
		return
	var si := rng.randi() % sets.size()
	var meshes: Array = sets[si]["meshes"]
	var mesh: Mesh = meshes[rng.randi() % meshes.size()]
	var aabb := mesh.get_aabb()
	var ext := maxf(aabb.size.x, aabb.size.z) * scale
	# Sit on the lowest ground under the footprint, so the downhill side doesn't hang.
	var r := ext * 0.3
	var h := _terrain.height_at(x, z)
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		h = minf(h, _terrain.height_at(x + d.x, z + d.y))
	if h < MapLayout.SEA_LEVEL - 0.6:
		return
	var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12))
	var b := Basis(Vector3.UP, rng.randf() * TAU) * tilt
	b = b.scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.1), scale))
	spots.append({"set": si, "mesh": mesh, "xform": Transform3D(b, Vector3(x, h - 0.06 * scale, z)), "radius": ext * 0.36})


## The procedural boulders (sphere colliders): used when the rock models are missing.
func _add_rocks_procedural(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "Rocks"
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 70:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(60.0, 170.0)
		var x := MapLayout.MOUNTAIN_CENTER.x + cos(ang) * dist
		var z := MapLayout.MOUNTAIN_CENTER.y + sin(ang) * dist
		if _terrain.road_weight_at(x, z) > 0.01 or _keep_clear(x, z):
			continue
		var h := _terrain.height_at(x, z)
		var r := rng.randf_range(0.8, 2.6)
		var col := ArtPalette.ROCK_DARK.lerp(ArtPalette.ROCK_LIGHT, rng.randf())
		_smooth_rock(mb, Vector3(x, h + r * 0.2, z), Vector3(r * 1.2, r * 0.8, r), col, rng)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.8
		cs.shape = sh
		cs.position = Vector3(x, h + r * 0.1, z)
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(load("res://assets/materials/env/concrete.tres"))
	body.add_child(mi)
	root.add_child(body)


## A boulder: a lumpy ellipsoid with smooth normals, darker underneath
## (concrete.gdshader adds pores, blotches and weathering streaks).
func _smooth_rock(mb: MeshBuilder, c: Vector3, radii: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var rings := 6
	var segs := 9
	var pts: Array = []
	for ri in rings + 1:
		var phi := PI * ri / rings
		var row: Array[Vector3] = []
		for si in segs:
			var th := TAU * si / segs + (0.35 if ri % 2 == 1 else 0.0)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var lump := 1.0 if ri == 0 or ri == rings else rng.randf_range(0.82, 1.15)
			# Flatter underneath, so it sits in the ground.
			if d.y < 0.0:
				d.y *= 0.6
			row.append(c + d * radii * lump)
		pts.append(row)
	# Vertex normals: average of the four faces around each vertex.
	var nrm: Array = []
	for ri in rings + 1:
		var row_n: Array[Vector3] = []
		for si in segs:
			var p: Vector3 = pts[ri][si]
			var up: Vector3 = pts[maxi(ri - 1, 0)][si]
			var dn: Vector3 = pts[mini(ri + 1, rings)][si]
			var lf: Vector3 = pts[ri][(si - 1 + segs) % segs]
			var rt: Vector3 = pts[ri][(si + 1) % segs]
			var n := (rt - lf).cross(up - dn)
			if n.length_squared() < 1e-8 or ri == 0 or ri == rings:
				n = (p - c)
			if n.dot(p - c) < 0.0:
				n = -n
			row_n.append(n.normalized())
		nrm.append(row_n)
	var base := Color(col, 0.0)
	for ri in rings:
		for si in segs:
			var s1 := (si + 1) % segs
			var q: Array[Vector3] = [pts[ri][si], pts[ri][s1], pts[ri + 1][s1], pts[ri + 1][si]]
			var n: Array[Vector3] = [nrm[ri][si], nrm[ri][s1], nrm[ri + 1][s1], nrm[ri + 1][si]]
			var cs: Array[Color] = []
			for p in q:
				cs.append(base.darkened(clampf((c.y - p.y) / radii.y, 0.0, 1.0) * 0.35))
			mb.add_quad_ex(q[0], q[1], q[2], q[3], n[0], n[1], n[2], n[3], cs[0], cs[1], cs[2], cs[3])


func _add_sea(root: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mat := load("res://assets/materials/water.tres") as ShaderMaterial
	_bake_shore(mat)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.position.y = MapLayout.SEA_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## The water's depth mask for water.gdshader: one texel per terrain cell,
## depth below sea level / 8 m (0 on land).
func _bake_shore(mat: ShaderMaterial) -> void:
	var n := _terrain.n
	var data := PackedByteArray()
	data.resize(n * n)
	for k in n * n:
		data[k] = int(clampf((MapLayout.SEA_LEVEL - _terrain.heights[k]) / 8.0, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_L8, data)
	mat.set_shader_parameter("shore", ImageTexture.create_from_image(img))
	# Texel centres on the terrain's grid points.
	var c := _terrain.cell
	mat.set_shader_parameter("shore_rect", Vector4(-_terrain.half - c * 0.5, -_terrain.half - c * 0.5, n * c, n * c))


## Spots trees mustn't grow: the tunnel's hill (it would stick through) and
## around the lighthouse.
static func _keep_clear(x: float, z: float) -> bool:
	if absf(x) < MapLayout.TUNNEL_HILL_HALF_WIDTH + 3.0 and z > MapLayout.TUNNEL_Z0 - 3.0 and z < MapLayout.TUNNEL_Z1 + 3.0:
		return true
	return Vector2(x, z).distance_to(MapLayout.ISLET_CENTER) < 16.0
