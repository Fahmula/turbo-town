class_name AudioMix
extends RefCounted
## The game's audio mix (ART_BIBLE.md §33): the bus layout, the processing on
## each bus and its settings, per speaker profile.
##
## Buses (each sends to the one in brackets):
##   Master                 speaker tone (high-pass, high shelf), glue
##                          compressor, limiter (headroom: ceiling -1 dBFS)
##   Player [Master]        the player's vehicle; tunnel reverb (VehicleAudio)
##     Engine [Player]      engine layers, start-up, turbo, pops, shifts: tone
##                          EQ, harmonic exciter, compressor
##     Tyres [Player]       road roll, suspension knocks and landings
##     Surface [Player]     gravel / grass roll and slides
##     Skid [Player]        tyre squeal, air brakes: de-harsh shelf, low-pass,
##                          compressor
##     Impacts [Player]     crashes, metal, glass, debris, scraping: thump
##                          shelf, de-harsh shelf, low-pass, compressor, limiter
##     Environment [Player] wind, splashes
##     Signals [Player]     horn, reverse beeper
##   Traffic [Master]       every traffic sound but engines: de-harsh shelf,
##                          compressor
##     TrafficEngine [Traffic]  traffic engines: the Engine tone and exciter
##   UI [Master]            menu sounds (none yet)
##
## The harmonic exciter is Godot's distortion in waveshape mode: it only
## saturates what is below `crossover_hz` and passes the rest untouched, so an
## engine's 60-250 Hz firing note gains odd harmonics at 200 Hz-1.2 kHz, the
## range small speakers (the Steam Deck's) can play. Without it, they lose
## most of an engine recording and the engine sinks under tyres and crashes.
##
## Profiles: "flat" (PC speakers, headphones) and "deck" (the Steam Deck's own
## speakers). Settings "speakers" picks one (Auto: deck on a Steam Deck).
## Values: DEFAULTS below, then res://assets/audio/mix.cfg (tuned defaults,
## committed), then user://audio_mix.cfg (saved from the dev audio panel;
## only in normal runs, never in tests).

const PROFILES: Array[String] = ["flat", "deck"]
const DEFAULTS_PATH := "res://assets/audio/mix.cfg"
const USER_PATH := "user://audio_mix.cfg"

## Bus, parent, effect names in chain order.
const LAYOUT := [
	["Player", "Master", ["reverb"]],
	["Traffic", "Master", ["treble", "comp"]],
	["UI", "Master", []],
	["Engine", "Player", ["eq", "harmonics", "comp"]],
	["Tyres", "Player", ["bass", "treble"]],
	["Surface", "Player", ["treble"]],
	["Skid", "Player", ["treble", "lowpass", "comp"]],
	["Impacts", "Player", ["thump", "treble", "lowpass", "comp", "limiter"]],
	["Environment", "Player", ["treble"]],
	["Signals", "Player", ["treble"]],
	["TrafficEngine", "Traffic", ["eq", "harmonics"]],
]
const MASTER_FX: Array[String] = ["highpass", "treble", "comp", "limiter"]

## Parameter group (the part of a key before the dot) -> bus.
const GROUP_BUS := {
	"master": "Master", "player": "Player", "traffic": "Traffic", "ui": "UI",
	"engine": "Engine", "tyres": "Tyres", "surface": "Surface", "skid": "Skid",
	"impacts": "Impacts", "environment": "Environment", "signals": "Signals",
	"traffic_engine": "TrafficEngine",
}

