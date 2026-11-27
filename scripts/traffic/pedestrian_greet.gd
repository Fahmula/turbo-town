class_name PedestrianGreet
extends Interactable
## "Say hi" to a pedestrian on foot: they stop, turn to you, wave and say
## something (Pedestrian.greet). In the "interactables" group only while a
## player on foot is close (PedestrianManager adds and removes it), so the
## Possession's scan stays short.

var ped: Pedestrian


func _init() -> void:
	reach = 1.9


func _enter_tree() -> void:
	pass         # the manager decides when it's in the group


func set_listed(on: bool) -> void:
	if on and not is_in_group(GROUP):
		add_to_group(GROUP)
	elif not on and is_in_group(GROUP):
		remove_from_group(GROUP)


func reach_distance(point: Vector3) -> float:
	if not ped.visible:
		return INF
	var d := Vector2(point.x - ped.global_position.x, point.z - ped.global_position.z).length()
	return d if d <= reach else INF


func prompt(_actor: Node3D) -> String:
	return "Say hi" if ped.can_greet() else ""


func interact(actor: Node3D) -> bool:
	if not ped.can_greet():
		return false
	ped.greet(actor)
	return true
