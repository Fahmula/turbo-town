extends "res://scripts/dev/split_tests.gd"
## The fuel and charging dev test (run from DevTools):
##   --fuel=<dir>   a full tank to start, how fast it drains (flat out, idling,
##                  ordinary), the low warning (toast, red gauge, the arrow to
##                  the nearest station), running dry (sputtering, crawling,
##                  R doesn't refill, an empty bus can still climb), "Get out
##                  to fill up", grabbing the nozzle, the hose's lead,
##                  filling by hand (readout, FULL!), taking it out, hanging
##                  it up, getting in or driving off with it in, teleporting
##                  while holding it, the Fuel setting off, starting levels
##                  (garage, a parked car), the electric SUV (a nozzle doesn't
##                  fit, charging at a charger), the plane (gliding home on
##                  an empty tank, filling at the airfield), the helicopter
##                  (sinks gently and lands itself, creeps along low, filling
##                  at a helipad), split-screen (player 2 fills player 1's
##                  car while player 1 waits at the wheel; a passenger has no
##                  gauge) (checks and shots)
##   --fuelbench    what the fuel places cost: draw calls, render CPU and GPU
##                  with them shown and hidden (A/B, three rounds) by the gas
##                  station, a city car park's chargers and the helipads;
##                  CPU of the fuel tick and of a hose being carried (run
##                  with --gpu-index 0 --graphics=1: the Deck stand-in)
## Run with --fixed-fps 60.

const GAS := MapLayout.GAS_STATION


func p() -> LocalPlayer:
	return game.players[0]


func press_f() -> void:
	key(KEY_F, true)
	await wait(3)
	key(KEY_F, false)
	await wait(3)


func _site(site_name: String) -> FuelSite:
	for node in tools.get_tree().get_nodes_in_group(FuelSite.GROUP):
		if node.name == site_name:
			return node as FuelSite
	return null


## The ground under `at` (or `at` itself), looking from a little above it
## (not the gas station's canopy).
func ground(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 2.5, at.z), Vector3(at.x, at.y - 30.0, at.z), 1)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else at


## Parks `v` standing at `at` (on the ground), facing `heading`.
func park(v: Vehicle, at: Vector3, heading: Vector3) -> void:
	var g := ground(at)
	v.teleport(Transform3D(Basis.looking_at(heading, Vector3.UP), g + Vector3.UP * (v.ride_height() + 0.05)))


## Puts the character on the ground at `at` and lets it look around.
func stand(pc: PlayerCharacter, at: Vector3, facing := Vector3.FORWARD) -> void:
	pc.place(Transform3D(Basis.looking_at(facing, Vector3.UP), ground(at)))
	await wait_s(0.25)


func prompt(pl: LocalPlayer = null) -> String:
	return (pl if pl else p()).hud.prompt_text()


func get_out() -> void:
	game.possession.exit()
	await wait_s(1.8)


## The hose of `site` whose handle rests nearest `at`.
func nearest_hose(site: FuelSite, at: Vector3) -> FuelPump:
	var best: FuelPump = null
	for h in site.pumps:
		if best == null or h.rest.origin.distance_to(at) < best.rest.origin.distance_to(at):
			best = h
	return best


## Where to stand to use a resting hose: beside its handle, toward `toward`.
func by_hose(h: FuelPump, toward: Vector3) -> Vector3:
	var d := toward - h.rest.origin
	d.y = 0.0
	return h.rest.origin + d.normalized() * 0.6


## Where to stand at a filler flap: just out from it.
func by_flap(flap: FillerFlap) -> Vector3:
	var n := flap.normal()
	var out := 0.7
	if absf(n.y) > 0.7:
		# On top of a wing: behind it.
		n = flap.vehicle.global_basis.z
		out = 1.2
	n.y = 0.0
	return flap.point() + n.normalized() * out


