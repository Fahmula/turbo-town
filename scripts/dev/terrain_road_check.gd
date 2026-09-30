extends SceneTree
## Finds places where terrain pokes above road decks.
##   godot --headless --path . -s res://scripts/dev/terrain_road_check.gd

func _init() -> void:
	var terrain := TerrainBuilder.new()
	terrain.generate_base()
	var roads := RoadBuilder.new(terrain)
	roads.define_all()
	roads.raster_into_terrain()
	terrain.apply_raster()
	for r in roads.roads:
		var rights := MeshBuilder._path_rights(r.points, r.closed)
		var worst := 0.0
		var worst_p := Vector3.ZERO
		var bad := 0
		for i in r.points.size():
			for f: float in [-0.9, -0.5, 0.0, 0.5, 0.9]:
				var p := r.points[i] + rights[i] * r.width * 0.5 * f
				var above := terrain.height_at(p.x, p.z) - p.y
				if above > 0.05:
					bad += 1
				if above > worst:
					worst = above
					worst_p = p
		if bad > 0:
			print("%-18s terrain above deck at %d samples, worst %.2f m at %s (elevated=%d)" % [r.name, bad, worst, worst_p.round(), r.elevated[r.points.find(r.points[0])]])
	quit()
