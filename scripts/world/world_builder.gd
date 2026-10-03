@tool
class_name WorldBuilder
extends Node3D
## Builds the whole map at startup from MapLayout: terrain, roads, city,
## nature, stunt park and props. Also provides the named spawn points.
##
## Generation takes ~1-2 s. Everything is deterministic (fixed seeds), so the
## map is identical every run.
##
## It runs in the editor too, so the island shows in the 3D viewport when
## main.tscn or world.tscn is open. The generated nodes have no owner, so they
## are never saved into the scene. After changing map_layout.gd or a builder,
## press "Rebuild map preview" in this node's inspector.

const PROP_SCENES := {
	"cone": preload("res://scenes/props/traffic_cone.tscn"),
	"barrel": preload("res://scenes/props/barrel.tscn"),
	"crate": preload("res://scenes/props/crate.tscn"),
	"bowling_pin": preload("res://scenes/props/bowling_pin.tscn"),
	"lamp": preload("res://scenes/props/street_lamp.tscn"),
	"traffic_light": preload("res://scenes/props/traffic_signal.tscn"),
	"parked_car": preload("res://scenes/props/parked_car.tscn"),
	"parked_sedan": preload("res://scenes/props/parked_sedan.tscn"),
	"parked_van": preload("res://scenes/props/parked_van.tscn"),
	"ramp": preload("res://scenes/props/ramp.tscn"),
	"hydrant": preload("res://scenes/props/hydrant.tscn"),
	"bin": preload("res://scenes/props/street_bin.tscn"),
	"bench": preload("res://scenes/props/bench.tscn"),
	"cabinet": preload("res://scenes/props/signal_cabinet.tscn"),
}


## Build the map in the editor viewport as well (turn off if the editor gets slow).
@export var preview_in_editor := true
@export_tool_button("Rebuild map preview", "Reload") var rebuild_preview := _rebuild_preview

## Array of {"name": String, "xform": Transform3D}
var spawn_points: Array[Dictionary] = []
var terrain: TerrainBuilder
var roads: RoadBuilder


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	_build()


## Editor: throws away the generated map and builds it again.
func _rebuild_preview() -> void:
	for child in get_children():
		if child.owner == null:  # generated, not part of the saved scene
			remove_child(child)
			child.queue_free()
	spawn_points.clear()
	_build()


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	terrain = TerrainBuilder.new()
	terrain.generate_base()
	roads = RoadBuilder.new(terrain)
	roads.define_all()
	roads.raster_into_terrain()
	terrain.apply_raster()
	var t1 := Time.get_ticks_msec()

	terrain.build(self, load("res://assets/materials/terrain.tres"))
	roads.build(self)
	var city := CityBuilder.new(terrain)
	city.build(self, roads.intersections)
	var nature := NatureBuilder.new(terrain)
	nature.build(self, city.tree_spots)
	if not Engine.is_editor_hint():
		var grass := GrassField.new()
		add_child(grass)
		grass.setup(terrain)
	var park := StuntParkBuilder.new()
	park.build(self)
	LandmarksBuilder.new(roads).build(self)

	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	_spawn_props(props, city.prop_spawns)
	_spawn_props(props, park.prop_spawns)
	_spawn_props(props, _extra_props())
	_define_spawns()
	print("World built in %d ms (terrain/roads %d ms)" % [Time.get_ticks_msec() - t0, t1 - t0])


func _spawn_props(parent: Node3D, list: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	for s in list:
		var key: String = s["scene"]
		if key == "parked_car":
			# Mix of parked vehicle types.
			var r := rng.randf()
			key = "parked_sedan" if r < 0.45 else ("parked_van" if r < 0.65 else "parked_car")
		var scene: PackedScene = PROP_SCENES.get(key)
		if scene == null:
			push_warning("Unknown prop scene: %s" % key)
			continue
		var node := scene.instantiate() as Node3D
		if node is Ramp:
			var r := node as Ramp
			r.shape = s.get("shape", Ramp.RampShape.KICKER)
			r.length = s.get("length", 8.0)
			r.height = s.get("height", 2.0)
			r.width = s.get("width", 6.0)
			r.deck_length = s.get("deck", 0.0)
			if s.has("color"):
				r.surface_color = s["color"]
		if node is TrafficLightProp and s.has("signal"):
			(node as TrafficLightProp).intersection_id = s["signal"][0]
			(node as TrafficLightProp).axis = s["signal"][1]
		node.transform = s["xform"]
		parent.add_child(node)
		if Engine.is_editor_hint():
			_editor_mesh(node)


## Props that belong to no particular builder.
func _extra_props() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	# Big jump off the mountain top, facing north.
	var c := MapLayout.MOUNTAIN_CENTER
	var y := roads.summit_height - 0.15
	list.append({"scene": "ramp", "xform": Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.y - 8.0)),
		"shape": 1, "length": 12.0, "height": 3.2, "width": 9.0, "color": Color(0.95, 0.35, 0.3)})
	# Kickers on the open fields between the city and the highway.
	list.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-185, 0.0, 60)),
		"shape": 1, "length": 9.0, "height": 2.5, "width": 7.0})
	list.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(185, 0.0, -60)),
		"shape": 1, "length": 9.0, "height": 2.5, "width": 7.0})
	list.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, PI), Vector3(-60, 0.0, 195)),
		"shape": 0, "length": 14.0, "height": 3.0, "width": 8.0, "deck": 6.0})
	# Dirt field kickers.
	for k in 3:
		var p := Vector3(370 + k * 40.0, 0, 150)
		p.y = terrain.height_at(p.x, p.z) - 0.1
		list.append({"scene": "ramp", "xform": Transform3D(Basis(Vector3.UP, PI * 0.5), p),
			"shape": 1, "length": 8.0 + k * 2.0, "height": 2.0 + k, "width": 7.0, "color": Color(0.75, 0.55, 0.35)})
	list.append_array(_highway_junction_lights())
	# Dirt kickers on two of the mountain trail's long legs.
	var trail := roads.find_road("MountainTrail")
	for f in [0.27, 0.6]:
		var i := int(trail.points.size() * f)
		var d := trail.points[i + 2] - trail.points[i]
		list.append({"scene": "ramp", "xform": Transform3D(Basis.looking_at(d.normalized()), trail.points[i] + Vector3.DOWN * 0.08),
			"shape": 1, "length": 6.0, "height": 1.3, "width": 5.0, "color": Color(0.62, 0.45, 0.3)})
	# Beach barrels.
	for k in 6:
		list.append({"scene": "barrel", "xform": Transform3D(Basis.IDENTITY, Vector3(-360, roads.beach_height, -12 + k * 4.0))})
	return list


