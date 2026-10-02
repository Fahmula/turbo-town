class_name VehicleSoundBank
extends RefCounted
## Sounds every vehicle shares: tyres, wind, scraping, crashes and knocks,
## glass, suspension, brakes, splashes. Loaded once on first use. A "set" is
## numbered variants (`impact/crash_1.wav`, `impact/crash_2.wav`...), picked
## at random without repeating the last one. Files are made by
## tools/audio/build_audio.py; sources and licences are in ASSET_MANIFEST.md.

const DIR := "res://assets/audio/"

## Loops (one file each).
const ROLL_ASPHALT := "tyre/roll_asphalt.wav"
const ROLL_GRAVEL := "tyre/roll_gravel.wav"
const SQUEAL := "tyre/squeal.wav"
const SKID_GRAVEL := "tyre/skid_gravel.wav"
const WIND := "body/wind.wav"
const SCRAPE := "body/scrape.wav"
const BEEPER := "body/reverse_beeper.wav"

static var _sets := {}
static var _loops := {}
static var _last := {}


## One looping stream (null if the file is missing).
static func loop(path: String) -> AudioStream:
	if not _loops.has(path):
		_loops[path] = load(DIR + path) if ResourceLoader.exists(DIR + path) else null
	return _loops[path]


## All variants of a set, e.g. "impact/crash" -> crash_1.wav, crash_2.wav...
static func variants(set_name: String) -> Array:
	if not _sets.has(set_name):
		var list := []
		var k := 1
		while ResourceLoader.exists("%s%s_%d.wav" % [DIR, set_name, k]):
			list.append(load("%s%s_%d.wav" % [DIR, set_name, k]))
			k += 1
		_sets[set_name] = list
	return _sets[set_name]


## A random variant of a set, never the same one twice in a row.
static func pick(set_name: String, rng: RandomNumberGenerator) -> AudioStream:
	var list := variants(set_name)
	if list.is_empty():
		return null
	var i := rng.randi() % list.size()
	if list.size() > 1 and i == int(_last.get(set_name, -1)):
		i = (i + 1 + rng.randi() % (list.size() - 1)) % list.size()
	_last[set_name] = i
	return list[i]


## Drops the cache (at exit, so no cached stream outlives the engine).
static func clear() -> void:
	_sets.clear()
	_loops.clear()
	_last.clear()
