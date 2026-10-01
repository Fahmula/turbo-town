extends Node
## Player settings, saved to user://settings.cfg (autoload "Settings").
##
## Read a value with Settings.get_value("traffic_density"), change it with
## Settings.set_value(...) — that saves the file and emits `changed`, so the
## systems that care (HUD, traffic, graphics...) update right away.
## Dev/test runs (any command-line user args) never load or save the file, so
## they always start from the defaults.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"

## Key -> default value.
const DEFAULTS := {
	"units_mph": false,
	"traffic_density": 1,  # 0 few, 1 normal, 2 busy
	"graphics": 2,  # 0 low, 1 medium, 2 high
	"fullscreen": false,
	"master_volume": 0.8,
	"vibration": true,
	"minimap": true,
	"time_of_day": 0,  # 0 day, 1 sunset, 2 night, 3 cycle
	"assists": true,
	"vehicle": "sports_car",
	"paint": Color(0.93, 0.22, 0.14),
}

const TRAFFIC_LABELS := ["Few", "Normal", "Busy"]
const TRAFFIC_CARS := [10, 22, 30]
const GRAPHICS_LABELS := ["Low", "Medium", "High"]
const TIME_LABELS := ["Day", "Sunset", "Night", "Day & night"]

## False for dev/test runs: nothing is read from or written to disk.
var persist := OS.get_cmdline_user_args().is_empty()
var path := PATH

var _values := {}


func _enter_tree() -> void:
	_values = DEFAULTS.duplicate()
	if persist:
		load_file()


func _ready() -> void:
	_apply_global("master_volume")
	if get_value("fullscreen"):
		_apply_global("fullscreen")


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply_global(key)
	save_file()
	changed.emit(key, value)


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var v: Variant = cfg.get_value("settings", key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]):
			_values[key] = v
	# Garage choice saved by an older build (before this file had a section).
	if cfg.has_section_key("player", "vehicle") and not cfg.has_section_key("settings", "vehicle"):
		_values["vehicle"] = cfg.get_value("player", "vehicle")
		_values["paint"] = cfg.get_value("player", "paint", DEFAULTS["paint"])


func save_file() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value("settings", key, _values[key])
	cfg.save(path)


## Settings that belong to the whole app rather than to one scene.
func _apply_global(key: String) -> void:
	match key:
		"master_volume":
			var v: float = get_value("master_volume")
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(0, v <= 0.001)
		"fullscreen":
			if DisplayServer.get_name() == "headless":
				return
			var full: bool = get_value("fullscreen")
			var mode := DisplayServer.window_get_mode()
			var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if full != is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
