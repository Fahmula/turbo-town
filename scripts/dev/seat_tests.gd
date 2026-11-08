extends "res://scripts/dev/split_tests.gd"
## The seated-character dev tools (run from DevTools):
##   --seatsheet=<dir>  look-dev: every vehicle with a driver and a passenger
##                      (player 2's blue T-shirt) from fixed cameras, cut
##                      open with the camera's near plane (side, top, front)
##                      and from outside, plus how well each limb reaches
##                      its target (cm). --vehicles=a,b --views=cut_side,...
##                      --try=z,y,recline[,wheel z,wheel y];... tries other
##                      driver's seat numbers (--views=none: numbers only)
##   --seats=<dir>      checks: getting in and out (the figure sits in the
##                      seat, the character waits hidden), the hood /
##                      cockpit view leaves it out, replays show it, garage
##                      swaps, the bus (nobody shows), the plane, teleports,
##                      split-screen: a passenger in player 2's shirt, each
##                      player's cockpit view, player 2 leaving mid-ride
##   --seatbench        what a seated figure costs while driving in the city:
##                      draw calls, render CPU and GPU shown vs hidden, the
##                      animation and IK per frame
## Uses the split-screen test's helpers (check, shot, waits).

const VIEWS := ["cut_side", "cut_top", "cut_front", "ext_side", "ext_rear", "ext_front34"]


# =========================================================================
# --seats
# =========================================================================

