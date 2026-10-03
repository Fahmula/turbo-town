class_name ParkedCarEntry
extends Interactable
## Lets the player get into a parked car. Parked cars are cheap sleeping
## Props (hundreds cost nothing), not Vehicles, so using one swaps it for the
## real drivable vehicle of the same type, paint and place, and the player
## gets into that. Prop adds one to every parked car whose scene names a
## `drive_scene`.

var prop: Prop
var _half := Vector3(1.0, 0.8, 2.3)
var _center := Vector3.ZERO
var _name := "car"


func _init() -> void:
	name = "Entry"
	reach = 1.4


func _ready() -> void:
	prop = get_parent() as Prop
	if prop == null:
		return
	# Footprint from the prop's collision boxes.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for child in prop.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var h := (cs.shape as BoxShape3D).size * 0.5
		lo = lo.min(cs.position - h)
		hi = hi.max(cs.position + h)
	if lo != Vector3.INF:
		_half = (hi - lo) * 0.5
		_center = (hi + lo) * 0.5
	for e: Dictionary in VehicleCatalog.ENTRIES:
		if e["scene"] == prop.drive_scene:
			_name = String(e["name"]).to_lower()


func reach_distance(point: Vector3) -> float:
	if prop == null:
		return INF
	var local := prop.global_transform.affine_inverse() * point - _center
	if absf(local.y) > _half.y + 2.0:
		return INF
	var d := Vector2(maxf(absf(local.x) - _half.x, 0.0), maxf(absf(local.z) - _half.z, 0.0)).length()
	return d if d <= reach else INF


func prompt(actor: Node3D) -> String:
	if prop == null or prop.drive_scene == "" or not prop.is_inside_tree():
		return ""
	# Knocked over or still rolling: leave it.
	if prop.global_basis.y.y < 0.85 or prop.linear_velocity.length() > 0.5:
		return ""
	if actor is PlayerCharacter and not (actor as PlayerCharacter).can_act():
		return ""
	return "Get in the %s" % _name


## Swaps the prop for a real vehicle and asks to get into it.
func interact(actor: Node3D) -> bool:
	var pc := actor as PlayerCharacter
	if pc == null or prompt(actor) == "":
		return false
	var scene := load(prop.drive_scene) as PackedScene
	if scene == null:
		return false
	var car := scene.instantiate() as Vehicle
	var body := car.get_node_or_null("Body") as VehicleBodyVisual
	if body and prop.paint != Color.TRANSPARENT:
		body.paint_color = prop.paint
	var fwd := -prop.global_basis.z
	fwd.y = 0.0
	var xform := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP),
		prop.global_position + Vector3.UP * (car.ride_height() + 0.05))
	var parent := prop.get_parent()
	# Out of the way first, so the new car doesn't start inside it.
	parent.remove_child(prop)
	prop.queue_free()
	# Placed before it enters the tree (see TrafficManager._spawn).
	var parent_xf := (parent as Node3D).global_transform if parent is Node3D else Transform3D.IDENTITY
	car.transform = parent_xf.affine_inverse() * xform
	parent.add_child(car)
	car.teleport(xform)
	pc.vehicle_requested.emit(car)
	return true
