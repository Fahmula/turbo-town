class_name TrafficManager
extends Node3D
## Ambient AI traffic around the player.
##
## Builds the lane graph from the world's roads, runs the city traffic
## signals, and keeps up to `max_cars` AI cars alive: spawning them out of
## sight near the player and removing ones that are far away or wrecked.
## Traffic cars are ordinary Vehicles with a TrafficDriver instead of a player
## controller, so they crash, dent and flip just like the player's car.

signal traffic_toggled(on: bool)

@export var world: WorldBuilder
@export var player: Vehicle
@export var camera: Camera3D
## Vehicle types that appear in traffic, and how often (relative weights).
@export var car_scenes: Array[PackedScene] = [
	preload("res://scenes/vehicles/sports_car.tscn"),
	preload("res://scenes/vehicles/sedan.tscn"),
	preload("res://scenes/vehicles/van.tscn"),
	preload("res://scenes/vehicles/box_truck.tscn"),
	preload("res://scenes/vehicles/bus.tscn"),
	preload("res://scenes/vehicles/pickup.tscn"),
]
@export var car_weights: Array[float] = [0.18, 0.32, 0.17, 0.11, 0.09, 0.13]
@export var enabled := true
@export var max_cars := 22
@export var spawn_min_distance := 60.0
@export var spawn_max_distance := 260.0
@export var despawn_distance := 330.0
@export var paint_colors: Array[Color] = [
	Color(0.25, 0.55, 0.95), Color(0.98, 0.78, 0.2), Color(0.3, 0.8, 0.45),
	Color(0.95, 0.95, 0.93), Color(0.6, 0.4, 0.9), Color(0.2, 0.22, 0.26),
	Color(1.0, 0.55, 0.2), Color(0.35, 0.85, 0.9), Color(0.95, 0.45, 0.6),
]

var network: TrafficNetwork
var drivers: Array[TrafficDriver] = []
## All vehicles AI should avoid (traffic + player).
var vehicles: Array[Vehicle] = []
var time := 0.0

## Per city intersection signal controller:
## {"green": axis, "phase": 0 green / 1 amber / 2 all-red, "t": seconds in phase,
##  "demand": [last time a car approached on axis 0, axis 1]}
var _signals: Array[Dictionary] = []

const MIN_GREEN := 5.0
const MAX_GREEN := 14.0
const AMBER := 2.5
const ALL_RED := 1.2

var _rng := RandomNumberGenerator.new()
var _horn_was_on := false
var _horn_repeat := 0.0
var _manage_timer := 0.0
var _light_timer := 0.0
var _initial_fill := true


func _ready() -> void:
	_rng.randomize()
	max_cars = Settings.TRAFFIC_CARS[Settings.get_value("traffic_density")]
	Settings.changed.connect(_on_setting_changed)
	if world and not world.is_node_ready():
		await world.ready
	network = TrafficNetwork.new()
	network.build(world.roads)
	for sig in network.signals:
		_signals.append({"green": _rng.randi() % 2, "phase": 0, "t": _rng.randf() * MAX_GREEN, "demand": [-100.0, -100.0]})
	if player:
		var p := player
		player = null
		set_player(p)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key != "traffic_density":
		return
	max_cars = Settings.TRAFFIC_CARS[value]
	# Fewer cars: drop the ones furthest from the player.
	if drivers.size() > max_cars and player:
		var ppos := player.global_position
		var by_dist := drivers.duplicate()
		by_dist.sort_custom(func(a: TrafficDriver, b: TrafficDriver) -> bool:
			return a.vehicle.global_position.distance_squared_to(ppos) > b.vehicle.global_position.distance_squared_to(ppos))
		for i in drivers.size() - max_cars:
			_despawn(by_dist[i])


## Tells traffic which vehicle the player drives (after a vehicle change).
func set_player(v: Vehicle) -> void:
	if player:
		vehicles.erase(player)
		if player.vehicle_reset.is_connected(_on_player_reset):
			player.vehicle_reset.disconnect(_on_player_reset)
	player = v
	if player:
		if not vehicles.has(player):
			vehicles.append(player)
		if not player.vehicle_reset.is_connected(_on_player_reset):
			player.vehicle_reset.connect(_on_player_reset)


