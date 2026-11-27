class_name Pedestrian
extends Node3D
## One person out walking in town (ART_BIBLE.md §34, "Pedestrians").
## PedestrianManager spawns, pools and updates them (tick() every frame,
## advance_anim() at a rate that drops with distance).
##
## They walk the PedestrianNetwork's sidewalks, keeping to the right of its
## line by their own `lane`; stop now and then to look around or chat with
## someone walking by; wait at the kerb for the lights and cross on the zebra
## while the traffic they cross has a red (cars turning across it stop for
## them: they're in TrafficManager.walkers then), hurrying if the lights change.
##
## Kid-safe (§0 rule 8): nobody gets hurt. They hop out of the way of a car
## coming at them; one that bumps them anyway sends them staggering, rolling
## or (fast) flying in a hop that lands on their feet; they say "Hey!" and
## walk back to the sidewalk. Players can say hi on foot (they stop and wave),
## honk (they wave; three honks and they dance) and pull stunts nearby (they
## cheer).
##
## No physics: a Node3D moved along its path each frame. A small static body
## (layer PedestrianManager.LAYER) stops players on foot walking through them;
## vehicles never touch it (the manager does the bumping).

enum State { WALK, WAIT, CROSS, PAUSE, CHAT, GREET, REACT, DODGE, KNOCKED, RETURN }
enum React { WAVE, CHEER, DANCE, LOOK }

## Natural ground speed of each clip (m/s at speed_scale 1), as the player's.
const CLIP_SPEED := {"Walk": 1.45, "Walk_Formal": 1.35, "Jog_Fwd": 4.0, "Sprint": 6.4}
const GRAVITY := 12.0
const TURN_RATE := 7.0
const RADIUS := 0.28

var manager: PedestrianManager
var net: PedestrianNetwork

var state := State.WALK
var state_time := 0.0
## Who they are (PedestrianLook.dress).
var who := {}
var jogger := false
var formal := false

# --- On the network ---
var edge: PedestrianNetwork.Edge
## Walking edge from its a end (true) or its b end.
var from_a := true
## Metres along the edge in the direction of travel.
var s := 0.0
## How far to the right of the line they keep (m); negative = left.
var lane := 0.3
var walk_speed := 1.4
var speed := 0.0
## An extra sideways step (m) to pass someone coming the other way.
var _sidestep := 0.0
## Speed limit from someone slow ahead (m/s; INF = none).
var _follow_cap := INF

# --- Body ---
var facing := 0.0
var _vel := Vector3.ZERO
var _vy := 0.0
var _airborne := false
var _ground := 0.15
var _seconds := 0.0
var _next_pause := 0.0
var _crossed_light := false

# --- Model ---
var model: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var anim: AnimationPlayer
var pose: PedestrianPose
var body: StaticBody3D
var greeter: PedestrianGreet
var _clip := ""
var _anim_speed := 1.0
## Set by the manager's level of detail: distance to the nearest camera, and
## whether any camera sees them.
var lod_dist := INF
var lod_seen := false
## Time waiting for the next tick (far off: PedestrianManager.FAR_TICK).
var tick_acc := 0.0

# --- Reactions ---
var _react := React.WAVE
var _react_len := 0.0
var _face_to := Vector3.INF
var _partner: Pedestrian
var _bubble: Label3D
var _bubble_time := 0.0
## Counters for the dev test.
var greeted_count := 0
var horn_reactions := 0
var dodged_count := 0
var knocked_count := 0
var cheer_count := 0
var dance_count := 0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Builds the model and body (once; the manager pools pedestrians).
func setup(m: PedestrianManager) -> void:
	manager = m
	net = m.network
	_rng.randomize()
	var parts := PedestrianLook.build(self)
	model = parts["model"]
	skeleton = parts["skeleton"]
	mesh = parts["mesh"]
	anim = parts["anim"]
	pose = PedestrianPose.new()
	pose.name = "Pose"
	skeleton.add_child(pose)
	pose.setup(skeleton)
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PedestrianManager.LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3.UP * 0.85
	body.add_child(cs)
	add_child(body)
	greeter = PedestrianGreet.new()
	greeter.name = "Greet"
	greeter.ped = self
	greeter.position = Vector3.UP * 0.9
	add_child(greeter)