## Drives the player's vehicle with the right trigger at `amount` for
## `seconds`; returns [top speed km/h, saw sputtering, saw running].
func drive(amount: float, seconds: float) -> Array:
	var v := game.vehicle
	var f := VehicleFuel.of(v)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, amount)
	var top := 0.0
	var sput := false
	var ran := false
	var t := 0.0
	while t < seconds:
		await tools.get_tree().physics_frame
		t += dt()
		top = maxf(top, v.speed_kmh)
		if f:
			sput = sput or f.sputtering
			ran = ran or not f.sputtering
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	return [top, sput, ran]


## The player's vehicle at the runway's west end, facing down it: flat and
## open for driving tests.
func to_runway() -> void:
	var v := game.vehicle
	v.teleport(game.runway_start(v))
	p().snap_camera()
	await wait_s(1.0)


func dt() -> float:
	return tools.get_physics_process_delta_time()


func telemetry(label: String) -> void:
	var v := game.vehicle
	print("  [%s] mode %s, %s gear %d thr %.2f brk %.2f hb %s, %.1f km/h, fuel %.3f power %.2f cap %.1f, damage %.2f, rpm %.0f, wheels %d, up %.2f at %s" % [
		label, Possession.Mode.keys()[game.possession.mode], v.display_name, v.gear, v.throttle_input, v.brake_input, v.handbrake_input,
		v.speed_kmh, VehicleFuel.of(v).level if VehicleFuel.of(v) else -1.0, v.fuel_power, v.fuel_max_speed, v.damage_power,
		v.engine_rpm, v.grounded_wheels, v.global_basis.y.y, v.global_position])


func run() -> void:
	var g := game
	Settings.set_value("fuel", true)
	Settings.set_value("assists", true)
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(1.0)
	g.ensure_driving()
	g.possession.settle()
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	check(f != null and f.level > 0.995 and not f.is_battery(), "the starting car has a full tank")
	check(car.get_node_or_null("FillerFlap") is FillerFlap, "and a filler flap")
	await wait(5)
	check(absf(g.hud.speedometer.fuel_level - 1.0) < 0.01 and not g.hud.speedometer.fuel_battery, "the gauge shows it full")
	await _drain()
	await _low_and_empty()
	await _bus_climb()
	await _fill_up()
	await _setting_off()
	await _parked_car_level()
	await _electric()
	await _plane()
	await _helicopter()
	await _split()
	print("FUEL: %d checks, %d failed" % [checks, fails])


# --- Using fuel ------------------------------------------------------------------

func _drain() -> void:
	print("-- using fuel")
	var g := game
	await to_runway()
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	var before := f.level
	await drive(1.0, 4.0)
	var flat_out := 4.0 / maxf(before - f.level, 1e-7) / 60.0
	check(flat_out > 6.0 and flat_out < 13.0, "flat out, a full tank lasts %.1f minutes" % flat_out)
	await stop(p(), 0)
	before = f.level
	await wait_s(3.0)
	var idle := 3.0 / maxf(before - f.level, 1e-7) / 60.0
	check(idle > 60.0, "idling, it would last %.0f minutes" % idle)
	await to_runway()
	before = f.level
	await drive(0.45, 6.0)
	var ordinary := 6.0 / maxf(before - f.level, 1e-7) / 60.0
	check(ordinary > 9.0 and ordinary < 20.0, "driving along, it lasts %.1f minutes" % ordinary)
	await stop(p(), 0)


