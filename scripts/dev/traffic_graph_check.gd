extends SceneTree
## godot --headless --path . -s res://scripts/dev/traffic_graph_check.gd

func _init() -> void:
	var terrain := TerrainBuilder.new()
	terrain.generate_base()
	var roads := RoadBuilder.new(terrain)
	roads.define_all()
	var net := TrafficNetwork.new()
	net.build(roads)
	print(net.debug_report(roads))
	# Junction connectors near each special junction.
	for p in [Vector3(250, 0, 0), Vector3(-250, 0, 0), Vector3(0, 0, -300), Vector3(-147, 0, -440)]:
		var n := 0
		for lane in net.lanes:
			if lane.connector and lane.points[0].distance_to(p) < 40.0:
				n += 1
		print("connectors starting near %s: %d" % [p, n])
	quit()
