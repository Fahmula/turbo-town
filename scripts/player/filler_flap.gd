class_name FillerFlap
extends Interactable
## Where a vehicle takes the fuel nozzle or charging plug: the right rear
## quarter, worked out from its body like the doors (VehicleEntry), or the
## vehicle's `filler` / `filler_normal` (the plane: on top of the right
## wing; the helicopter: the cabin's right side). VehicleFuel adds one to
## every vehicle a player drives.
##
## Holding a hose that fits: "Fill up" / "Charge it" (it outranks "Get in":
## VehicleEntry offers nothing to someone holding a hose). With a nozzle in
## and empty hands: "Take the nozzle out". Either player can fill either
## vehicle, also while the other sits at the wheel (it mustn't move, or the
## nozzle pops out).

var vehicle: Vehicle
## The filler's point and outward direction on the vehicle (local; worked
## out once, the body doesn't change).
var _local := Vector3.ZERO
var _normal := Vector3.RIGHT


func _init() -> void:
	name = "FillerFlap"
	reach = 1.25
	priority = 2


func _ready() -> void:
	vehicle = get_parent() as Vehicle
	if vehicle:
		_local = vehicle.filler_point()
		_normal = vehicle.filler_normal()
		position = _local


## The filler's point and its outward direction, world space.
func point(interpolated := false) -> Vector3:
	var xf := vehicle.get_global_transform_interpolated() if interpolated else vehicle.global_transform
	return xf * _local


func normal(interpolated := false) -> Vector3:
	var xf := vehicle.get_global_transform_interpolated() if interpolated else vehicle.global_transform
	return (xf.basis * _normal).normalized()


## Where a nozzle sits in the filler: its spout into the body, tipped down,
## the grip just outside.
func nozzle_transform(interpolated := false) -> Transform3D:
	var p := point(interpolated)
	var n := normal(interpolated)
	var into := -n
	if absf(n.y) < 0.7:
		into = (-n * cos(0.6) + Vector3.DOWN * sin(0.6)).normalized()
	var up := Vector3.UP if absf(into.y) < 0.95 else (vehicle.global_basis.z if not interpolated else vehicle.get_global_transform_interpolated().basis.z)
	var b := Basis.looking_at(into, up)
	# The spout tip is ~0.26 m ahead of the grip: the grip sits outside.
	return Transform3D(b, p - into * 0.2)


func _fuel() -> VehicleFuel:
	return VehicleFuel.of(vehicle)


func reach_distance(at: Vector3) -> float:
	if vehicle == null or not vehicle.is_inside_tree():
		return INF
	var p := point()
	if at.y > p.y + 0.6 or at.y < p.y - 2.6:
		return INF
	var d := maxf(Vector2(at.x - p.x, at.z - p.z).length() - 0.3, 0.0)
	return d if d <= reach else INF


## Still enough (and upright) to fill?
func _usable() -> bool:
	return vehicle != null and vehicle.is_inside_tree() and not vehicle.is_queued_for_deletion() \
		and vehicle.linear_velocity.length() < 0.6 and vehicle.global_basis.y.y > 0.6


func prompt(actor: Node3D) -> String:
	var pc := actor as PlayerCharacter
	var fuel := _fuel()
	if pc == null or fuel == null or not fuel.enabled or not pc.can_act() or not _usable():
		return ""
	var held := FuelPump.held_by(pc)
	var inside := fuel.nozzle as FuelPump if is_instance_valid(fuel.nozzle) else null
	if held:
		if inside:
			return ""  # (already filling: hang this one up)
		if held.fits(vehicle):
			return "Charge it" if held.plug else "Fill up"
		return "This one needs a charger" if fuel.is_battery() else "This one needs fuel"
	if inside:
		return "Take the %s out" % inside.noun()
	return ""


func interact(actor: Node3D) -> bool:
	var pc := actor as PlayerCharacter
	if pc == null or prompt(actor) == "":
		return false
	var held := FuelPump.held_by(pc)
	if held:
		if held.fits(vehicle):
			held.insert(vehicle, self)
		return true  # (the wrong kind: the prompt says so)
	var inside := _fuel().nozzle as FuelPump
	if inside and is_instance_valid(inside):
		inside.take_out(pc)
		return true
	return false