## Every tunable value: key, label, min, max, step. Keys ending in "_on" are
## switches (0/1). The dev panel lists them in this order, one group per bus.
const SPECS := [
	["master.gain_db", "Master gain (into limiter)", -12.0, 12.0, 0.5],
	["master.highpass_hz", "Master bass cut (high-pass Hz, 20 = off)", 20.0, 300.0, 5.0],
	["master.treble_db", "Master treble (high shelf dB)", -12.0, 6.0, 0.5],
	["master.treble_hz", "Master treble shelf from (Hz)", 1500.0, 10000.0, 100.0],
	["master.comp_threshold_db", "Master glue comp threshold", -30.0, 0.0, 0.5],
	["master.comp_ratio", "Master glue comp ratio (real)", 1.0, 10.0, 0.1],
	["master.ceiling_db", "Master limiter ceiling", -6.0, 0.0, 0.1],
	["player.volume_db", "Player vehicle (group)", -24.0, 12.0, 0.5],
	["engine.volume_db", "Engine", -24.0, 12.0, 0.5],
	["engine.eq_on", "Engine tone EQ", 0.0, 1.0, 1.0],
	["engine.eq_62", "Engine EQ 31-62 Hz (sub)", -24.0, 12.0, 0.5],
	["engine.eq_125", "Engine EQ 125 Hz", -24.0, 12.0, 0.5],
	["engine.eq_250", "Engine EQ 250 Hz (body)", -12.0, 12.0, 0.5],
	["engine.eq_500", "Engine EQ 500 Hz", -12.0, 12.0, 0.5],
	["engine.eq_1k", "Engine EQ 1 kHz (presence)", -12.0, 12.0, 0.5],
	["engine.eq_2k", "Engine EQ 2 kHz (bite)", -12.0, 12.0, 0.5],
	["engine.eq_4k", "Engine EQ 4k+ (fizz)", -12.0, 6.0, 0.5],
	["engine.harmonics_on", "Engine harmonic exciter", 0.0, 1.0, 1.0],
	["engine.harmonics_drive_db", "Exciter drive (dB into saturation)", 0.0, 30.0, 0.5],
	["engine.harmonics_shape", "Exciter hardness", 0.0, 0.9, 0.05],
	["engine.harmonics_trim_db", "Exciter output trim (0 = unity)", -12.0, 12.0, 0.5],
	["engine.crossover_hz", "Exciter works below (Hz)", 80.0, 1000.0, 10.0],
	["engine.comp_threshold_db", "Engine comp threshold", -40.0, 0.0, 0.5],
	["engine.comp_ratio", "Engine comp ratio (real)", 1.0, 10.0, 0.1],
	["engine.comp_makeup_db", "Engine comp makeup", -6.0, 18.0, 0.5],
	["tyres.volume_db", "Tyres / road", -24.0, 12.0, 0.5],
	["tyres.bass_db", "Tyres low shelf (<150 Hz)", -18.0, 6.0, 0.5],
	["tyres.treble_db", "Tyres high shelf (>2 kHz)", -18.0, 6.0, 0.5],
	["surface.volume_db", "Surface (gravel, grass)", -24.0, 12.0, 0.5],
	["surface.treble_db", "Surface high shelf (>3 kHz)", -18.0, 6.0, 0.5],
	["skid.volume_db", "Skid / brakes", -24.0, 12.0, 0.5],
	["skid.treble_db", "Skid de-harsh shelf", -18.0, 6.0, 0.5],
	["skid.treble_hz", "Skid shelf from (Hz)", 1000.0, 8000.0, 100.0],
	["skid.lowpass_hz", "Skid low-pass (Hz, 20000 = off)", 2000.0, 20000.0, 250.0],
	["skid.comp_threshold_db", "Skid comp threshold", -40.0, 0.0, 0.5],
	["skid.comp_ratio", "Skid comp ratio (real)", 1.0, 20.0, 0.1],
	["impacts.volume_db", "Impacts / damage", -24.0, 12.0, 0.5],
	["impacts.thump_db", "Impacts low shelf (<120 Hz, power)", -12.0, 12.0, 0.5],
	["impacts.treble_db", "Impacts de-harsh shelf", -18.0, 6.0, 0.5],
	["impacts.treble_hz", "Impacts shelf from (Hz)", 1000.0, 8000.0, 100.0],
	["impacts.lowpass_hz", "Impacts low-pass (Hz, 20000 = off)", 2000.0, 20000.0, 250.0],
	["impacts.comp_threshold_db", "Impacts comp threshold", -40.0, 0.0, 0.5],
	["impacts.comp_ratio", "Impacts comp ratio (real)", 1.0, 20.0, 0.5],
	["impacts.ceiling_db", "Impacts limiter ceiling", -18.0, 0.0, 0.5],
	["environment.volume_db", "Environment (wind, water)", -24.0, 12.0, 0.5],
	["environment.treble_db", "Environment high shelf (>3 kHz)", -18.0, 6.0, 0.5],
	["signals.volume_db", "Horn / beeper", -24.0, 12.0, 0.5],
	["signals.treble_db", "Horn high shelf (>3 kHz)", -18.0, 6.0, 0.5],
	["traffic.volume_db", "Traffic (group)", -24.0, 12.0, 0.5],
	["traffic_engine.volume_db", "Traffic engines", -24.0, 12.0, 0.5],
	["traffic.treble_db", "Traffic high shelf (>3 kHz)", -18.0, 6.0, 0.5],
	["traffic.comp_threshold_db", "Traffic comp threshold", -40.0, 0.0, 0.5],
	["ui.volume_db", "UI", -24.0, 12.0, 0.5],
]

