class_name VehicleEntry
extends Interactable
## A vehicle's doors and seats: where the player gets in, who rides along,
## and where it's safe to get out. Every Vehicle adds one (named "Entry") in
## _ready, so any vehicle, the player's or a traffic car, can be entered;
## nothing per vehicle needs editing. The doors come from the vehicle's
## measured body (half width, length) and its `driver_eye`; a Marker3D child
## of the vehicle named "DriverDoor" overrides the door position if a model
## ever needs it.
##
## Seats: the driver's (left-hand drive: the driver's door is on the left,
## -X) and a passenger seat beside it. In split-screen a player can ride
## along in the other player's vehicle (`riders`; the other player drives).
## Getting out tries the player's own door first, then the other side,
## behind, in front, a ring of spots further out, and finally the roof; each
## spot needs walkable ground at about the vehicle's level, room for the
## character's capsule and no wall between the seat and it.

## What the interact button does for someone standing by the vehicle.
enum Use { NONE, FLIP, DRIVE, RIDE }

## Too fast to get in (m/s).
const MAX_ENTER_SPEED := 2.5
## How far out from the bodywork the door spots are (m).
const DOOR_GAP := 0.6
## Ground under an exit spot may be this much above or below the vehicle's.
const MAX_STEP := 1.2
## Physics layers: world, vehicles, props.
const BLOCKERS := 0b111

var vehicle: Vehicle
## Passenger seats besides the driver's. One: there are at most two players.
var passenger_seats := 1
## The players riding along as passengers (their Possessions; untyped so
## vehicles don't load the player code).
var riders: Array[Node] = []


func _init() -> void:
	name = "Entry"
	reach = 1.4


func _ready() -> void:
	vehicle = get_parent() as Vehicle


## The Entry of `v`, or null.
static func of(v: Node) -> VehicleEntry:
	if v == null or not is_instance_valid(v):
		return null
	return v.get_node_or_null("Entry") as VehicleEntry


## Distance from `point` to the vehicle's footprint (its collision boxes as
## one box), so the prompt shows anywhere along the sides, not only at the
## door.
func reach_distance(point: Vector3) -> float:
	if vehicle == null:
		return INF
	var local := vehicle.global_transform.affine_inverse() * point
	if local.y < -2.0 or local.y > vehicle.body_top + 1.5:
		return INF
	var dx := maxf(absf(local.x) - vehicle.footprint_half_width, 0.0)
	var dz := maxf(maxf(local.z - vehicle.body_rear, -vehicle.body_front - local.z), 0.0)
	var d := Vector2(dx, dz).length()
	return d if d <= reach else INF


func is_overturned() -> bool:
	return vehicle.global_basis.y.y < 0.45


func in_water() -> bool:
	return vehicle.global_position.y < MapLayout.SEA_LEVEL - 0.3


## What the interact button would do for `actor` now.
func use_for(actor: Node3D) -> Use:
	if vehicle == null or not vehicle.is_inside_tree() or vehicle.is_queued_for_deletion() or in_water():
		return Use.NONE
	if vehicle.linear_velocity.length() > MAX_ENTER_SPEED:
		return Use.NONE
	var c := Controllable.of(vehicle)
	var taken := c != null and not c.is_free() and not c.yields
	if not taken and is_overturned():
		return Use.FLIP
	if actor is PlayerCharacter and not (actor as PlayerCharacter).can_act():
		return Use.NONE
	if taken or _belongs_to_other(actor):
		# Someone (the other player) drives it, or it's theirs: ride along.
		return Use.RIDE if _can_ride(actor) else Use.NONE
	return Use.DRIVE


func prompt(actor: Node3D) -> String:
	match use_for(actor):
		Use.FLIP:
			return "Flip the %s back over" % vehicle.display_name.to_lower()
		Use.DRIVE:
			return "Get in the %s" % vehicle.display_name.to_lower()
		Use.RIDE:
			var who := "Player %d" % (owner_index() + 1)
			if Controllable.of(vehicle).is_free():
				return "Sit in %s's %s" % [who, vehicle.display_name.to_lower()]
			return ("Fly with %s" if vehicle is Aircraft else "Ride with %s") % who
	return ""


