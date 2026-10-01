class_name TrafficLightProp
extends Prop
## Knock-over-able traffic light whose lamps follow a TrafficManager signal.
## The manager finds these via the "traffic_lights" group.

@export var intersection_id := -1
## 0 = serves north/south traffic, 1 = east/west.
@export var axis := 0
@export var red_lamp: MeshInstance3D
@export var amber_lamp: MeshInstance3D
@export var green_lamp: MeshInstance3D
## New style: one StreetKit mesh whose lenses light by the instance uniform
## `signal` (street_props.gdshader), instead of three lamp meshes.
@export var model: MeshInstance3D
@export var kit_kind := ""

var _mats: Array[StandardMaterial3D] = []
var _colors := [Color(1.0, 0.12, 0.08), Color(1.0, 0.65, 0.05), Color(0.1, 1.0, 0.35)]
var _state := -1


func _ready() -> void:
	super._ready()
	add_to_group("traffic_lights")
	if model and kit_kind != "":
		model.mesh = StreetKit.mesh(kit_kind)
	for lamp in [red_lamp, amber_lamp, green_lamp]:
		if lamp == null:
			continue
		var m := StandardMaterial3D.new()
		m.roughness = 0.3
		(lamp as MeshInstance3D).material_override = m
		_mats.append(m)
	set_state(TrafficNetwork.SignalState.RED if intersection_id >= 0 else TrafficNetwork.SignalState.GREEN)


## state: TrafficNetwork.SignalState (RED, AMBER, GREEN)
func set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	if model:
		model.set_instance_shader_parameter("signal", [TrafficNetwork.SignalState.RED, TrafficNetwork.SignalState.AMBER,
			TrafficNetwork.SignalState.GREEN].find(state))
	if _mats.is_empty():
		return
	var lit := [state == TrafficNetwork.SignalState.RED, state == TrafficNetwork.SignalState.AMBER, state == TrafficNetwork.SignalState.GREEN]
	for i in 3:
		var m := _mats[i]
		var c: Color = _colors[i]
		if lit[i]:
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5
		else:
			m.albedo_color = c.darkened(0.8)
			m.emission_enabled = false