func _low_and_empty() -> void:
	print("-- low and empty")
	var g := game
	await to_runway()
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	f.set_level(0.201)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var t := 0.0
	while t < 8.0 and not f.is_low():
		await tools.get_tree().physics_frame
		t += dt()
	await wait_s(0.6)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(f.is_low(), "it gets low")
	check(g.hud._toast.text == "Low fuel! Find a gas station", "toast: %s" % g.hud._toast.text)
	check(g.hud.speedometer.fuel_level < 0.2, "the gauge is in the red")
	var nearest := FuelSite.nearest_for(tools.get_tree(), car, car.global_position)
	check(p().fuel_guide.showing() and p().fuel_guide.site == nearest and nearest.kind == VehicleFuel.Kind.FUEL,
		"the arrow points to the nearest pump (%s)" % (nearest.name if nearest else "none"))
	await shot("01_low_fuel")
	await stop(p(), 0)
	f.set_level(0.00001)
	await drive(0.3, 1.0)
	check(f.is_empty(), "it runs dry")
	check(g.hud._toast.text == "Out of fuel! Find a gas station", "toast: %s" % g.hud._toast.text)
	check(f.power == VehicleFuel.EMPTY_POWER and car.fuel_max_speed == VehicleFuel.EMPTY_SPEED, "some power left, a crawl")
	await to_runway()
	var res := await drive(1.0, 7.0)
	check(res[0] > 15.0 and res[0] < 48.0, "empty, it still crawls along (%.0f km/h)" % res[0])
	check(res[1] and res[2], "the engine sputters")
	await shot("02_empty")
	await stop(p(), 0)
	car.reset_upright()
	await wait(3)
	check(f.level == 0.0, "R doesn't refill it")


## Empty, the heaviest vehicle still pulls away briskly enough to climb a
## hill (the acceleration on the flat, as a slope it could take).
func _bus_climb() -> void:
	print("-- an empty bus")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("bus"))
	await wait(10)
	var bus := g.vehicle
	var f := VehicleFuel.of(bus)
	check(f.level > 0.995, "a vehicle from the garage starts full")
	await to_runway()
	f.set_level(0.0)
	await wait(2)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await wait_s(2.0)
	var v := absf(bus.forward_speed)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	var grade := v / 2.0 / 9.81
	check(grade > 0.12, "empty, the bus could still climb a %d%% slope" % roundi(grade * 100.0))
	await stop(p(), 0)


# --- Filling up ------------------------------------------------------------------

