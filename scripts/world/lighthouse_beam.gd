class_name LighthouseBeam
extends Node3D
## The lighthouse's sweeping beam: a spot light and a faint light cone that
## turn round and round after dark.

const TURN_SPEED := 0.9


func _ready() -> void:
	add_to_group("night_lights")
	visible = false
	var spot := SpotLight3D.new()
	spot.spot_range = 320.0
	spot.spot_angle = 6.0
	spot.light_energy = 10.0
	spot.light_color = Color(1.0, 0.92, 0.65)
	add_child(spot)
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 9.0
	mesh.height = 90.0
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.9, 0.6, 0.08)
	mat.no_depth_test = false
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lay the cone along -Z (the spot's direction), narrow end at the lamp.
	cone.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -45.0))
	add_child(cone)


func set_night(on: bool) -> void:
	visible = on


func _process(dt: float) -> void:
	if visible:
		rotate_y(TURN_SPEED * dt)