func interact(actor: Node3D) -> bool:
	var use := use_for(actor)
	if use == Use.FLIP:
		vehicle.reset_upright()
		return true
	var pc := actor as PlayerCharacter
	if pc == null:
		return false
	if use == Use.DRIVE:
		pc.vehicle_requested.emit(vehicle)
		return true
	if use == Use.RIDE:
		pc.ride_requested.emit(vehicle)
		return true
	return false


# --- Passengers --------------------------------------------------------------

## Can `actor` (a player on foot) ride along in the other player's vehicle?
func _can_ride(actor: Node3D) -> bool:
	if not (actor is PlayerCharacter) or is_overturned() or not has_free_seat():
		return false
	var mine: int = actor.get_meta(Controllable.OWNER_META, -1)
	return owner_index() >= 0 and owner_index() != mine


## Which player (0, 1) the vehicle belongs to (-1 = nobody's).
func owner_index() -> int:
	return vehicle.get_meta(Controllable.OWNER_META, -1) if vehicle else -1


func has_free_seat() -> bool:
	_prune_riders()
	return riders.size() < passenger_seats


func has_riders() -> bool:
	_prune_riders()
	return not riders.is_empty()


## `who` sits in a passenger seat. False if they're all taken.
func add_rider(who: Node) -> bool:
	if riders.has(who):
		return true
	if not has_free_seat():
		return false
	riders.append(who)
	return true


func remove_rider(who: Node) -> void:
	riders.erase(who)


func _prune_riders() -> void:
	for i in range(riders.size() - 1, -1, -1):
		if not is_instance_valid(riders[i]):
			riders.remove_at(i)


# --- Doors and seat --------------------------------------------------------

## The driver's door (local, at the sill), from a "DriverDoor" marker or the body.
func driver_door_local() -> Vector3:
	var marker := vehicle.get_node_or_null("DriverDoor") as Node3D
	if marker:
		return marker.position
	return Vector3(-vehicle.body_half_width, 0.0, _door_z())


func _door_z() -> float:
	return clampf(vehicle.driver_eye.z + 0.25, -vehicle.body_front + 0.7, vehicle.body_rear - 0.7)


## Where the character stands to open the door on the side nearest `point`
## (world space, at the height of `point`).
func door_spot(point: Vector3) -> Vector3:
	var door := driver_door_local()
	var local := vehicle.global_transform.affine_inverse() * point
	var side := -1.0 if local.x <= 0.0 else 1.0
	var p := vehicle.global_transform * Vector3(side * (absf(door.x) + DOOR_GAP * 0.7), 0.0, door.z)
	p.y = point.y
	return p


## A safe place for `character` to stand after getting out, as a transform
## (feet, facing the way the vehicle points), or null if there's no room
## anywhere nearby. A `passenger` gets out on the passenger side first.
func find_exit(character: PlayerCharacter, passenger := false) -> Variant:
	var space := vehicle.get_world_3d().direct_space_state
	var frame := _ground_frame(space)
	var base: Vector3 = frame.origin
	var basis: Basis = frame.basis
	var side := 1.0 if passenger else -1.0
	var hw := (vehicle.body_half_width + DOOR_GAP) * side
	var door := driver_door_local()
	var dz := door.z
	var spots: Array[Vector3] = [
		Vector3(hw, 0, dz), Vector3(hw, 0, dz + 1.0), Vector3(hw, 0, dz - 1.0),
		Vector3(-hw, 0, dz), Vector3(-hw, 0, dz + 1.0), Vector3(-hw, 0, dz - 1.0),
		Vector3(0, 0, vehicle.body_rear + DOOR_GAP + 0.2), Vector3(0, 0, -vehicle.body_front - DOOR_GAP - 0.2),
	]
	# Further out: rings around the vehicle, nearest to the player's door first.
	var ring: Array[Vector3] = []
	for r: float in [1.6, 2.8, 4.2]:
		for k in 16:
			var a := TAU * k / 16.0
			var rx := (vehicle.body_half_width + r) * cos(a)
			var rz := ((vehicle.body_front + vehicle.body_rear) * 0.5 + r) * sin(a) + (vehicle.body_rear - vehicle.body_front) * 0.5
			ring.append(Vector3(rx, 0, rz))
	var my_door := Vector3(hw, 0, dz)
	ring.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(my_door) < b.distance_squared_to(my_door))
	spots.append_array(ring)
	var seat := vehicle.global_transform * Vector3(absf(door.x) * 0.5 * side, minf(vehicle.driver_eye.y, vehicle.body_top) - 0.25, dz)
	var facing := Basis.looking_at(-basis.z, Vector3.UP)
	for s in spots:
		var feet: Variant = _check_spot(space, character, base + basis * s, base.y, seat)
		if feet != null:
			return Transform3D(facing, feet)
	# Last resort: stand on the roof (an overturned car: on its underside).
	var top := _top_spot()
	if _capsule_clear(space, character, top):
		return Transform3D(facing, top)
	return null


