class_name VehicleAudio
extends Node3D
## Layered, adaptive vehicle sound. A child named "Audio" of every Vehicle,
## with a VehicleSoundProfile (the engine and horn) plus the shared
## VehicleSoundBank (tyres, wind, crashes...). All sources are
## AudioStreamPlayer3D on the vehicle, so replays and camera moves place them
## right.
##
## Engine: steady loops recorded at known rpm, on and off load. The two loops
## either side of the current rpm play, pitched to it (rpm / recorded rpm) and
## crossfaded with equal power; the on- and off-load sets are blended by a
## smoothed engine load (throttle, dropping during gear changes). Loudness
## rises with rpm and load. Extras from the profile: start-up, turbo whine and
## blow-off, exhaust pops on lift-off, a shift clunk, a rev-limiter stutter.
##
## FULL detail (the player's vehicle) adds tyre roll per surface (asphalt,
## gravel), squeal and gravel slides, wind, bodywork scraping, suspension
## knocks and landings, brake squeal, air brakes, reverse beeper, a splash,
## and reverb in tunnels and under bridges (the "Player" bus). LITE detail
## (traffic) keeps the engine (on-load pair), tyre roll up close, squeal,
## horn, beeper and crashes, with a Doppler shift as cars pass, and only plays
## its loops while the AudioDirector gives it a voice (the nearest few).
## Crashes (both): thud / crunch / crash tiers by impact strength and what
## was hit (car, wall, plastic, wood, metal), metal deformation on big hits,
## glass when glass or lamps break, plastic clatter as parts fall off.

enum Detail { FULL, LITE }

@export var profile: VehicleSoundProfile
@export var detail := Detail.FULL
@export var volume_db := 0.0

## Set by the AudioDirector (LITE): may this vehicle's loops play?
var audible := true
## Dev tests: called with (sound path, world position) for every one-shot.
static var on_shot := Callable()
## Dev tests: called with (sound path, "start" / "resume" / "pause") when a
## loop starts or stops.
static var on_voice := Callable()
var vehicle: Vehicle

const SPEED_OF_SOUND := 343.0
## One-shot players per vehicle (crashes, knocks, horn blips...).
const SHOTS := {Detail.FULL: 5, Detail.LITE: 2}
## Engine loops a traffic vehicle uses (spread over its recorded set).
const LITE_LAYERS := 4

var _rng := RandomNumberGenerator.new()
var _on: Array[AudioStreamPlayer3D] = []
var _on_rpm := PackedFloat32Array()
var _off: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_i := 0
var _built := -1
var _load := 0.0
var _prev_throttle := 0.0
var _engine_fade := 1.0
var _startup_t := -1.0
var _time := 0.0
var _pops_left := 0
var _pop_timer := 0.0
var _peak_load_time := 0.0
var _last_gear := 1
var _skid := 0.0
var _scrape := 0.0
var _horn_until := 0.0
var _impact_cooldown := 0.0
var _knock_cooldown := 0.0
var _braked_from := 0.0
var _air_cooldown := 0.0
var _squeal_cooldown := 0.0
var _splashed := false
var _enclosure := 0.0
var _enclosure_timer := 0.0
var _doppler := 1.0
var _damage: VehicleDamage
var _registered := false
var _copies := {}


func _ready() -> void:
	vehicle = get_parent() as Vehicle
	_rng.randomize()
	ensure_buses()
	if vehicle == null or profile == null:
		set_process(false)
		return
	vehicle.impact.connect(_on_impact)
	vehicle.landed.connect(_on_landed)
	vehicle.vehicle_reset.connect(_on_reset)
	_damage = vehicle.get_node_or_null("Damage") as VehicleDamage
	if _damage:
		_damage.broke.connect(_on_broke)
		_damage.detached.connect(_on_detached)
	_build()


func _enter_tree() -> void:
	_registered = false
	add_to_group(&"vehicle_audio")


func _exit_tree() -> void:
	if AudioDirector.instance:
		AudioDirector.instance.unregister(self)
	_registered = false
	_stop_all()


## Paused playbacks stay registered with the AudioServer (it never gets to
## delete them): unpause and stop them all when the vehicle leaves (traffic
## pool, garage swap, quitting).
func _stop_all() -> void:
	for p in _on + _off + _shots + Array(_loops.values()):
		var pl := p as AudioStreamPlayer3D
		pl.stream_paused = false
		pl.stop()
		pl.set_meta("starting", false)


