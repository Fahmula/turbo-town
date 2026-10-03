@tool
class_name TreeColliders
extends Node
## Trunk colliders for the island's trees: a cylinder per tree, as shapes of
## one static body per 64 m chunk, made through PhysicsServer3D directly (ten
## thousand CollisionShape3D nodes would cost far more to build than the
## trunks are worth). Shapes are shared between trees of a similar size.
##   add(...) for every tree, then commit() once the node is in the tree.
## The bodies and shapes are freed with the node.

const CHUNK := 64.0

var _items := {}  # Vector2i chunk -> Array of [origin, shape RID]
var _shapes := {}  # "r_h" -> RID
var _bodies: Array[RID] = []


## A trunk at `origin` (the tree's foot), `radius` and `height` in metres.
func add(origin: Vector3, radius: float, height: float) -> void:
	var r := snappedf(radius, 0.04)
	var h := snappedf(height, 0.5)
	var key := "%.2f_%.1f" % [r, h]
	var shape: RID
	if _shapes.has(key):
		shape = _shapes[key]
	else:
		shape = PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(shape, {"radius": maxf(r, 0.08), "height": h})
		_shapes[key] = shape
	var ck := Vector2i(floori(origin.x / CHUNK), floori(origin.z / CHUNK))
	if not _items.has(ck):
		_items[ck] = []
	(_items[ck] as Array).append([origin + Vector3.UP * (h * 0.5), shape])


## Creates the bodies in the world's physics space. Does nothing in the editor.
func commit() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var space := get_viewport().world_3d.space
	for ck: Vector2i in _items:
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 1)
		for it: Array in _items[ck]:
			PhysicsServer3D.body_add_shape(body, it[1], Transform3D(Basis.IDENTITY, it[0]))
		_bodies.append(body)
	_items.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for b in _bodies:
			PhysicsServer3D.free_rid(b)
		for k in _shapes:
			PhysicsServer3D.free_rid(_shapes[k])
		_bodies.clear()
		_shapes.clear()