## Puts them on `e`, `at` m along it walking from its a end or not, as someone new.
func spawn(e: PedestrianNetwork.Edge, at: float, forward: bool, only_look := "") -> void:
	who = PedestrianLook.dress(mesh, model, _rng, only_look)
	jogger = who["jog"]
	formal = who["formal"]
	var tall: float = who["height"] / PedestrianLook.MODEL_HEIGHT
	if jogger:
		walk_speed = _rng.randf_range(2.6, 3.3)
	else:
		walk_speed = _rng.randf_range(1.15, 1.55) * lerpf(1.0, tall, 0.5) * (0.85 if who["old"] else 1.0)
	lane = _rng.randf_range(0.1, 0.55) if _rng.randf() < 0.75 else _rng.randf_range(-0.45, 0.1)
	edge = e
	from_a = forward
	s = at
	speed = walk_speed
	_sidestep = 0.0
	_follow_cap = INF
	_partner = null
	_face_to = Vector3.INF
	_airborne = false
	_vel = Vector3.ZERO
	_seconds = 0.0
	_next_pause = _rng.randf_range(15.0, 60.0)
	greeted_count = 0
	horn_reactions = 0
	dodged_count = 0
	knocked_count = 0
	cheer_count = 0
	dance_count = 0
	var at_pt := _path_point()
	global_position = at_pt[0]
	facing = _yaw_of(at_pt[1])
	rotation.y = facing
	_ground = global_position.y
	_set_state(State.WALK)
	_clip = ""
	_walk_clip(0.0)
	anim.seek(_rng.randf() * anim.current_animation_length, true)
	pose.look_weight = 0.0
	pose.gesture_weight = 0.0
	pose.gesture = PedestrianPose.Gesture.NONE
	pose.active = false
	_hide_bubble()
	visible = true


## Taken off the street (back to the pool).
func despawn() -> void:
	manager.set_crossing(self, false)
	_partner = null
	_hide_bubble()
	visible = false


func _set_state(st: State) -> void:
	if state == State.CROSS and st != State.CROSS:
		manager.set_crossing(self, false)
	if state == State.RETURN and st != State.RETURN:
		manager.set_crossing(self, false)
	state = st
	state_time = 0.0


# ================================================================== update ==

func tick(dt: float) -> void:
	state_time += dt
	_seconds += dt
	if _bubble_time > 0.0:
		_bubble_time -= dt
		if _bubble_time <= 0.0:
			_hide_bubble()
	match state:
		State.WALK, State.CROSS:
			_walk(dt)
		State.WAIT:
			_wait(dt)
		State.PAUSE:
			_stand(dt, 6.0)
			if state_time > _react_len:
				_resume()
		State.CHAT:
			_stand(dt, 6.0)
			if state_time > _react_len or not is_instance_valid(_partner) or _partner.state != State.CHAT:
				_resume()
		State.GREET:
			_stand(dt, 8.0)
			pose.gesture_weight = _ease(state_time, 0.25, 2.2, 0.35)
			if state_time > 3.2:
				_resume()
		State.REACT:
			_reacting(dt)
		State.DODGE, State.KNOCKED:
			_airborne_move(dt)
		State.RETURN:
			_return(dt)
	pose.time += dt
	if pose.look_weight > 0.0 and state in [State.WALK, State.CROSS] and _face_to == Vector3.INF:
		pose.look_weight = maxf(pose.look_weight - dt * 2.0, 0.0)


func _resume() -> void:
	_face_to = Vector3.INF
	_partner = null
	pose.gesture = PedestrianPose.Gesture.NONE
	pose.gesture_weight = 0.0
	if edge.kind == PedestrianNetwork.Kind.CROSSING and s < 0.2:
		# Stopped while waiting at the kerb: back to waiting for the lights.
		_set_state(State.WAIT)
		play("Idle", 0.3, 1.0)
		return
	_set_state(State.CROSS if edge.kind == PedestrianNetwork.Kind.CROSSING else State.WALK)
	_walk_clip(0.3)


# --------------------------------------------------------------- walking --

