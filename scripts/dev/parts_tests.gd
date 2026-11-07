extends "res://scripts/dev/split_tests.gd"
## The garage parts dev test (run from DevTools):
##   --parts=<dir>   every body part on every vehicle in the garage (each from
##                   its row's camera view), paint finishes, two-tone, decals
##                   and race numbers, underglow, horns; then checks: parts
##                   that don't fit are refused, kit bumpers and wings still
##                   fall off in a crash and come back on repair, wide arches
##                   push the wheels out, setups save and load, nothing leaks
##                   when parts are swapped (checks and shots)
##   add --vehicles=a,b to shoot only those vehicles' parts
##   --partsbench    cost of a fully kitted player car against a stock one:
##                   GPU / frame time / draw calls, A/B three times (run on the
##                   iGPU with --gpu-index 0 and --graphics=1 for a Deck proxy)
## Uses the split-screen test's helpers (check, shot, wait).

var _only: PackedStringArray = []


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicles="):
			_only = arg.split("=")[1].split(",")
	var g := game
	g.traffic.set_enabled(false)
	g.teleport_to(0)
	await wait_s(0.5)
	g.open_garage()
	await wait(5)
	var p := g.picker

	# --- Every body part on every vehicle -------------------------------------------------
	for i in VehicleCatalog.count():
		var e: Dictionary = VehicleCatalog.ENTRIES[i]
		var vid: String = e["id"]
		if e.get("air", false) or (not _only.is_empty() and not _only.has(vid)):
			continue
		_show(p, i)
		await wait(20)
		for slot: String in PartsCatalog.BODY_PARTS:
			var opts := PartsCatalog.options(slot, vid)
			if opts.size() <= 1:
				check(VehiclePicker.why_not(slot, p.loadout(), p._car) != "", "%s: %s row greyed out (nothing fits)" % [vid, slot])
				continue
			for o: Dictionary in opts:
				await _pick(p, slot, o["id"])
				await wait(8)
				if o["id"] != "stock" and o["id"] != "none":
					var part := BodyKit.fitted_part(p._car, slot)
					check(part != null and part.visible, "%s wears %s %s" % [vid, slot, o["id"]])
				if slot in BodyKit.REPLACES:
					var stock := BodyKit._stock_meshes(p._car.get_node("Body"), BodyKit.REPLACES[slot])
					var shown := stock.filter(func(mi: MeshInstance3D) -> bool: return mi.visible).size()
					check(shown == (stock.size() if o["id"] == "stock" else 0), "%s: stock %s shown only when stock (%d of %d)" % [vid, slot, shown, stock.size()])
				await shot("body_%s_%s_%s" % [vid, slot, o["id"]])
			await _pick(p, slot, "stock")
		# Everything at once (the last option of each row), front and back.
		for slot: String in PartsCatalog.BODY_PARTS:
			var opts := PartsCatalog.options(slot, vid)
			if opts.size() > 1:
				await _pick(p, slot, opts[-1]["id"])
		await _view(p, "front")
		await shot("body_%s_all_front" % vid)
		await _view(p, "rear")
		await shot("body_%s_all_rear" % vid)
		for slot: String in PartsCatalog.BODY_PARTS:
			await _pick(p, slot, "stock")
		check(not BodyKit.is_fitted(p._car) or p._car.get_node("Body/Kit").get_child_count() == 0, "%s back to stock: no kit parts left" % vid)

	# --- Paint: finishes, two-tone, decals, numbers ---------------------------------------
	_show(p, VehicleCatalog.index_of_id("sports_car"))
	await wait(10)
	for o: Dictionary in PartsCatalog.FINISHES:
		await _pick(p, "finish", o["id"])
		await _view(p, "front")
		await shot("paint_finish_%s" % o["id"])
	await _pick(p, "finish", "stock")
	for o: Dictionary in PartsCatalog.TWO_TONES:
		await _pick(p, "two_tone", o["id"])
		await _view(p, "top")
		await shot("paint_tone_%s" % o["id"])
	await _pick(p, "two_tone", "off")
	for o: Dictionary in PartsCatalog.DECALS:
		await _pick(p, "decal", o["id"])
		await _view(p, "side")
		await shot("decal_%s" % o["id"])
	var m := (p._car.get_node("Body") as VehicleBodyVisual).paint()
	check(m.shader == VehicleBodyVisual.PAINT_CUSTOM_SHADER, "decals put the custom paint shader on")
	await _pick(p, "decal", "flames")
	await _pick(p, "decal_color", "orange")
	await _pick(p, "number", "42")
	await _view(p, "side")
	await shot("decal_flames_42")
	await _view(p, "top")
	await shot("decal_flames_42_top")
	await _pick(p, "decal", "none")
	await _pick(p, "number", "none")
	check(m.shader == VehicleBodyVisual.PAINT_SHADER, "plain paint again: back to the shared paint shader")
	for vid: String in ["sedan", "van", "pickup", "box_truck", "bus", "buggy", "monster_truck"]:
		_show(p, VehicleCatalog.index_of_id(vid))
		await wait(10)
		await _pick(p, "decal", "lightning" if vid in ["van", "bus"] else "flames")
		await _pick(p, "number", "7")
		await _pick(p, "two_tone", "roof")
		await _view(p, "side")
		await shot("decal_%s" % vid)
		await _pick(p, "decal", "none")
		await _pick(p, "number", "none")
		await _pick(p, "two_tone", "off")

	# --- Underglow ----------------------------------------------------------------------
	_show(p, VehicleCatalog.index_of_id("sports_car"))
	await wait(10)
	for o: Dictionary in PartsCatalog.UNDERGLOW:
		await _pick(p, "underglow", o["id"])
		await wait(3)
		check((p._car.get_node_or_null("Underglow") != null) == (o["id"] != "off"), "underglow %s" % o["id"])
		if o["id"] in ["off", "blue", "pink"]:
			await shot("glow_%s" % o["id"])

	# --- Planes keep their own shape ----------------------------------------------------
	var plane := VehicleCatalog.index_of_id("plane")
	_show(p, plane)
	await wait(5)
	for slot in ["spoiler", "decal", "underglow", "horn"]:
		check(VehiclePicker.why_not(slot, p.loadout(), p._car) == "Not on planes", "plane: %s row greyed out" % slot)
	# Back out the way the player does (Game unpauses and keeps the car).
	p.close()
	p.cancelled.emit()
	await wait(5)
	check(not g.get_tree().paused, "the world runs again after the garage")

	# --- Fit checks: what a vehicle can't wear is refused ---------------------------------
	var van := Loadout.stock("van")
	van.set_value("front", "race")
	van.set_value("bonnet", "scoop")
	van.set_value("spoiler", "none")
	check(van.body_stock(), "van refuses a race bumper, a bonnet scoop and 'no spoiler' (it has none)")
	van.set_value("spoiler", "mega")
	check(van.get_value("spoiler") == "mega", "van takes a Mega Wing")

	# --- On the road: a full kit on the sports car, then a crash ---------------------------
	var l := Loadout.stock("sports_car")
	for slot_id: Array in [["front", "race"], ["rear", "race"], ["skirts", "race"], ["flares", "widebody"], ["spoiler", "wing"],
			["bonnet", "blower"], ["roof", "lights"], ["finish", "pearl"], ["decal", "speed"], ["number", "88"], ["underglow", "cyan"],
			["horn", "tune"], ["paint", PaintPalette.GARAGE[6]]]:
		l.set_value(slot_id[0], slot_id[1])
	g.change_vehicle(0, l)
	await wait_s(1.0)
	var v := g.vehicle
	var w := v.wheels[0]
	check(absf(absf(w.get_node("Visual").position.x) - 0.045) < 0.002, "wide body pushes the wheels out 4.5 cm (%.3f)" % w.get_node("Visual").position.x)
	var audio := v.get_node("Audio") as VehicleAudio
	check(audio.horn_id == "tune", "the horn is the Tune")
	var dmg := v.get_node("Damage") as VehicleDamage
	check(dmg._parts.has("FrontBumper") and (dmg._parts["FrontBumper"]["mesh"] as Node).get_parent().name == "Kit",
		"the race bumper is the one that can fall off")
	check(dmg._parts.has("Spoiler") and (dmg._parts["Spoiler"]["mesh"] as Node).get_parent().name == "Kit", "so is the GT wing")
	g.camera.snap()
	await wait_s(1.5)
	await shot("road_kit_chase")
	await tools._ram_wall(g, 70.0)
	var lost: Array = dmg._parts.keys().filter(func(k: String) -> bool: return dmg._parts[k]["debris"] != null)
	check(lost.has("FrontBumper"), "a 70 km/h wall crash knocks the race bumper off (lost: %s)" % ", ".join(lost))
	await shot("road_kit_crashed")
	dmg.repair()
	await wait(3)
	var front := BodyKit.fitted_part(v, "front")
	check(front != null and front.visible and front.get_parent().name == "Kit", "repair puts the race bumper back")
	var stock_front := BodyKit._stock_meshes(v.get_node("Body"), "FrontBumper")
	check(stock_front.all(func(mi: MeshInstance3D) -> bool: return not mi.visible), "the stock bumper stays hidden after repair")
	await tools._ram_wall(g, 60.0, true)
	await shot("road_kit_crashed_rear")
	dmg.repair()
	# Swapping parts many times leaves nothing behind.
	var kids := v.get_node("Body").get_child_count()
	for k in 6:
		g.loadout.set_value("spoiler", ["mega", "lip", "stock"][k % 3])
		g.loadout.apply(v)
		await wait(2)
	check(v.get_node("Body").get_child_count() == kids, "swapping spoilers six times leaves no extra nodes")

	# --- Save and load ---------------------------------------------------------------------
	Settings.persist = true
	Settings.path = dir.path_join("settings_parts.cfg")
	l.save()
	Settings.persist = false
	Settings.set_value("loadouts", {})
	Settings.load_file()
	var back := Loadout.saved("sports_car")
	check(back.get_value("front") == "race" and back.get_value("flares") == "widebody" and back.get_value("decal") == "speed"
		and back.get_value("number") == "88" and back.get_value("underglow") == "cyan" and back.get_value("horn") == "tune",
		"a full setup saves and loads (%s)" % back.overrides())

	# --- Night drive with underglow ---------------------------------------------------------
	var dn := g.get_tree().root.find_children("*", "DayNight", true, false)
	if not dn.is_empty():
		(dn[0] as DayNight).set_mode(2)  # night
		g.teleport_to(0)
		await wait_s(1.0)
		g.camera.snap()
		await wait_s(0.5)
		await shot("road_kit_night")
		check(v.get_node("Underglow") != null and (v.get_node("Underglow") as Underglow)._mat.get_shader_parameter("energy") == Underglow.NIGHT_ENERGY,
			"underglow is brighter at night")
	print("PARTS: %d checks, %d failed" % [checks, fails])