## Code defaults ("flat"); "deck" starts from these plus DECK.
const FLAT := {
	"master.gain_db": 0.0, "master.highpass_hz": 20.0, "master.treble_db": 0.0, "master.treble_hz": 5000.0,
	"master.comp_threshold_db": -10.0, "master.comp_ratio": 2.0, "master.ceiling_db": -1.0,
	"player.volume_db": 4.0,
	"engine.volume_db": 1.5, "engine.eq_on": 0.0, "engine.eq_62": 0.0, "engine.eq_125": 0.0, "engine.eq_250": 0.0,
	"engine.eq_500": 0.0, "engine.eq_1k": 0.0, "engine.eq_2k": 0.0, "engine.eq_4k": 0.0,
	"engine.harmonics_on": 1.0, "engine.harmonics_drive_db": 9.0, "engine.harmonics_shape": 0.3,
	"engine.harmonics_trim_db": 0.0, "engine.crossover_hz": 300.0,
	"engine.comp_threshold_db": -14.0, "engine.comp_ratio": 2.0, "engine.comp_makeup_db": 0.0,
	"tyres.volume_db": -3.0, "tyres.bass_db": 0.0, "tyres.treble_db": -3.0,
	"surface.volume_db": 3.0, "surface.treble_db": -4.0,
	"skid.volume_db": 0.0, "skid.treble_db": -6.0, "skid.treble_hz": 2500.0, "skid.lowpass_hz": 9000.0,
	"skid.comp_threshold_db": -22.0, "skid.comp_ratio": 3.0,
	"impacts.volume_db": 2.0, "impacts.thump_db": 3.0, "impacts.treble_db": -9.0, "impacts.treble_hz": 2500.0,
	"impacts.lowpass_hz": 9000.0, "impacts.comp_threshold_db": -20.0, "impacts.comp_ratio": 4.0, "impacts.ceiling_db": -4.0,
	"environment.volume_db": -2.0, "environment.treble_db": -3.0,
	"signals.volume_db": 0.0, "signals.treble_db": -2.0,
	"traffic.volume_db": -3.0, "traffic_engine.volume_db": 0.0, "traffic.treble_db": -4.0, "traffic.comp_threshold_db": -18.0,
	"ui.volume_db": 0.0,
}
const DECK := {
	"master.gain_db": 5.0, "master.highpass_hz": 110.0, "master.treble_db": -3.0,
	"engine.volume_db": 2.0, "engine.eq_on": 1.0, "engine.eq_62": -18.0, "engine.eq_125": -6.0, "engine.eq_250": 3.0,
	"engine.eq_500": 6.0, "engine.eq_1k": 6.0, "engine.eq_2k": 2.0,
	"engine.harmonics_drive_db": 15.0, "engine.harmonics_shape": 0.45, "engine.crossover_hz": 350.0,
	"engine.comp_threshold_db": -20.0, "engine.comp_ratio": 2.5, "engine.comp_makeup_db": 2.0,
	"tyres.volume_db": -1.0, "surface.volume_db": 2.0, "skid.volume_db": -2.0, "skid.treble_db": -9.0,
	"impacts.volume_db": 0.0, "impacts.treble_db": -9.0, "environment.volume_db": -2.0, "signals.volume_db": -2.0,
}

static var _values := {}  # profile -> {key: value}
static var _defaults := {}  # profile -> {key: value}, before user overrides
static var _profile := "flat"
static var _loaded := false


static func profile() -> String:
	return _profile


## "speakers" setting (0 auto, 1 on, 2 off) -> profile. `--speakers=on|off`
## on the command line overrides it.
static func profile_for_setting(setting: int) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--speakers=on":
			return "deck"
		if arg == "--speakers=off":
			return "flat"
	return "deck" if setting == 1 or (setting == 0 and is_steam_deck()) else "flat"