# After a teleport/respawn, repopulate around the new position right away.
func _on_player_reset() -> void:
	_initial_fill = enabled


## The traffic driver of `v`, or null if it isn't a traffic vehicle.
func driver_of(v: Object) -> TrafficDriver:
	for d in drivers:
		if d.vehicle == v:
			return d
	return null


## Removes one traffic vehicle right away (e.g. to make room for the player).
func remove_vehicle(v: Vehicle) -> void:
	var d := driver_of(v)
	if d:
		_despawn(d)


func signal_state(id: int, axis: int) -> int:
	if id < 0 or id >= _signals.size() or not network.signals[id]["signalized"]:
		return TrafficNetwork.SignalState.GREEN
	var sg := _signals[id]
	match int(sg["phase"]):
		0:
			return TrafficNetwork.SignalState.GREEN if axis == sg["green"] else TrafficNetwork.SignalState.RED
		1:
			return TrafficNetwork.SignalState.AMBER if axis == sg["green"] else TrafficNetwork.SignalState.RED
	return TrafficNetwork.SignalState.RED


## Called by drivers approaching (or waiting at) a signal.
func request_signal(id: int, axis: int) -> void:
	if id >= 0 and id < _signals.size():
		_signals[id]["demand"][axis] = time


func _update_signals(dt: float) -> void:
	for sg in _signals:
		sg["t"] += dt
		var t: float = sg["t"]
		var g: int = sg["green"]
		match int(sg["phase"]):
			0:
				var demand: Array = sg["demand"]
				var green_busy: bool = time - demand[g] < 2.0
				var other_waiting: bool = time - demand[1 - g] < 1.0
				if other_waiting and ((t > MIN_GREEN and not green_busy) or t > MAX_GREEN):
					sg["phase"] = 1
					sg["t"] = 0.0
			1:
				if t > AMBER:
					sg["phase"] = 2
					sg["t"] = 0.0
			2:
				if t > ALL_RED:
					sg["phase"] = 0
					sg["green"] = 1 - g
					sg["t"] = 0.0


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		for d: TrafficDriver in drivers.duplicate():
			_despawn(d)
	else:
		_initial_fill = true
	traffic_toggled.emit(on)


func _physics_process(dt: float) -> void:
	if network == null:
		return
	time += dt
	_update_signals(dt)
	_check_player_horn(dt)
	_light_timer -= dt
	if _light_timer <= 0.0:
		_light_timer = 0.2
		_update_lights()
	_manage_timer -= dt
	if _manage_timer > 0.0:
		return
	_manage_timer = 0.25
	_despawn_pass()
	if not enabled or player == null:
		return
	if _initial_fill:
		# First fill: spawn a batch at once (visible spawns allowed, not too close).
		_initial_fill = false
		for k in max_cars * 4:
			if drivers.size() >= max_cars:
				break
			_try_spawn(true)
	elif drivers.size() < max_cars:
		for k in 6:
			if _try_spawn(false):
				break


## Drivers near a honking player react (pull over, move right, hurry up).
func _check_player_horn(dt: float) -> void:
	var on := player != null and player.horn_input
	_horn_repeat -= dt
	if on and (not _horn_was_on or _horn_repeat <= 0.0):
		_horn_repeat = 1.5
		var ppos := player.global_position
		for d in drivers:
			if is_instance_valid(d.vehicle) and d.vehicle.global_position.distance_squared_to(ppos) < 40.0 * 40.0:
				d.on_player_horn(player)
	_horn_was_on = on


func _is_visible(p: Vector3) -> bool:
	if camera == null:
		return false
	return camera.global_position.distance_to(p) < 260.0 and camera.is_position_in_frustum(p)


