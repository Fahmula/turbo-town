class_name TrafficAudio
extends RefCounted
## Tiny procedural sound bank for traffic cars. Samples are generated once
## (no audio files) and shared; each car just plays them with its own pitch.

const RATE := 22050
## Engine loop base frequency; RPM maps to pitch_scale = firing_freq / BASE_FREQ.
const BASE_FREQ := 45.0

static var _engine: AudioStreamWAV
static var _horn: AudioStreamWAV
static var _crash: AudioStreamWAV


static func engine_loop() -> AudioStreamWAV:
	if _engine == null:
		# A whole number of periods so the loop is seamless.
		var period := int(RATE / BASE_FREQ)
		var n := period * 20
		var samples := PackedFloat32Array()
		samples.resize(n)
		var lp := 0.0
		var lp2 := 0.0
		for pass_i in 2:  # second pass = filters at steady state
			for i in n:
				var ph := float(i % period) / period
				var x := 1.0 - 2.0 * ph + 0.6 * sin(TAU * ph * 0.5 + TAU * float(i / period % 2) * 0.5)
				lp += (x - lp) * 0.12
				lp2 += (lp - lp2) * 0.12
				samples[i] = lp2 * 0.8
		_engine = _to_wav(samples, true)
	return _engine


static func horn() -> AudioStreamWAV:
	if _horn == null:
		var n := int(RATE * 0.45)
		var samples := PackedFloat32Array()
		samples.resize(n)
		for i in n:
			var t := float(i) / RATE
			var env := clampf(t / 0.02, 0.0, 1.0) * clampf((0.45 - t) / 0.05, 0.0, 1.0)
			var s := signf(sin(TAU * 392.0 * t)) + signf(sin(TAU * 494.0 * t))
			samples[i] = s * 0.3 * env
		_horn = _to_wav(samples, false)
	return _horn


static func crash() -> AudioStreamWAV:
	if _crash == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var n := int(RATE * 0.6)
		var samples := PackedFloat32Array()
		samples.resize(n)
		var lp := 0.0
		for i in n:
			var t := float(i) / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
			var thump := sin(TAU * 60.0 * t) * exp(-t * 10.0)
			samples[i] = clampf((lp * 1.6 * exp(-t * 7.0) + thump) * 0.8, -1.0, 1.0)
		_crash = _to_wav(samples, false)
	return _crash


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