func _walk(dt: float) -> void:
	var target := walk_speed
	if state == State.CROSS and _crossed_light:
		target = maxf(walk_speed, 2.6)                 # the lights changed: hurry
	target = minf(target, _follow_cap)
	speed = move_toward(speed, target, dt * (3.0 if target > speed else 4.0))
	s += speed * dt
	_sidestep = move_toward(_sidestep, 0.0, dt * 0.25)
	if state == State.CROSS and not _crossed_light and edge.signal_id >= 0:
		if not manager.walk_light(edge):
			_crossed_light = true
	while s >= edge.length:
		s -= edge.length
		if not _arrive():
			return
	var pt := _path_point()
	var p: Vector3 = pt[0]
	var k := 1.0 - exp(-dt * 7.0)
	var cur := global_position
	var nxt := Vector3(lerpf(cur.x, p.x, k), lerpf(cur.y, p.y, 1.0 - exp(-dt * 10.0)), lerpf(cur.z, p.z, k))
	var moved := nxt - cur
	moved.y = 0.0
	global_position = nxt
	if moved.length_squared() > 0.000001:
		_turn_to(_yaw_of(moved), dt)
	_walk_clip(0.25)
	if state == State.WALK and edge.kind == PedestrianNetwork.Kind.SIDEWALK and _seconds > _next_pause and not jogger:
		_next_pause = _seconds + _rng.randf_range(25.0, 80.0)
		_pause(_rng.randf_range(2.5, 6.0))


## The path point at s (with the lane and any sidestep): [position, direction].
func _path_point() -> Array:
	var pd := net.point_on(edge, s, from_a)
	var dir: Vector3 = pd[1]
	var right := Vector3(-dir.z, 0.0, dir.x)
	pd[0] = (pd[0] as Vector3) + right * (lane * edge.spread + _sidestep)
	return pd


## Reached the end of the edge: on to the next one. False if they stopped.
func _arrive() -> bool:
	var node := net.end_node(edge, from_a)
	var came := edge
	if came.kind == PedestrianNetwork.Kind.CROSSING:
		manager.set_crossing(self, false)
		_crossed_light = false
	var next := _choose(node, came)
	if next == null:
		# Nowhere else: turn round.
		from_a = not from_a
		s = 0.0
		return true
	edge = next
	from_a = next.a == node
	s = 0.0
	if next.kind == PedestrianNetwork.Kind.CROSSING:
		_set_state(State.WAIT)
		_crossed_light = false
		play("Idle", 0.3, 1.0)
		speed = 0.0
		return false
	if state == State.CROSS:
		_set_state(State.WALK)
	return true


## The next edge at `node`, arriving by `came`: mostly onward, rarely back.
func _choose(node: int, came: PedestrianNetwork.Edge) -> PedestrianNetwork.Edge:
	var heading := Vector3(sin(facing + PI), 0.0, cos(facing + PI))
	var options: Array[PedestrianNetwork.Edge] = []
	var weights: Array[float] = []
	var total := 0.0
	var at_tip := false
	for id in net.adj[node]:
		if net.edges[id].kind == PedestrianNetwork.Kind.CROSSING:
			at_tip = true
	for id in net.adj[node]:
		var e := net.edges[id]
		if e == came:
			continue
		var fwd := e.a == node
		var dir: Vector3 = net.point_on(e, 0.3, fwd)[1]
		var w := e.weight
		if at_tip:
			var crossing := e.kind == PedestrianNetwork.Kind.CROSSING
			if came.kind == PedestrianNetwork.Kind.CROSSING:
				w = 0.12 if crossing else 1.0      # just crossed: on along the sidewalk
			else:
				w = 1.0 if crossing else 0.12      # came out to the tip to cross: mostly do
			if jogger and crossing:
				w *= 0.5
		else:
			var d := heading.dot(dir)
			w *= 0.25 + 1.75 * clampf(d * 0.5 + 0.5, 0.0, 1.0) ** 2   # keep going the same way
		if w <= 0.0:
			continue
		options.append(e)
		weights.append(w)
		total += w
	if options.is_empty():
		return came if came.kind != PedestrianNetwork.Kind.CROSSING else null
	var pick := _rng.randf() * total
	for i in options.size():
		pick -= weights[i]
		if pick <= 0.0:
			return options[i]
	return options[-1]


