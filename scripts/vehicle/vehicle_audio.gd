class_name VehicleAudio
extends AudioStreamPlayer
## Procedural car sounds, synthesized in real time (no audio files needed):
## engine (pitch follows RPM, brightness follows throttle), tire squeal,
## wind, impact thumps and a two-tone horn. Add as a child of a Vehicle.

@export var engine_volume := 0.55
@export var cylinders := 8
@export var tire_volume := 0.35
@export var wind_volume := 0.25
@export var horn_enabled := true

const MIX_RATE := 22050.0

var _vehicle: Vehicle
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _freq := 30.0
var _load := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _tire_lp := 0.0
var _tire_bp := 0.0
var _wind_lp := 0.0
var _skid := 0.0
var _speed := 0.0
var _impact_env := 0.0
var _impact_phase := 0.0
var _horn := false
var _horn_phase_a := 0.0
var _horn_phase_b := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -4.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	if _vehicle:
		_vehicle.impact.connect(_on_impact)
		_vehicle.landed.connect(func(air: float) -> void: _on_impact(clampf(air, 0.3, 2.0) * 9000.0, Vector3.ZERO, Vector3.UP))


func _exit_tree() -> void:
	stop()
	_playback = null
	stream = null


func _on_impact(strength: float, _pos: Vector3, _n: Vector3) -> void:
	_impact_env = maxf(_impact_env, clampf(strength / 30000.0, 0.15, 1.0))


func _process(_dt: float) -> void:
	if _vehicle == null or _playback == null:
		return
	_horn = horn_enabled and _vehicle.horn_input
	var rpm := _vehicle.engine_rpm
	var target_freq := rpm / 60.0 * cylinders * 0.5
	var target_load := _vehicle.engine_load
	var target_skid := _vehicle.get_skid_amount()
	var target_speed := _vehicle.linear_velocity.length()
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	_playback.push_buffer(synth(frames, target_freq, target_load, target_skid, target_speed))


## Generates `frames` stereo samples. Public so it can be rendered offline
## for testing/tuning.
func synth(frames: int, target_freq: float, target_load: float, target_skid: float, target_speed: float) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(frames)
	# Locals for speed (this loop runs ~400 times per frame).
	var freq := _freq
	var eload := _load
	var skid := _skid
	var speed := _speed
	var phase := _phase
	var lp := _lp
	var lp2 := _lp2
	var tlp := _tire_lp
	var tbp := _tire_bp
	var wlp := _wind_lp
	var imp := _impact_env
	var imp_ph := _impact_phase
	var ha := _horn_phase_a
	var hb := _horn_phase_b
	var horn_on := _horn
	var ev := engine_volume
	var tv := tire_volume
	var wv := wind_volume * 3.0
	var inv_rate := 1.0 / MIX_RATE
	for i in frames:
		freq += (target_freq - freq) * 0.002
		eload += (target_load - eload) * 0.001
		skid += (target_skid - skid) * 0.001
		speed += (target_speed - speed) * 0.001
		var noise := _rng.randf() * 2.0 - 1.0

		# Engine: saw + half-rate lope + noise, through two low-pass stages.
		phase += freq * inv_rate
		if phase > 1.0:
			phase -= 1.0
		var pulse := 1.0 - 2.0 * phase + 0.6 * sin(TAU * phase * 0.5) + noise * (0.08 + 0.18 * eload)
		var cutoff := 0.05 + 0.2 * eload + freq * inv_rate * 2.0
		lp += (pulse - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var s := lp2 * (0.35 + 0.65 * eload) * ev

		# Tire squeal: band-passed noise.
		tlp += (noise - tlp) * 0.35
		tbp += (tlp - tbp) * 0.08
		s += (tlp - tbp) * 2.2 * skid * tv

		# Wind rises with speed squared.
		wlp += (noise - wlp) * 0.02
		var w := clampf(speed / 55.0, 0.0, 1.0)
		s += wlp * w * w * wv

		# Impact thump.
		if imp > 0.001:
			imp_ph += 55.0 * inv_rate
			s += (sin(TAU * imp_ph) * 0.8 + noise * 0.5) * imp
			imp *= 0.9994

		if horn_on:
			ha = fmod(ha + 392.0 * inv_rate, 1.0)
			hb = fmod(hb + 494.0 * inv_rate, 1.0)
			s += (signf(sin(TAU * ha)) + signf(sin(TAU * hb))) * 0.09

		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_freq = freq
	_load = eload
	_skid = skid
	_speed = speed
	_phase = phase
	_lp = lp
	_lp2 = lp2
	_tire_lp = tlp
	_tire_bp = tbp
	_wind_lp = wlp
	_impact_env = imp
	_impact_phase = imp_ph
	_horn_phase_a = ha
	_horn_phase_b = hb
	return buf
