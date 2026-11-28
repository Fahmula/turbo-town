class_name PedestrianManager
extends Node3D
## Pedestrians around the players (ART_BIBLE.md §34, "Pedestrians"): spawns
## people on the PedestrianNetwork's sidewalks out of sight near each player,
## takes them away far off, and keeps up to Settings' "pedestrians" count
## (Off / Few / Normal / Busy) shared between split-screen players. Removed
## ones wait in a pool and come back as someone new (a different look, height
## and clothes: PedestrianLook).
##
## Every frame it moves them (Pedestrian.tick) and checks every moving
## vehicle against them: one heading straight at someone makes them hop
## aside, one that touches them knocks them over (unhurt) - vehicles never
## collide with them physically. It also tells them about honks (wave; three
## quick honks and they dance) and stunts (cheer), lets them chat with each
## other, keeps them from walking into each other and into players on foot,
## decides when they may cross (the lights, and nothing coming), and puts the
## ones on a road in TrafficManager.walkers so drivers stop for them.
##
## Steam Deck (§27): one skinned mesh and one material each (one draw call,
## plus shadows); hidden beyond VIEW_END, shadows only inside SHADOW_END, the
## animation every frame up close, 30 Hz, then 15 Hz further off, 4 Hz out of
## view; head turns and gestures (PedestrianPose) only up close.

## Physics layer 5 ("pedestrians"): players on foot collide with it, nothing
## else does.
const LAYER := 16
## Spawn distances (m) from a player: out of sight (round a corner, behind
## a building or the camera) between SPAWN_MIN and SPAWN_MAX, in plain view
## only beyond SEEN_SPAWN_MIN; during a fill (start, teleport) anywhere from
## FILL_MIN. A tight ring keeps the streets round the players busy.
const SPAWN_MIN := 18.0
const SPAWN_MAX := 80.0
const FILL_MIN := 8.0
const SEEN_SPAWN_MIN := 68.0
const DESPAWN := 105.0
## Per graphics level (Low, Medium, High, Ultra): hidden beyond, shadow inside (m).
const VIEW_END := [80.0, 95.0, 110.0, 120.0]
const SHADOW_END := [12.0, 18.0, 30.0, 45.0]
## Animation rate by distance (m): every frame inside ANIM_NEAR, 30 Hz inside
## ANIM_MID, 15 Hz beyond, 4 Hz out of view.
const ANIM_NEAR := 22.0
const ANIM_MID := 50.0
## Head turns and gestures inside POSE_NEAR; "Say hi" inside GREET_NEAR of a
## player on foot; the body that stops players inside BODY_NEAR.
const POSE_NEAR := 20.0
const GREET_NEAR := 10.0
const BODY_NEAR := 25.0
## Beyond this (m) and out of view they move ten times a second.
const FAR_TICK := 60.0
const SPAWN_BUDGET_MS := 2.0
const MAX_BUBBLES := 4

const LINES := {
	"hi": ["Hi there!", "Hello!", "Nice day, isn't it?", "Have you been to the Stunt Park?",
		"The speedboat at the marina is so fast!", "I saw a plane do a loop!", "Love your shirt!",
		"The view from Mountain Top is amazing!", "Hi! Drive safe!", "The lighthouse is lovely at sunset.",
		"Have a great day!", "Hey! Cool car you've got.", "Good to see you!"],
	"honk": ["Hi!", "Hello!", "Beep beep!", "Nice car!", "Hey there!"],
	"dance": ["Party time!", "Woo!", "Dance with me!", "I love this song!"],
	"cheer": ["Wow!", "Awesome!", "Do it again!", "So cool!", "Woo-hoo!", "Amazing!"],
	"dodge": ["Whoa!", "Yikes!", "Eek!", "Watch out!"],
	"bump": ["Hey!", "Oof!", "I'm OK!", "Whoa!", "Careful!"],
	"excuse": ["Excuse me!", "Oops, sorry!", "Pardon me!"],
}

