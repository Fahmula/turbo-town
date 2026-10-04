class_name ShopGlow
extends MeshInstance3D
## The shop light glow on the sidewalks (shop_light_spill.gdshader): only
## drawn after dark. DayNight switches it with the "night_lights" group, so
## by day its additive quads cost no fill rate at all.


func _ready() -> void:
	add_to_group("night_lights")
	visible = false


func set_night(on: bool) -> void:
	visible = on