func _fill_up() -> void:
	print("-- filling up")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	await wait(10)
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	f.set_level(0.15)
	telemetry("before the pump")
	var site := _site("GasStation")
	# Beside the east island, heading north: the right side faces the pumps.
	park(car, GAS + Vector3(5.0 - 2.85, 0.0, 0.4), Vector3.FORWARD)
	await wait_s(1.0)
	check(prompt() == "Get out to fill up", "stopped at a pump: %s" % prompt())
	check(not p().fuel_guide.showing(), "no arrow at the station")
	await shot("03_at_the_pump")
	await get_out()
	check(g.possession.on_foot(), "got out")
	var pc := g.character
	var flap := car.get_node("FillerFlap") as FillerFlap
	var hose := nearest_hose(site, flap.point())
	await stand(pc, by_hose(hose, flap.point()))
	check(prompt() == "Grab the nozzle", "by the pump: %s" % prompt())
	await press_f()
	check(FuelPump.held_by(pc) == hose and pc.is_holding() and hose.state == FuelPump.State.HELD, "F: the nozzle is in the right hand")
	check(VehicleEntry.of(car).use_for(pc) == VehicleEntry.Use.NONE, "hands full: no getting in")
	await wait(4)
	var hand := pc.hold_transform().origin
	check(hose._handle.visible and hose._handle.global_position.distance_to(hand) < 0.05 and hand.distance_to(pc.global_position + Vector3.UP) < 0.6,
		"the nozzle is in the hand")
	check(hose._hose.visible and hose._hose_mesh.get_surface_count() == 1, "the hose runs from the pump to it")
	await shot("04_holding")
	# Walking off: the hose holds you back.
	g.foot_controller.control(null)
	pc.move_input = Vector3.BACK
	await wait_s(3.5)
	pc.move_input = Vector3.ZERO
	g.foot_controller.control(pc)
	var d := Vector2(pc.global_position.x - hose.outlet.x, pc.global_position.z - hose.outlet.z).length()
	check(d <= hose.lead + 0.1 and d > hose.lead - 0.7, "the hose holds you back at %.1f m (it's %.0f m)" % [d, hose.lead])
	await shot("05_end_of_the_hose")
	await stand(pc, by_flap(flap), -flap.normal())
	check(prompt() == "Fill up", "at the filler: %s" % prompt())
	await press_f()
	check(hose.state == FuelPump.State.IN_VEHICLE and f.nozzle == hose and not pc.is_holding() and FuelPump.held_by(pc) == null,
		"F: the nozzle goes in, hands free")
	var lvl := f.level
	await wait_s(1.0)
	check(f.level > lvl + 0.18, "it fills (%d%% after a second)" % roundi(f.level * 100.0))
	check(hose._readout.visible and hose._readout.text.ends_with(" L"), "the pump counts the litres: %s" % hose._readout.text)
	check(hose._loop.playing and hose._loop.stream == FuelPump.FLOW, "fuel gurgles in")
	await shot("06_filling")
	await wait_s(3.5)
	check(f.is_full() and g.hud._popup.text == "FULL!", "full: %s" % g.hud._popup.text)
	check(not hose._loop.playing, "the gurgle stops")
	await shot("07_full")
	check(prompt() == "Take the nozzle out", "by the filler: %s" % prompt())
	await press_f()
	check(hose.state == FuelPump.State.HELD and hose.holder == pc, "F: back in the hand")
	await stand(pc, flap.point() + flap.normal() * 0.7 + Vector3(0.0, 0.0, 2.2))
	check(prompt() == "Hang up the nozzle", "away from the filler: %s" % prompt())
	await press_f()
	check(hose.state == FuelPump.State.REELING and not pc.is_holding() and pc.leash_length == 0.0, "F: let go, it reels back")
	await wait_s(0.8)
	check(hose.state == FuelPump.State.RESTING and not hose._handle.visible and site._rest_mesh.get_surface_count() == 1,
		"back in its holster")

	# Getting in with the nozzle in pops it out.
	f.set_level(0.5)
	await stand(pc, by_hose(hose, flap.point()))
	await press_f()
	await stand(pc, by_flap(flap), -flap.normal())
	await press_f()
	check(hose.state == FuelPump.State.IN_VEHICLE, "nozzle in again")
	await stand(pc, car.global_transform * Vector3(car.body_half_width + 0.7, 0.0, -0.8))
	check(prompt().begins_with("Get in"), "by the door: %s" % prompt())
	await press_f()
	await wait_s(1.5)
	check(g.possession.driving() and hose.state != FuelPump.State.IN_VEHICLE and f.nozzle == null, "getting in pops it out")
	await wait_s(0.8)
	check(hose.state == FuelPump.State.RESTING, "and it reels home")
	await get_out()

	# The car moving off with it in pops it out too.
	pc = g.character
	hose.grab(pc)
	hose.insert(car, flap)
	await wait(3)
	car.global_position += car.global_basis.z * -0.6
	await wait(3)
	check(hose.state != FuelPump.State.IN_VEHICLE, "the car rolling off pops it out")
	await wait_s(1.0)

	# Teleporting with it in hand: it goes home by itself.
	hose.grab(pc)
	await wait(2)
	g.teleport_to(0)
	await wait_s(0.3)
	check(hose.state != FuelPump.State.HELD and not pc.is_holding() and pc.leash_length == 0.0, "teleporting: the hose lets go")
	await wait_s(1.0)
	g.ensure_driving()
	await wait(5)