## Quits the game once every vehicle sound has been let go. The AudioServer
## frees a stopped playback only after its mixer and then the main loop have
## run again; get_tree().quit() alone tears the tree down first, which leaves
## the playbacks (and their streams) behind ("ObjectDB instances were leaked
## at exit"). Waits real time, so it also works under --fixed-fps.
static func quit_quietly(tree: SceneTree) -> void:
	if tree.has_meta(&"quitting"):
		return
	tree.set_meta(&"quitting", true)
	tree.paused = true
	for a in tree.get_nodes_in_group(&"vehicle_audio"):
		(a as Node).process_mode = Node.PROCESS_MODE_DISABLED
	# Every player, including the clatter players riding on loose debris.
	for p in tree.root.find_children("*", "AudioStreamPlayer3D", true, false):
		(p as AudioStreamPlayer3D).stream_paused = false
		(p as AudioStreamPlayer3D).stop()
	var until := Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < until:
		await tree.process_frame
	await tree.process_frame
	tree.quit()


## Switches between the player's FULL sound and traffic's LITE sound.
func set_detail(d: Detail) -> void:
	if d == detail and _built == d:
		return
	detail = d
	if AudioDirector.instance and d == Detail.FULL:
		AudioDirector.instance.unregister(self)
	_registered = false
	audible = true
	if is_node_ready():
		_build()


## Plays the start-up sound; the engine fades in when it catches.
func start_engine() -> void:
	if _startup_t >= 0.0 and _startup_t < 0.2:
		return  # already starting
	if profile and profile.startup and detail == Detail.FULL:
		_engine_fade = 0.0
		_startup_t = 0.0
		_shot(profile.startup, 0.0, 1.0)


## A short beep of the horn (traffic).
func honk(seconds := 0.45) -> void:
	_horn_until = _time + seconds


# ------------------------------------------------------------------ setup --

