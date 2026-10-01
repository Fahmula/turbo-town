class_name MenuCamera
extends Camera3D
## Slow orbit around the player's car, shown behind the title screen. Aims a
## little to the left of the car so it sits to the right of the menu column.

var target: Node3D
var radius := 11.0
var height := 3.2
var speed := 0.12
var _angle := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 55.0
	far = 3000.0


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_angle += speed * dt
	var center := target.global_position
	var size := 1.0
	if target is Vehicle:
		size = maxf((target as Vehicle).body_length() / 4.4, 1.0)
	global_position = center + Vector3(cos(_angle) * radius * size, height * size, sin(_angle) * radius * size)
	look_at(center + Vector3.UP * 0.8 * size, Vector3.UP)
	rotate_object_local(Vector3.UP, 0.32)
