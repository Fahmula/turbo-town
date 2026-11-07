class_name BodyKit
extends RefCounted
## Fits garage body parts to a vehicle (Loadout.apply): bumpers, side skirts,
## wheel arches, spoilers, bonnets and roof parts from the vehicle's kit
## (assets/models/kits/<vehicle>_kit.glb, tools/blender/make_kits.py). Each
## kit node is "<slot>_<id>" (PartsCatalog.BODY_PARTS), modelled in the
## vehicle's own space, so it goes on with an identity transform.
##
## A fitted vehicle looks like this:
##   Body/Model/...      the stock model; a stock part a kit replaces is hidden
##   Body/Kit/<part>     the kit parts. Bumpers and spoilers are renamed to the
##                       names VehicleDamage knocks off (FrontBumper,
##                       RearBumper, Spoiler), so they still fall off.
## Then VehicleDamage rescans the body, and wide arches push the wheel models
## out (VehicleWheel.track_offset). Cosmetic only: the collision shapes and
## physics don't change.

## Slot -> the stock mesh name it replaces (and the kit part's new name).
const REPLACES := {"front": "FrontBumper", "rear": "RearBumper", "spoiler": "Spoiler"}

static var _scenes := {}


static func fit(v: Vehicle, l: Loadout) -> void:
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	if body == null or v is Aircraft:
		return
	var old := body.get_node_or_null("Kit")
	# Untouched stock bodies are already right.
	if l.body_stock() and old == null:
		return
	var damage := v.get_node_or_null("Damage") as VehicleDamage
	if damage:
		damage.repair()  # puts fallen parts back before they're swapped
	if old:
		body.remove_child(old)
		old.free()
	var kit := Node3D.new()
	kit.name = "Kit"
	body.add_child(kit)
	var scene := _scene(PartsCatalog.kit_scene(l.vehicle_id))
	var source: Node = scene.instantiate() if scene else null
	var added: Array[Node] = []
	var track := 0.0
	for slot: String in PartsCatalog.BODY_PARTS:
		var id: String = l.get_value(slot)
		if REPLACES.has(slot):
			for stock in _stock_meshes(body, REPLACES[slot]):
				stock.visible = id == "stock"
		if id == "stock" or id == "none":
			continue
		var part := source.find_child("%s_%s" % [slot, id], true, false) as Node3D if source else null
		if part == null:
			push_warning("BodyKit: %s has no %s_%s" % [l.vehicle_id, slot, id])
			continue
		part.get_parent().remove_child(part)
		part.owner = null
		part.transform = Transform3D.IDENTITY
		if REPLACES.has(slot):
			part.name = REPLACES[slot]
		kit.add_child(part)
		added.append(part)
		track = maxf(track, PartsCatalog.option(slot, id).get("track", 0.0))
	if source:
		source.free()
	for root in added:
		var meshes := root.find_children("*", "GeometryInstance3D", true, false)
		if root is GeometryInstance3D:
			meshes.append(root)
		for gi in meshes:
			(gi as GeometryInstance3D).layers = Vehicle.VISUAL_LAYER
			(gi as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	body.adopt_meshes(added)
	for w in v.wheels:
		w.set_track_offset(signf(w.position.x) * track)
	if damage:
		damage.rescan()


## True once kit parts have been fitted.
static func is_fitted(v: Vehicle) -> bool:
	return v.get_node_or_null("Body/Kit") != null


## The kit part fitted for `slot` (null if none).
static func fitted_part(v: Vehicle, slot: String) -> Node3D:
	var kit := v.get_node_or_null("Body/Kit")
	if kit == null:
		return null
	if REPLACES.has(slot):
		return kit.get_node_or_null(REPLACES[slot]) as Node3D
	for c in kit.get_children():
		if String(c.name).begins_with(slot + "_"):
			return c as Node3D
	return null


## The stock model's meshes called `mesh_name` (not the kit's own).
static func _stock_meshes(body: Node, mesh_name: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in body.find_children(mesh_name, "MeshInstance3D", true, false):
		if not String(body.get_path_to(n)).begins_with("Kit/"):
			out.append(n as MeshInstance3D)
	return out


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]
