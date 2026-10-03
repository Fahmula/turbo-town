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


## Boulders scattered round the mountain (sphere colliders).
func _add_rocks(root: Node3D) -> void:
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
