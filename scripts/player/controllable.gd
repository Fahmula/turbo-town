class_name Controllable
extends Node
## Makes its parent (a "pawn") something that can be controlled: the player's
## character and every Vehicle have one (Vehicle adds it in _ready). It records
## who is in control right now (the player's Possession, a TrafficDriver, or
## nobody), so two controllers never drive the same pawn, and `kind` tells the
## Possession which input controller and camera to use for it.
##
## The kinds are "character", "vehicle" (cars, trucks, buses...) and "plane"
## (Aircraft). A new kind (a boat...) gets its own controller and camera
## (Possession.add_rig); the rest of the hand-over stays the same.

signal taken(by: Object)
signal dropped(by: Object)

const CHARACTER := &"character"
const VEHICLE := &"vehicle"
const PLANE := &"plane"
## Meta on a split-screen player's own vehicle and their character: which
## player (0, 1) it belongs to (LocalPlayer sets it, VehicleEntry reads it).
const OWNER_META := &"player"

@export var kind := VEHICLE

## Whoever drives the pawn now (null = nobody).
var controller: Object = null
## The current controller hands the pawn over when the player wants it
## (traffic drivers do: the player can take a traffic car).
var yields := false


## The Controllable of `pawn`, or null.
static func of(pawn: Node) -> Controllable:
	if pawn == null or not is_instance_valid(pawn):
		return null
	return pawn.get_node_or_null("Controllable") as Controllable


func pawn() -> Node3D:
	return get_parent() as Node3D


func is_free() -> bool:
	return controller == null or not is_instance_valid(controller)


func is_controlled_by(who: Object) -> bool:
	return controller == who and who != null


## `who` takes control (`yield_to_player`: see `yields`). False if someone
## else still has it (they must drop it first: a traffic car is claimed from
## its driver through the TrafficManager).
func take(who: Object, yield_to_player := false) -> bool:
	if not is_free() and controller != who:
		return false
	yields = yield_to_player
	if controller != who:
		controller = who
		taken.emit(who)
	return true


## `who` lets go (does nothing if it wasn't in control).
func drop(who: Object) -> void:
	if controller == who and who != null:
		controller = null
		yields = false
		dropped.emit(who)
