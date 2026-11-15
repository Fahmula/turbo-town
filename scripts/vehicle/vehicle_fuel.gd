class_name VehicleFuel
extends Node
## A vehicle's tank (petrol and diesel vehicles, the plane, the helicopter) or
## battery (`Vehicle.electric`): a child named "Fuel" of every vehicle a
## player has driven (LocalPlayer.adopt_vehicle adds it), so the 30 traffic
## cars carry none and cost nothing.
##
## The player who drives it calls burn() every physics tick: a full tank lasts
## about FULL_TANK_SECONDS of ordinary driving; full throttle at speed uses
## more, idling hardly any. Running out is a small moment, never a dead end:
## the vehicle keeps EMPTY_POWER (a car crawls at up to EMPTY_SPEED and
## sputters, an electric car goes slow and quiet), the plane keeps enough
## power to land, the helicopter sinks to a low hover and lands itself
## (Aircraft / Helicopter read `power`). Filling up happens by hand at a pump
## or charger (FuelPump, FillerFlap); fill() tops it up while the nozzle is
## in.
##
## The Fuel setting off: it never runs out and the gauge hides (`enabled`).

signal level_changed(level: float)
## The level dropped below LOW (the gauge turns red, a toast, the arrow).
signal got_low
## The tank ran dry.
signal emptied
## A fill-up reached the top.
signal filled

enum Kind { FUEL, BATTERY }

## Below this the gauge turns red and the arrow points to a station.
const LOW := 0.2
## A full tank lasts this long (s) driving normally.
const FULL_TANK_SECONDS := 600.0
## Fuel "units" a second of ordinary driving burns (see _use()); the tank
## holds FULL_TANK_SECONDS of that. Measured (--fuel): flat out (how a kid
## drives) ~10 min, gently on part throttle ~18 min, idling ~1.5 h.
const NORMAL_USE := 0.75
## An empty tank to full in this long (s) at a pump or charger.
const FILL_SECONDS := 4.0
## Empty: this much of the engine's power is left (petrol and electric):
## with the crawl speed below, enough to pull even the bus up a steep hill.
const EMPTY_POWER := 0.4
## Empty: a car crawls no faster than this (m/s, ~40 km/h).
const EMPTY_SPEED := 11.0
## Empty: a plane keeps this much power: enough to taxi to a pump; in the
## air it glides down gently (Aircraft.EMPTY_GLIDE_SINK) and lands itself.
const EMPTY_PLANE_POWER := 0.25

var vehicle: Vehicle
var kind := Kind.FUEL
## 0 (empty) .. 1 (full).
var level := 1.0
## False with the Fuel setting off: it never drains (and the HUD hides it).
var enabled := true
## The engine's power factor from fuel (1 = full power). Vehicle reads it.
var power := 1.0
## Empty and sputtering this tick (the engine sound cuts out; petrol only).
var sputtering := false
## The pump hose whose nozzle (or plug) is in the filler now, or null.
var nozzle: Node = null

var _was_low := false
var _sputter_t := 0.0
var _rng := RandomNumberGenerator.new()


## The Fuel of `v`, or null (a vehicle no player has driven).
static func of(v: Node) -> VehicleFuel:
	if v == null or not is_instance_valid(v):
		return null
	return v.get_node_or_null("Fuel") as VehicleFuel


## `v`'s Fuel, made (with `start_level`) if it has none yet.
static func ensure(v: Vehicle, start_level := 1.0) -> VehicleFuel:
	var f := of(v)
	if f:
		return f
	f = VehicleFuel.new()
	f.name = "Fuel"
	f.level = clampf(start_level, 0.0, 1.0)
	v.add_child(f)
	if v.get_node_or_null("FillerFlap") == null:
		v.add_child(FillerFlap.new())
	return f


## Is the Fuel setting on? (Dev and test runs start with it on too.)
static func setting_on() -> bool:
	return bool(Settings.get_value("fuel"))


func _ready() -> void:
	vehicle = get_parent() as Vehicle
	kind = Kind.BATTERY if vehicle and vehicle.electric else Kind.FUEL
	_rng.seed = hash(vehicle.name) if vehicle else 1
	enabled = setting_on()
	_was_low = level < LOW
	_apply()
	if not Settings.changed.is_connected(_on_setting):
		Settings.changed.connect(_on_setting)