## Steam sets SteamDeck=1 for games on the Deck; the DMI product name covers
## launching it some other way (Jupiter: LCD model, Galileo: OLED).
static func is_steam_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	var f := FileAccess.open("/sys/devices/virtual/dmi/id/product_name", FileAccess.READ)
	if f == null:
		return false
	var product := f.get_line().strip_edges()
	return product == "Jupiter" or product == "Galileo"


static func set_profile(p: String) -> void:
	_load()
	_profile = p if p in PROFILES else "flat"
	apply_all()


static func value(key: String) -> float:
	_load()
	return float(_values[_profile].get(key, FLAT.get(key, 0.0)))


static func default_value(key: String) -> float:
	_load()
	return float(_defaults[_profile].get(key, 0.0))


## Changes a value of the current profile and applies it at once.
static func set_value(key: String, v: float) -> void:
	_load()
	_values[_profile][key] = v
	_apply(key)


static func reset_profile() -> void:
	_load()
	_values[_profile] = _defaults[_profile].duplicate()
	apply_all()


## Creates the buses and their effects (once), then applies the values.
static func ensure() -> void:
	if AudioServer.get_bus_index(&"Player") >= 0:
		return
	_load()
	for fx: AudioEffect in [_filter(AudioEffectHighPassFilter.new(), 20.0, AudioEffectFilter.FILTER_12DB),
			_filter(AudioEffectHighShelfFilter.new(), 5000.0), _compressor(2000.0, 200.0), _limiter()]:
		AudioServer.add_bus_effect(0, fx)
	for entry: Array in LAYOUT:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, entry[0])
		AudioServer.set_bus_send(idx, entry[1])
		for fx_name: String in entry[2]:
			AudioServer.add_bus_effect(idx, _make(entry[0], fx_name))
	apply_all()


static func apply_all() -> void:
	if AudioServer.get_bus_index(&"Player") < 0:
		return
	for spec: Array in SPECS:
		_apply(spec[0])


## Saves the values that differ from the defaults, per profile.
static func save_user() -> Error:
	return _save(USER_PATH, true)


## Writes every value of both profiles as the new defaults (only possible when
## running from the project folder; exported builds can't write res://).
static func save_defaults() -> Error:
	var err := _save(DEFAULTS_PATH, false)
	if err == OK:
		for p in PROFILES:
			_defaults[p] = _values[p].duplicate()
	return err


static func can_save_defaults() -> bool:
	return not OS.has_feature("template")


static func user_file_path() -> String:
	return ProjectSettings.globalize_path(USER_PATH)


# ------------------------------------------------------------------ inside --

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var base := {"flat": FLAT.duplicate(), "deck": FLAT.duplicate()}
	base["deck"].merge(DECK, true)
	var cfg := ConfigFile.new()
	if cfg.load(DEFAULTS_PATH) == OK:
		_merge_cfg(base, cfg)
	_defaults = {"flat": base["flat"].duplicate(), "deck": base["deck"].duplicate()}
	# Saved tuning: normal runs only (tests start from the defaults).
	if _settings_persist() and cfg.load(USER_PATH) == OK:
		_merge_cfg(base, cfg)
	_values = base


## Settings.persist, looked up at run time: tool scripts (-s) have no
## autoloads to compile against.
static func _settings_persist() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null(^"Settings") if tree else null
	return settings != null and bool(settings.get("persist"))


static func _merge_cfg(into: Dictionary, cfg: ConfigFile) -> void:
	for p in PROFILES:
		if not cfg.has_section(p):
			continue
		for key in cfg.get_section_keys(p):
			if FLAT.has(key):
				into[p][key] = float(cfg.get_value(p, key))


static func _save(path: String, only_changes: bool) -> Error:
	_load()
	var cfg := ConfigFile.new()
	for p in PROFILES:
		for spec: Array in SPECS:
			var key: String = spec[0]
			var v: float = _values[p].get(key, 0.0)
			if not only_changes or not is_equal_approx(v, float(_defaults[p].get(key, 0.0))):
				cfg.set_value(p, key, v)
	return cfg.save(path)


