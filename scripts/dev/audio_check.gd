extends SceneTree
## Offline sanity check of the engine synth levels:
##   godot --headless --path . -s res://scripts/dev/audio_check.gd

func _init() -> void:
	var a := VehicleAudio.new()
	var cases := [
		["idle", 900.0, 0.0, 0.0, 0.0],
		["full throttle 3000rpm", 3000.0, 1.0, 0.0, 10.0],
		["full throttle 6500rpm", 6500.0, 1.0, 0.0, 30.0],
		["coast 4000rpm", 4000.0, 0.0, 0.0, 30.0],
		["tire squeal", 3000.0, 0.5, 1.0, 15.0],
		["wind 180kmh", 5500.0, 0.7, 0.0, 50.0],
	]
	for c in cases:
		var freq: float = c[1] / 60.0 * 4.0
		var buf := a.synth(22050, freq, c[2], c[3], c[4])
		var peak := 0.0
		var sum := 0.0
		var clipped := 0
		for i in range(11025, buf.size()):
			var v := absf(buf[i].x)
			peak = maxf(peak, v)
			sum += v * v
			if v >= 0.999:
				clipped += 1
		print("%-24s rms=%.3f peak=%.3f clipped=%d" % [c[0], sqrt(sum / 11025.0), peak, clipped])
	a.free()
	# Every vehicle's engine profile at idle, mid revs and near the redline.
	print("")
	for id in ["sports_car", "sedan", "van", "box_truck", "bus", "pickup", "buggy", "monster_truck"]:
		var car := (load("res://scenes/vehicles/%s.tscn" % id) as PackedScene).instantiate() as Vehicle
		var audio := car.get_node("Audio") as VehicleAudio
		var line := "%-14s" % id
		for c in [[car.idle_rpm, 0.0], [car.redline_rpm * 0.55, 1.0], [car.redline_rpm * 0.92, 1.0]]:
			var freq: float = c[0] / 60.0 * audio.cylinders * 0.5
			var buf := audio.synth(22050, freq, c[1], 0.0, 0.0)
			var peak := 0.0
			var sum := 0.0
			for i in range(11025, buf.size()):
				var v := absf(buf[i].x)
				peak = maxf(peak, v)
				sum += v * v
			line += "  %4.0frpm rms=%.3f peak=%.2f" % [c[0], sqrt(sum / 11025.0), peak]
		print(line)
		car.free()
	quit()
