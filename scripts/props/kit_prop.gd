class_name KitProp
extends Prop
## A knock-over-able prop whose mesh comes from StreetKit (built once in code
## and shared by every copy): street lamps, hydrants, bins, benches...

@export var kind := "lamp"
@export var model: MeshInstance3D


func _ready() -> void:
	if model:
		model.mesh = StreetKit.mesh(kind)
	super._ready()


func _apply_color(col: Color) -> void:
	if model:
		model.set_instance_shader_parameter("tint", col)
