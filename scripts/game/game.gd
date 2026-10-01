class_name Game
extends Node3D
## Top-level game flow: spawning/teleporting the player car, respawn after
## falling in the sea, pause, the garage (changing vehicle), and wiring the
## HUD to vehicle events.

@export var world: WorldBuilder
@export var vehicle: Vehicle
@export var controller: PlayerVehicleController
@export var camera: ChaseCamera
@export var hud: Hud
@export var traffic: TrafficManager

var spawn_index := 0
var picker: VehiclePicker
## Remember the chosen vehicle between sessions. Off for dev/test runs (they
## pass command-line args) so they always start in the default car.
var persist_choice := OS.get_cmdline_user_args().is_empty()
var settings_path := "user://settings.cfg"
var _lost_timer := 0.0
var _best_air := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	picker = VehiclePicker.new()
	picker.name = "VehiclePicker"
	add_child(picker)
	picker.picked.connect(_on_vehicle_picked)
	picker.cancelled.connect(_close_garage)
	vehicle.landed.connect(_on_landed)
	if persist_choice:
		_load_choice()
	teleport_to(0)


func teleport_to(index: int) -> void:
	if world.spawn_points.is_empty():
		return
	spawn_index = wrapi(index, 0, world.spawn_points.size())
	var sp: Dictionary = world.spawn_points[spawn_index]
	vehicle.teleport(sp["xform"])
	camera.snap()
	hud.show_toast(sp["name"])


func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	# Fell into the sea or off the island: respawn after a moment.
	var p := vehicle.global_position
	var lost := p.y < MapLayout.SEA_LEVEL - 0.8 or p.y < -60.0 or absf(p.x) > 1500.0 or absf(p.z) > 1500.0
	if lost:
		if _lost_timer == 0.0:
			hud.show_popup("SPLASH!" if p.y > -60.0 else "WHOOPS!")
		_lost_timer += dt
		if _lost_timer > 2.0:
			_lost_timer = 0.0
			teleport_to(spawn_index)
	else:
		_lost_timer = 0.0


func _on_landed(airtime: float) -> void:
	if airtime < 1.0:
		return
	var msg := "AIR TIME %.1fs" % airtime
	if airtime > _best_air:
		_best_air = airtime
		if airtime > 2.0:
			msg = "NEW RECORD! %.1fs" % airtime
	if airtime > 3.0:
		msg = "HUGE AIR! " + msg
	hud.show_popup(msg)


func _unhandled_input(event: InputEvent) -> void:
	if picker.is_open:
		return  # the garage reads its own input
	if event.is_action_pressed("change_vehicle"):
		open_garage()
		return
	if event.is_action_pressed("pause"):
		var p := not get_tree().paused
		get_tree().paused = p
		hud.set_paused(p)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		get_tree().quit()
		return
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("respawn"):
		teleport_to(spawn_index)
	elif event.is_action_pressed("teleport_next"):
		teleport_to(spawn_index + 1)
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("toggle_traffic") and traffic:
		traffic.set_enabled(not traffic.enabled)
		hud.show_toast("Traffic ON" if traffic.enabled else "Traffic OFF")
	elif event.is_action_pressed("toggle_units"):
		hud.speedometer.use_mph = not hud.speedometer.use_mph
	elif event.is_action_pressed("toggle_traction_control"):
		vehicle.traction_control = not vehicle.traction_control
		hud.show_toast("Assists ON" if vehicle.traction_control else "Assists OFF - drift mode!")
	else:
		for i in 6:
			if event.is_action_pressed("teleport_%d" % (i + 1)):
				teleport_to(i)
				break


# --- Garage / changing vehicle -------------------------------------------------

func open_garage() -> void:
	get_tree().paused = true
	hud.set_paused(false)
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	picker.open(VehicleCatalog.index_of_vehicle(vehicle), _paint_of(vehicle))


func _close_garage() -> void:
	get_tree().paused = false
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_vehicle_picked(index: int, color: Color) -> void:
	_close_garage()
	if index == VehicleCatalog.index_of_vehicle(vehicle):
		var body := vehicle.get_node_or_null("Body") as VehicleBodyVisual
		if body:
			body.set_paint_color(color)
	else:
		change_vehicle(index, color)
	hud.show_toast(VehicleCatalog.ENTRIES[index]["name"])
	_save_choice(index, color)


## Replaces the player's vehicle with catalog entry `index`, parked upright where
## the old one was (or at the current spawn point if there's no room there).
## With `place_here` false the caller positions it (e.g. a teleport right after).
func change_vehicle(index: int, color: Color, place_here := true) -> void:
	var old := vehicle
	var car := VehicleCatalog.scene(index).instantiate() as Vehicle
	car.traction_control = old.traction_control
	var body := car.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.paint_color = color
	var spot := _find_room(car, old) if place_here else {}

	var slot := old.get_index()
	remove_child(old)
	old.queue_free()
	car.name = "PlayerCar"
	add_child(car)
	move_child(car, slot)
	vehicle = car
	controller.vehicle = car
	camera.set_target(car)
	hud.set_vehicle(car)
	if traffic:
		traffic.set_player(car)
	car.landed.connect(_on_landed)
	if not place_here:
		return
	if spot.is_empty():
		teleport_to(spawn_index)
	else:
		car.teleport(spot["xform"])
		camera.snap()


## Where `car` can be placed in place of `old`: {"xform": Transform3D}, or {} if
## the spot is blocked. Traffic cars in the way are removed; light props
## (cones, crates...) just get pushed aside.
func _find_room(car: Vehicle, old: Vehicle) -> Dictionary:
	var base := old.upright_ground_transform()
	var ride := car.ride_height()
	var space := get_world_3d().direct_space_state
	for lift: float in [0.15, 0.8]:
		var xform := base.translated(Vector3.UP * (ride + lift))
		var in_traffic: Array[Vehicle] = []
		var blocked := false
		for child in car.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = xform * cs.transform
			q.collision_mask = 0b111
			q.exclude = [old.get_rid()]
			for hit in space.intersect_shape(q, 16):
				var col: Object = hit["collider"]
				if traffic and col is Vehicle and traffic.driver_of(col):
					in_traffic.append(col as Vehicle)
				elif not (col is RigidBody3D and (col as RigidBody3D).mass < 400.0):
					blocked = true
		if not blocked:
			for v in in_traffic:
				traffic.remove_vehicle(v)
			return {"xform": xform}
	return {}


func _paint_of(v: Vehicle) -> Color:
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	return body.paint_color if body else Color.RED


func _save_choice(index: int, color: Color) -> void:
	if not persist_choice:
		return
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # keep anything else stored there
	cfg.set_value("player", "vehicle", VehicleCatalog.ENTRIES[index]["id"])
	cfg.set_value("player", "paint", color)
	cfg.save(settings_path)


func _load_choice() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	var index := VehicleCatalog.index_of_id(cfg.get_value("player", "vehicle", ""))
	var color: Color = cfg.get_value("player", "paint", _paint_of(vehicle))
	if index < 0:
		return
	if index == VehicleCatalog.index_of_vehicle(vehicle):
		var body := vehicle.get_node_or_null("Body") as VehicleBodyVisual
		if body:
			body.set_paint_color(color)
	else:
		change_vehicle(index, color, false)
