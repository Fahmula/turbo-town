class_name TrafficLightProp
extends Prop
## Knock-over-able traffic light whose lamps follow a TrafficManager signal.
## The manager finds these via the "traffic_lights" group.

@export var intersection_id := -1
## 0 = serves north/south traffic, 1 = east/west.
@export var axis := 0
## The StreetKit mesh; its lenses light by the instance uniform `signal`
## (street_props.gdshader), so the whole light is one draw call.
@export var model: MeshInstance3D
@export var kit_kind := "signal"

var _state := -1


func _ready() -> void:
	super._ready()
	add_to_group("traffic_lights")
	if model and kit_kind != "":
		model.mesh = StreetKit.mesh(kit_kind)
		# Dirt and road spray low on the pole, like the other street props.
		model.set_instance_shader_parameter("grime", 1.0)
	set_state(TrafficNetwork.SignalState.RED if intersection_id >= 0 else TrafficNetwork.SignalState.GREEN)


## state: TrafficNetwork.SignalState (RED, AMBER, GREEN)
func set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	if model:
		model.set_instance_shader_parameter("signal", [TrafficNetwork.SignalState.RED, TrafficNetwork.SignalState.AMBER,
			TrafficNetwork.SignalState.GREEN].find(state))