## The vehicle's position on the ground and its heading, upright (the frame
## exit spots are measured in, also when the vehicle lies on its side).
func _ground_frame(space: PhysicsDirectSpaceState3D) -> Transform3D:
	var fwd := -vehicle.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.2:
		fwd = vehicle.global_basis.y
		fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	var pos := vehicle.global_position
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 6.0, 1)
	var hit := space.intersect_ray(q)
	pos.y = (hit["position"] as Vector3).y if not hit.is_empty() else pos.y - vehicle.ride_height()
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)


## Feet position for an exit at `p` (ground found under it), or null.
func _check_spot(space: PhysicsDirectSpaceState3D, character: PlayerCharacter, p: Vector3, ground_y: float, seat: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, ground_y + MAX_STEP + 0.6, p.z), Vector3(p.x, ground_y - MAX_STEP - 0.6, p.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null  # off an edge
	var feet: Vector3 = hit["position"]
	if (hit["normal"] as Vector3).y < 0.7 or absf(feet.y - ground_y) > MAX_STEP:
		return null  # too steep, or a ledge / the top of a wall
	if feet.y < MapLayout.SEA_LEVEL + 0.05:
		return null  # in the sea
	if not _capsule_clear(space, character, feet):
		return null
	# No wall between the driver's seat and the spot (getting out through a
	# building or a barrier).
	var los := PhysicsRayQueryParameters3D.create(seat, feet + Vector3.UP * 1.0, 1)
	if not space.intersect_ray(los).is_empty():
		return null
	return feet


## Room for the character standing at `feet`: nothing solid in its capsule.
## Light props (cones, bins) don't count: the character just nudges them.
func _capsule_clear(space: PhysicsDirectSpaceState3D, character: PlayerCharacter, feet: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = character.query_shape()
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * character.query_shape_center())
	q.collision_mask = BLOCKERS
	for hit in space.intersect_shape(q, 8):
		var col: Object = hit["collider"]
		if col is RigidBody3D and not (col is Vehicle) and (col as RigidBody3D).mass < 150.0:
			continue
		return false
	return true


## On top of the vehicle: the highest point of its collision boxes.
func _top_spot() -> Vector3:
	var top := -INF
	for child in vehicle.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var h := (cs.shape as BoxShape3D).size * 0.5
		for x in [-h.x, h.x]:
			for y in [-h.y, h.y]:
				for z in [-h.z, h.z]:
					top = maxf(top, (vehicle.global_transform * (cs.transform * Vector3(x, y, z))).y)
	if top == -INF:
		top = vehicle.global_position.y + vehicle.body_top
	var p := vehicle.global_position
	return Vector3(p.x, top + 0.05, p.z)


## Is this the other split-screen player's own vehicle? (They can flip it
## back over, but not take it.)
func _belongs_to_other(actor: Node3D) -> bool:
	var mine: int = actor.get_meta(Controllable.OWNER_META, -1) if actor else -1
	var theirs: int = vehicle.get_meta(Controllable.OWNER_META, -1)
	return mine >= 0 and theirs >= 0 and mine != theirs
