class_name Interactable
extends Node3D
## Something the player can use on foot by walking up to it and pressing the
## interact button (F / gamepad B): a vehicle's doors (VehicleEntry), a parked
## car (ParkedCarEntry), later shops, doors, pick-ups...
##
## Interactables put themselves in the "interactables" group; the Possession
## asks the ones near the character which is closest and shows its prompt.
## Subclasses override reach_distance(), prompt() and interact().

const GROUP := &"interactables"

## How close (m) the actor must be (see reach_distance()).
@export var reach := 1.6
## Each step of priority counts as half a metre closer.
@export var priority := 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## Distance from `point` (the actor's feet) to where this can be used from.
## INF = out of reach.
func reach_distance(point: Vector3) -> float:
	var d := point.distance_to(global_position)
	return d if d <= reach else INF


## What the prompt says ("Get in the van"), or "" if it can't be used now.
func prompt(_actor: Node3D) -> String:
	return ""


## Use it. Returns true if something happened.
func interact(_actor: Node3D) -> bool:
	return false


## The best interactable `actor` can use from `point`, or null. Only looks at
## interactables in the same 3D world (the garage preview has its own).
static func best_for(actor: Node3D, point: Vector3) -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var world := actor.get_world_3d()
	for node in actor.get_tree().get_nodes_in_group(GROUP):
		var it := node as Interactable
		if it == null or it.get_world_3d() != world:
			continue
		var score := it.reach_distance(point) - it.priority * 0.5
		if score >= best_score or it.prompt(actor) == "":
			continue
		best = it
		best_score = score
	return best
