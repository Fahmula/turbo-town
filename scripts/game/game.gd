class_name Game
extends Node3D
## Top-level game flow: spawning/teleporting the player car, respawn after
## falling in the sea, pause, and wiring the HUD to vehicle events.

@export var world: WorldBuilder
@export var vehicle: Vehicle
@export var camera: ChaseCamera
@export var hud: Hud
@export var traffic: TrafficManager

var spawn_index := 0
var _lost_timer := 0.0
var _best_air := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	vehicle.landed.connect(_on_landed)
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