func _despawn_pass() -> void:
	var ppos := player.global_position if player else Vector3.ZERO
	for d: TrafficDriver in drivers.duplicate():
		if not is_instance_valid(d.vehicle):
			drivers.erase(d)
			continue
		var p := d.vehicle.global_position
		var dist := p.distance_to(ppos)
		var remove := dist > despawn_distance or p.y < MapLayout.SEA_LEVEL - 2.0
		if d.state == TrafficDriver.State.LOST:
			remove = remove or not _is_visible(p) or d.state_time > 45.0
		if remove:
			_despawn(d)


func _despawn(d: TrafficDriver) -> void:
	drivers.erase(d)
	vehicles.erase(d.vehicle)
	if is_instance_valid(d.vehicle):
		d.vehicle.queue_free()


func _try_spawn(allow_visible: bool) -> bool:
	var pick := network.random_spawn(_rng)
	if pick.is_empty():
		return false
	var lane: TrafficNetwork.Lane = pick["lane"]
	var s: float = pick["s"]
	var p := lane.point_at(s)
	var ppos := player.global_position
	var dist := p.distance_to(ppos)
	var min_d := 40.0 if allow_visible else spawn_min_distance
	if dist < min_d or dist > spawn_max_distance:
		return false
	if not allow_visible and _is_visible(p):
		return false
	for v in vehicles:
		if is_instance_valid(v) and v.global_position.distance_to(p) < 22.0:
			return false
	_spawn(lane, s)
	return true


func _scene_wheelbase(car: Vehicle) -> float:
	var f := car.get_node_or_null("WheelFL") as Node3D
	var r := car.get_node_or_null("WheelRL") as Node3D
	return absf(f.position.z - r.position.z) if f and r else 2.7


func _pick_scene() -> PackedScene:
	var total := 0.0
	for i in car_scenes.size():
		total += car_weights[i] if i < car_weights.size() else 1.0
	var r := _rng.randf() * total
	for i in car_scenes.size():
		r -= car_weights[i] if i < car_weights.size() else 1.0
		if r <= 0.0:
			return car_scenes[i]
	return car_scenes[0]


func _spawn(lane: TrafficNetwork.Lane, s: float, scene: PackedScene = null) -> TrafficDriver:
	var car := (scene if scene else _pick_scene()).instantiate() as Vehicle
	# Long vehicles can't turn around at dead ends; swap for a small car there.
	if lane.dead_end and _scene_wheelbase(car) > 3.2:
		car.free()
		car = car_scenes[_rng.randi() % 2].instantiate() as Vehicle
	car.name = "Traffic%d" % _rng.randi()
	# Traffic cars stay quiet (the synth is for the player's car) and keep
	# their own damage/effects.
	var audio := car.get_node_or_null("Audio")
	if audio:
		car.remove_child(audio)
		audio.free()
	var body := car.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		var palette: Array[Color] = body.paint_palette if not body.paint_palette.is_empty() else paint_colors
		body.paint_color = palette[_rng.randi() % palette.size()]
	add_child(car)
	var dir := lane.dir_at(s)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	car.teleport(Transform3D(Basis.looking_at(flat, Vector3.UP), lane.point_at(s) + Vector3.UP * (car.wheel_radius() + 0.08)))
	car.linear_velocity = dir * lane.speed * 0.7
	var driver := TrafficDriver.new()
	driver.name = "Driver"
	car.add_child(driver)
	driver.setup(self, lane, s)
	drivers.append(driver)
	vehicles.append(car)
	return driver


## Spawns a specific vehicle on the lane nearest to `pos` (used by dev tools).
func spawn_near(scene: PackedScene, pos: Vector3) -> TrafficDriver:
	var best: TrafficNetwork.Lane = null
	var best_s := 0.0
	var best_d := INF
	for lane in network.lanes:
		if lane.connector:
			continue
		var ls := lane.closest_distance(pos)
		var d := lane.point_at(ls).distance_to(pos)
		if d < best_d:
			best_d = d
			best = lane
			best_s = ls
	return _spawn(best, best_s, scene) if best else null


func _update_lights() -> void:
	for node in get_tree().get_nodes_in_group("traffic_lights"):
		var light := node as TrafficLightProp
		if light and light.intersection_id >= 0:
			light.set_state(signal_state(light.intersection_id, light.axis))