## Creates the "Player" and "Traffic" buses and a limiter on the master bus,
## once (no bus layout file to keep in sync).
static func ensure_buses() -> void:
	if AudioServer.get_bus_index("Player") >= 0:
		return
	var master := 0
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, limiter)
	for bus_name: String in ["Player", "Traffic"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	var player := AudioServer.get_bus_index("Player")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.4
	reverb.spread = 0.8
	reverb.predelay_msec = 35.0
	reverb.dry = 1.0
	reverb.wet = 0.0
	AudioServer.add_bus_effect(player, reverb)
	AudioServer.set_bus_effect_enabled(player, 0, false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Traffic"), -3.0)


func _build() -> void:
	for p in _on + _off + _shots:
		p.queue_free()
	for p: AudioStreamPlayer3D in _loops.values():
		p.queue_free()
	_on.clear()
	_off.clear()
	_shots.clear()
	_loops.clear()
	_built = detail
	var full := detail == Detail.FULL
	_on_rpm = profile.engine_on_rpm
	var picks := range(mini(profile.engine_on.size(), profile.engine_on_rpm.size()))
	if not full and picks.size() > LITE_LAYERS:
		# Traffic: a few loops spread over the range are plenty.
		var step := float(picks.size() - 1) / (LITE_LAYERS - 1)
		picks = range(LITE_LAYERS).map(func(k: int) -> int: return roundi(k * step))
		_on_rpm = PackedFloat32Array(picks.map(func(i: int) -> float: return profile.engine_on_rpm[i]))
	for i: int in picks:
		_on.append(_player(profile.engine_on[i], true))
	if full:
		for i in profile.engine_off.size():
			_off.append(_player(profile.engine_off[i], true))
		_add_loop("roll", VehicleSoundBank.loop(VehicleSoundBank.ROLL_ASPHALT))
		_add_loop("gravel", VehicleSoundBank.loop(VehicleSoundBank.ROLL_GRAVEL))
		_add_loop("skid", VehicleSoundBank.loop(VehicleSoundBank.SKID_GRAVEL))
		_add_loop("wind", VehicleSoundBank.loop(VehicleSoundBank.WIND))
		_add_loop("scrape", VehicleSoundBank.loop(VehicleSoundBank.SCRAPE))
		_add_loop("whine", profile.whine)
	else:
		_add_loop("roll", VehicleSoundBank.loop(VehicleSoundBank.ROLL_ASPHALT))
	_add_loop("squeal", VehicleSoundBank.loop(VehicleSoundBank.SQUEAL))
	_add_loop("horn", profile.horn)
	if profile.reverse_beeper:
		_add_loop("beeper", VehicleSoundBank.loop(VehicleSoundBank.BEEPER))
	for k in SHOTS[detail]:
		_shots.append(_player(null, false))
	if full:
		_prime.call_deferred()


## The player's loops start once, silently, and pause themselves 0.15 s later
## (_drive): from then on every start is a resume from silence, the path that
## measured click-free.
func _prime() -> void:
	if not is_inside_tree():
		return
	for p in _on + _off + Array(_loops.values()):
		var pl := p as AudioStreamPlayer3D
		if pl.stream and not pl.playing:
			pl.volume_db = -80.0
			pl.play(_rng.randf() * pl.stream.get_length())


func _add_loop(key: String, stream: AudioStream) -> void:
	if stream:
		_loops[key] = _player(stream, true)


func _player(stream: AudioStream, looping: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _own(stream)
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	if detail == Detail.FULL:
		p.bus = &"Player"
		p.unit_size = 14.0
		p.max_db = 0.0
		p.panning_strength = 0.5
		p.attenuation_filter_cutoff_hz = 20500.0
	else:
		p.bus = &"Traffic"
		p.unit_size = 7.0
		p.max_distance = 140.0
		p.panning_strength = 0.9
		p.attenuation_filter_cutoff_hz = 7000.0
		p.attenuation_filter_db = -18.0
	p.volume_db = -80.0
	p.set_meta("looping", looping)
	add_child(p)
	return p


# ------------------------------------------------------------------ frame --

func _process(dt: float) -> void:
	if vehicle == null or profile == null:
		return
	_time += dt
	_impact_cooldown -= dt
	_knock_cooldown -= dt
	_air_cooldown -= dt
	_squeal_cooldown -= dt
	if _startup_t >= 0.0:
		_startup_t += dt
		if _startup_t > profile.startup_catch:
			_engine_fade = move_toward(_engine_fade, 1.0, dt * 3.0)
			if _engine_fade >= 1.0:
				_startup_t = -1.0
	if detail == Detail.LITE and not _registered and AudioDirector.instance:
		AudioDirector.instance.register(self)
		_registered = true
	var live := detail == Detail.FULL or audible
	_update_doppler(dt)
	_update_engine(dt, live)
	_update_tyres(dt, live)
	_update_horn_and_beeper(live)
	if detail == Detail.FULL:
		_update_body(dt)
		_update_extras(dt)


## Pitch factor from the speed toward / away from the listener (traffic).
func _update_doppler(dt: float) -> void:
	_doppler = 1.0
	if detail == Detail.FULL or AudioDirector.instance == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - vehicle.global_position
	var dist := to_cam.length()
	if dist < 0.5:
		return
	var dir := to_cam / dist
	var v_src := vehicle.linear_velocity.dot(dir)
	var v_lis := AudioDirector.instance.listener_velocity.dot(dir)
	_doppler = clampf((SPEED_OF_SOUND + v_lis) / maxf(SPEED_OF_SOUND - v_src, 1.0), 0.85, 1.18)


func _update_engine(dt: float, live: bool) -> void:
	var p := profile
	var rpm := vehicle.engine_rpm * p.rpm_scale
	var idle := vehicle.idle_rpm * p.rpm_scale
	var red := vehicle.redline_rpm * p.rpm_scale
	var throttle := vehicle.engine_load
	# Load follows the throttle quickly up, a bit slower down.
	_load = move_toward(_load, throttle, dt * (10.0 if throttle > _load else 6.0))
	var rpm_t := clampf((rpm - idle) / maxf(red - idle, 1.0), 0.0, 1.0)
	var gain := db_to_linear(p.engine_volume_db + volume_db + (rpm_t - 1.0) * p.rpm_gain_db + (_load - 1.0) * p.load_gain_db)
	gain *= _engine_fade
	if not live:
		gain = 0.0
	# Rev limiter: the engine stutters against the cut at full throttle.
	if rpm >= red * 0.985 and throttle > 0.5:
		gain *= 0.65 if fmod(_time * 14.0, 1.0) < 0.5 else 1.0
	var on_w := sin(_load * PI * 0.5)
	var off_w := cos(_load * PI * 0.5)
	if _off.is_empty():
		on_w = 1.0
	var pitch_mul := _doppler
	_mix_set(_on, _on_rpm, rpm, gain * on_w, pitch_mul)
	_mix_set(_off, p.engine_off_rpm, rpm, gain * off_w, pitch_mul)
	if _loops.has("whine"):
		var w := db_to_linear(p.whine_volume_db + volume_db) * _load * _load * clampf(rpm / p.whine_rpm, 0.0, 1.3) * _engine_fade
		_set_loop("whine", w, clampf(rpm / p.whine_rpm, 0.3, 2.0) * pitch_mul)


## Plays the two loops of a set either side of `rpm`, crossfaded with equal
## power and pitched to match; everything else in the set is paused.
func _mix_set(players: Array[AudioStreamPlayer3D], rpms: PackedFloat32Array, rpm: float, gain: float, pitch_mul: float) -> void:
	var n := mini(players.size(), rpms.size())
	if n == 0:
		return
	var lo := 0
	while lo < n - 1 and rpms[lo + 1] <= rpm:
		lo += 1
	var hi := mini(lo + 1, n - 1)
	var w := 0.0
	if hi != lo and rpm > rpms[lo]:
		w = clampf((rpm - rpms[lo]) / (rpms[hi] - rpms[lo]), 0.0, 1.0)
	for i in n:
		var g := 0.0
		if i == lo:
			g = cos(w * PI * 0.5) if hi != lo else 1.0
		elif i == hi:
			g = sin(w * PI * 0.5)
		_drive(players[i], g * gain, clampf(rpm / rpms[i], 0.35, 2.6) * pitch_mul)


func _update_tyres(dt: float, live: bool) -> void:
	var speed := vehicle.linear_velocity.length()
	var grounded := 0
	var dirt := 0
	for w in vehicle.wheels:
		if w.grounded:
			grounded += 1
			if w.surface_grip < 0.95:
				dirt += 1
	var ground := float(grounded) / maxf(vehicle.wheels.size(), 1.0)
	var dirt_frac := float(dirt) / maxf(grounded, 1.0)
	var raw_skid := vehicle.get_skid_amount() if grounded > 0 else 0.0
	_skid = move_toward(_skid, raw_skid, dt * (8.0 if raw_skid > _skid else 3.0))
	var roll := smoothstep(0.3, 22.0, speed) * ground
	var near := 1.0
	if detail == Detail.LITE:
		near = 1.0 - smoothstep(18.0, 35.0, _listener_distance())
	if not live:
		roll = 0.0
		near = 0.0
	var roll_pitch := clampf(0.65 + speed / 38.0, 0.6, 1.7) * _doppler
	_set_loop("roll", roll * (1.0 - dirt_frac) * 0.9 * near, roll_pitch)
	_set_loop("gravel", roll * dirt_frac, clampf(0.75 + speed / 45.0, 0.7, 1.5))
	var squeal := _skid * (1.0 - dirt_frac) * near
	_set_loop("squeal", squeal * 0.8, (0.92 + _skid * 0.12 + 0.03 * sin(_time * 5.3)) * _doppler)
	_set_loop("skid", _skid * dirt_frac, 0.9 + _skid * 0.2)


func _update_horn_and_beeper(live: bool) -> void:
	var horn_on := vehicle.horn_input or _time < _horn_until
	if _loops.has("horn"):
		_set_loop("horn", (db_to_linear(profile.horn_volume_db + volume_db) if horn_on and (live or detail == Detail.LITE) else 0.0),
			profile.horn_pitch * _doppler, true)
	if _loops.has("beeper"):
		var reversing := vehicle.gear == -1 and (vehicle.brake_input > 0.1 or absf(vehicle.forward_speed) > 0.3)
		_set_loop("beeper", 0.5 if reversing and live else 0.0, 1.0, true)


## Wind, scraping, suspension, splash and tunnel reverb (FULL).
func _update_body(dt: float) -> void:
	var speed := vehicle.linear_velocity.length()
	var wind := clampf(speed / 50.0, 0.0, 1.2)
	_set_loop("wind", wind * wind * 0.8, clampf(0.75 + speed / 70.0, 0.75, 1.6))
	var raw := clampf((vehicle.scrape_speed - 1.5) / 14.0, 0.0, 1.0)
	_scrape = move_toward(_scrape, raw, dt * (12.0 if raw > _scrape else 5.0))
	_set_loop("scrape", _scrape * 0.9, 0.8 + _scrape * 0.4)
	# Suspension knocks over kerbs and bumps.
	var bump := 0.0
	for w in vehicle.wheels:
		bump = maxf(bump, w.compression_speed)
	if bump > 1.1 and _knock_cooldown <= 0.0 and vehicle.airtime == 0.0:
		_knock_cooldown = 0.14
		var k := clampf((bump - 1.1) / 2.5, 0.15, 1.0)
		_shot(VehicleSoundBank.pick("suspension/knock", _rng), linear_to_db(k) - 6.0, _size_pitch() * _rng.randf_range(0.92, 1.08))
	# Into the sea.
	var wet := vehicle.global_position.y < MapLayout.SEA_LEVEL - 0.3
	if wet and not _splashed and speed > 2.0:
		_shot(VehicleSoundBank.pick("body/splash", _rng), 0.0, _rng.randf_range(0.9, 1.05))
	_splashed = wet
	_update_enclosure(dt)


## Reverb when something is overhead (tunnels, under bridges and overpasses).
func _update_enclosure(dt: float) -> void:
	_enclosure_timer -= dt
	if _enclosure_timer <= 0.0:
		_enclosure_timer = 0.2
		var space := vehicle.get_world_3d().direct_space_state
		var from := vehicle.global_position + Vector3.UP * (vehicle.body_top + 0.3)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 14.0, 1)
		q.exclude = [vehicle.get_rid()]
		var covered := not space.intersect_ray(q).is_empty()
		_enclosure = 1.0 if covered else 0.0
	var bus := AudioServer.get_bus_index("Player")
	if bus < 0:
		return
	var reverb := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	if reverb == null:
		return
	reverb.wet = move_toward(reverb.wet, _enclosure * 0.32, dt * 0.8)
	AudioServer.set_bus_effect_enabled(bus, 0, reverb.wet > 0.005)


## Gear changes, turbo blow-off, exhaust pops, brakes (FULL).
func _update_extras(dt: float) -> void:
	var p := profile
	# The pedal, not engine load (load drops during every gear change).
	var throttle := vehicle.throttle_input if vehicle.gear >= 1 else 0.0
	var red := vehicle.redline_rpm
	if vehicle.gear != _last_gear:
		if vehicle.gear > _last_gear and _last_gear >= 1 and p.shift:
			_shot(p.shift, p.shift_volume_db, _rng.randf_range(0.95, 1.05))
		_last_gear = vehicle.gear
	# Lifting off after hard throttle at high revs.
	if throttle > 0.8 and vehicle.engine_rpm > red * 0.55:
		_peak_load_time += dt
	var lifted := _prev_throttle > 0.6 and throttle < 0.1 and vehicle.gear >= 1
	if lifted and _peak_load_time > 0.4:
		if p.blowoff:
			_shot(p.blowoff, -6.0, _rng.randf_range(0.95, 1.08))
		if not p.pops.is_empty() and vehicle.engine_rpm > red * 0.6:
			_pops_left = _rng.randi_range(3, 7)
			_pop_timer = 0.05
	if throttle > 0.1 or lifted:
		if throttle < 0.8:
			_peak_load_time = 0.0
	_prev_throttle = throttle
	if _pops_left > 0:
		_pop_timer -= dt
		if _pop_timer <= 0.0:
			_pops_left -= 1
			_pop_timer = _rng.randf_range(0.04, 0.16)
			_shot(p.pops[_rng.randi() % p.pops.size()], p.pops_volume_db + _rng.randf_range(-6.0, 0.0), _rng.randf_range(0.85, 1.15))
	# Brakes: an occasional squeal as a car stops, air brakes on big ones.
	var speed := absf(vehicle.forward_speed)
	if vehicle.is_braking and speed > 2.0:
		_braked_from = maxf(_braked_from, speed)
	if speed < 2.5 and speed > 0.6 and vehicle.is_braking and _braked_from > 5.0 and _squeal_cooldown <= 0.0 and p.air_brake == null:
		_squeal_cooldown = 8.0
		if _rng.randf() < 0.35:
			_shot(VehicleSoundBank.pick("brake/squeal", _rng), -16.0, _rng.randf_range(0.9, 1.1))
	if speed < 0.3:
		if p.air_brake and _braked_from > 3.0 and _air_cooldown <= 0.0:
			_air_cooldown = 4.0
			_shot(p.air_brake, -4.0, _rng.randf_range(0.95, 1.05))
		_braked_from = 0.0


# ---------------------------------------------------------------- impacts --

func _on_impact(strength: float, pos: Vector3, _normal: Vector3) -> void:
	if detail == Detail.LITE:
		if _listener_distance() > 130.0:
			return
		# Hit by the player's car: its own sound plays the crash once.
		var other := vehicle.last_impact_collider as Vehicle
		var other_audio := other.get_node_or_null("Audio") as VehicleAudio if other else null
		if other_audio and other_audio.detail == Detail.FULL:
			return
	var mass_scale := maxf(vehicle.mass / 1300.0, 1.0)
	var s := clampf(strength / (26000.0 * mass_scale), 0.0, 1.0)
	if _impact_cooldown > 0.0 and s < 0.5:
		return
	_impact_cooldown = 0.09
	var what := _material_of(vehicle.last_impact_collider)
	var pitch := _size_pitch() * _rng.randf_range(0.92, 1.08)
	var vol := linear_to_db(clampf(0.35 + s * 0.8, 0.0, 1.0))
	match what:
		"plastic", "wood", "metal":
			_shot_at(VehicleSoundBank.pick("impact/" + what, _rng), pos, vol, _rng.randf_range(0.9, 1.1))
			if s > 0.25:
				_shot_at(VehicleSoundBank.pick("impact/thud", _rng), pos, vol - 6.0, pitch)
		_:
			if s < 0.18:
				_shot_at(VehicleSoundBank.pick("impact/thud", _rng), pos, vol, pitch)
			elif s < 0.5:
				_shot_at(VehicleSoundBank.pick("impact/crunch", _rng), pos, vol, pitch)
			else:
				_shot_at(VehicleSoundBank.pick("impact/crash", _rng), pos, vol, pitch)
				_shot_at(VehicleSoundBank.pick("impact/deform", _rng), pos, vol - 5.0, pitch * 0.9)


func _on_landed(airtime: float) -> void:
	var s := clampf(airtime / 2.0, 0.2, 1.0)
	var set_name := "suspension/land" if airtime > 0.8 else "suspension/knock"
	_shot(VehicleSoundBank.pick(set_name, _rng), linear_to_db(s) - 2.0, _size_pitch() * _rng.randf_range(0.93, 1.05))


func _on_broke(what: String, pos: Vector3) -> void:
	if what == "glass":
		_shot_at(VehicleSoundBank.pick("impact/glass", _rng), pos, -1.0, _rng.randf_range(0.95, 1.08))
	else:
		_shot_at(VehicleSoundBank.pick("impact/tinkle", _rng), pos, -4.0, _rng.randf_range(0.9, 1.15))


## A part came off: it clatters when it hits the ground (a few times).
func _on_detached(debris: RigidBody3D) -> void:
	_shot_at(VehicleSoundBank.pick("impact/plastic", _rng), debris.global_position, -3.0, _rng.randf_range(0.85, 1.0))
	debris.contact_monitor = true
	debris.max_contacts_reported = 1
	var player := AudioStreamPlayer3D.new()
	player.bus = &"Player" if detail == Detail.FULL else &"Traffic"
	player.unit_size = 6.0
	player.max_distance = 80.0
	debris.add_child(player)
	var hits := [0, 0.0]
	debris.body_entered.connect(func(_b: Node) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		var v := debris.linear_velocity.length()
		if hits[0] >= 4 or now - float(hits[1]) < 0.15 or v < 1.5:
			return
		hits[0] += 1
		hits[1] = now
		player.stream = _own(VehicleSoundBank.pick("impact/debris", _rng))
		player.volume_db = linear_to_db(clampf(v / 8.0, 0.2, 1.0)) - 2.0
		player.pitch_scale = _rng.randf_range(0.85, 1.15)
		player.play())


func _on_reset() -> void:
	_skid = 0.0
	_scrape = 0.0
	_pops_left = 0
	_braked_from = 0.0


## What the vehicle hit, for picking a sound: "car", "wall", "plastic",
## "wood" or "metal".
func _material_of(collider: Object) -> String:
	if collider is Vehicle:
		return "car"
	var node := collider as Node
	if node == null:
		return "wall"
	if node.has_meta("impact_sound"):
		return node.get_meta("impact_sound")
	var path := node.scene_file_path.get_file()
	if path.is_empty():
		return "wall"
	if path.begins_with("parked"):
		return "car"
	if "cone" in path or "pin" in path or "bin" in path:
		return "plastic"
	if "crate" in path or "bench" in path:
		return "wood"
	if "lamp" in path or "signal" in path or "hydrant" in path or "barrel" in path or "cabinet" in path:
		return "metal"
	return "wall"


# --------------------------------------------------------------- players --

## Bigger vehicles sound lower.
## This vehicle's own copy of a stream (the sample data is shared). Godot
## can leave a playback that was still fading out at quit registered with
## the AudioServer; if it held the cached res:// stream, the engine would
## report it as a resource still in use (an ERROR the release smoke test
## rejects). Copies aren't in the resource cache.
func _own(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	if not _copies.has(stream):
		var copy := stream.duplicate() as AudioStream
		copy.resource_name = stream.resource_path.get_file()
		_copies[stream] = copy
	return _copies[stream]


func _size_pitch() -> float:
	return clampf(1.0 / sqrt(profile.size), 0.7, 1.15)


func _listener_distance() -> float:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position.distance_to(vehicle.global_position) if cam else 0.0


## Sets a looping player's level (linear) and pitch; pauses it when silent
## so it costs nothing, and resumes it (from a random point) when needed.
## `instant` loops (horn, beeper) restart from the top.
func _set_loop(key: String, gain: float, pitch: float, instant := false) -> void:
	var p: AudioStreamPlayer3D = _loops.get(key)
	if p:
		_drive(p, gain, pitch, instant)


## Godot ramps volume changes over a mix block, but starting or pausing a
## stream cuts it at once: so a loop fades in from silence over FADE_IN s
## when it (re)starts, and only pauses after being silent for a moment.
const FADE_IN := 0.04
const PAUSE_AFTER := 0.15


func _drive(p: AudioStreamPlayer3D, gain: float, pitch: float, instant := false) -> void:
	var dt := get_process_delta_time()
	if gain < 0.002:
		if p.playing and not p.stream_paused:
			p.volume_db = -80.0
			var quiet: float = p.get_meta("quiet", 0.0) + dt
			p.set_meta("quiet", quiet)
			if quiet >= PAUSE_AFTER:
				p.stream_paused = true
				if on_voice.is_valid():
					on_voice.call(p.stream.resource_name, "pause %s %d" % [vehicle.name, get_instance_id()])
		p.set_meta("ramp", 0.0)
		return
	p.set_meta("quiet", 0.0)
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	# play() only takes effect on the player's next physics tick (until then
	# `playing` is still false): don't start it twice.
	if p.get_meta("starting", false):
		if not p.playing:
			return
		p.set_meta("starting", false)
	if not p.playing or p.stream_paused:
		p.set_meta("ramp", 0.0)
		p.volume_db = -80.0
		if not p.playing:
			var length := p.stream.get_length() if p.stream else 0.0
			p.play(0.0 if instant or length <= 0.0 else _rng.randf() * length)
			p.set_meta("starting", true)
		else:
			p.stream_paused = false
			if instant:
				p.seek(0.0)
		if on_voice.is_valid():
			on_voice.call(p.stream.resource_name, "start %s %d" % [vehicle.name, get_instance_id()])
		return
	var ramp := minf(float(p.get_meta("ramp", 1.0)) + dt / FADE_IN, 1.0)
	p.set_meta("ramp", ramp)
	p.volume_db = linear_to_db(gain * ramp)


func _shot(stream: AudioStream, vol_db: float, pitch: float) -> void:
	_shot_at(stream, vehicle.global_position, vol_db, pitch)


## A one-shot from the vehicle's small pool (the oldest is cut off if all are
## busy), played at `pos`.
func _shot_at(stream: AudioStream, pos: Vector3, vol_db: float, pitch: float) -> void:
	if stream == null or _shots.is_empty():
		return
	var p := _shots[_shot_i]
	_shot_i = (_shot_i + 1) % _shots.size()
	p.stream = _own(stream)
	p.global_position = pos
	p.volume_db = vol_db + volume_db
	p.pitch_scale = pitch
	p.play()
	if on_shot.is_valid():
		on_shot.call(stream.resource_path, pos)