func _exit_tree() -> void:
	if vehicle and is_instance_valid(vehicle):
		vehicle.fuel_power = 1.0
		vehicle.fuel_max_speed = 0.0


func _on_setting(key: String, value: Variant) -> void:
	if key == "fuel":
		enabled = bool(value)
		_apply()


func is_battery() -> bool:
	return kind == Kind.BATTERY


func is_low() -> bool:
	return enabled and level < LOW


func is_empty() -> bool:
	return enabled and level <= 0.0


func is_full() -> bool:
	return level >= 0.999


## Burns fuel for `dt` seconds of the vehicle's running (the player driving
## it calls this each physics tick). `scale` 0 = nothing (during a race).
func burn(dt: float, scale := 1.0) -> void:
	if not enabled or vehicle == null:
		return
	var running := true
	var audio := vehicle.get_node_or_null("Audio") as VehicleAudio
	if audio:
		running = audio.engine_running
	if running and scale > 0.0 and level > 0.0:
		set_level(level - _use() * scale * dt / (NORMAL_USE * FULL_TANK_SECONDS))
	_update_sputter(dt)


## How hard the engine works now, in "units": ordinary driving is about
## NORMAL_USE, flat out at top speed about half as much again, idling a
## tenth.
func _use() -> float:
	var load := clampf(vehicle.engine_load, 0.0, 1.0)
	if vehicle is Aircraft:
		return 0.12 + 0.95 * clampf((vehicle as Aircraft).throttle, 0.0, 1.0)
	var speed := clampf(absf(vehicle.forward_speed) / 25.0, 0.0, 1.5)
	return 0.08 + 0.55 * load + 0.35 * speed


## Tops up for `dt` seconds of a nozzle in the filler. True once full.
func fill(dt: float) -> bool:
	if is_full():
		return true
	set_level(level + dt / FILL_SECONDS)
	if is_full():
		set_level(1.0)
		filled.emit()
		return true
	return false


func set_level(v: float) -> void:
	var old := level
	level = clampf(v, 0.0, 1.0)
	if level == old:
		return
	var low := level < LOW
	if low and not _was_low and enabled:
		got_low.emit()
	_was_low = low
	if level <= 0.0 and old > 0.0 and enabled:
		emptied.emit()
	_apply()
	level_changed.emit(level)


## What the engine gets: full power with fuel, the empty rules without.
func _apply() -> void:
	if vehicle == null:
		return
	var empty := enabled and level <= 0.0
	if not empty:
		power = 1.0
		if sputtering:
			# (Filled up or switched off mid-cough: the engine's sound comes back.)
			sputtering = false
			_set_audio_cut(false)
		vehicle.fuel_power = 1.0
		vehicle.fuel_max_speed = 0.0
		return
	if vehicle is Helicopter:
		power = EMPTY_POWER  # (Helicopter has its own gentle descent)
		vehicle.fuel_max_speed = 0.0
	elif vehicle is Aircraft:
		power = EMPTY_PLANE_POWER
		vehicle.fuel_max_speed = 0.0
	else:
		power = EMPTY_POWER
		vehicle.fuel_max_speed = EMPTY_SPEED
	vehicle.fuel_power = power


## An empty petrol engine coughs: its power (and sound) cut out for a
## moment now and then, at random.
func _update_sputter(dt: float) -> void:
	if not is_empty() or is_battery() or vehicle is Aircraft:
		if sputtering:
			sputtering = false
			_set_audio_cut(false)
			_apply()
		return
	_sputter_t -= dt
	if _sputter_t <= 0.0:
		sputtering = not sputtering
		_sputter_t = _rng.randf_range(0.06, 0.18) if sputtering else _rng.randf_range(0.25, 0.9)
		_set_audio_cut(sputtering)
	vehicle.fuel_power = power * (0.15 if sputtering else 1.25)


func _set_audio_cut(on: bool) -> void:
	var audio := vehicle.get_node_or_null("Audio") as VehicleAudio
	if audio:
		audio.sputter_cut = on
