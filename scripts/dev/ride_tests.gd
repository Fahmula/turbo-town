extends "res://scripts/dev/split_tests.gd"
## The riding-along dev test (run from DevTools):
##   --ride=<dir>   split-screen passengers: sitting in the other player's
##                  parked car and their moving one, prompts, no driving it,
##                  the passenger's camera / HUD / maps / markers, no
##                  controls of their own, no getting out while moving or
##                  flying, the passenger-seat close-up view, getting out on
##                  the passenger side, the driver getting out and back in,
##                  the driver's teleports and falling in the sea (the
##                  passenger comes along), the passenger's own teleport and
##                  "go to the other player", the driver's garage swap (the
##                  passenger moves to the new vehicle), the plane, the
##                  passenger's garage, player 1 riding with player 2, player
##                  2 leaving mid-ride, leak check (checks and shots)
## Uses the split-screen test's helpers (simulated gamepads 0 and 1).


func run() -> void:
	var g := game
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(1.0)
	g.ensure_driving()
	g.possession.settle()
	g._step_out_beside(g.vehicle)
	await wait_s(0.5)
	var kids_before := g.get_children().map(func(n: Node) -> String: return String(n.name))

	await join(0, 1)
	check(g.is_split(), "player 2 joins")
	var p1 := g.players[0]
	var p2 := g.players[1]
	# Out to the open Dirt Fields (nothing to drive into).
	p1.teleport_to(4)
	await wait_s(0.5)
	p2.regroup(p1)
	await wait_s(0.8)
	var car := p1.vehicle
	var entry := VehicleEntry.of(car)
	var car_name := car.display_name.to_lower()

	# --- Player 1's parked car ----------------------------------------------------
	await _stand_by(p2, car, 1.0)
	check(entry.use_for(p2.character) == VehicleEntry.Use.RIDE, "by player 1's parked car, player 2 can ride, not drive")
	check(entry.prompt(p2.character) == "Sit in Player 1's %s" % car_name, "prompt: %s" % entry.prompt(p2.character))
	check(p2.hud.prompt_text() == entry.prompt(p2.character), "player 2 sees the prompt")
	check(not p2.possession.enter(car), "player 2 still can't drive player 1's car")
	check(VehicleEntry.of(p2.vehicle).use_for(p1.character) == VehicleEntry.Use.RIDE, "player 1 could ride in player 2's car too")
	await shot("ride_prompt")
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p2.possession.riding() and p2.possession.ride == car, "B: player 2 sits in player 1's car")
	check(entry.riders == [p2.possession] and not entry.has_free_seat(), "the passenger seat is taken")
	check(not p2.character.visible, "player 2's character is hidden in the car")
	check(p2.view_camera() == p2.camera and p2.camera.target == car and p2.camera.passenger, "player 2 watches through their chase camera, aimed at the car")
	check(p2.controller.vehicle == null and p2.flight_controller.aircraft == null and p2.foot_controller.character == null,
		"player 2 has no controls")
	check(p2.hud.vehicle == car and not p2.hud.on_foot and p2.controller.riding == car, "player 2's gauges show the car; they feel its bumps")
	check(p2.hud._toast.text == "Waiting for Player 1", "toast: %s" % p2.hud._toast.text)

	# --- Player 1 drives, player 2 rides ---------------------------------------------
	# (Player 2's own car out of the way first.)
	var away := car.global_transform * Vector3(-25.0, 0.0, 0.0)
	var down := g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(away + Vector3.UP * 30.0, away + Vector3.DOWN * 30.0, 1))
	if not down.is_empty():
		p2.vehicle.teleport(Transform3D(car.global_basis, (down["position"] as Vector3) + Vector3.UP * (p2.vehicle.ride_height() + 0.3)))
	await _stand_by(p1, car, -1.0)
	await wait_s(0.6)
	var p2_car_at := p2.vehicle.global_position
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.driving() and p1.possession.vehicle == car and p2.possession.riding(), "player 1 gets in to drive, player 2 still rides")
	check(not p1._tag.visible and not p2._tag.visible, "no P1 / P2 markers over a car both sit in")
	check(p1.focus_node() == car and p2.focus_node() == car, "traffic and maps follow both in the car")
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)  # player 2's trigger drives nothing
	axis(1, JOY_AXIS_LEFT_X, 1.0)
	var sp := await top_speed(car, 3.0)
	await shot("ride_driving")
	check(sp > 15.0, "player 1 drives with player 2 aboard (%.0f km/h)" % sp)
	check(p2.vehicle.global_position.distance_to(p2_car_at) < 0.5, "player 2's buttons don't drive anything")
	check(p2.camera.global_position.distance_to(car.global_position) < 16.0, "player 2's camera follows the car (%.1f m)" % p2.camera.global_position.distance_to(car.global_position))
	check(p2.hud.speedometer.speed_kmh > 15.0, "player 2's speedometer shows the car's speed (%.0f)" % p2.hud.speedometer.speed_kmh)
	axis(1, JOY_AXIS_LEFT_X, 0.0)
	await pad(1, JOY_BUTTON_B)
	await wait_s(0.2)
	check(p2.possession.riding() and p2.hud._toast.text == "Wait until Player 1 stops!", "no getting out while it's moving (%s)" % p2.hud._toast.text)
	release_pads()
	await stop(p1, 0)
	# The close-up view is from the passenger seat.
	p2.camera.mode = ChaseCamera.Mode.HOOD
	await wait(5)
	var cam_local := car.global_transform.affine_inverse() * p2.camera.global_position
	check(cam_local.x > 0.2 and absf(cam_local.x - car.passenger_eye().x) < 0.1, "player 2's close-up view is from the passenger seat (x %.2f)" % cam_local.x)
	await shot("ride_passenger_view")
	p2.camera.mode = ChaseCamera.Mode.CHASE

	# --- Getting out ------------------------------------------------------------------
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.2)
	check(p2.possession.on_foot() and p2.character.visible, "B once stopped: player 2 gets out")
	var side := (car.global_transform.affine_inverse() * p2.character.global_position).x
	check(side > 0.5, "on the passenger side (%.1f m)" % side)
	check(entry.riders.is_empty() and entry.has_free_seat(), "the seat is free again")
	check(p2.view_camera() == p2.foot_camera, "player 2's view is back on foot")
	check(p2.camera.target == p2.vehicle and not p2.camera.passenger and p2.hud.vehicle == p2.vehicle and p2.controller.riding == null,
		"player 2's chase camera and gauges go back to their own car")
	check(p1.possession.driving(), "player 1 still driving")
	await wait_s(0.7)
	check(entry.prompt(p2.character) == "Ride with Player 1", "with player 1 in it: %s" % entry.prompt(p2.character))
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p2.possession.riding() and p1.hud._toast.text == "Player 2 is riding with you!" and p2.hud._toast.text == "Riding with Player 1!",
		"in again: toasts on both screens")

	# --- The driver gets out and back in ----------------------------------------------
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.on_foot() and p2.possession.riding() and p2.possession.ride == car, "player 1 gets out, player 2 stays in")
	check(p2.hud._toast.text == "Player 1 got out", "player 2 is told (%s)" % p2.hud._toast.text)
	check(p1._tag.visible and p2._tag.visible, "markers are back")
	await wait_s(0.7)
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.driving() and p2.possession.riding(), "player 1 back in, player 2 still there")

	# --- Places ------------------------------------------------------------------------
	var city: Transform3D = g.world.spawn_points[0]["xform"]
	p1.teleport_to(0)
	await wait_s(0.8)
	check(p2.possession.ride == car and flat_dist(car, p2.character) < 1.0 and car.global_position.distance_to(city.origin) < 10.0,
		"player 1's teleport takes player 2 along")
	check(p2.hud._toast.text == g.world.spawn_points[0]["name"], "player 2 sees where they went")
	await pad(1, JOY_BUTTON_X)
	await wait_s(0.3)
	check(p2.possession.riding() and p2.hud._toast.text == "You're with Player 1!", "X while riding with player 1: already there")
	var here := car.global_position
	await pad(1, JOY_BUTTON_DPAD_RIGHT)
	await wait_s(1.0)
	check(p2.possession.on_foot() and entry.has_free_seat() and p2.character.global_position.distance_to(here) > 60.0,
		"player 2's teleport: out, and off alone")
	check(flat_dist(p2.character, p2.vehicle) < 8.0, "player 2's own car came along")
	check(p1.possession.driving() and car.global_position.distance_to(here) < 2.0, "player 1 stays")
	await pad(1, JOY_BUTTON_X)
	await wait_s(1.0)
	await _stand_by(p2, car, 1.0)
	await wait_s(0.5)
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p2.possession.riding(), "back with player 1 and in")
	# Off the edge of the island: the driver's respawn brings the car back, with both.
	car.teleport(Transform3D(car.global_basis, Vector3(1600.0, 2.0, 0.0)))
	await wait_s(3.2)
	check(p1.possession.driving() and p2.possession.ride == car and absf(car.global_position.x) < 1500.0, "lost at sea: the car comes back with both in it")

	# --- The driver's garage --------------------------------------------------------------
	p1.teleport_to(4)
	await wait_s(0.5)
	p1.change_vehicle(VehicleCatalog.index_of_id("pickup"))
	await wait_s(1.0)
	var truck := p1.vehicle
	check(truck != car and p2.possession.riding() and p2.possession.ride == truck and VehicleEntry.of(truck).riders.size() == 1,
		"player 1 swaps to the pickup: player 2 rides along in it")
	check(p2.camera.target == truck and p2.hud.vehicle == truck and p2.view_camera() == p2.camera, "player 2's camera and gauges follow")

	# --- Flying -------------------------------------------------------------------------------
	p1.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await wait_s(1.5)
	var plane := p1.vehicle as Aircraft
	check(plane != null and p2.possession.ride == plane and p2.view_camera() == p2.flight_camera and p2.flight_camera.target == plane,
		"the plane: player 2 comes along, flight camera")
	check(p2.flight_controller.aircraft == null and p1.flight_controller.aircraft == plane, "only player 1 flies it")
	plane.place_in_flight(plane.global_position + Vector3.UP * 120.0, -plane.global_basis.z)
	await wait_s(2.0)
	check(p2.possession.riding() and not plane.on_ground, "flying with player 1")
	await shot("ride_flying")
	await pad(1, JOY_BUTTON_B)
	await wait_s(0.2)
	check(p2.possession.riding() and p2.hud._toast.text == "Wait until Player 1 lands!", "no getting out in the air (%s)" % p2.hud._toast.text)
	p2.flight_camera.mode = FlightCamera.Mode.COCKPIT
	await wait(5)
	cam_local = plane.global_transform.affine_inverse() * p2.flight_camera.global_position
	check(cam_local.x > 0.15, "player 2's cockpit view is from the right seat (x %.2f)" % cam_local.x)
	await shot("ride_cockpit")
	p2.flight_camera.mode = FlightCamera.Mode.CHASE
	var airfield := 0
	for i in g.world.spawn_points.size():
		if g.world.spawn_points[i]["name"] == "Airfield":
			airfield = i
	p1.teleport_to(airfield)
	await wait_s(1.5)
	check(plane.on_ground and p2.possession.ride == plane, "back on the runway, together")
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.2)
	check(p2.possession.on_foot(), "player 2 gets out of the plane on the ground")

	# --- The passenger's own garage -------------------------------------------------------
	p1.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	p1.teleport_to(4)
	await wait_s(0.5)
	p2.regroup(p1)
	await wait_s(0.8)
	car = p1.vehicle
	await _stand_by(p2, car, 1.0)
	await pad(1, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p2.possession.ride == car, "player 2 rides in player 1's new car")
	g.open_garage(p2)
	await wait(10)
	g._on_vehicle_picked(VehicleCatalog.index_of_id("van"))
	await wait_s(1.0)
	check(p2.possession.driving() and VehicleCatalog.id_of_vehicle(p2.vehicle) == "van" and VehicleEntry.of(car).has_free_seat(),
		"player 2 picks the van in the garage while riding: out, and driving it")
	check(flat_dist(p2.vehicle, car) < 15.0, "the van is right by player 1's car (%.1f m)" % flat_dist(p2.vehicle, car))

	# --- Player 1 rides with player 2 ------------------------------------------------------
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.on_foot(), "player 1 gets out of their car")
	await _stand_by(p1, p2.vehicle, 1.0)
	check(VehicleEntry.of(p2.vehicle).prompt(p1.character) == "Ride with Player 2", "player 1 by player 2's van: %s" % VehicleEntry.of(p2.vehicle).prompt(p1.character))
	await pad(0, JOY_BUTTON_B)
	await wait_s(1.5)
	check(p1.possession.riding() and p1.possession.ride == p2.vehicle, "player 1 rides with player 2")
	check(g.traffic.focus == p2.vehicle, "traffic follows player 1 in the van")
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	sp = await top_speed(p2.vehicle, 2.0)
	axis(1, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await shot("ride_p1_rides")
	check(sp > 10.0 and p1.possession.riding(), "player 2 drives player 1 around (%.0f km/h)" % sp)
	await stop(p2, 1)

	# --- Player 2 leaves mid-ride -------------------------------------------------------------
	g._enter_pause()
	g._on_menu_action("remove_player")
	await wait(10)
	check(not g.is_split() and p1.possession.on_foot() and p1.character.visible, "player 2 leaves while player 1 rides in their van: player 1 is on foot")
	check(p1.view_camera() == p1.foot_camera and p1.camera.target == p1.vehicle and not p1.camera.passenger, "player 1's cameras are back to their own")
	check(p1.hud.vehicle == p1.vehicle and g.traffic.focus == p1.character, "player 1's gauges and traffic follow them again")
	check(VehicleEntry.of(p1.vehicle).use_for(p1.character) == VehicleEntry.Use.DRIVE, "one player: getting in means driving")
	await shot("ride_left")
	await wait_s(1.0)
	var kids_after := g.get_children().map(func(n: Node) -> String: return String(n.name))
	var extra := kids_after.filter(func(n: String) -> bool: return not kids_before.has(n))
	check(extra.is_empty(), "nothing of player 2's left in the game (%s)" % ", ".join(extra))
	print("RIDE: %d checks, %d failed" % [checks, fails])


## Stands player `p` on foot beside `v`: `side` -1 = the driver's side, 1 = the
## passenger's.
func _stand_by(p: LocalPlayer, v: Vehicle, side: float) -> void:
	var at := v.global_transform * Vector3(side * (v.body_half_width + 0.7), 0.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	p.character.place(Transform3D(v.global_basis, hit["position"] if not hit.is_empty() else at))
	p.foot_camera.snap()
	await wait_s(0.4)
