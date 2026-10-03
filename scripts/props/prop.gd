class_name Prop
extends RigidBody3D
## A knock-over-able physics prop (cone, barrel, lamp post, parked car...).
## Props start asleep so hundreds of them cost nothing until something hits them.

## If set, one colour is picked at random and applied to `color_mesh`
## surface 0, and to every surface using a material named `paint_material_name`.
@export var random_colors: Array[Color] = []
@export var color_mesh: MeshInstance3D
@export var paint_material_name := "Paint"
## Parked cars: paint from the weighted traffic mix (PaintPalette) instead of
## `random_colors`.
@export var traffic_paint := false


## Parked cars are drawn out to this distance (with a fade); beyond it
## they're a few pixels and only cost triangles.
const PARKED_CAR_RANGE := 200.0


func _ready() -> void:
	# Props get knocked about: they take bounce light (SDFGI on High) but are
	# never baked into it.
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	# Parked cars share the vehicles' models: optional racing stripes stay off.
	for stripes in find_children("Stripes", "MeshInstance3D", true, false):
		(stripes as MeshInstance3D).visible = false
	if traffic_paint:
		for gi in find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).visibility_range_end = PARKED_CAR_RANGE
			(gi as GeometryInstance3D).visibility_range_end_margin = 20.0
			(gi as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if random_colors.is_empty() and not traffic_paint:
		return
	var col: Color
	if traffic_paint:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		col = PaintPalette.pick_traffic(rng)
	else:
		col = random_colors.pick_random()
	_apply_color(col)


## Paints the prop: `color_mesh` surface 0 and every surface using the paint
## material. Parked cars get the vehicles' paint, glass, lamp, trim and tyre
## shaders instead (lamps dark). (KitProp tints its one mesh instead.)
func _apply_color(col: Color) -> void:
	if traffic_paint:
		VehicleBodyVisual.apply_vehicle_materials([self], col, true)
		return
	if color_mesh:
		_recolor(color_mesh, 0, col)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat and mat.resource_name == paint_material_name:
				_recolor(mi, i, col)


func _recolor(mi: MeshInstance3D, surface: int, col: Color) -> void:
	var mat := mi.get_active_material(surface) as BaseMaterial3D
	if mat == null:
		return
	var m := mat.duplicate() as BaseMaterial3D
	m.albedo_color = col
	mi.set_surface_override_material(surface, m)