var game: Game
var traffic: TrafficManager
var network: PedestrianNetwork
var max_peds := 18
var enabled := true
## Off: nobody spawns or goes away by themselves (dev tests stage scenes).
var managing := true
var active: Array[Pedestrian] = []
## The players' cameras, positions and characters on foot (this frame).
var cameras: Array[Camera3D] = []
var foci := PackedVector3Array()
var on_foot: Array[Node3D] = []
## Pedestrians made so far (pooled ones are reused).
var made := 0
## Microseconds spent in _process so far (--pedbench), and per part while
## `profile` is on.
var _cost_usec := 0
var profile := false
var cost_parts := {}

var _pool: Array[Pedestrian] = []
var _rng := RandomNumberGenerator.new()
var _fill := true
var _fill_tries := 0
var _last_foci := PackedVector3Array()
var _spawn_timer := 0.0
var _lod_index := 0
var _anim_acc := {}
var _anim_every := {}
var _movers: Array[Vehicle] = []
var _horns := {}
var _speaking: Array[Pedestrian] = []
var _stunt_players := {}
var _player_check := 0.0
var _chatted := {}
var _blocked := {}
var _edge_mid := PackedVector3Array()


func setup(g: Game) -> void:
	game = g
	traffic = g.traffic
	_rng.randomize()
	network = PedestrianNetwork.new()
	network.build(_signal_at)
	for e in network.edges:
		_edge_mid.append(network.point_on(e, e.length * 0.5, true)[0])
	max_peds = Settings.PEDESTRIAN_COUNTS[Settings.get_value("pedestrians")]
	Settings.changed.connect(_on_setting_changed)


func _signal_at(x: float, z: float) -> int:
	if traffic == null or traffic.network == null:
		return -1
	for i in traffic.network.signals.size():
		var p: Vector3 = traffic.network.signals[i]["pos"]
		if absf(p.x - x) < 1.0 and absf(p.z - z) < 1.0:
			return i if traffic.network.signals[i]["signalized"] else -1
	return -1


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "pedestrians":
		set_count(Settings.PEDESTRIAN_COUNTS[int(value)])


## How many may be out at once (0 takes everyone away).
func set_count(n: int) -> void:
	max_peds = n
	if active.size() > n:
		var by_dist := active.duplicate()
		by_dist.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool: return _focus_sq(a.global_position) > _focus_sq(b.global_position))
		for i in active.size() - n:
			_despawn(by_dist[i])
	if n > 0:
		_fill = true
		_fill_tries = n * 6


# ================================================================== frame ==

func _process(dt: float) -> void:
	if network == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame(dt)
	_cost_usec += Time.get_ticks_usec() - t0


func _frame(dt: float) -> void:
	var t := Time.get_ticks_usec()
	_refresh_players()
	t = _part("players", t)
	for p in active:
		# Far off and out of view: ten steps a second is plenty.
		if p.lod_dist > FAR_TICK and not p.lod_seen:
			p.tick_acc += dt
			if p.tick_acc >= 0.1:
				p.tick(p.tick_acc)
				p.tick_acc = 0.0
		else:
			p.tick(dt + p.tick_acc)
			p.tick_acc = 0.0
	t = _part("tick", t)
	_lod_pass()
	t = _part("lod", t)
	_animate(dt)
	t = _part("animate", t)
	_danger()
	t = _part("danger", t)
	_horns_pass()
	_spawn_timer -= dt
	if _fill or _spawn_timer <= 0.0:
		_spawn_timer = 0.25
		_manage()
	_part("manage", t)


