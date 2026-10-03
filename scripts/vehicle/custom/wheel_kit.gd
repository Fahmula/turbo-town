class_name WheelKit
extends RefCounted
## Fits garage wheels to a vehicle (Loadout.apply): a PartsCatalog rim inside
## a PartsCatalog tyre, in place of each wheel's own model under "Visual".
## The rim is scaled to the tyre (rims are all built to one standard fit),
## then gets the chosen finish; open rims get a brake caliper in the chosen
## colour; the tyre stripe is a band in the car's tyre material. Cosmetic
## only: the physics wheel (radius, grip) doesn't change.
##
## A fitted wheel looks like this (VehicleWheel.add_caliper reads Model/Rim
## to size the caliper):
##   WheelFL/Visual/Model   the wheel model's own transform (size, mirror)
##                  Model/Rim    rim_<id>.glb, scaled to the tyre
##                  Model/Tyre   tyre_<id>.glb

## Every wheel model is 0.37 m round; scenes scale it to the wheel radius.
const BASE_RADIUS := 0.37
## The standard fit every rim is built to (make_wheels.py).
const RIM_BEAD := 0.243
const RIM_WIDTH := 0.254
## Where the tyre shader's tread starts (object space).
const TREAD_RADIUS := 0.345

static var _scenes := {}
static var _finishes := {}


static func fit(v: Vehicle, l: Loadout) -> void:
	# Untouched stock wheels are already right: keep the scene's own models.
	if l.wheels_stock() and not is_fitted(v):
		return
	var rim := PartsCatalog.option("rims", l.get_value("rims"))
	var tyre := PartsCatalog.option("tyres", l.get_value("tyres"))
	var rim_scene := _scene(PartsCatalog.rim_scene(rim["id"]))
	var tyre_scene := _scene(PartsCatalog.tyre_scene(tyre["id"]))
	if rim_scene == null or tyre_scene == null:
		return
	var finish := _finish(l, rim)
	var caliper: Color = PartsCatalog.option("calipers", l.get_value("calipers"))["color"]
	var rim_scale := Vector3(tyre["width"] / RIM_WIDTH, tyre["bead"] / RIM_BEAD, tyre["bead"] / RIM_BEAD)
	var roots: Array[Node] = []
	for w in v.wheels:
		var vis := w.get_node_or_null("Visual") as Node3D
		if vis == null:
			continue
		var old := vis.get_node_or_null("Model") as Node3D
		var xf := old.transform if old else Transform3D(Basis.from_scale(Vector3.ONE * w.radius / BASE_RADIUS), Vector3.ZERO)
		if old:
			vis.remove_child(old)
			old.queue_free()
		var model := Node3D.new()
		model.name = "Model"
		model.transform = xf
		var r := rim_scene.instantiate() as Node3D
		r.name = "Rim"
		r.scale = rim_scale
		model.add_child(r)
		var t := tyre_scene.instantiate() as Node3D
		t.name = "Tyre"
		model.add_child(t)
		vis.add_child(model)
		for gi in model.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).layers = Vehicle.WHEEL_LAYER
		if finish:
			_set_material(model, "Rim", finish)
		w.set_caliper(Vehicle.CALIPER_SCENE if rim["open"] else null, caliper)
		roots.append(model)
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.adopt_meshes(roots)
		var stripe := PartsCatalog.option("tyre_stripe", l.get_value("tyre_stripe"))
		var band: Vector2 = stripe.get("band", Vector2.ZERO)
		var bead: float = tyre["bead"]
		body.set_tyre_stripe(stripe["color"], Vector2(lerpf(bead, TREAD_RADIUS, band.x), lerpf(bead, TREAD_RADIUS, band.y)))


## True once garage wheels have been fitted (the models are rim + tyre).
static func is_fitted(v: Vehicle) -> bool:
	for w in v.wheels:
		if w.get_node_or_null("Visual/Model/Rim"):
			return true
	return false


## The material for the chosen rim finish (null = the rim's own).
static func _finish(l: Loadout, rim: Dictionary) -> Material:
	var id: String = l.get_value("rim_color")
	if id == "stock":
		return null
	var key := id
	var col: Color
	var metal := 0.0
	var rough := 0.3
	if id == "body":
		col = l.get_value("paint")
		key = "body_%s" % col.to_html()
		rough = 0.22
	else:
		var o := PartsCatalog.option("rim_color", id)
		col = o["color"]
		metal = o["metal"]
		rough = o["rough"]
	if not _finishes.has(key):
		var m := StandardMaterial3D.new()
		m.resource_name = "Rim"
		m.albedo_color = col
		m.metallic = metal
		m.roughness = rough
		if metal < 0.5:
			# Painted rims get a clear coat like the body paint.
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.1
		_finishes[key] = m
	return _finishes[key]


static func _set_material(root: Node, mat_name: String, mat: Material) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == mat_name:
				mi.set_surface_override_material(i, mat)


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		if not ResourceLoader.exists(path):
			push_warning("WheelKit: missing wheel part %s" % path)
			return null
		_scenes[path] = load(path)
	return _scenes[path]
