class_name WingDoors
extends Node
## Gull-wing rear doors that fold in two (the electric SUV). Each door is two
## body meshes: WingDoorUpper<L|R>, the roof half, hinged on the roof's centre
## line, and WingDoorLower<L|R>, the side half with the window, hinged on the
## roof edge. They rise when the vehicle stands still with nobody driving it
## and someone on foot comes close, and close again when it's driven off or
## everyone walks away.
##
## The meshes are modelled shut at the vehicle's origin (make_suv.py) like
## every other body mesh, so shut = the identity transform, and whatever
## measures the body (paint lines, garage kits, the far LOD) sees them shut.
## Dents still land right on an open door: VehicleDamage works in each
## mesh's own space.

## Hinge lines along the vehicle (x = out to the right, y = up, metres in the
## vehicle's space), as make_suv.py prints them: the roof's centre line and
## the fold on the roof edge (the right door's; the left one is mirrored).
@export var centre_hinge := Vector2(0.0, 1.325)
@export var fold_hinge := Vector2(0.742, 1.238)
## Fully open (degrees): the roof half swings up, the side half folds back
## down so the door stays close to the body.
@export var upper_angle := 70.0
@export var lower_angle := -40.0
## Seconds to open or close.
@export var open_time := 1.6
## Someone on foot this close (m) to the bodywork opens them.
@export var near := 3.0
## Faster than this (m/s) they stay shut.
@export var max_speed := 1.0

const CHECK_EVERY := 0.2

var vehicle: Vehicle
## 0 = shut, 1 = open (eased when posing the meshes).
var amount := 0.0
var _target := 0.0
var _check := 0.0
## side (-1 left, 1 right) -> [upper MeshInstance3D, lower MeshInstance3D]
var _doors := {}


func _ready() -> void:
	vehicle = get_parent() as Vehicle
	var model := vehicle.get_node_or_null("Body/Model") if vehicle else null
	if model == null:
		set_process(false)
		return
	for side: int in [-1, 1]:
		var s := "L" if side < 0 else "R"
		var up := model.find_child("WingDoorUpper" + s, true, false) as MeshInstance3D
		var lo := model.find_child("WingDoorLower" + s, true, false) as MeshInstance3D
		if up and lo:
			_doors[side] = [up, lo]
	_check = randf() * CHECK_EVERY  # spread the checks of several vehicles
	set_process(not _doors.is_empty())


## Opens (true) or shuts them right away, e.g. for a garage shot.
func set_open(open: bool, instant := false) -> void:
	_target = 1.0 if open else 0.0
	if instant:
		amount = _target
		_pose()


func is_open() -> bool:
	return amount > 0.0


func _process(dt: float) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_EVERY
		_target = 1.0 if _wanted() else 0.0
	if amount == _target:
		return
	amount = move_toward(amount, _target, dt / open_time)
	_pose()


## Open when standing still, free (nobody driving: traffic drivers keep
## theirs shut) and someone on foot is close.
func _wanted() -> bool:
	if vehicle.linear_velocity.length() > max_speed:
		return false
	var c := Controllable.of(vehicle)
	if c and not c.is_free():
		return false
	var inv := vehicle.global_transform.affine_inverse()
	for n in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var pc := n as PlayerCharacter
		if pc == null or pc.state == PlayerCharacter.State.HIDDEN or not pc.is_inside_tree():
			continue
		var p := inv * pc.global_position
		var dx := maxf(absf(p.x) - vehicle.body_half_width, 0.0)
		var dz := maxf(maxf(p.z - vehicle.body_rear, -vehicle.body_front - p.z), 0.0)
		if Vector2(dx, dz).length() <= near and absf(p.y) < 3.0:
			return true
	return false


func _pose() -> void:
	var e := amount * amount * (3.0 - 2.0 * amount)
	for side: int in _doors:
		var up := _hinge(Vector2(centre_hinge.x * side, centre_hinge.y), deg_to_rad(upper_angle) * e * side)
		var fold := _hinge(Vector2(fold_hinge.x * side, fold_hinge.y), deg_to_rad(lower_angle) * e * side)
		(_doors[side][0] as MeshInstance3D).transform = up
		(_doors[side][1] as MeshInstance3D).transform = up * fold


## A rotation by `angle` about the line along the vehicle through `at`.
static func _hinge(at: Vector2, angle: float) -> Transform3D:
	var b := Basis(Vector3.BACK, angle)
	var p := Vector3(at.x, at.y, 0.0)
	return Transform3D(b, p - b * p)
