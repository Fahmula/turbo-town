extends SceneTree
## Offline check of every vehicle's sound set (no audio device needed):
##   godot --headless --path . -s res://scripts/dev/audio_check.gd
## For each vehicle scene: the Audio node has a VehicleSoundProfile, every
## stream loads, engine loops are marked as loops, their rpm lists match and
## rise, and they cover the vehicle's idle..redline range without extreme
## pitch factors. Also checks the shared VehicleSoundBank sets. Prints FAIL
## lines and exits with code 1 if anything is wrong.

var _fails := 0


func _init() -> void:
	for id in ["sports_car", "sedan", "van", "box_truck", "bus", "pickup", "buggy", "monster_truck"]:
		var car := (load("res://scenes/vehicles/%s.tscn" % id) as PackedScene).instantiate() as Vehicle
		var audio := car.get_node_or_null("Audio") as VehicleAudio
		_check(audio != null and audio.profile != null, "%s: Audio node with a profile" % id)
		if audio and audio.profile:
			_check_profile(id, car, audio.profile)
		car.free()
	for loop_path in [VehicleSoundBank.ROLL_ASPHALT, VehicleSoundBank.ROLL_GRAVEL, VehicleSoundBank.SQUEAL,
			VehicleSoundBank.SKID_GRAVEL, VehicleSoundBank.WIND, VehicleSoundBank.SCRAPE, VehicleSoundBank.BEEPER]:
		var st := VehicleSoundBank.loop(loop_path)
		_check(st != null and _loops(st), "bank loop %s loads and loops" % loop_path)
	for set_name in ["impact/thud", "impact/crunch", "impact/crash", "impact/metal", "impact/plastic", "impact/wood",
			"impact/glass", "impact/tinkle", "impact/debris", "suspension/knock", "suspension/land", "brake/squeal", "body/splash"]:
		var n := VehicleSoundBank.variants(set_name).size()
		_check(n >= 2, "bank set %s has %d variants" % [set_name, n])
	print("audio check: %s" % ("all good" if _fails == 0 else "%d problems" % _fails))
	quit(1 if _fails > 0 else 0)


func _check_profile(id: String, car: Vehicle, p: VehicleSoundProfile) -> void:
	for pair in [[p.engine_on, p.engine_on_rpm, "on"], [p.engine_off, p.engine_off_rpm, "off"]]:
		var streams: Array = pair[0]
		var rpms: PackedFloat32Array = pair[1]
		if streams.is_empty() and pair[2] == "off":
			continue
		_check(streams.size() == rpms.size() and streams.size() >= 2, "%s: %d %s-load loops, %d rpm values" % [id, streams.size(), pair[2], rpms.size()])
		var ok := true
		for i in streams.size():
			ok = ok and streams[i] != null and _loops(streams[i])
			if i > 0 and i < rpms.size():
				ok = ok and rpms[i] > rpms[i - 1]
		_check(ok, "%s: %s-load loops load, loop, and their rpm rises" % [id, pair[2]])
		if rpms.size() >= 2:
			var idle := car.idle_rpm * p.rpm_scale
			var red := car.redline_rpm * p.rpm_scale
			var lo_pitch := idle / rpms[0]
			var hi_pitch := red / rpms[rpms.size() - 1]
			print("  %-14s %s-load: idle pitch %.2f, redline pitch %.2f (%d loops %.0f-%.0f rpm)" % [
				id, pair[2], lo_pitch, hi_pitch, rpms.size(), rpms[0], rpms[rpms.size() - 1]])
			_check(lo_pitch > 0.5 and lo_pitch < 1.6 and hi_pitch > 0.6 and hi_pitch < 1.6,
				"%s: %s-load loops cover idle..redline without extreme pitch" % [id, pair[2]])
	_check(p.horn != null and _loops(p.horn), "%s: horn loop" % id)
	for st in [p.startup, p.whine, p.blowoff, p.shift, p.air_brake]:
		_check(st == null or st.get_length() > 0.0, "%s: optional sounds load" % id)
	if p.whine:
		_check(_loops(p.whine), "%s: whine loops" % id)


func _loops(st: AudioStream) -> bool:
	var wav := st as AudioStreamWAV
	return wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)
