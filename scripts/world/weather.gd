class_name Weather
extends Node
## The weather: Clear, Cloudy, Rain or Thunderstorm, or Changing (it drifts
## from one to the next by itself). Sets how cloudy the sky is (DayNight lays
## the cloud photos over the time of day's sky, dims the sun and thickens the
## haze), how hard it rains (a RainFx round each player's camera), how wet
## the ground is (the global shader uniform `wet`, which lags behind the
## rain: roads take a while to soak and longer to dry), the tyres' grip, and
## lightning and thunder in a storm. ART_BIBLE.md §11.

enum Kind { CLEAR, CLOUDY, RAIN, STORM }
## The setting's last option: no fixed weather.
const CHANGING := 4

## Per kind: [clouds (0 clear, 0.5 the cloudy sky, 1 overcast), storm 0-1,
## rain 0-1].
const TARGETS := [[0.0, 0.0, 0.0], [0.5, 0.0, 0.0], [1.0, 0.0, 0.6], [1.0, 1.0, 1.0]]
## Changing: how long each kind lasts (seconds, min and max) and which kinds
## can come next (one is picked at random).
const STAY := [[150.0, 260.0], [90.0, 150.0], [120.0, 200.0], [70.0, 120.0]]
const NEXT := [[Kind.CLOUDY], [Kind.CLEAR, Kind.RAIN], [Kind.CLOUDY, Kind.STORM], [Kind.RAIN]]
## Seconds to blend from one kind to the next: Changing, and after the
## player picks a weather in the menu.
const BLEND_CHANGING := 45.0
const BLEND_MENU := 4.0
## Seconds for dry ground to soak in steady rain, and for soaked ground to dry.
const SOAK_TIME := 25.0
const DRY_TIME := 120.0
## Grip lost on a soaked surface (VehicleWheel.weather_grip).
const WET_GRIP_LOSS := 0.12

var kind := Kind.CLEAR
var changing := false
## Current values (they ease toward the kind's TARGETS).
var clouds := 0.0
var storm := 0.0
var rain := 0.0
var wet := 0.0

var _day_night: DayNight
var _blend := BLEND_MENU
var _stay_left := 0.0
var _rain_fx: Array[RainFx] = []
var _lightning: Lightning
var _rng := RandomNumberGenerator.new()
## What DayNight was last given (it only re-renders the sky on a real change).
var _sent := Vector2(-1.0, -1.0)


func setup(day_night: DayNight) -> void:
	_day_night = day_night
	_rng.randomize()
	_lightning = Lightning.new()
	_lightning.name = "Lightning"
	_lightning.day_night = day_night
	add_child(_lightning)


## The Weather setting: a Kind, or CHANGING. `instant` jumps straight there
## (starting the game); otherwise the sky and rain blend over a few seconds.
func set_mode(mode: int, instant := false) -> void:
	changing = mode >= CHANGING
	if changing:
		# Start under a few clouds, so rain can come along soon.
		_go(Kind.CLOUDY if instant else kind, BLEND_CHANGING)
	else:
		_go(mode as Kind, BLEND_MENU)
	if instant:
		var t: Array = TARGETS[kind]
		clouds = t[0]
		storm = t[1]
		rain = t[2]
		wet = 1.0 if rain > 0.05 else 0.0
	_push()


func _go(k: Kind, blend: float) -> void:
	kind = k
	_blend = blend
	var stay: Array = STAY[k]
	_stay_left = _rng.randf_range(stay[0], stay[1])


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	if changing:
		_stay_left -= dt
		if _stay_left <= 0.0:
			var next: Array = NEXT[kind]
			_go(next[_rng.randi() % next.size()], BLEND_CHANGING)
	var t: Array = TARGETS[kind]
	var step := dt / _blend
	# Clouds gather before the rain starts, and the rain stops before they clear.
	var raining: bool = t[2] > rain
	clouds = move_toward(clouds, t[0], step * (1.6 if raining or t[0] > clouds else 1.0))
	storm = move_toward(storm, t[1], step)
	if not raining or clouds > 0.85:
		rain = move_toward(rain, t[2], step * 1.4)
	if rain > 0.05:
		wet = move_toward(wet, 1.0, dt * rain / SOAK_TIME)
	else:
		wet = move_toward(wet, 0.0, dt / DRY_TIME)
	_push()
	_fit_rain()


## Hands the values on: the shaders, the tyres, DayNight (only when the sky
## changed enough to see: each change re-renders the sky's reflections).
func _push() -> void:
	RenderingServer.global_shader_parameter_set("wet", wet)
	RenderingServer.global_shader_parameter_set("rain", rain)
	VehicleWheel.weather_grip = 1.0 - WET_GRIP_LOSS * wet
	_lightning.active = storm > 0.6
	var now := Vector2(clouds, storm)
	var t: Array = TARGETS[kind]
	if _day_night and now != _sent and (now.distance_to(_sent) > 0.01 or now == Vector2(t[0], t[1])):
		_sent = now
		_day_night.set_weather(clouds, storm)


## One RainFx per player camera, each seen only in its own view.
func _fit_rain() -> void:
	var cams := Views.cameras(self)
	if rain <= 0.0 and _rain_fx.is_empty():
		return
	while _rain_fx.size() < cams.size():
		var fx := RainFx.new()
		fx.name = "Rain%d" % (_rain_fx.size() + 1)
		add_child(fx)
		_rain_fx.append(fx)
	for i in _rain_fx.size():
		var fx := _rain_fx[i]
		var cam: Camera3D = cams[i] if i < cams.size() else null
		fx.follow(cam, rain, i)


## A graphics change: the rain is rebuilt with that quality's drop count.
func refresh() -> void:
	for fx in _rain_fx:
		fx.queue_free()
	_rain_fx.clear()
