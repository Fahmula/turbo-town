extends Node
## Scripted driving scenarios for tuning, run from the command line, e.g.
##   godot --path . --headless --fixed-fps 120 res://scenes/dev/physics_test.tscn -- --autotest=accel
## Does nothing unless --autotest=<name> is passed.

@export var vehicle: Vehicle

var _scenario := ""
var _t := 0.0
var _log_t := 0.0
var _max_air := 0.0
var _max_roll := 0.0
var _start_pos := Vector3.ZERO
var _phase := 0
var _phase_t := 0.0
var _mark := Vector3.ZERO


func _ready() -> void:
	var vehicle_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			_scenario = arg.split("=")[1]
		elif arg.begins_with("--vehicle="):
			vehicle_path = arg.split("=")[1]
	if _scenario == "":
		set_physics_process(false)
		return
	if vehicle_path != "":
		set_physics_process(false)
		await _swap_vehicle(vehicle_path)
		set_physics_process(true)
	print("AUTOTEST scenario=", _scenario)
	if _scenario == "jump":
		vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(-40, 1, 0)))
	if _scenario == "rollover":
		var ramp := preload("res://scenes/props/ramp.tscn").instantiate() as Ramp
		ramp.shape = Ramp.RampShape.WEDGE
		ramp.length = 6.0
		ramp.height = 2.2
		ramp.width = 2.0
		# Only the left wheels hit it: rolls the car to the right.
		ramp.position = Vector3(-0.9, 0, -60)
		get_parent().add_child.call_deferred(ramp)
	vehicle.landed.connect(func(a: float) -> void: print("  landed after %.2fs air" % a))
	vehicle.impact.connect(func(s: float, _p: Vector3, _n: Vector3) -> void: print("  impact %.0f at t=%.2f" % [s, _t]))


## Replaces the test car with another vehicle scene (e.g. --vehicle=res://scenes/vehicles/bus.tscn).
func _swap_vehicle(path: String) -> void:
	await get_tree().process_frame  # the scene is still being set up during _ready
	var old := vehicle
	var nv := (load(path) as PackedScene).instantiate() as Vehicle
	nv.transform = old.transform
	old.get_parent().add_child(nv)
	old.queue_free()
	vehicle = nv
	for node in get_parent().get_children():
		if node is PlayerVehicleController:
			(node as PlayerVehicleController).vehicle = nv
		elif node is ChaseCamera:
			(node as ChaseCamera).set_target(nv)
	await get_tree().physics_frame
	print("AUTOTEST vehicle=%s mass=%.0f wheelbase=%.2f length=%.2f width=%.2f" % [
		nv.display_name, nv.mass, nv.wheelbase, nv.body_length(), nv.body_half_width * 2.0])


func _press(action: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _physics_process(dt: float) -> void:
	_t += dt
	_phase_t += dt
	if _t < 0.05:
		_start_pos = vehicle.global_position
	var roll := rad_to_deg(asin(clampf(vehicle.global_basis.x.y, -1, 1)))
	_max_roll = maxf(_max_roll, absf(roll))
	_max_air = maxf(_max_air, vehicle.airtime)
	match _scenario:
		"rest":
			if _t > 4.0:
				_finish()
		"accel":
			_press("accelerate", _t > 1.0)
			if _t > 16.0:
				_finish()
		"turn":
			_press("accelerate", _t > 1.0 and vehicle.speed_kmh < 70.0)
			_press("steer_right", _t > 7.0)
			if _t > 16.0:
				_finish()
		"fastturn":
			_press("accelerate", _t > 1.0 and vehicle.speed_kmh < 120.0)
			_press("steer_left", _t > 10.0)
			if _t > 18.0:
				_finish()
		"brake":
			if _phase == 0:
				_press("accelerate", true)
				if vehicle.speed_kmh > 100.0:
					_press("accelerate", false)
					_phase = 1
					_phase_t = 0.0
					_mark = vehicle.global_position
					print("  braking from %.1f km/h" % vehicle.speed_kmh)
			elif _phase == 1:
				_press("brake", true)
				if vehicle.speed_kmh < 1.0 or vehicle.gear == -1:
					print("  stopped in %.2fs over %.1fm" % [_phase_t, vehicle.global_position.distance_to(_mark)])
					_press("brake", false)
					_phase = 2
					_phase_t = 0.0
			elif _phase == 2:
				_press("brake", true)  # now reverse
				if _phase_t > 4.0:
					_finish()
		"handbrake":
			_press("accelerate", _t > 1.0 and _t < 7.0)
			_press("steer_left", _t > 7.0 and _t < 9.0)
			_press("handbrake", _t > 7.0 and _t < 8.0)
			if _t > 12.0:
				_finish()
		"jump":
			_press("accelerate", _t > 1.0 and vehicle.speed_kmh < 95.0)
			if _t > 14.0:
				_finish()
		"rollover":
			# Hit a sideways-tilted ramp at speed with one side of the car.
			_press("accelerate", _t > 0.5 and _t < 6.0 and vehicle.speed_kmh < 75.0)
			if _t > 9.0 and _phase == 0:
				print("  before reset: up.y=%.2f upside_down_time=%.1f" % [vehicle.global_basis.y.y, vehicle.upside_down_time])
				vehicle.reset_upright()
				_phase = 1
			if _t > 11.0:
				print("  after reset: up.y=%.2f y=%.2f grounded=%d" % [vehicle.global_basis.y.y, vehicle.global_position.y, vehicle.grounded_wheels])
				_finish()
		"wall":
			# Drive toward the wall at x=40,z=-60.
			var to := Vector3(40, 0, -60) - vehicle.global_position
			var local := vehicle.global_basis.inverse() * to
			var steer := clampf(local.x * 0.2, -1, 1)
			_press("steer_right", steer > 0.05, absf(steer))
			_press("steer_left", steer < -0.05, absf(steer))
			_press("accelerate", _t > 1.0 and vehicle.speed_kmh < 65.0)
			if _t > 12.0:
				_finish()
		_:
			print("unknown scenario")
			_finish()

	_log_t += dt
	if _log_t >= 0.5:
		_log_t = 0.0
		var v := vehicle
		var yaw_rate := rad_to_deg(v.angular_velocity.y)
		print("t=%5.2f spd=%6.1fkmh gear=%2d rpm=%5.0f y=%5.2f roll=%5.1f pitch=%5.1f yawrate=%6.1f grounded=%d skid=%.2f pos=(%.0f,%.0f)" % [
			_t, v.speed_kmh, v.gear, v.engine_rpm, v.global_position.y, roll,
			rad_to_deg(asin(clampf(-v.global_basis.z.y, -1, 1))), yaw_rate, v.grounded_wheels, v.get_skid_amount(),
			v.global_position.x, v.global_position.z])


func _finish() -> void:
	print("AUTOTEST done: max_roll=%.1f max_air=%.2f dist=%.1f" % [_max_roll, _max_air, vehicle.global_position.distance_to(_start_pos)])
	get_tree().quit()