static func _make(bus: String, fx_name: String) -> AudioEffect:
	match fx_name:
		"reverb":
			var r := AudioEffectReverb.new()
			r.room_size = 0.55
			r.damping = 0.4
			r.spread = 0.8
			r.predelay_msec = 35.0
			r.dry = 1.0
			r.wet = 0.0
			return r
		"eq":
			return AudioEffectEQ10.new()
		"harmonics":
			var d := AudioEffectDistortion.new()
			d.mode = AudioEffectDistortion.MODE_WAVESHAPE
			return d
		"comp":
			# Fast on hits and squeal (catch the transient), slower on the rest.
			return _compressor(100.0 if bus in ["Impacts", "Skid"] else 2000.0, 120.0)
		"limiter":
			return _limiter()
		"bass":
			return _filter(AudioEffectLowShelfFilter.new(), 150.0)
		"thump":
			return _filter(AudioEffectLowShelfFilter.new(), 120.0)
		"treble":
			return _filter(AudioEffectHighShelfFilter.new(), 2000.0 if bus == "Tyres" else 3000.0)
		"lowpass":
			return _filter(AudioEffectLowPassFilter.new(), 20000.0, AudioEffectFilter.FILTER_12DB)
	push_error("AudioMix: unknown effect %s" % fx_name)
	return AudioEffectAmplify.new()


static func _filter(f: AudioEffectFilter, cutoff: float, slope := AudioEffectFilter.FILTER_6DB) -> AudioEffectFilter:
	f.cutoff_hz = cutoff
	f.resonance = 0.5
	f.db = slope
	return f


## Godot's compressor attack runs 20-2000 us.
static func _compressor(attack_us: float, release_ms: float) -> AudioEffectCompressor:
	var c := AudioEffectCompressor.new()
	c.ratio = godot_ratio(2.0)  # its own default (4) over-compresses, see godot_ratio
	c.attack_us = attack_us
	c.release_ms = release_ms
	return c


static func _limiter() -> AudioEffectHardLimiter:
	var l := AudioEffectHardLimiter.new()
	l.ceiling_db = -1.0
	return l


static func _bus_index(bus: String) -> int:
	return AudioServer.get_bus_index(StringName(bus))


static func _fx_index(bus: String, fx_name: String) -> int:
	if bus == "Master":
		return MASTER_FX.find(fx_name)
	for entry: Array in LAYOUT:
		if entry[0] == bus:
			return (entry[2] as Array).find(fx_name)
	return -1


static func _fx(bus: String, fx_name: String) -> AudioEffect:
	var idx := _bus_index(bus)
	var i := _fx_index(bus, fx_name)
	return AudioServer.get_bus_effect(idx, i) if idx >= 0 and i >= 0 else null


static func _enable(bus: String, fx_name: String, on: bool) -> void:
	var idx := _bus_index(bus)
	var i := _fx_index(bus, fx_name)
	if idx >= 0 and i >= 0:
		AudioServer.set_bus_effect_enabled(idx, i, on)


## A shelf: `db` of boost (or cut) above / below its cutoff; 0 dB switches it
## off. Godot's shelf gain is 40*log10(gain) dB.
static func _set_shelf(bus: String, fx_name: String, db: float) -> void:
	var f := _fx(bus, fx_name) as AudioEffectFilter
	if f:
		f.gain = pow(10.0, db / 40.0)
	_enable(bus, fx_name, absf(db) > 0.05)


