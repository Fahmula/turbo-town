class_name Prop
extends RigidBody3D
## A knock-over-able physics prop (cone, barrel, lamp post, parked car...).
## Props start asleep so hundreds of them cost nothing until something hits them.

## If set, one colour is picked at random and applied to `color_mesh`
## surface 0, and to every surface using a material named `paint_material_name`.
@export var random_colors: Array[Color] = []
@export var color_mesh: MeshInstance3D
@export var paint_material_name := "Paint"


func _ready() -> void:
	if random_colors.is_empty():
		return
	var col: Color = random_colors.pick_random()
	if color_mesh:
		_recolor(color_mesh, 0, col)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat and mat.resource_name == paint_material_name:
				_recolor(mi, i, col, true)


## `car_paint`: the vehicles' paint look (clear coat), so parked cars match.
func _recolor(mi: MeshInstance3D, surface: int, col: Color, car_paint := false) -> void:
	var mat := mi.get_active_material(surface) as BaseMaterial3D
	if mat == null:
		return
	var m: BaseMaterial3D
	if car_paint:
		m = VehicleBodyVisual.paint_material(mat, col)
	else:
		m = mat.duplicate() as BaseMaterial3D
		m.albedo_color = col
	mi.set_surface_override_material(surface, m)