func _show(p: VehiclePicker, i: int) -> void:
	p._set_tab(0)
	p.index = i
	p._show_vehicle()


## Picks option `id` in `slot` on the garage's shown vehicle, focusing its
## row (so the camera turns to the part).
func _pick(p: VehiclePicker, slot: String, id: Variant) -> void:
	for t in PartsCatalog.TABS.size():
		var slots: Array = PartsCatalog.TABS[t]["slots"]
		var row := slots.find(slot)
		if row < 0:
			continue
		if p.tab != t:
			p._set_tab(t)
		p._focus_row(row)
		var vid := p.loadout().vehicle_id
		p._set_slot(slot, PartsCatalog.index_of(slot, id, vid))
		p._snap_camera = true
		await wait(4)
		return


## Turns the garage camera to `view` (as if that kind of row were picked).
func _view(p: VehiclePicker, view: String) -> void:
	for slot: String in PartsCatalog.SLOTS:
		if PartsCatalog.SLOTS[slot].get("view", "") == view and VehiclePicker.why_not(slot, p.loadout(), p._car) == "":
			for t in PartsCatalog.TABS.size():
				var row := (PartsCatalog.TABS[t]["slots"] as Array).find(slot)
				if row >= 0:
					p._set_tab(t)
					p._focus_row(row)
					p._snap_camera = true
					await wait(6)
					return


