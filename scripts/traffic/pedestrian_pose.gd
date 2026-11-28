class_name PedestrianPose
extends SkeletonModifier3D
## After a pedestrian's animation: the head turns toward something (a player
## walking by, a honking car) and the arms wave or cheer, by two-bone IK
## (LimbIK._solve). Inactive (no cost) while it has nothing to do; the
## Pedestrian turns it on only up close (PedestrianManager's level of detail).
##
## Skeleton space is the model's: it faces +Z, up is +Y, its left is +X.

enum Gesture { NONE, WAVE, CHEER }

## Where to look (world space); INF = straight ahead.
var look_target := Vector3.INF
var gesture := Gesture.NONE
## 0..1: how much of the look and the gesture show (eased by the Pedestrian).
var look_weight := 0.0
var gesture_weight := 0.0
var time := 0.0

var _neck := -1
var _head := -1
var _arms: Array[Dictionary] = []       # [left, right] LimbIK chains
var _shoulders := PackedInt32Array()
## The head bone's forward (+Z of the model) in its own frame, at rest.
var _head_fwd := Vector3.BACK

const ARMS := [["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L"], ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R"]]
## Head turn limits (radians): yaw either way, pitch up and down.
const MAX_YAW := 1.25
const MAX_UP := 0.35
const MAX_DOWN := 0.45


func setup(sk: Skeleton3D) -> void:
	_neck = sk.find_bone("DEF-neck")
	_head = sk.find_bone("DEF-head")
	if _head >= 0:
		_head_fwd = sk.get_bone_global_rest(_head).basis.inverse() * Vector3.BACK
	for arm: Array in ARMS:
		var a := sk.find_bone(arm[0])
		_shoulders.append(a)
		_arms.append({"a": a, "b": sk.find_bone(arm[1]), "c": sk.find_bone(arm[2]),
			"target": Vector3.ZERO, "pole": Vector3.ZERO, "short": 0.0})
	active = false


func busy() -> bool:
	return look_weight > 0.001 or gesture_weight > 0.001


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _head < 0:
		return
	if gesture_weight > 0.001 and gesture != Gesture.NONE:
		_gesture(sk)
	if look_weight > 0.001 and look_target != Vector3.INF:
		_look(sk)


func _look(sk: Skeleton3D) -> void:
	var to := sk.global_transform.affine_inverse() * look_target
	var gh := sk.get_bone_global_pose(_head)
	var dir := (to - gh.origin)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var yaw := clampf(atan2(dir.x, dir.z), -MAX_YAW, MAX_YAW)
	var pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), -MAX_DOWN, MAX_UP)
	# Facing straight back is ambiguous: let it go rather than snap.
	var w := look_weight * clampf((2.6 - absf(atan2(dir.x, dir.z))) / 0.6, 0.0, 1.0)
	# What the animation already has the head doing (its forward, flattened).
	var cur := gh.basis * _head_fwd
	var cur_yaw := atan2(cur.x, cur.z)
	var cur_pitch := asin(clampf(cur.y, -1.0, 1.0))
	var dyaw := (yaw - cur_yaw) * w
	var dpitch := (pitch - cur_pitch) * w
	# The neck takes 40% of the turn, the head the rest.
	for pair: Array in [[_neck, 0.4], [_head, 0.6]]:
		var bone: int = pair[0]
		if bone < 0:
			continue
		var k: float = pair[1]
		var r := Basis(Vector3.UP, dyaw * k) * Basis(Vector3.RIGHT, -dpitch * k)
		var g := r * sk.get_bone_global_pose(bone).basis
		var parent := sk.get_bone_parent(bone)
		var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(bone, (pg.inverse() * g).get_rotation_quaternion())


func _gesture(sk: Skeleton3D) -> void:
	var w := gesture_weight
	var t := time
	for side in 2:
		var ch: Dictionary = _arms[side]
		if ch["a"] < 0 or ch["c"] < 0:
			continue
		var out := 1.0 if side == 0 else -1.0     # +X is the left
		var sh := sk.get_bone_global_pose(_shoulders[side]).origin
		var wrist := sk.get_bone_global_pose(ch["c"]).origin
		var elbow := sk.get_bone_global_pose(ch["b"]).origin
		var target: Vector3
		var pole: Vector3
		if gesture == Gesture.WAVE:
			if side == 0:
				continue                              # the right hand waves
			target = sh + Vector3(out * (0.24 + 0.09 * sin(t * TAU * 2.2)), 0.40, 0.12)
			pole = sh + Vector3(out * 0.45, -0.15, -0.05)
		else:
			target = sh + Vector3(out * 0.16, 0.48 + 0.05 * sin(t * TAU * 1.8 + side), 0.06)
			pole = sh + Vector3(out * 0.5, 0.1, -0.1)
		ch["target"] = wrist.lerp(target, w)
		ch["pole"] = elbow.lerp(pole, w) if w < 0.999 else pole
		LimbIK._solve(sk, ch)
