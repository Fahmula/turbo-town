class_name FuelGuide
extends Node3D
## The low-fuel arrow: while a player's tank or battery is low, an arrow
## floats over their vehicle (like the race arrow, RaceManager.make_arrow)
## pointing to the nearest place that serves it (FuelSite.nearest_for). It
## hides near the place, during a race and with the Fuel setting off.
## LocalPlayer sets `vehicle` (null hides it) and `site`. In split-screen
## only its own player sees it.

## Red: the gauge's low colour (ART_BIBLE §20: red = danger).
const COLOR := Color(1.0, 0.35, 0.25)

var vehicle: Vehicle
var site: FuelSite
## The player (0, 1) it's for: split-screen shows it in their view only.
var player_index := 0

var _arrow: MeshInstance3D


func _ready() -> void:
	_arrow = RaceManager.make_arrow(COLOR)
	_arrow.name = "Arrow"
	_arrow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arrow.visible = false
	add_child(_arrow)


func showing() -> bool:
	return _arrow.visible


func _process(_dt: float) -> void:
	var on := vehicle != null and is_instance_valid(vehicle) and vehicle.is_inside_tree() \
		and site != null and is_instance_valid(site)
	if on:
		var top := vehicle.get_global_transform_interpolated().origin + Vector3.UP * (vehicle.body_top + 1.6)
		var to := site.center() - top
		to.y = 0.0
		if to.length() > 0.5:
			_arrow.global_transform = Transform3D(Basis.looking_at(to.normalized(), Vector3.UP), top)
		else:
			on = false
	_arrow.visible = on
	if on:
		_arrow.layers = Views.VIEW_LAYERS[player_index] if Views.is_split() else 1