func _part(key: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if profile:
		cost_parts[key] = cost_parts.get(key, 0) + now - since
	return now


func _refresh_players() -> void:
	cameras = Views.cameras(self)
	if cameras.is_empty() and get_viewport().get_camera_3d():
		cameras = [get_viewport().get_camera_3d()]
	foci = traffic.focus_positions() if traffic else PackedVector3Array()
	if foci.is_empty():
		for p in game.players:
			if is_instance_valid(p) and p.focus_node():
				foci.append(p.focus_node().global_position)
	on_foot.clear()
	for p in game.players:
		if is_instance_valid(p) and p.possession and p.possession.on_foot() and p.character and p.character.visible:
			on_foot.append(p.character)
	# A teleport (or a player joining far away): fill around the new spot.
	if foci.size() != _last_foci.size():
		_start_fill()
	else:
		for i in foci.size():
			if foci[i].distance_squared_to(_last_foci[i]) > 60.0 * 60.0:
				_start_fill()
				break
	_last_foci = foci.duplicate()
	_player_check -= get_process_delta_time()
	if _player_check <= 0.0:
		_player_check = 1.0
		_watch_stunts()


func _start_fill() -> void:
	_fill = true
	_fill_tries = max_peds * 6


func _focus_sq(p: Vector3) -> float:
	var best := INF
	for f in foci:
		best = minf(best, p.distance_squared_to(f))
	return best


# ============================================================ spawning ==

func _manage() -> void:
	if not managing:
		return
	var want := max_peds if enabled else 0
	for p in active.duplicate():
		var d2 := _focus_sq(p.global_position)
		var seen: bool = p.lod_seen
		if d2 > DESPAWN * DESPAWN or (d2 > (SPAWN_MAX + 10.0) ** 2 and not seen) or active.size() > want:
			if p.state != Pedestrian.State.CROSS or d2 > DESPAWN * DESPAWN:
				_despawn(p)
	if foci.is_empty() or active.size() >= want:
		_fill = false
		return
	var t0 := Time.get_ticks_usec()
	var tries := 6
	while active.size() < want and tries > 0:
		tries -= 1
		if _fill:
			_fill_tries -= 1
		_try_spawn(_fill)
		if Time.get_ticks_usec() - t0 > SPAWN_BUDGET_MS * 1000.0:
			break
	if _fill and (active.size() >= want or _fill_tries <= 0):
		_fill = false


func _try_spawn(fill: bool) -> bool:
	var f := foci[_rng.randi() % foci.size()]
	var lo := FILL_MIN if fill else SPAWN_MIN
	# Sidewalks, corners and paths that reach into the ring around `f`.
	var cands: Array[int] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for e in network.edges:
		if e.kind == PedestrianNetwork.Kind.CROSSING:
			continue
		var d := _edge_mid[e.id].distance_to(f)
		if d - e.length * 0.5 > SPAWN_MAX or d + e.length * 0.5 < lo:
			continue
		cands.append(e.id)
		var w := e.length * (0.4 if e.kind == PedestrianNetwork.Kind.CORNER else 1.0)
		weights.append(w)
		total += w
	if cands.is_empty():
		return false
	var pick := _rng.randf() * total
	var e: PedestrianNetwork.Edge = network.edges[cands[-1]]
	for i in cands.size():
		pick -= weights[i]
		if pick <= 0.0:
			e = network.edges[cands[i]]
			break
	var s := _rng.randf() * e.length
	var p: Vector3 = network.point_on(e, s, true)[0]
	var d := sqrt(_focus_sq(p))
	if d < lo or d > SPAWN_MAX:
		return false
	if not fill and d < SEEN_SPAWN_MIN and _in_sight(p):
		return false
	for o in active:
		if o.global_position.distance_squared_to(p) < 2.5 * 2.5:
			return false
	var ped := _take()
	var fwd := _rng.randf() < 0.5
	ped.spawn(e, s if fwd else e.length - s, fwd)
	active.append(ped)
	_anim_acc[ped] = 0.0
	_lod(ped)
	return true


## Puts one on the street now (dev tests): on the edge nearest `at`.
func spawn_at(at: Vector3, look := "") -> Pedestrian:
	var near := network.nearest(at)
	if near[0] == null:
		return null
	var ped := _take()
	ped.spawn(near[0], near[1], true, look)
	active.append(ped)
	_anim_acc[ped] = 0.0
	_lod(ped)
	return ped


func _take() -> Pedestrian:
	if not _pool.is_empty():
		return _pool.pop_back()
	var p := Pedestrian.new()
	p.name = "Pedestrian%d" % made
	made += 1
	add_child(p)
	p.setup(self)
	return p


func _despawn(p: Pedestrian) -> void:
	p.despawn()
	active.erase(p)
	_speaking.erase(p)
	_anim_acc.erase(p)
	_anim_every.erase(p)
	p.greeter.set_listed(false)
	p.body.collision_layer = 0
	_pool.append(p)


## A camera sees `p` (in its view and not behind a building).
func _in_sight(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for cam in cameras:
		if not is_instance_valid(cam):
			continue
		var head := p + Vector3.UP * 1.3
		if not cam.is_position_in_frustum(head) and not cam.is_position_in_frustum(p + Vector3.UP * 0.2):
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head, 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false


# ======================================================= level of detail ==

## A few each frame, so a full pass takes about eight frames.
func _lod_pass() -> void:
	if active.is_empty():
		return
	var n := maxi(1, ceili(active.size() / 8.0))
	for i in n:
		_lod_index = (_lod_index + 1) % active.size()
		var p := active[_lod_index]
		_lod(p)
		_neighbours(p)


func _lod(p: Pedestrian) -> void:
	var level := clampi(GraphicsQuality.current, 0, 3)
	var pos := p.global_position
	var d := INF
	var seen := false
	for cam in cameras:
		if not is_instance_valid(cam):
			continue
		var dd := cam.global_position.distance_to(pos)
		d = minf(d, dd)
		if dd < VIEW_END[level] and cam.is_position_in_frustum(pos + Vector3.UP):
			seen = true
	p.lod_dist = d
	p.lod_seen = seen
	p.mesh.visible = d < VIEW_END[level]
	p.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < SHADOW_END[level] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var every := 0.0
	if not p.mesh.visible:
		every = INF
	elif not seen:
		every = 0.25
	elif d > ANIM_MID:
		every = 1.0 / 15.0
	elif d > ANIM_NEAR:
		every = 1.0 / 30.0
	_anim_every[p] = every
	p.pose.active = d < POSE_NEAR and p.pose.busy() and p.mesh.visible
	var foot_d := INF
	for c in on_foot:
		foot_d = minf(foot_d, c.global_position.distance_to(pos))
	p.greeter.set_listed(foot_d < GREET_NEAR)
	p.body.collision_layer = LAYER if foot_d < BODY_NEAR else 0
	# People notice a player on foot walking up to them.
	if foot_d < 4.5 and p.state in [Pedestrian.State.WALK, Pedestrian.State.WAIT, Pedestrian.State.PAUSE]:
		for c in on_foot:
			if c.global_position.distance_to(pos) < 4.5 and p.heading().dot((c.global_position - pos).normalized()) > -0.2:
				p.look_at_point(c.global_position + Vector3.UP * 1.6, 0.9)
				p.pose.active = p.mesh.visible
				break


func _animate(dt: float) -> void:
	for p in active:
		var acc: float = _anim_acc.get(p, 0.0) + dt
		var every: float = _anim_every.get(p, 0.0)
		if acc >= every:
			p.advance_anim(acc)
			acc = 0.0
		elif every == INF:
			acc = minf(acc, 1.0)
		_anim_acc[p] = acc


## Keeping out of each other's way (and chatting), and out of players' way.
func _neighbours(p: Pedestrian) -> void:
	if p.state != Pedestrian.State.WALK and p.state != Pedestrian.State.CROSS:
		return
	var pos := p.global_position
	var fwd := p.heading()
	var cap := INF
	for o in active:
		if o == p:
			continue
		var rel := o.global_position - pos
		rel.y = 0.0
		var dd := rel.length_squared()
		if dd > 9.0:
			continue
		var ahead := rel.dot(fwd)
		var side := absf(rel.dot(Vector3(-fwd.z, 0.0, fwd.x)))
		var same := o.heading().dot(fwd)
		if ahead > 0.2 and side < 0.6:
			if same > 0.5 and ahead < 1.6:
				cap = minf(cap, o.path_speed() if o.path_speed() > 0.2 else 0.0)
				if o.path_speed() < 0.2:
					p.sidestep(0.5)          # step round someone standing still
			elif same < -0.4 and ahead < 3.0:
				p.sidestep(0.45)             # keep right of someone coming
				if ahead < 1.8 and p.can_chat() and o.can_chat() and _may_chat(p, o):
					var t := _rng.randf_range(5.0, 9.0)
					p.chat_with(o, t)
					o.chat_with(p, t)
					return
	# Players on foot: stop rather than walk into them, and step round.
	var blocked := false
	for c in on_foot:
		var rel := c.global_position - pos
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		var side := absf(rel.dot(Vector3(-fwd.z, 0.0, fwd.x)))
		if ahead > 0.0 and ahead < 1.9 and side < 0.8:
			cap = 0.0 if ahead < 1.1 else minf(cap, 0.6)
			p.sidestep(0.6)
			blocked = true
	# A car standing on their path (parked on the sidewalk, stopped on the
	# zebra): turn back, or wait on a crossing.
	var probe := pos + fwd * 1.3
	for v: Vehicle in _vehicles():
		if not is_instance_valid(v) or not v.is_inside_tree():
			continue
		var rv := v.global_position - pos
		if rv.x * rv.x + rv.z * rv.z > 64.0 or v.linear_velocity.length_squared() > 1.0:
			continue
		var local := v.global_transform.affine_inverse() * probe
		if absf(local.x) < v.body_half_width + 0.45 and local.z > -v.body_front - 0.45 \
				and local.z < v.body_rear + 0.45 and absf(local.y) < 2.5:
			if p.state == Pedestrian.State.CROSS:
				cap = 0.0
			else:
				p.turn_back()
	if blocked:
		var now := Time.get_ticks_msec() / 1000.0
		if not _blocked.has(p):
			_blocked[p] = now
		elif now - float(_blocked[p]) > 1.5:
			if _rng.randf() < 0.35:
				p.say(line("excuse", p))
			_blocked[p] = now + 5.0           # not again for a while
	else:
		_blocked.erase(p)
	p.set_follow_cap(cap)


func _may_chat(a: Pedestrian, b: Pedestrian) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_chatted.get(a, -100.0)) < 40.0 or now - float(_chatted.get(b, -100.0)) < 40.0:
		return false
	if _rng.randf() > 0.12:
		_chatted[a] = now - 30.0     # not this time; maybe the next person
		return false
	_chatted[a] = now
	_chatted[b] = now
	return true


# ============================================================== vehicles ==

func _vehicles() -> Array:
	if traffic:
		return traffic.vehicles
	var out := []
	for p in game.players:
		if is_instance_valid(p) and p.vehicle:
			out.append(p.vehicle)
	return out


func _is_player_vehicle(v: Vehicle) -> bool:
	for p in game.players:
		if is_instance_valid(p) and p.vehicle == v:
			return true
	return false


## Moving vehicles near any player; for each, everyone it's about to hit hops
## aside and everyone it touches is knocked over.
func _danger() -> void:
	_movers.clear()
	for v: Vehicle in _vehicles():
		if not is_instance_valid(v) or not v.is_inside_tree() or not v.visible:
			continue
		if v.linear_velocity.length_squared() < 1.5 * 1.5:
			continue
		if _focus_sq(v.global_position) > 150.0 * 150.0:
			continue
		_movers.append(v)
	if _movers.is_empty():
		return
	for p in active:
		if p.state == Pedestrian.State.KNOCKED and p.state_time < 0.5:
			continue
		var pos := p.global_position
		for v in _movers:
			var vel := v.linear_velocity
			var sp := vel.length()
			var rel := pos - v.global_position
			var reach := 7.0 + sp * 1.2
			if rel.x * rel.x + rel.z * rel.z > reach * reach or absf(rel.y) > 3.5:
				continue
			var local := v.global_transform.affine_inverse() * pos
			var hw := v.body_half_width + Pedestrian.RADIUS
			if absf(local.x) < hw and local.z > -v.body_front - Pedestrian.RADIUS and local.z < v.body_rear + Pedestrian.RADIUS \
					and local.y > -1.2 and local.y < 2.6:
				_bump(p, v, rel)
				break
			if p.state in [Pedestrian.State.DODGE, Pedestrian.State.KNOCKED]:
				continue
			var flat := Vector3(vel.x, 0.0, vel.z)
			var fsp := flat.length()
			if fsp < 1.5:
				continue
			var dir := flat / fsp
			var rf := Vector3(rel.x, 0.0, rel.z)
			var along := rf.dot(dir)
			if along <= 0.0:
				continue
			var lead := v.body_front if dir.dot(-v.global_basis.z) > 0.0 else v.body_rear
			var t := (along - lead) / fsp
			var player := _is_player_vehicle(v)
			var horizon := 0.95 if player else 0.5
			var lat_v := rf - dir * along
			if t < horizon and t > 0.12 and lat_v.length() < hw + (0.55 if player else 0.2):
				var away := lat_v
				if away.length() < 0.15:
					away = dir.cross(Vector3.UP) * (1.0 if _rng.randf() < 0.5 else -1.0)
				p.dodge(away)
				break


func _bump(p: Pedestrian, v: Vehicle, rel: Vector3) -> void:
	var point_vel := v.linear_velocity + v.angular_velocity.cross(rel)
	point_vel.y = 0.0
	var strength := point_vel.length()
	if strength < 1.0:
		return
	var along := point_vel / strength
	var side := Vector3(rel.x, 0.0, rel.z)
	side -= along * side.dot(along)
	if side.length() < 0.2:
		side = along.cross(Vector3.UP) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var push := point_vel * 0.45 + side.normalized() * (2.5 + strength * 0.3)
	if push.length() > 9.0:
		push = push.normalized() * 9.0
	p.knock(push, strength)


# ============================================================ crossings ==

## The light shows "walk" for this crossing: the traffic it crosses has a red
## and the traffic beside it a green.
func walk_light(e: PedestrianNetwork.Edge) -> bool:
	if e.signal_id < 0 or traffic == null:
		return true
	return traffic.signal_state(e.signal_id, e.axis) == TrafficNetwork.SignalState.RED \
		and traffic.signal_state(e.signal_id, 1 - e.axis) == TrafficNetwork.SignalState.GREEN


## Like pressing the button: ask for the green beside the crossing.
func ask_to_cross(e: PedestrianNetwork.Edge) -> void:
	if e.signal_id >= 0 and traffic:
		traffic.request_signal(e.signal_id, 1 - e.axis)


## Safe to step off now: the walk light with time to get across, and nothing
## driving through the zebra.
func can_cross(e: PedestrianNetwork.Edge, _p: Pedestrian) -> bool:
	if e.signal_id >= 0 and traffic:
		if not walk_light(e) or traffic.green_left(e.signal_id, 1 - e.axis) < 6.0:
			return false
	var z0 := Vector2(e.pts[1].x, e.pts[1].z)
	var z1 := Vector2(e.pts[2].x, e.pts[2].z)
	for v: Vehicle in _vehicles():
		if not is_instance_valid(v) or not v.is_inside_tree():
			continue
		var vel := Vector2(v.linear_velocity.x, v.linear_velocity.z)
		var vp := Vector2(v.global_position.x, v.global_position.z)
		var mid := (z0 + z1) * 0.5
		if vp.distance_to(mid) > 45.0:
			continue
		# Anything on the zebra, or heading across it within 3 s.
		if _seg_dist(vp, z0, z1) < v.body_half_width + 1.2:
			return false
		if vel.length() > 1.0 and Geometry2D.segment_intersects_segment(vp, vp + vel * 3.0, z0, z1) != null:
			return false
	return true


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## On (or off) the road: drivers stop for them while they're on it.
func set_crossing(p: Pedestrian, on: bool) -> void:
	if traffic == null:
		return
	if on and not traffic.walkers.has(p):
		traffic.walkers.append(p)
	elif not on:
		traffic.walkers.erase(p)


# ======================================================== horns, stunts ==

func _horns_pass() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for pl in game.players:
		if not is_instance_valid(pl) or pl.vehicle == null or not pl.possession or not pl.possession.driving():
			continue
		var v := pl.vehicle
		var id := v.get_instance_id()
		var st: Dictionary = _horns.get(id, {"on": false, "presses": []})
		var on := v.horn_input
		if on and not st["on"]:
			var presses: Array = st["presses"]
			presses.append(now)
			while not presses.is_empty() and now - float(presses[0]) > 2.5:
				presses.pop_front()
			_honked(v, presses.size() >= 3)
		st["on"] = on
		_horns[id] = st


func _honked(v: Vehicle, party: bool) -> void:
	var near := _near(v.global_position, 25.0 if party else 32.0)
	var said := 0
	var waved := 0
	for p in near:
		if not p.can_react():
			continue
		if party:
			p.react(Pedestrian.React.DANCE, v.global_position, "dance" if said < 2 else "")
			said += 1
		elif waved < 4:
			p.react(Pedestrian.React.WAVE, v.global_position, "honk" if said < 1 and _rng.randf() < 0.6 else "")
			said += 1
			waved += 1


func _watch_stunts() -> void:
	for pl in game.players:
		if not is_instance_valid(pl) or pl.stunts == null or _stunt_players.has(pl.get_instance_id()):
			continue
		_stunt_players[pl.get_instance_id()] = true
		pl.stunts.combo_banked.connect(_on_combo.bind(pl))


func _on_combo(points: int, _place: int, pl: LocalPlayer) -> void:
	if points < 150 or not is_instance_valid(pl) or pl.vehicle == null:
		return
	cheer_at(pl.vehicle.global_position)


## Everyone who can see it cheers (a stunt at `at`).
func cheer_at(at: Vector3) -> void:
	var n := 0
	for p in _near(at, 50.0):
		if n >= 8:
			break
		if p.can_react():
			p.react(Pedestrian.React.CHEER, at, "cheer" if n < 2 else "")
			n += 1


## Active pedestrians within `r` m of `at`, nearest first.
func _near(at: Vector3, r: float) -> Array[Pedestrian]:
	var out: Array[Pedestrian] = []
	for p in active:
		if p.global_position.distance_squared_to(at) < r * r:
			out.append(p)
	out.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool:
		return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	return out


# ================================================================ speech ==

func line(key: String, _p: Pedestrian) -> String:
	var list: Array = LINES.get(key, [])
	return list[_rng.randi() % list.size()] if not list.is_empty() else ""


## Speech bubbles only near a player, a few at once, never two side by side.
func may_speak(p: Pedestrian) -> bool:
	_speaking = _speaking.filter(func(o: Pedestrian) -> bool: return is_instance_valid(o) and o.speaking())
	if _speaking.has(p):
		return true
	if _speaking.size() >= MAX_BUBBLES or p.lod_dist > 35.0:
		return false
	for o in _speaking:
		if o.global_position.distance_squared_to(p.global_position) < 5.0 * 5.0:
			return false
	return true


func spoke(p: Pedestrian) -> void:
	if not _speaking.has(p):
		_speaking.append(p)