func _setting_off() -> void:
	print("-- the Fuel setting")
	var g := game
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	f.set_level(0.0)
	await wait(3)
	check(car.fuel_max_speed > 0.0, "empty before")
	Settings.set_value("fuel", false)
	await wait(3)
	check(not f.enabled and car.fuel_power == 1.0 and car.fuel_max_speed == 0.0, "Fuel off: full power with an empty tank")
	check(g.hud.speedometer.fuel_level < 0.0 and not p().fuel_guide.showing(), "no gauge, no arrow")
	f.set_level(0.5)
	await to_runway()
	await drive(1.0, 2.0)
	check(f.level == 0.5, "nothing used")
	await shot("08_fuel_off")
	await stop(p(), 0)
	Settings.set_value("fuel", true)
	await wait(3)
	check(f.enabled and g.hud.speedometer.fuel_level >= 0.0, "Fuel on again: the gauge is back")
	f.set_level(1.0)


func _parked_car_level() -> void:
	print("-- a car from a car park")
	var g := game
	var entry: ParkedCarEntry = null
	for node in tools.get_tree().get_nodes_in_group(Interactable.GROUP):
		if node is ParkedCarEntry and (node as ParkedCarEntry).prop and (node as ParkedCarEntry).prop.is_inside_tree():
			entry = node
			break
	if entry == null:
		check(false, "found a parked car")
		return
	await get_out()
	var pc := g.character
	var at := entry.prop.global_position + entry.prop.global_basis.x * 2.2
	await stand(pc, at)
	entry.interact(pc)
	await wait_s(1.6)
	var f := VehicleFuel.of(g.vehicle)
	check(g.possession.driving() and f != null and f.level >= 0.5 and f.level <= 1.0, "a parked car has %d%% in its tank" % roundi(f.level * 100.0 if f else -1.0))


# --- Electric ----------------------------------------------------------------------

func _electric() -> void:
	print("-- the electric SUV")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("suv"))
	await wait(10)
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	check(car.electric and f.is_battery() and f.level > 0.995, "a full battery")
	await wait(3)
	check(g.hud.speedometer.fuel_battery, "the gauge shows a plug")
	await to_runway()
	f.set_level(0.1)
	await wait(5)
	check(g.hud._toast.text == "Low battery! Find a charger", "toast: %s" % g.hud._toast.text)
	await wait_s(0.4)
	var guide := p().fuel_guide
	check(guide.showing() and guide.site.kind == VehicleFuel.Kind.BATTERY, "the arrow points to chargers (%s)" % (guide.site.name if guide.site else "none"))
	f.set_level(0.0)
	await to_runway()
	var res := await drive(1.0, 6.0)
	check(res[0] > 15.0 and res[0] < 48.0 and not res[1], "empty: slow and quiet, no sputter (%.0f km/h)" % res[0])
	await stop(p(), 0)

	# A fuel nozzle doesn't fit.
	f.set_level(0.3)
	park(car, GAS + Vector3(5.0 - 2.9, 0.0, 0.4), Vector3.FORWARD)
	await wait_s(0.8)
	await get_out()
	var pc := g.character
	var flap := car.get_node("FillerFlap") as FillerFlap
	var hose := nearest_hose(_site("GasStation"), flap.point())
	await stand(pc, by_hose(hose, flap.point()))
	await press_f()
	await stand(pc, by_flap(flap), -flap.normal())
	check(prompt() == "This one needs a charger", "a nozzle at an electric car: %s" % prompt())
	await press_f()
	check(hose.state == FuelPump.State.HELD, "nothing happens")
	hose.hang_up()
	await wait_s(0.8)

	# Charging at the station's chargers: nose into the green bay.
	var site := _site("StationChargers")
	var charger := site.pumps[0]
	g.ensure_driving()
	await wait(5)
	var bay := charger.rest.origin + Vector3(-3.0, 0.0, 0.3)
	park(car, bay, Vector3.RIGHT)
	await wait_s(1.0)
	check(prompt() == "Get out to charge", "in the bay: %s" % prompt())
	await get_out()
	pc = g.character
	await stand(pc, by_hose(charger, charger.rest.origin + Vector3(0.0, 0.0, -1.0)))
	check(prompt() == "Grab the plug", "by the charger: %s" % prompt())
	await press_f()
	await stand(pc, by_flap(flap), -flap.normal())
	check(prompt() == "Charge it", "at the car: %s" % prompt())
	await press_f()
	check(charger.state == FuelPump.State.IN_VEHICLE and charger._loop.stream == FuelPump.HUM, "plugged in: it hums")
	await wait_s(1.0)
	check(charger._readout.visible and charger._readout.text.ends_with("%"), "the charger shows %s" % charger._readout.text)
	await shot("09_charging")
	await wait_s(3.0)
	check(f.is_full() and g.hud._popup.text == "CHARGED!", "charged: %s" % g.hud._popup.text)
	await press_f()
	charger.hang_up()
	await wait_s(0.8)
	g.ensure_driving()
	await wait(5)

	# A city car park's chargers: nose into a green bay.
	var park_site := _site("ParkingChargers1")
	var corner := MapLayout.ev_parking_corner(MapLayout.EV_PARKING[0])
	var stall := Vector3(corner.x + MapLayout.STALL_X_INSET + MapLayout.STALL_WIDTH * 1.5, MapLayout.CURB_HEIGHT,
		corner.y + MapLayout.STALL_ROW_INSET + MapLayout.STALL_DEPTH * 0.5)
	f.set_level(0.5)
	park(car, stall, Vector3.FORWARD)
	await wait_s(1.0)
	check(park_site != null and prompt() == "Get out to charge", "in a car park's green bay: %s" % prompt())
	await shot("16_car_park_chargers")


