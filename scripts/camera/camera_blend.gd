class_name CameraBlend
extends Camera3D
## Smooth hand-over between two cameras (getting in and out of vehicles):
## takes over from the current camera, glides from where it was to wherever
## the next camera is now (it keeps moving during the blend), then makes the
## next camera current.

signal finished

var blending := false
var _from := Transform3D.IDENTITY
var _from_fov := 70.0
var _to: Camera3D
var _t := 0.0
var _seconds := 0.7


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# After the cameras it blends between have moved this frame.
	process_priority = 100
	far = 3000.0


## Glides from `from` (where it is now) to `to` over `seconds`.
func start(from: Camera3D, to: Camera3D, seconds := 0.7) -> void:
	if from == null or from == to or seconds <= 0.0:
		_finish(to)
		return
	_from = from.global_transform if from != self else global_transform
	_from_fov = from.fov
	_to = to
	_t = 0.0
	_seconds = seconds
	near = to.near
	far = to.far
	global_transform = _from
	fov = _from_fov
	blending = true
	current = true


## Stops a blend in progress and shows its target right away.
func cancel() -> void:
	if blending:
		_finish(_to)


func _process(dt: float) -> void:
	if not blending:
		return
	if _to == null or not is_instance_valid(_to):
		blending = false
		return
	_t = minf(_t + dt / _seconds, 1.0)
	var k := _t * _t * (3.0 - 2.0 * _t)
	var to := _to.global_transform
	global_transform = Transform3D(_from.basis.orthonormalized().slerp(to.basis.orthonormalized(), k), _from.origin.lerp(to.origin, k))
	fov = lerpf(_from_fov, _to.fov, k)
	if _t >= 1.0:
		_finish(_to)


func _finish(to: Camera3D) -> void:
	blending = false
	if to and is_instance_valid(to):
		to.current = true
	finished.emit()
