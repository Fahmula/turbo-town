class_name SeatFigure
extends Node3D
## A player's character sitting in a vehicle, seen through the glass: a copy
## of their model (same clothes) in the driver's or the passenger's seat. The
## driver holds the steering wheel (a pilot the stick), a passenger sits with
## their hands on their thighs. LimbIK fits the arms and legs to each cabin from
## the vehicle's "Seats" settings (Vehicle.seat_hip...), so the feet stay in
## the footwell and the hands on the wheel.
##
## It's a child of the vehicle, not of its Body (whose meshes get dented,
## repainted and merged into far LODs), and copies the Body's roll and pitch
## every tick. Its owner's cockpit camera sits inside its head, so the owner's
## own view leaves it out there (set_own_view_hidden). It casts no shadow: the
## cabin around it is in the vehicle's shadow anyway.
##
## PlayerCharacter keeps one and moves it from vehicle to vehicle (sit_in);
## while on foot it waits, hidden, under the character.

const DRIVE_CLIP := "Driving"
const SIT_CLIP := "Sitting_Idle"
## [root, middle, end] bones of each limb, left (-X) first.
const ARMS := [["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L"], ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R"]]
const LEGS := [["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L"], ["DEF-thigh.R", "DEF-shin.R", "DEF-foot.R"]]
## Where the hands hold the wheel: this far round from the top (degrees;
## 60 = "ten to two").
const GRIP_ANGLE := 62.0
## The wrist sits this far from the grip: toward the driver, out to the side
## and down the rim (m).
const WRIST_BACK := 0.05
const WRIST_OUT := 0.025
const WRIST_DOWN := 0.03
## Ankles: this far out from the middle of the seat and above the heels (m).
const ANKLE_SPREAD := 0.12
const ANKLE_UP := 0.08
## The sitting clip leans forward more than the driving one: a passenger
## leans back this much more (degrees) so both sit against the seat back.
const SIT_LEAN := 15.0
## Hands resting on the thighs: the wrist this far from hip to knee (0..1)
## and this far above the thigh's bone (m).
const LAP_ALONG := 0.55
const LAP_UP := 0.1

## The vehicle it sits in (null while waiting under the character).
var vehicle: Vehicle
var passenger := false

var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _ik: LimbIK
var _body: Node3D
var _meshes: Array[GeometryInstance3D] = []
var _layers := -1
var _clip := ""


## A figure that looks like `source`: the character's Model node (its child
## "Mesh" is the instanced character model, with any clothes overrides).
static func make(source: Node3D) -> SeatFigure:
	var f := SeatFigure.new()
	f.name = "SeatFigure"
	var src := source.get_node_or_null("Mesh") as Node3D
	if src == null or src.scene_file_path == "":
		push_error("SeatFigure: the character model has no Mesh scene")
		return f
	var mesh := (load(src.scene_file_path) as PackedScene).instantiate() as Node3D
	mesh.name = "Mesh"
	mesh.transform = src.transform
	f._model = Node3D.new()
	f._model.name = "Model"
	f._model.add_child(mesh)
	f.add_child(f._model)
	copy_look(src, mesh)
	var players := mesh.find_children("*", "AnimationPlayer", true, false)
	f._anim = players[0] as AnimationPlayer if not players.is_empty() else null
	var skeletons := mesh.find_children("*", "Skeleton3D", true, false)
	f._skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if f._skeleton:
		f._ik = LimbIK.new()
		f._ik.name = "LimbIK"
		f._skeleton.add_child(f._ik)
	for gi in mesh.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		f._meshes.append(g)
	f._set_layers(Vehicle.VISUAL_LAYER)
	f.visible = false
	f.set_physics_process(false)
	return f


## Copies the material overrides (clothes colours) of every mesh under `from`
## to the same mesh under `to` (two instances of one model).
static func copy_look(from: Node, to: Node) -> void:
	for node in from.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var twin := to.get_node_or_null(from.get_path_to(mi)) as MeshInstance3D
		if twin == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			twin.set_surface_override_material(s, mi.get_surface_override_material(s))


## Sits down in `v`: the driver's seat, or the passenger's if `as_passenger`.
func seat(v: Vehicle, as_passenger: bool) -> void:
	if get_parent() != v:
		if get_parent():
			get_parent().remove_child(self)
		v.add_child(self)
	vehicle = v
	passenger = as_passenger
	_body = v.get_node_or_null("Body") as Node3D
	transform = _body.transform if _body else Transform3D.IDENTITY
	reset_physics_interpolation()
	visible = true
	set_physics_process(true)
	if _anim == null or _skeleton == null:
		return
	_anim.active = true
	_play(SIT_CLIP if passenger else DRIVE_CLIP)
	_fit()


## Gets out: waits, hidden and still, under `home` (the character).
func leave(home: Node) -> void:
	vehicle = null
	_body = null
	visible = false
	set_physics_process(false)
	if _anim:
		_anim.active = false
	if get_parent() != home:
		if get_parent():
			get_parent().remove_child(self)
		home.add_child(self)
	transform = Transform3D.IDENTITY


func is_seated() -> bool:
	return vehicle != null and is_inside_tree()


## Leaves it out of its owner's view (their cockpit camera is in its head):
## `view` = the owner's split-screen view (-1 with one player: hidden).
func set_own_view_hidden(hidden: bool, view: int) -> void:
	if hidden and view < 0:
		visible = false
		return
	visible = vehicle != null
	var layers := Vehicle.VISUAL_LAYER
	if hidden:
		layers = 0
		for i in Views.VIEW_LAYERS.size():
			if i != view:
				layers |= Views.VIEW_LAYERS[i]
	_set_layers(layers)


func _set_layers(layers: int) -> void:
	if layers == _layers:
		return
	_layers = layers
	for g in _meshes:
		g.layers = layers


func _physics_process(_dt: float) -> void:
	# Leans with the bodywork (VehicleBodyVisual rolls and pitches the Body).
	if _body:
		transform = _body.transform


func _play(clip: String) -> void:
	var name_found := ""
	for n: String in _anim.get_animation_list():
		if n.to_lower() == clip.to_lower():
			name_found = n
	if name_found == "":
		return
	var a := _anim.get_animation(name_found)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR
	if _clip != name_found:
		_clip = name_found
		_anim.play(name_found, 0.0)
		_anim.seek(0.0, true)


## Places the model so its hips sit on the seat, leaning back with the seat
## back, and aims the arms and legs at the wheel and the footwell.
func _fit() -> void:
	var v := vehicle
	var side := 1.0 if passenger else -1.0  # the seat's side (driver: left, -X)
	var hip := v.seat_hip
	hip.x = absf(hip.x) * side
	# The clip's hip joint, in Model space.
	var mesh_xf := _local_to(_skeleton, _model)
	var hips_bone := _skeleton.find_bone("DEF-hips")
	var hips := mesh_xf * _skeleton.get_bone_global_pose(hips_bone).origin if hips_bone >= 0 else Vector3(0.0, 0.54, 0.31)
	var recline := v.seat_recline + (SIT_LEAN if passenger else 0.0)
	_model.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(recline)), hip) * Transform3D(Basis.IDENTITY, -hips)
	# Skeleton space <-> the figure's (= the vehicle's) space.
	var to_fig := _model.transform * mesh_xf
	var to_skel := to_fig.affine_inverse()
	_ik.chains.clear()
	# The whole body leans back with the seat: the neck and head lean forward
	# again (half each), so the driver looks at the road, not the roof.
	var level_axis := (to_skel.basis * Vector3.RIGHT).normalized()
	_ik.turns.clear()
	for b in ["DEF-neck", "DEF-head"]:
		var i := _skeleton.find_bone(b)
		if i >= 0:
			_ik.turns.append([i, level_axis, -deg_to_rad(recline) * 0.5])

	# Legs: heels on the floor in front of the seat, knees up and a little
	# out. Where the knees end up (for hands resting on the thighs).
	var feet := hip + Vector3(0.0, v.seat_feet.y, v.seat_feet.z)
	var thighs: Array[Vector3] = []
	var knees: Array[Vector3] = []
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var ankle := feet + Vector3(s * ANKLE_SPREAD, ANKLE_UP, 0.0)
		var thigh := to_fig * _bone_pos(LEGS[k][0])
		var shin := to_fig * _bone_pos(LEGS[k][1])
		var foot := to_fig * _bone_pos(LEGS[k][2])
		var pole := (thigh + ankle) * 0.5 + Vector3(s * 0.12, 0.6, -0.25)
		_ik.add_chain(_skeleton, LEGS[k], to_skel * ankle, to_skel * pole)
		thighs.append(thigh)
		knees.append(knee_of(thigh, ankle, pole, thigh.distance_to(shin), shin.distance_to(foot)))

	# Arms: the driver's on the wheel or the stick; a passenger's (and a
	# pilot's free hand) rest on the thighs.
	var wheel := v.steering_wheel
	wheel.x = absf(wheel.x) * side if absf(wheel.x) > 0.01 else wheel.x
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var wrist := Vector3.ZERO
		var pole_dir := Vector3(s * 0.35, -0.4, 0.15)
		if not passenger and v.steering_wheel_radius > 0.0:
			var t := deg_to_rad(v.steering_wheel_tilt)
			var up := Vector3(0.0, cos(t), -sin(t))
			var back := Vector3(0.0, sin(t), cos(t))
			var g := deg_to_rad(GRIP_ANGLE)
			var grip := wheel + Vector3(s * sin(g) * v.steering_wheel_radius, 0.0, 0.0) + up * (cos(g) * v.steering_wheel_radius)
			wrist = grip + back * WRIST_BACK + Vector3(s * WRIST_OUT, 0.0, 0.0) - up * WRIST_DOWN
		elif not passenger and k == 1:
			# A plane's stick: the right hand on the grip.
			wrist = wheel + Vector3(0.03, -0.02, 0.07)
		else:
			# On the thigh, a little past halfway to the knee.
			var along := knees[k] - thighs[k]
			var normal := (Vector3.UP - along.normalized() * along.normalized().y).normalized()
			wrist = thighs[k] + along * LAP_ALONG + normal * LAP_UP + Vector3(-s * 0.02, 0.0, 0.0)
			pole_dir = Vector3(s * 0.3, -0.15, 0.3)
		var shoulder := to_fig * _bone_pos(ARMS[k][0])
		var pole := (shoulder + wrist) * 0.5 + pole_dir
		_ik.add_chain(_skeleton, ARMS[k], to_skel * wrist, to_skel * pole)


## Where a two-bone limb from `root` reaching for `target` bends its middle
## joint, toward `pole` (LimbIK's solution, worked out ahead).
static func knee_of(root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float) -> Vector3:
	var to_t := target - root
	var dir := to_t.normalized()
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var bend := pole - root
	bend = (bend - dir * bend.dot(dir)).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	return root + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))


func _bone_pos(bone_name: String) -> Vector3:
	var i := _skeleton.find_bone(bone_name)
	return _skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


## The transform from `node`'s space to `ancestor`'s (node under ancestor).
static func _local_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
