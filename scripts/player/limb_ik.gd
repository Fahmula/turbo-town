class_name LimbIK
extends SkeletonModifier3D
## Two-bone IK for arms and legs (SeatFigure): bends each limb so its end
## bone (wrist, ankle) reaches a target, with the middle joint (elbow, knee)
## turned toward a pole. Runs after the animation, every time the skeleton
## updates; the end bone keeps its animated angle to the middle bone, so a
## gripping hand stays a gripping hand.
##
## Targets and poles are points in skeleton space (the seat doesn't move
## inside the figure, so they're worked out once when it sits down).

## {"a": root bone, "b": middle bone, "c": end bone, "target": Vector3,
## "pole": Vector3, "short": how far the limb fell short of the target the
## last time (m; negative = it reached with that much to spare)}
var chains: Array[Dictionary] = []
## Extra turns after the limbs, in order: [bone, axis (skeleton space),
## angle (rad)], about the bone's own joint (the head kept level when the
## whole body leans back with the seat).
var turns: Array = []


## Adds a limb by bone names. False if the skeleton lacks one of them.
func add_chain(sk: Skeleton3D, bones: Array, target: Vector3, pole: Vector3) -> bool:
	var a := sk.find_bone(bones[0])
	var b := sk.find_bone(bones[1])
	var c := sk.find_bone(bones[2])
	if a < 0 or b < 0 or c < 0:
		return false
	chains.append({"a": a, "b": b, "c": c, "target": target, "pole": pole, "short": 0.0})
	return true


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for ch in chains:
		_solve(sk, ch)
	for t: Array in turns:
		var bone: int = t[0]
		var parent := sk.get_bone_parent(bone)
		var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var g := Basis(t[1] as Vector3, t[2] as float) * sk.get_bone_global_pose(bone).basis
		sk.set_bone_pose_rotation(bone, (pg.inverse() * g).get_rotation_quaternion())


static func _solve(sk: Skeleton3D, ch: Dictionary) -> void:
	var a: int = ch["a"]
	var b: int = ch["b"]
	var ga := sk.get_bone_global_pose(a)
	var gb := sk.get_bone_global_pose(b)
	var pa := ga.origin
	var pb := gb.origin
	var pc := sk.get_bone_global_pose(ch["c"]).origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	if l1 < 0.001 or l2 < 0.001:
		return
	var to_t: Vector3 = (ch["target"] as Vector3) - pa
	if to_t.length() < 0.001:
		return
	var dir := to_t.normalized()
	ch["short"] = to_t.length() - (l1 + l2)
	# Out of reach: the limb points straight at the target.
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	# The middle joint bends toward the pole, in the plane through the root,
	# the target and the pole.
	var bend: Vector3 = (ch["pole"] as Vector3) - pa
	bend -= dir * bend.dot(dir)
	if bend.length_squared() < 1e-8:
		bend = (pb - pa) - dir * (pb - pa).dot(dir)
		if bend.length_squared() < 1e-8:
			return
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var new_b := pa + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var new_c := pa + dir * d
	# Swing the root bone onto the new middle joint, then the middle bone onto
	# the target.
	var q1 := Quaternion((pb - pa).normalized(), (new_b - pa).normalized())
	var cur_c := pa + q1 * (pc - pa)
	var q2 := Quaternion((cur_c - new_b).normalized(), (new_c - new_b).normalized())
	var ra := Basis(q1) * ga.basis
	var rb := Basis(q2) * Basis(q1) * gb.basis
	var parent := sk.get_bone_parent(a)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(a, (pg.inverse() * ra).get_rotation_quaternion())
	sk.set_bone_pose_rotation(b, (ra.inverse() * rb).get_rotation_quaternion())