func _wait(dt: float) -> void:
	_stand(dt, 5.0)
	var dir: Vector3 = net.point_on(edge, 1.5, from_a)[1]
	_turn_to(_yaw_of(dir), dt)
	if fmod(state_time, 0.25) < dt:
		manager.ask_to_cross(edge)
		if manager.can_cross(edge, self):
			_set_state(State.CROSS)
			manager.set_crossing(self, true)
			speed = walk_speed * 0.5
			_walk_clip(0.25)
			return
	if state_time > 45.0:
		# Given up waiting: back along the sidewalk.
		var node := edge.a if from_a else edge.b
		var back: PedestrianNetwork.Edge = null
		for id in net.adj[node]:
			if net.edges[id].kind != PedestrianNetwork.Kind.CROSSING:
				back = net.edges[id]
				break
		if back == null:
			state_time = 0.0
			return
		edge = back
		from_a = back.a == node
		s = 0.0
		_set_state(State.WALK)


func _walk_clip(blend: float) -> void:
	var clip := "Walk"
	if jogger and state != State.CROSS:
		clip = "Jog_Fwd"
	elif state == State.CROSS and _crossed_light:
		clip = "Jog_Fwd"
	elif formal:
		clip = "Walk_Formal"
	elif state == State.RETURN and speed > 2.2:
		clip = "Jog_Fwd"
	if speed < 0.3 and state != State.RETURN:
		play("Idle", 0.3, 1.0)               # held up: stand, don't walk on the spot
		return
	var scale_by := model.scale.x
	play(clip, blend, clampf(speed / (CLIP_SPEED[clip] * scale_by), 0.5, 1.6))


# --------------------------------------------------------------- standing --

func _stand(dt: float, turn: float) -> void:
	speed = 0.0
	_settle_y(dt)
	if _face_to != Vector3.INF:
		var to := _face_to - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			_turn_to(_yaw_of(to), dt * turn / TURN_RATE)


func _pause(seconds: float) -> void:
	_set_state(State.PAUSE)
	_react_len = seconds
	play("Idle", 0.35, 1.0)
	# Look at something: a shop window, the street, someone.
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var ahead := Vector3(sin(facing + PI), 0.0, cos(facing + PI))
	var right := Vector3(-ahead.z, 0.0, ahead.x)
	look_at_point(global_position + (ahead * 2.0 + right * side * 3.0) + Vector3.UP * 1.5, 1.0)


## Stops to chat with `other` (who stops too).
func chat_with(other: Pedestrian, seconds: float) -> void:
	_partner = other
	_face_to = other.global_position
	_react_len = seconds
	_set_state(State.CHAT)
	play("Idle_Talking", 0.35, 1.0)
	look_at_point(other.global_position + Vector3.UP * 1.6, 1.0)


func can_chat() -> bool:
	return state == State.WALK and not jogger and edge.kind == PedestrianNetwork.Kind.SIDEWALK and _seconds > 6.0


## Free to stop and react to something (not crossing, dodging or tumbling).
func can_react() -> bool:
	return state in [State.WALK, State.PAUSE, State.WAIT, State.CHAT, State.REACT] and visible


func look_at_point(p: Vector3, weight: float) -> void:
	pose.look_target = p
	pose.look_weight = weight


## A player on foot said hi.
func greet(actor: Node3D) -> void:
	if not can_greet():
		return
	_face_to = actor.global_position
	_set_state(State.GREET)
	play("Idle", 0.3, 1.0)
	pose.gesture = PedestrianPose.Gesture.WAVE
	pose.time = 0.0
	look_at_point(actor.global_position + Vector3.UP * 1.6, 1.0)
	greeted_count += 1
	say(manager.line("hi", self))


func can_greet() -> bool:
	return state in [State.WALK, State.PAUSE, State.WAIT, State.CHAT] and visible


