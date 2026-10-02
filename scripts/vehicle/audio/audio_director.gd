class_name AudioDirector
extends Node
## Keeps traffic sound cheap: only the nearest few traffic vehicles
## (MAX_VOICES, within RANGE metres of the camera) get to play their engine
## and tyre loops; the rest are paused until they come closer. Crashes and
## horns always play (they're short). Also tracks the listener's (camera's)
## velocity for the traffic Doppler shift. Game owns one; without it every
## LITE vehicle just plays.

static var instance: AudioDirector

const MAX_VOICES := 6
const RANGE := 95.0

var listener_velocity := Vector3.ZERO
var _members: Array[VehicleAudio] = []
var _timer := 0.0
var _prev_cam := Vector3.INF


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	VehicleSoundBank.clear()


func register(a: VehicleAudio) -> void:
	if not _members.has(a):
		_members.append(a)
		a.audible = false
		_timer = 0.0


func unregister(a: VehicleAudio) -> void:
	_members.erase(a)


func voiced_count() -> int:
	return _members.filter(func(a: VehicleAudio) -> bool: return a.audible).size()


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pos := cam.global_position
	if _prev_cam != Vector3.INF and dt > 0.0:
		var v := (pos - _prev_cam) / dt
		if v.length() > 90.0:
			v = Vector3.ZERO  # a camera cut or teleport, not motion
		listener_velocity = listener_velocity.lerp(v, 1.0 - exp(-8.0 * dt))
	_prev_cam = pos
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.25
	var by_dist := []
	for a in _members:
		if is_instance_valid(a) and a.vehicle and a.is_inside_tree():
			by_dist.append([a.vehicle.global_position.distance_squared_to(pos), a])
	by_dist.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for i in by_dist.size():
		var a: VehicleAudio = by_dist[i][1]
		a.audible = i < MAX_VOICES and float(by_dist[i][0]) < RANGE * RANGE