static func _apply(key: String) -> void:
	if AudioServer.get_bus_index(&"Player") < 0:
		return
	var v := value(key)
	var group := key.get_slice(".", 0)
	var bus: String = GROUP_BUS.get(group, "")
	if key.ends_with(".volume_db"):
		AudioServer.set_bus_volume_db(_bus_index(bus), v)
		return
	match key:
		"master.gain_db":
			(_fx("Master", "limiter") as AudioEffectHardLimiter).pre_gain_db = v
		"master.ceiling_db":
			(_fx("Master", "limiter") as AudioEffectHardLimiter).ceiling_db = v
		"master.highpass_hz":
			(_fx("Master", "highpass") as AudioEffectFilter).cutoff_hz = v
			_enable("Master", "highpass", v > 25.0)
		"master.treble_db":
			_set_shelf("Master", "treble", v)
		"master.treble_hz":
			(_fx("Master", "treble") as AudioEffectFilter).cutoff_hz = v
		"master.comp_threshold_db", "master.comp_ratio":
			_set_comp("Master", key, v)
		"engine.eq_on":
			for b in ["Engine", "TrafficEngine"]:
				_enable(b, "eq", v > 0.5)
		"engine.eq_62", "engine.eq_125", "engine.eq_250", "engine.eq_500", "engine.eq_1k", "engine.eq_2k", "engine.eq_4k":
			_apply_engine_eq()
		"engine.harmonics_on":
			for b in ["Engine", "TrafficEngine"]:
				_enable(b, "harmonics", v > 0.5)
		"engine.harmonics_drive_db", "engine.harmonics_shape", "engine.harmonics_trim_db", "engine.crossover_hz":
			for b in ["Engine", "TrafficEngine"]:
				var d := _fx(b, "harmonics") as AudioEffectDistortion
				var drive := value("engine.harmonics_drive_db")
				var shape := value("engine.harmonics_shape")
				# The waveshaper's gain for quiet signals is (1 + k): undo it
				# and the drive, so the trim is relative to unity and drive only
				# adds harmonics (and squeezes the loudest bass a little).
				var k := 2.0 * shape / (1.00001 - shape)
				d.pre_gain = drive
				d.drive = shape
				d.post_gain = value("engine.harmonics_trim_db") - drive - 20.0 * log(1.0 + k) / log(10.0)
				d.keep_hf_hz = value("engine.crossover_hz")
		"engine.comp_threshold_db", "engine.comp_ratio", "engine.comp_makeup_db":
			_set_comp("Engine", key, v)
		"tyres.bass_db":
			_set_shelf("Tyres", "bass", v)
		"impacts.thump_db":
			_set_shelf("Impacts", "thump", v)
		"tyres.treble_db", "surface.treble_db", "skid.treble_db", "impacts.treble_db", "environment.treble_db", \
				"signals.treble_db", "traffic.treble_db":
			_set_shelf(bus, "treble", v)
		"skid.treble_hz", "impacts.treble_hz":
			(_fx(bus, "treble") as AudioEffectFilter).cutoff_hz = v
		"skid.lowpass_hz", "impacts.lowpass_hz":
			(_fx(bus, "lowpass") as AudioEffectFilter).cutoff_hz = v
			_enable(bus, "lowpass", v < 19500.0)
		"skid.comp_threshold_db", "skid.comp_ratio", "impacts.comp_threshold_db", "impacts.comp_ratio", \
				"traffic.comp_threshold_db":
			_set_comp(bus, key, v)
		"impacts.ceiling_db":
			(_fx("Impacts", "limiter") as AudioEffectHardLimiter).ceiling_db = v
		_:
			push_error("AudioMix: no way to apply %s" % key)


static func _set_comp(bus: String, key: String, v: float) -> void:
	var c := _fx(bus, "comp") as AudioEffectCompressor
	if c == null:
		return
	if key.ends_with("threshold_db"):
		c.threshold = v
	elif key.ends_with("ratio"):
		c.ratio = godot_ratio(v)
	elif key.ends_with("makeup_db"):
		c.gain = v


## Godot 4.7's compressor doubles the overshoot before applying its ratio
## (gain reduction = 2.08 * over * (r - 1) / r), so its `ratio` is far
## stronger than it reads: 2 already over-compresses (louder in, quieter
## out). The mix values are real ratios (2 = 2:1); this converts them.
static func godot_ratio(real: float) -> float:
	var k := (1.0 - 1.0 / maxf(real, 1.0)) / 2.08136898
	return 1.0 / maxf(1.0 - k, 0.001)


## Godot's 10-band EQ (31 Hz ... 16 kHz) from the engine tone values.
static func _apply_engine_eq() -> void:
	var sub := value("engine.eq_62")
	var gains := [sub - 6.0, sub, value("engine.eq_125"), value("engine.eq_250"), value("engine.eq_500"),
		value("engine.eq_1k"), value("engine.eq_2k"), value("engine.eq_4k"), value("engine.eq_4k"), value("engine.eq_4k")]
	for b in ["Engine", "TrafficEngine"]:
		var eq := _fx(b, "eq") as AudioEffectEQ10
		for i in gains.size():
			eq.set_band_gain_db(i, gains[i])