## Something happened nearby: wave (a honk), cheer (a stunt), dance (lots of
## honking) or just look (at `from`).
func react(kind: React, from: Vector3, line_key := "") -> void:
	if not can_react():
		return
	_react = kind
	_face_to = from
	_set_state(State.REACT)
	pose.time = _rng.randf()
	look_at_point(from + Vector3.UP * 1.0, 1.0)
	match kind:
		React.WAVE:
			_react_len = 2.2
			play("Idle", 0.3, 1.0)
			pose.gesture = PedestrianPose.Gesture.WAVE
			horn_reactions += 1
		React.CHEER:
			_react_len = 2.8
			play("Idle", 0.3, 1.0)
			pose.gesture = PedestrianPose.Gesture.CHEER
			cheer_count += 1
		React.DANCE:
			_react_len = _rng.randf_range(4.0, 5.5)
			play("Dance", 0.3, 1.0)
			pose.gesture = PedestrianPose.Gesture.NONE
			horn_reactions += 1
			dance_count += 1
		React.LOOK:
			_react_len = 1.6
			play("Idle", 0.3, 1.0)
			pose.gesture = PedestrianPose.Gesture.NONE
	if line_key != "":
		say(manager.line(line_key, self))


func _reacting(dt: float) -> void:
	_stand(dt, 7.0 if _react != React.DANCE else 2.0)
	if pose.gesture != PedestrianPose.Gesture.NONE:
		pose.gesture_weight = _ease(state_time, 0.2, _react_len - 0.35, 0.3)
	if state_time > _react_len:
		_resume()


# ----------------------------------------------------- dodging and bumps --

## A vehicle is about to hit them: hop out of its way, toward `away` (flat).
func dodge(away: Vector3) -> void:
	if state in [State.DODGE, State.KNOCKED]:
		return
	manager.set_crossing(self, true)
	away.y = 0.0
	away = away.normalized()
	_vel = away * 3.6
	_vy = 3.4
	_airborne = true
	_set_state(State.DODGE)
	_face_to = Vector3.INF
	pose.gesture_weight = 0.0
	play("Jump", 0.08, 1.0)
	dodged_count += 1
	if _rng.randf() < 0.5:
		say(manager.line("dodge", self))


## A vehicle bumped them: `push` (m/s, flat) and how hard it hit (m/s).
func knock(push: Vector3, strength: float) -> void:
	if state == State.KNOCKED and state_time < 0.5:
		return
	manager.set_crossing(self, true)
	push.y = 0.0
	knocked_count += 1
	_set_state(State.KNOCKED)
	_face_to = Vector3.INF
	pose.gesture_weight = 0.0
	pose.look_weight = 0.0
	_vel = push
	if strength < 5.0:
		_vy = 0.0
		_airborne = false
		_react_len = 0.75
		play("Hit_Chest", 0.05, 1.0)
	elif strength < 13.0:
		_vy = 0.0
		_airborne = false
		_react_len = 1.4
		facing = _yaw_of(push)
		rotation.y = facing
		play("Roll", 0.05, 1.0)
		anim.seek(0.0, true)
	else:
		_vy = clampf(3.0 + strength * 0.12, 3.0, 5.5)
		_airborne = true
		_react_len = 0.0
		play("Jump", 0.05, 1.0)
	say(manager.line("bump", self))


func _airborne_move(dt: float) -> void:
	var p := global_position + _vel * dt
	var g := net.ground_y(p.x, p.z)
	if _airborne:
		_vy -= GRAVITY * dt
		p.y += _vy * dt
		if p.y <= g and _vy < 0.0:
			p.y = g
			_airborne = false
			_vel *= 0.35
			play("Jump_Land", 0.05, 1.3)
			_react_len = state_time + 0.45
	else:
		p.y = lerpf(p.y, g, 1.0 - exp(-dt * 12.0))
		var drag := 3.0 if state == State.KNOCKED and _clip == "Roll" else 7.0
		_vel = _vel.move_toward(Vector3.ZERO, dt * drag)
	global_position = p
	if not _airborne and state_time > _react_len:
		_start_return()