# --- Aircraft ----------------------------------------------------------------------

func _plane() -> void:
	print("-- the plane")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await wait(20)
	var plane := g.vehicle as Aircraft
	var f := VehicleFuel.of(plane)
	check(plane != null and f.level > 0.995, "a full plane")
	plane.place_in_flight(Vector3(0.0, 220.0, 250.0), Vector3.FORWARD)
	await wait_s(1.0)
	f.set_level(0.0)
	Input.action_press("fly_power", 0.98)
	await wait_s(1.0)
	check(g.hud._toast.text == "Out of fuel! Land at the airfield", "toast: %s" % g.hud._toast.text)
	var lowest := 0.0
	var t := 0.0
	var start_y := plane.global_position.y
	while t < 45.0:
		await tools.get_tree().physics_frame
		t += dt()
		lowest = minf(lowest, plane.vertical_speed)
	var lost := start_y - plane.global_position.y
	check(plane.throttle <= VehicleFuel.EMPTY_PLANE_POWER + 0.01, "full power gives %.0f%%" % (plane.throttle * 100.0))
	check(not plane.on_ground and lost > 60.0 and lost < 160.0 and lowest > -6.0,
		"it slows and glides down gently (%.0f m lost in 45 s, %.0f km/h, sinking %.1f m/s at most)" % [lost, plane.speed_kmh, -lowest])
	await shot("10_plane_gliding")
	Input.action_release("fly_power")

	# Filling up at the airfield: parked south of the cabinet, the right
	# wing toward it.
	var site := _site("AirfieldFuel")
	var hose := site.pumps[0]
	f.set_level(0.2)
	park(plane, hose.outlet + Vector3(3.0, 0.0, 4.8), Vector3.FORWARD)
	await wait_s(1.0)
	await get_out()
	check(g.possession.on_foot(), "out of the plane")
	var pc := g.character
	var flap := plane.get_node("FillerFlap") as FillerFlap
	await stand(pc, by_hose(hose, flap.point()))
	check(prompt() == "Grab the nozzle", "by the cabinet: %s" % prompt())
	await press_f()
	await stand(pc, by_flap(flap), Vector3.FORWARD)
	check(prompt() == "Fill up", "by the wing: %s" % prompt())
	await press_f()
	await wait_s(1.0)
	check(hose.state == FuelPump.State.IN_VEHICLE and f.level > 0.4, "filling the wing tank")
	await shot("11_plane_filling")
	await wait_s(3.0)
	check(f.is_full(), "full")
	await press_f()
	hose.hang_up()
	await wait_s(0.8)
	g.ensure_driving()
	await wait(5)


