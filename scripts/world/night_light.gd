class_name NightLight
extends Light3D
## A light that's only on after dark (DayNight switches the "night_lights"
## group). If its parent has a "Head" mesh (a lamp post), that glows too.
## On Low graphics only the head glows (no real light, for frame rate).

static var _lit_head: StandardMaterial3D


func _ready() -> void:
	add_to_group("night_lights")
	visible = false


func set_night(on: bool) -> void:
	visible = on and Settings.get_value("graphics") > GraphicsQuality.LOW
	var head := get_parent().get_node_or_null("Head") as MeshInstance3D
	if head:
		if _lit_head == null:
			_lit_head = StandardMaterial3D.new()
			_lit_head.albedo_color = Color(1, 0.95, 0.8)
			_lit_head.emission_enabled = true
			_lit_head.emission = Color(1, 0.88, 0.62)
			_lit_head.emission_energy_multiplier = 5.0
		head.material_override = _lit_head if on else null