## Traffic lights for the two highway/avenue junctions (east, then west — the
## same order TrafficNetwork gives their signals, after the city intersections).
func _highway_junction_lights() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var ring := MapLayout.HIGHWAY_HALF_EXTENT
	var hw := MapLayout.highway_width() * 0.5
	var k := 0
	for x in [ring, -ring]:
		var sig := roads.intersections.size() + k
		k += 1
		var p := Vector3(x, 0, 0)
		var out := Vector3(signf(x), 0, 0)  # from the city outwards along the avenue
		var t_in := Vector3(0, 0, signf(x))  # inner carriageway travel direction
		# [travel direction, position]
		var approaches := [
			[t_in, p - out * (hw + 1.2) - t_in * (TrafficNetwork.HJ_STOP + 1.0)],
			[-t_in, p + out * (hw + 1.2) + t_in * (TrafficNetwork.HJ_STOP + 1.0)],
			[out, p - out * (hw + TrafficNetwork.HJ_AVE_STOP + 0.8) + out.cross(Vector3.UP) * 7.3],
			[-out, p + out * (hw + TrafficNetwork.HJ_AVE_STOP + 0.8) - out.cross(Vector3.UP) * 7.3],
		]
		for a in approaches:
			var t: Vector3 = a[0]
			var pos: Vector3 = a[1]
			pos.y = terrain.height_at(pos.x, pos.z)
			var r := t.cross(Vector3.UP)
			list.append({"scene": "traffic_light", "xform": Transform3D(Basis(r, Vector3.UP, -t), pos),
				"signal": [sig, 0 if absf(t.z) > absf(t.x) else 1]})
	return list


func _define_spawns() -> void:
	var face := func(dir: Vector3) -> Basis: return Basis.looking_at(dir, Vector3.UP)
	var c := MapLayout.MOUNTAIN_CENTER
	var fields := Vector3(345, 0, 4)
	fields.y = terrain.height_at(fields.x, fields.z)
	spawn_points = [
		{"name": "City Center", "xform": Transform3D(face.call(Vector3.RIGHT), Vector3(-110, 0.6, 3))},
		{"name": "Highway", "xform": Transform3D(face.call(Vector3.BACK), Vector3(MapLayout.HIGHWAY_HALF_EXTENT - 7.0, 0.6, -60))},
		{"name": "Stunt Park", "xform": Transform3D(face.call(Vector3.BACK), Vector3(0, 0.6, MapLayout.PARK_MIN.y + 6.0))},
		{"name": "Mountain Top", "xform": Transform3D(face.call(Vector3.FORWARD), Vector3(c.x, roads.summit_height + 0.6, c.y + 14.0))},
		{"name": "Dirt Fields", "xform": Transform3D(face.call(Vector3.RIGHT), fields + Vector3.UP * 0.8)},
		{"name": "Beach", "xform": Transform3D(face.call(Vector3.LEFT), Vector3(-338, roads.beach_height + 0.6, 3))},
		{"name": "Airfield", "xform": Transform3D(face.call(Vector3.BACK), MapLayout.APRON_CENTER + Vector3(-11, 0.7, 6))},
		{"name": "Harbour", "xform": Transform3D(face.call(Vector3.BACK), MapLayout.HARBOR_QUAY_A + Vector3(-4, 0.7, -5))},
		{"name": "Lighthouse", "xform": Transform3D(face.call(Vector3.RIGHT),
			Vector3(MapLayout.ISLET_CENTER.x + 14.0, terrain.height_at(MapLayout.ISLET_CENTER.x + 14.0, 0.0) + 0.8, 0.0))},
	]


## The street props' scripts don't run in the editor, so give their models
## the StreetKit mesh here; the map preview then shows lamps, signals,
## hydrants, cones...
func _editor_mesh(node: Node) -> void:
	var kind: Variant = node.get("kind")
	if kind == null:
		kind = node.get("kit_kind")
	var model := node.get_node_or_null("Model") as MeshInstance3D
	if model and kind is String and kind != "":
		model.mesh = StreetKit.mesh(kind)