## Walk (or jog, off the road) back to the nearest sidewalk.
func _start_return() -> void:
	var near := net.nearest(global_position)
	if near[0] == null:
		_set_state(State.WALK)
		return
	var e: PedestrianNetwork.Edge = near[0]
	var d: float = near[1]
	# Carry on along it the way they were facing.
	var ahead := Vector3(sin(facing + PI), 0.0, cos(facing + PI))
	var dir: Vector3 = net.point_on(e, d, true)[1]
	edge = e
	from_a = ahead.dot(dir) >= 0.0
	s = d if from_a else e.length - d
	_sidestep = 0.0
	_set_state(State.RETURN)
	manager.set_crossing(self, net.ground_y(global_position.x, global_position.z) < 0.05)


func _return(dt: float) -> void:
	var p: Vector3 = _path_point()[0]
	var to := p - global_position
	to.y = 0.0
	var on_road := net.ground_y(global_position.x, global_position.z) < 0.05
	speed = move_toward(speed, 2.4 if on_road else walk_speed, dt * 3.0)
	var step := minf(speed * dt, to.length())
	if to.length() < 0.15 or state_time > 12.0:
		_set_state(State.WALK)
		return
	var move := to.normalized() * step
	global_position += move
	_settle_y(dt)
	_turn_to(_yaw_of(move), dt)
	_walk_clip(0.25)


# ------------------------------------------------------------------ bits --

func _settle_y(dt: float) -> void:
	var g := net.ground_y(global_position.x, global_position.z)
	global_position.y = lerpf(global_position.y, g, 1.0 - exp(-dt * 10.0))


func _turn_to(yaw: float, dt: float) -> void:
	facing = rotate_toward(facing, yaw, TURN_RATE * dt)
	rotation.y = facing


## Yaw that faces -Z along `dir`.
static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## 0 -> 1 over `rise` s, held until `hold`, back to 0 over `fall` s.
static func _ease(t: float, rise: float, hold: float, fall: float) -> float:
	if t < rise:
		return smoothstep(0.0, rise, t)
	if t < hold:
		return 1.0
	return 1.0 - smoothstep(hold, hold + fall, t)


func heading() -> Vector3:
	return Vector3(sin(facing + PI), 0.0, cos(facing + PI))


## Moving along the path at what speed (m/s, 0 when stopped).
func path_speed() -> float:
	return speed if state in [State.WALK, State.CROSS] else 0.0


func set_follow_cap(cap: float) -> void:
	_follow_cap = cap


## Something's in the way (a car parked on the sidewalk): back the way they came.
func turn_back() -> void:
	if state != State.WALK or state_time < 2.0:
		return
	from_a = not from_a
	s = edge.length - s
	state_time = 0.0


func sidestep(amount: float) -> void:
	_sidestep = clampf(_sidestep + amount, -0.9, 0.9)


# ------------------------------------------------------------- animation --

func play(clip: String, blend := 0.2, speed_scale := 1.0) -> void:
	if clip != _clip:
		anim.play(clip, blend)
		_clip = clip
	_anim_speed = speed_scale
	anim.speed_scale = speed_scale


## Called by the manager when this one's animation is due (dt = time since
## the last advance).
func advance_anim(dt: float) -> void:
	anim.advance(dt)


# ---------------------------------------------------------------- speech --

## A speech bubble over their head for a few seconds (only near a player).
func say(text: String) -> void:
	if text == "" or not manager.may_speak(self):
		return
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.name = "Bubble"
		_bubble.font = UiKit.display_font()
		_bubble.font_size = 44
		_bubble.outline_size = 12
		_bubble.modulate = Color(1, 1, 1)
		_bubble.outline_modulate = UiKit.OUTLINE
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.fixed_size = true
		_bubble.pixel_size = 0.0009
		_bubble.render_priority = 10
		_bubble.outline_render_priority = 9
		_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bubble.width = 600.0
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_bubble)
	_bubble.text = text
	_bubble.position = Vector3.UP * (who.get("height", 1.75) + 0.45)
	_bubble.visible = true
	_bubble_time = clampf(1.6 + text.length() * 0.06, 2.0, 4.0)
	manager.spoke(self)


func _hide_bubble() -> void:
	_bubble_time = 0.0
	if _bubble:
		_bubble.visible = false


func speaking() -> bool:
	return _bubble != null and _bubble.visible
