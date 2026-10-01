class_name NatureBuilder
extends RefCounted
## Trees (MultiMesh + trunk colliders), rocks, clouds and the sea.

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

	var round_spots: Array[Transform3D] = []
	var pine_spots: Array[Transform3D] = []
	for p in city_tree_spots:
		round_spots.append(_tree_xform(p, 0.85, 1.15))
	_scatter_trees(round_spots, pine_spots)

	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
	root.add_child(body)
	_add_tree_multimesh(root, body, _make_round_tree(), round_spots, 0.35)
	_add_tree_multimesh(root, body, _make_pine_tree(), pine_spots, 0.35)
	_add_rocks(root)
	_add_clouds(root)
	_add_sea(root)


func _tree_xform(p: Vector3, smin: float, smax: float) -> Transform3D:
	var s := _rng.randf_range(smin, smax)
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
	return Transform3D(b, p)


func _scatter_trees(round_spots: Array[Transform3D], pine_spots: Array[Transform3D]) -> void:
	var half := MapLayout.TERRAIN_HALF_SIZE - 20.0
	var attempts := 9000
	for k in attempts:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		# Keep the city, the stunt park and the dirt fields clear.
		if absf(x) < 165.0 and absf(z) < 165.0:
			continue
		if x > MapLayout.PARK_MIN.x - 15 and x < MapLayout.PARK_MAX.x + 15 and z > MapLayout.PARK_MIN.y - 15 and z < MapLayout.PARK_MAX.y + 15:
			continue
		if Vector2(x, z).distance_to(MapLayout.FIELDS_CENTER) < 150.0:
			continue
		var h := _terrain.height_at(x, z)
		if h < 1.5:
			continue
		if _terrain.road_weight_at(x, z) > 0.01 or _keep_clear(x, z):
			continue
		if _terrain.slope_at(x, z) > 0.55:
			continue
		var dens := _density.get_noise_2d(x, z) * 0.5 + 0.5
		var mountain := smoothstep(-320.0, -400.0, z)
		var chance := 0.03 + dens * dens * 0.25 + mountain * 0.12
		if _rng.randf() > chance:
			continue
		var p := Vector3(x, h - 0.1, z)
		if mountain > 0.5 or h > 14.0:
			pine_spots.append(_tree_xform(p, 0.8, 1.4))
		else:
			round_spots.append(_tree_xform(p, 0.8, 1.3))


func _add_tree_multimesh(root: Node3D, body: StaticBody3D, mesh: Mesh, xforms: Array[Transform3D], trunk_radius: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		var s := xforms[i].basis.get_scale().x
		shape.radius = trunk_radius * s
		shape.height = 4.0 * s
		cs.shape = shape
		cs.position = xforms[i].origin + Vector3.UP * 2.0 * s
		body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)


func _make_round_tree() -> Mesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	mb.add_prism(Vector3.ZERO, 0.32, 0.22, 3.2, 6, Color(0.5, 0.34, 0.22))
	mb.add_blob(Vector3(0, 4.4, 0), Vector3(2.4, 2.1, 2.4), Color(0.30, 0.62, 0.25), 3, 7, 0.12, rng)
	mb.add_blob(Vector3(0.9, 5.6, 0.3), Vector3(1.5, 1.4, 1.5), Color(0.36, 0.70, 0.28), 3, 6, 0.1, rng)
	mb.add_blob(Vector3(-0.8, 5.3, -0.5), Vector3(1.4, 1.3, 1.4), Color(0.33, 0.66, 0.26), 3, 6, 0.1, rng)
	return mb.build_mesh(load("res://assets/materials/foliage.tres"))


func _make_pine_tree() -> Mesh:
	var mb := MeshBuilder.new()
	mb.add_prism(Vector3.ZERO, 0.3, 0.2, 2.0, 6, Color(0.45, 0.3, 0.2))
	mb.add_prism(Vector3(0, 1.5, 0), 2.4, 0.0, 3.2, 7, Color(0.18, 0.48, 0.30))
	mb.add_prism(Vector3(0, 3.3, 0), 1.9, 0.0, 2.8, 7, Color(0.22, 0.54, 0.33))
	mb.add_prism(Vector3(0, 4.9, 0), 1.3, 0.0, 2.4, 7, Color(0.26, 0.60, 0.36))
	# Bottom faces for the cones so they don't look hollow from below.
	return mb.build_mesh(load("res://assets/materials/foliage.tres"))


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
		var col := Color(0.58, 0.56, 0.54).lerp(Color(0.68, 0.66, 0.63), rng.randf())
		mb.add_blob(Vector3(x, h + r * 0.2, z), Vector3(r * 1.2, r * 0.8, r), col, 3, 5, 0.25, rng)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.8
		cs.shape = sh
		cs.position = Vector3(x, h + r * 0.1, z)
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build_mesh(load("res://assets/materials/props.tres"))
	body.add_child(mi)
	root.add_child(body)


func _add_clouds(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for k in 26:
		var c := Vector3(rng.randf_range(-900, 900), rng.randf_range(110, 170), rng.randf_range(-900, 900))
		var puffs := rng.randi_range(3, 6)
		for p in puffs:
			var off := Vector3(rng.randf_range(-22, 22), rng.randf_range(-3, 5), rng.randf_range(-10, 10))
			var r := rng.randf_range(10, 20)
			mb.add_blob(c + off, Vector3(r * 1.3, r * 0.6, r), Color(1, 1, 1), 3, 7, 0.15, rng)
	var mi := MeshInstance3D.new()
	mi.name = "Clouds"
	mi.mesh = mb.build_mesh(load("res://assets/materials/cloud.tres"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _add_sea(root: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	plane.material = load("res://assets/materials/water.tres")
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.position.y = MapLayout.SEA_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Spots trees mustn't grow: the tunnel's hill (it would stick through) and
## around the lighthouse.
static func _keep_clear(x: float, z: float) -> bool:
	if absf(x) < MapLayout.TUNNEL_HILL_HALF_WIDTH + 3.0 and z > MapLayout.TUNNEL_Z0 - 3.0 and z < MapLayout.TUNNEL_Z1 + 3.0:
		return true
	return Vector2(x, z).distance_to(MapLayout.ISLET_CENTER) < 16.0