func run() -> void:
	var g := game
	g.traffic.set_enabled(false)
	g.teleport_to(4)  # the open Dirt Fields
	await wait_s(1.0)
	g.ensure_driving()
	g.possession.settle()
	var car := g.vehicle
	var ch := g.character

	# --- Getting in and out ---------------------------------------------------
	g._step_out_beside(car)
	await wait_s(0.5)
	check(g.possession.on_foot() and ch.seated_figure() == null, "on foot: nobody in the seat")
	check(g.possession.enter(car), "get in")
	await _until(func() -> bool: return g.possession.driving(), 3.0)
	var fig := ch.seated_figure()
	check(fig != null and fig.vehicle == car and fig.get_parent() == car and not fig.passenger, "driving: the character sits in the driver's seat")
	check(fig != null and fig.visible and not ch.visible, "the figure shows, the walking character is hidden")
	check(fig != null and fig._anim.active and fig._anim.current_animation.to_lower() == "driving", "it plays the driving clip")
	check(fig != null and fig._meshes[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow of its own")
	await shot("seats_chase")

	# --- Cockpit view ---------------------------------------------------------
	g.camera.mode = ChaseCamera.Mode.HOOD
	await wait(3)
	check(fig and not fig.visible, "hood view: the driver doesn't see their own figure")
	await shot("seats_hood")
	check(g.replay.play_last(2.0), "a replay plays")
	await wait(3)
	check(fig and fig.visible, "replay (its own camera): the figure shows")
	g.replay.stop()
	await wait(3)
	check(fig and not fig.visible, "back in the hood view: hidden again")
	g.camera.mode = ChaseCamera.Mode.CHASE
	await wait(3)
	check(fig and fig.visible, "chase view: shown again")

	# --- Teleports, getting out ------------------------------------------------
	g.teleport_to(0)
	await wait_s(0.8)
	check(ch.seated_figure() == fig and fig.vehicle == g.vehicle, "after a teleport: still in the seat")
	g.teleport_to(4)
	await wait_s(0.8)
	car = g.vehicle
	check(g.possession.exit(), "get out")
	await _until(func() -> bool: return g.possession.on_foot(), 5.0)
	check(ch.seated_figure() == null and ch.visible, "on foot again: the seat is empty, the character walks")
	check(is_instance_valid(fig) and fig.get_parent() == ch and not fig.visible, "the figure waits, hidden, under the character")
	check(_figures_in(car).is_empty(), "nothing left behind in the parked car")
	g.ensure_driving()
	g.possession.settle()
	await wait(3)
	check(ch.seated_figure() != null and ch.seated_figure() == fig, "back in: the same figure sits down again")

	# --- Garage swaps, the bus, the plane --------------------------------------
	var old := g.vehicle
	g.change_vehicle(VehicleCatalog.index_of_id("sedan"))
	await wait_s(0.6)
	fig = ch.seated_figure()
	check(fig != null and fig.vehicle == g.vehicle and g.vehicle != old, "garage swap: the figure moves to the new vehicle")
	g.change_vehicle(VehicleCatalog.index_of_id("bus"))
	await wait_s(0.6)
	check(ch.seated_figure() == null and not ch.visible, "the bus (dark glass, no cabin): nobody shows")
	g.change_vehicle(VehicleCatalog.index_of_id("plane"))
	await wait_s(0.8)
	fig = ch.seated_figure()
	check(fig != null and fig.vehicle == g.vehicle and g.vehicle is Aircraft, "the plane: the pilot sits in the left seat")
	g.flight_camera.mode = FlightCamera.Mode.COCKPIT
	await wait(3)
	check(fig and not fig.visible, "cockpit view: hidden from the pilot")
	await shot("seats_cockpit")
	g.flight_camera.mode = FlightCamera.Mode.CHASE
	await wait(3)
	check(fig and fig.visible, "plane chase view: shown")
	g.change_vehicle(VehicleCatalog.index_of_id("sports_car"))
	await wait_s(0.6)

	# --- Split-screen: riding along ---------------------------------------------
	await join(0, 1)
	check(g.is_split(), "player 2 joins")
	var p1 := g.players[0]
	var p2 := g.players[1]
	p1.teleport_to(4)
	await wait_s(0.5)
	car = p1.vehicle
	check(p2.possession.start_riding(car), "player 2 rides with player 1")
	await wait(3)
	var f1 := p1.character.seated_figure()
	var f2 := p2.character.seated_figure()
	check(f1 != null and f2 != null and f1.vehicle == car and f2.vehicle == car, "both sit in player 1's car")
	check(f2 != null and f2.passenger and not f1.passenger, "player 2 in the passenger seat")
	check(f2 != null and _shirt(f2) == LocalPlayer.P2_SHIRT and _shirt(f1) != LocalPlayer.P2_SHIRT, "player 2's figure wears their blue T-shirt")
	p2.camera.mode = ChaseCamera.Mode.HOOD
	await wait(3)
	check(f2.visible and f2._meshes[0].layers == Views.VIEW_LAYERS[0], "player 2's hood view: their figure shows in player 1's view only")
	check(f1.visible and f1._meshes[0].layers == Vehicle.VISUAL_LAYER, "player 1's figure shows in both views")
	await shot("seats_split_p2_hood")
	p2.camera.mode = ChaseCamera.Mode.CHASE
	await wait(3)
	check(f2._meshes[0].layers == Vehicle.VISUAL_LAYER, "player 2's chase view: seen by both again")
	g.remove_player()
	await wait(5)
	check(not g.is_split() and _figures_in(car).size() == 1, "player 2 leaves: only player 1 is left in the car")
	print("seats: %d checks, %d failed" % [checks, fails])


func _figures_in(v: Node) -> Array:
	return v.get_children().filter(func(n: Node) -> bool: return n is SeatFigure)


func _until(cond: Callable, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not cond.call():
		await tools.get_tree().physics_frame
		t += tools.get_physics_process_delta_time()


## The T-shirt colour a figure wears.
func _shirt(f: SeatFigure) -> Color:
	for node in f.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "Char_Shirt":
				var over := mi.get_surface_override_material(s) as BaseMaterial3D
				return over.albedo_color if over else (mat as BaseMaterial3D).albedo_color
	return Color.BLACK


# =========================================================================
# --seatbench
# =========================================================================

func bench() -> void:
	var g := game
	var vp := tools.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	g.hud.visible = false
	g.teleport_to(0)  # the city centre
	g.ensure_driving()
	g.possession.settle()
	await wait_s(2.0)
	g.traffic.set_enabled(false)
	await wait_s(1.0)
	var fig := g.character.seated_figure()
	if fig == null:
		push_error("seatbench: nobody in the seat")
		return
	print("--- driving, city centre, chase camera, graphics %s, %s" % [Settings.GRAPHICS_LABELS[Settings.get_value("graphics")], g.vehicle.display_name])
	# (The model inside: LocalPlayer sets the figure's own visibility every
	# frame for the cockpit view.)
	for round in 3:
		fig._model.visible = true
		await wait(20)
		var a: Array = await tools._frame_stats(240)
		fig._model.visible = false
		await wait(20)
		var b: Array = await tools._frame_stats(240)
		fig._model.visible = true
		print("figure shown:  %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [a[0], a[1], a[3], a[4]])
		print("figure hidden: %d draw calls, render CPU %.2f ms, GPU %.2f ms (peak %.2f)" % [b[0], b[1], b[3], b[4]])
	# CPU: the clip and the IK, timed directly.
	var anim := fig._anim
	var n := 600
	var t0 := Time.get_ticks_usec()
	for i in n:
		anim.advance(1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	for i in n:
		fig._ik._process_modification()
	var t2 := Time.get_ticks_usec()
	print("per frame: animation %.3f ms, LimbIK %.3f ms" % [(t1 - t0) / 1000.0 / n, (t2 - t1) / 1000.0 / n])
	g.traffic.set_enabled(true)
	g.hud.visible = true


func sheet() -> void:
	var g := game
	g.traffic.set_enabled(false)
	g.hud.visible = false
	var args := OS.get_cmdline_user_args()
	var ids: Array = VehicleCatalog.ENTRIES.map(func(e: Dictionary) -> String: return e["id"])
	var views: Array = VIEWS.duplicate()
	for arg in args:
		if arg.begins_with("--vehicles="):
			ids = Array(arg.split("=")[1].split(","))
		elif arg.begins_with("--views="):
			views = Array(arg.split("=")[1].split(",")) if arg != "--views=none" else []
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.far = 500.0
	g.add_child(cam)
	Settings.set_value("time_of_day", 0)
	var spot := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(2.4, 0.6, -38.0))
	var rider: SeatFigure = null
	for id: String in ids:
		var vi := VehicleCatalog.index_of_id(id)
		if vi < 0:
			continue
		g.change_vehicle(vi, null, false)
		g.possession.settle()
		var v := g.vehicle
		var here := spot
		if v is Aircraft:
			here = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), MapLayout.APRON_CENTER + Vector3(-12.0, 0.03, 13.0))
		v.teleport(here.translated(Vector3.UP * v.ride_height()))
		await wait_s(1.2)
		g.controller.set_physics_process(false)
		g.flight_controller.set_physics_process(false)
		v.brake_input = 0.0
		var driver := g.character.seated_figure()
		check(driver != null if v.has_seats() else driver == null, "%s: %s" % [id, "a driver in the seat" if v.has_seats() else "nobody shows (no seats)"])
		if v.has_seats():
			if rider == null or not is_instance_valid(rider):
				rider = SeatFigure.make(g.character.get_node("Model"))
				_dress_blue(rider)
			rider.seat(v, true)
		elif rider and is_instance_valid(rider):
			rider.leave(g)
		await wait(4)
		# --try=z,y,recline;...: other hip positions, numbers only (tuning).
		for arg in args:
			if driver and arg.begins_with("--try="):
				var keep := [v.seat_hip, v.seat_recline]
				var keep_wheel := v.steering_wheel
				for t: String in arg.split("=")[1].split(";"):
					# z,y,recline[,wheel z,wheel y]
					var n := t.split_floats(",")
					v.seat_hip = Vector3(v.seat_hip.x, n[1], n[0])
					v.seat_recline = n[2]
					if n.size() >= 5:
						v.steering_wheel = Vector3(v.steering_wheel.x, n[4], n[3])
					driver.seat(v, false)
					await wait(2)
					print("  try %s" % t)
					_report_reach(id, "driver", driver)
					v.steering_wheel = keep_wheel
				v.seat_hip = keep[0]
				v.seat_recline = keep[1]
				driver.seat(v, false)
				await wait(2)
		if driver:
			_report_reach(id, "driver", driver)
		if v.has_seats():
			_report_reach(id, "passenger", rider)
		cam.current = true
		for view: String in views:
			_aim_cam(cam, v, view)
			await wait(4)
			await shot("seat_%s_%s" % [id, view])
		cam.near = 0.05
		g.controller.set_physics_process(true)
		g.flight_controller.set_physics_process(true)
	if rider and is_instance_valid(rider):
		rider.queue_free()
	cam.queue_free()
	g.possession.show_camera()
	g.hud.visible = true
	print("seatsheet: %d checks, %d failed" % [checks, fails])


## Player 2's blue T-shirt on a spare figure.
func _dress_blue(f: SeatFigure) -> void:
	for node in f.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "Char_Shirt" and mat is BaseMaterial3D:
				var shirt := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				shirt.albedo_texture = null
				shirt.albedo_color = LocalPlayer.P2_SHIRT
				mi.set_surface_override_material(s, shirt)


## How far each wrist / ankle falls short of its spot (LimbIK), and the room
## between the top of the head and the roof above it, for tuning the seat
## numbers.
func _report_reach(id: String, who: String, f: SeatFigure) -> void:
	var sk := f._skeleton
	var to_fig := f._model.transform * SeatFigure._local_to(sk, f._model)
	var parts: PackedStringArray = []
	var worst := 0.0
	for ch: Dictionary in f._ik.chains:
		var short: float = ch["short"]
		worst = maxf(worst, short)
		parts.append("%s %.0f" % [sk.get_bone_name(ch["c"]).trim_prefix("DEF-"), short * 100.0])
	# The crown: ~0.25 m up the head bone from its root (the skull base).
	var head_pose := sk.get_bone_global_pose(sk.find_bone("DEF-head"))
	var head := to_fig * head_pose.origin
	var crown := head + (to_fig.basis * head_pose.basis.y).normalized() * 0.25
	var room := _roof_above(f.vehicle, crown, head.y) - crown.y
	print("  fit %s %s: short %s cm; crown y %.2f z %.2f, room to roof %s" % [id, who, ", ".join(parts), crown.y, crown.z,
		"%.0f cm" % (room * 100.0) if room < 5.0 else "open"])
	check(worst < 0.02, "%s %s: every hand and foot reaches its spot (worst %.1f cm short)" % [id, who, maxf(worst, 0.0) * 100.0])
	check(room > 0.02, "%s %s: the head fits under the roof (%.0f cm)" % [id, who, minf(room, 9.99) * 100.0])


## The lowest bodywork (roof, headliner) straight above `p` (vehicle
## space), INF with nothing overhead. `_from_y` is unused (kept for calls).
var _tris := {}


func _roof_above(v: Vehicle, p: Vector3, _from_y: float) -> float:
	var key := v.get_instance_id()
	if not _tris.has(key):
		var tris := PackedVector3Array()
		var body := v.get_node("Body") as Node3D
		for node in body.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var xf := v.global_transform.affine_inverse() * mi.global_transform
			for sfc in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(sfc)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if idx.is_empty():
					for i in verts.size():
						tris.append(xf * verts[i])
				else:
					for i in idx:
						tris.append(xf * verts[i])
		_tris[key] = tris
	var all: PackedVector3Array = _tris[key]
	var best := INF
	for i in range(0, all.size() - 2, 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(p + Vector3.DOWN * 0.08, Vector3.UP, all[i], all[i + 1], all[i + 2])
		if hit != null and (hit as Vector3).y < best and (hit as Vector3).y > p.y - 0.08:
			best = (hit as Vector3).y
	return best


func _aim_cam(cam: Camera3D, v: Vehicle, view: String) -> void:
	var hip := v.seat_hip
	var w := v.footprint_half_width
	var h := v.body_top
	var at := hip + Vector3(0.0, 0.3, -0.15)
	var from := Vector3.ZERO
	var cut := 0.0  # distance from the camera to the cut, 0 = none
	cam.fov = 32.0
	match view:
		"cut_side":
			# From the driver's side, cut just outside the driver's shoulder.
			from = at + Vector3(-5.0, 0.0, 0.0)
			cut = 5.0 - 0.3
		"cut_top":
			at = Vector3(0.0, hip.y + 0.3, hip.z - 0.3)
			from = at + Vector3(0.0, 5.0, 0.001)
			cut = 5.0 - 0.62
		"cut_front":
			var wz := v.steering_wheel.z if v.steering_wheel != Vector3.ZERO else hip.z - 0.6
			at = Vector3(0.0, hip.y + 0.35, hip.z)
			from = Vector3(0.0, hip.y + 0.45, wz - 5.0)
			cut = 5.0 - 0.06
			cam.fov = 26.0
		"ext_side":
			from = at + Vector3(-(w + 4.5), 0.25, 0.0)
		"ext_rear":
			from = Vector3(0.0, h + 1.2, v.body_rear + 4.5)
			at = Vector3(0.0, hip.y + 0.4, hip.z)
		"ext_front34":
			from = Vector3(-w - 2.6, h + 0.5, -v.body_front - 2.6)
			at = Vector3(hip.x * 0.5, hip.y + 0.35, hip.z)
	cam.near = maxf(cut, 0.05)
	cam.global_position = v.global_transform * from
	var up := v.global_basis.y if view != "cut_top" else -v.global_basis.z
	cam.look_at(v.global_transform * at, up)