func _helicopter() -> void:
	print("-- the helicopter")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("helicopter"))
	await wait(20)
	var h := g.vehicle as Helicopter
	var f := VehicleFuel.of(h)
	h.place_in_flight(Vector3(420.0, 45.0, 0.0), Vector3.LEFT)
	await wait_s(1.0)
	f.set_level(0.0)
	await wait_s(0.5)
	check(g.hud._toast.text == "Out of fuel! Landing...", "toast: %s" % g.hud._toast.text)
	var lowest := 0.0
	var t := 0.0
	var touch := 0.0
	while t < 40.0 and not h.on_ground:
		await tools.get_tree().physics_frame
		t += dt()
		lowest = minf(lowest, h.vertical_speed)
		touch = h.vertical_speed
	check(h.on_ground and lowest > -3.2 and touch > -2.0,
		"it sinks gently (%.1f m/s at most) and lands itself (%.1f m/s at touchdown, %.0f s)" % [-lowest, -touch, t])
	await wait_s(1.0)
	Input.action_press("fly_power", 0.98)
	await wait_s(3.0)
	check(h.altitude > 1.0 and h.altitude < 4.5, "the climb button lifts it to a low hover only (%.1f m)" % h.altitude)
	Input.action_press("fly_nose_down", 0.98)
	await wait_s(4.0)
	check(h.airspeed < Helicopter.EMPTY_CREEP + 1.5 and h.airspeed > 4.0, "it creeps along (%.0f km/h)" % h.speed_kmh)
	await shot("12_heli_creeping")
	Input.action_release("fly_nose_down")
	Input.action_release("fly_power")
	await wait_s(5.0)
	check(h.on_ground, "and settles again")

	# Filling up on the helipad.
	var site := _site("HelipadFuelA")
	var hose := site.pumps[0]
	h.teleport(g.helipad_start(h))
	f.set_level(0.3)
	await wait_s(1.0)
	await get_out()
	var pc := g.character
	var flap := h.get_node("FillerFlap") as FillerFlap
	await stand(pc, by_hose(hose, flap.point()))
	check(prompt() == "Grab the nozzle", "by the helipad's pump: %s" % prompt())
	await press_f()
	await stand(pc, by_flap(flap), -flap.normal())
	check(prompt() == "Fill up", "by the helicopter: %s" % prompt())
	await press_f()
	await wait_s(1.0)
	check(hose.state == FuelPump.State.IN_VEHICLE and f.level > 0.45, "filling the helicopter")
	await shot("13_heli_filling")
	await wait_s(3.0)
	await press_f()
	hose.hang_up()
	await wait_s(0.8)
	g.ensure_driving()
	await wait(5)


# --- Split-screen --------------------------------------------------------------------

