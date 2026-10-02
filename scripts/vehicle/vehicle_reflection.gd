class_name VehicleReflection
extends ReflectionProbe
## Real surroundings in the player car's paint and glass (ART_BIBLE.md §9,
## §13). Without it, cars only reflect the sky shader, whose bright ground
## half washes the lower bodywork out; with it the doors reflect dark road,
## the shoulders a horizon line and buildings, like real car paint.
##
## An UPDATE_ONCE probe that does NOT follow the car every frame: Godot
## re-renders a ONCE probe when it moves, one cube face per frame (so the
## cost is spread out), so it's only moved when the car has driven
## `move_threshold` metres from where it was last captured, at most every
## `min_interval` seconds. The box is big enough that the car stays inside
## it between captures. Only vehicles receive it (`reflection_mask`), so
## traffic driving through the box gets real reflections too. Only the
## player's vehicle carries one, and only on High (Medium and Low keep the
## sky reflections).

## Metres the car may drive from the last capture before a new one.
@export var move_threshold := 20.0
## Seconds between captures, at least.
@export var min_interval := 1.2

var vehicle: Vehicle
var _since := 0.0


func _init() -> void:
	name = "Reflection"
	top_level = true
	update_mode = ReflectionProbe.UPDATE_ONCE
	size = Vector3(44.0, 16.0, 44.0)
	origin_offset = Vector3.ZERO
	box_projection = false
	interior = false
	enable_shadows = false
	intensity = 1.0
	blend_distance = 4.0
	# Near surroundings only: each capture renders six views, so keep them
	# small (the Deck's CPU pays per object drawn).
	max_distance = 90.0
	# Cheaper captures: far LODs and only the world (layer 1, not cars).
	mesh_lod_threshold = 8.0
	cull_mask = 1
	# Only vehicles show it: the road and buildings inside the box keep the
	# sky reflections they were tuned with.
	reflection_mask = Vehicle.VISUAL_LAYER
	# Reflections only: the world's flat ambient light stays as DayNight sets it
	# (the captured street is much darker than that ambient).
	ambient_mode = ReflectionProbe.AMBIENT_DISABLED


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if vehicle:
		_capture()


func _process(dt: float) -> void:
	if vehicle == null:
		return
	_since += dt
	var p := _capture_point()
	if _since >= min_interval and p.distance_squared_to(global_position) > move_threshold * move_threshold:
		_capture()


## Re-centres the probe on the car, which makes Godot render it again.
func _capture() -> void:
	_since = 0.0
	global_transform = Transform3D(Basis.IDENTITY, _capture_point())


func _capture_point() -> Vector3:
	return vehicle.global_position + Vector3.UP * (vehicle.body_top * 0.6 + 0.2)