## A fully kitted sports car: every row on its showiest option.
func _full_kit() -> Loadout:
	var l := Loadout.stock("sports_car")
	for slot_id: Array in [["front", "race"], ["rear", "race"], ["skirts", "race"], ["flares", "widebody"], ["spoiler", "mega"],
			["bonnet", "blower"], ["roof", "lights"], ["finish", "pearl"], ["two_tone", "roof"], ["decal", "flames"], ["number", "88"],
			["underglow", "pink"]]:
		l.set_value(slot_id[0], slot_id[1])
	return l


func bench() -> void:
	var g := game
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	g.traffic.set_enabled(false)
	_report("PARTSBENCH GPU: %s, graphics %d" % [RenderingServer.get_video_adapter_name(), Settings.get_value("graphics")])
	# Stock, then each group alone, then everything.
	var full := _full_kit()
	var groups := {
		"stock": [],
		"body": PartsCatalog.BODY_PARTS.keys(),
		"paint": ["finish", "two_tone", "decal", "number"],
		"glow": ["underglow"],
		"kit": full.overrides().keys(),
	}
	var sums := {}
	for rep in 3:
		for which: String in groups:
			var l := Loadout.stock("sports_car")
			for slot: String in groups[which]:
				l.set_value(slot, full.get_value(slot))
			g.teleport_to(0)
			await wait_s(0.3)
			g.change_vehicle(0, l)
			await wait_s(1.5)
			g.camera.snap()
			await wait_s(0.5)
			var r: Array = await _measure(240)
			_report("  %s run %d: GPU %.2f ms, frame %.2f ms, %d draw calls, %d primitives" % [which, rep + 1, r[0], r[1], r[2], r[3]])
			var a: Array = sums.get(which, [0.0, 0.0, 0, 0])
			for k in 4:
				a[k] += r[k]
			sums[which] = a
	for which: String in groups:
		var a: Array = sums[which]
		_report("PARTSBENCH %s: GPU %.2f ms, frame %.2f ms, %d draw calls, %d primitives (average of 3)" % [which, a[0] / 3.0, a[1] / 3.0, a[2] / 3, a[3] / 3])