func _split() -> void:
	print("-- split-screen")
	var g := game
	g.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	await wait(10)
	var car := g.vehicle
	var f := VehicleFuel.of(car)
	f.set_level(0.3)
	park(car, GAS + Vector3(5.0 - 2.85, 0.0, 0.4), Vector3.FORWARD)
	await wait_s(0.8)
	await join(0, 1)
	check(g.is_split(), "player 2 joins")
	var p1 := g.players[0]
	var p2 := g.players[1]
	if not p2.possession.on_foot():
		p2.possession.exit()
		await wait_s(1.8)
	p2.vehicle.teleport(Transform3D(Basis.IDENTITY, ground(GAS + Vector3(-20.0, 0.0, 12.0)) + Vector3.UP * (p2.vehicle.ride_height() + 0.1)))
	await wait_s(0.5)
	var pc2 := p2.character
	var flap := car.get_node("FillerFlap") as FillerFlap
	var hose := nearest_hose(_site("GasStation"), flap.point())
	await stand(pc2, by_hose(hose, flap.point()))
	check(prompt(p2) == "Grab the nozzle", "player 2 by the pump: %s" % prompt(p2))
	await pad(1, JOY_BUTTON_B)
	check(hose.holder == pc2, "player 2's B grabs it")
	await stand(pc2, by_flap(flap), -flap.normal())
	check(prompt(p2) == "Fill up", "player 2 at player 1's car: %s" % prompt(p2))
	await pad(1, JOY_BUTTON_B)
	var lvl := f.level
	await wait_s(1.0)
	check(hose.state == FuelPump.State.IN_VEHICLE and f.level > lvl + 0.15 and p1.possession.driving(),
		"player 2 fills player 1's car while player 1 waits at the wheel")
	check(p1.hud.speedometer.fuel_level >= 0.0, "player 1 sees their gauge")
	await shot("14_split_filling")
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.5)
	await wait_s(1.0)
	axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(hose.state != FuelPump.State.IN_VEHICLE, "player 1 driving off pops it out")
	await stop(p1, 0)
	await wait_s(0.5)
	check(p2.possession.ride_with(car), "player 2 rides along")
	await wait_s(1.6)
	check(p2.possession.riding() and p2.hud.speedometer.fuel_level < 0.0 and p1.hud.speedometer.fuel_level >= 0.0,
		"the passenger has no fuel gauge, the driver does")
	await shot("15_split_passenger")
	p2.possession.leave_ride_now()
	await wait(5)
	g.remove_player()
	await wait(10)
	check(not g.is_split(), "back to one player")


# --- The bench ---------------------------------------------------------------------

func bench() -> void:
	var g := game
	var vp := tools.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	g.hud.visible = false
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(1.0)
	g.ensure_driving()
	g.possession.settle()
	var root := g.world.get_node_or_null("Fuel") as Node3D
	if root == null:
		push_error("fuelbench: no fuel places")
		return
	var corner := MapLayout.ev_parking_corner(MapLayout.EV_PARKING[0])
	var views := [
		["the gas station, at a pump", GAS + Vector3(5.0 - 2.85, 0.0, 6.0), Vector3.FORWARD],
		["a city car park's chargers", Vector3(corner.x + 4.5, MapLayout.CURB_HEIGHT, corner.y + 9.0), Vector3.FORWARD],
		["the helipads", MapLayout.HELIPAD_A + Vector3(0.0, 0.0, 22.0), Vector3.FORWARD],
	]
	print("--- fuel places, graphics %s" % Settings.GRAPHICS_LABELS[Settings.get_value("graphics")])
	for v: Array in views:
		park(g.vehicle, v[1], v[2])
		p().snap_camera()
		await wait_s(1.5)
		print("-- %s" % v[0])
		for round in 3:
			root.visible = true
			await wait(20)
			var a: Array = await tools._frame_stats(240)
			root.visible = false
			await wait(20)
			var b: Array = await tools._frame_stats(240)
			root.visible = true
			print("shown:  %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [a[0], a[1], a[3], a[4]])
			print("hidden: %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [b[0], b[1], b[3], b[4]])
	# CPU: the driver's fuel tick (burn, warnings, the 4 Hz station scan).
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in n:
		p()._fuel_tick(1.0 / 120.0)
	var t1 := Time.get_ticks_usec()
	print("fuel tick: %.4f ms per physics tick" % ((t1 - t0) / 1000.0 / n))
	# A hose carried around: its tube rebuilt every frame it moves.
	var hose := nearest_hose(_site("GasStation"), GAS)
	await get_out()
	hose.grab(g.character)
	await wait(5)
	n = 300
	t0 = Time.get_ticks_usec()
	for i in n:
		hose._last_ends = [Vector3.INF, Vector3.INF]
		hose._process(1.0 / 60.0)
	t1 = Time.get_ticks_usec()
	print("a hose in hand: %.3f ms per frame while it moves" % ((t1 - t0) / 1000.0 / n))
	hose.hang_up()
	g.hud.visible = true
	g.traffic.set_enabled(true)

