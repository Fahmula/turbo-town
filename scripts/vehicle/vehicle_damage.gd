class_name VehicleDamage
extends Node
## Visual crash damage: dents the body mesh around impact points.
## Purely cosmetic for now (handling is unaffected); resetting the car repairs it.
## Future: per-part health, detachable parts, damage affecting steering/engine.

signal damage_changed(total: float)

## Node whose MeshInstance3D descendants get deformed (the body model).
@export var body_path: NodePath = ^"../Body"
## Impact impulse needed before anything dents.
@export var min_impulse := 7000.0
## Impulse that produces the maximum single dent.
@export var full_impulse := 45000.0
@export var max_dent := 0.32
@export var max_total_dent := 0.5

## 0..100, rough "how smashed is it" value for UI.
var total_damage := 0.0

var _vehicle: Vehicle
var _meshes: Array[MeshInstance3D] = []
var _originals: Array = []  # per mesh: Array of surface arrays
var _offsets: Array = []    # per mesh: Array of PackedVector3Array (per surface)
var _materials: Array = []  # per mesh: Array of Material
var _cooldown := 0.0


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	# Heavier vehicles take proportionally bigger hits before denting.
	var mass_scale := maxf(_vehicle.mass / 1300.0, 1.0)
	min_impulse *= mass_scale
	full_impulse *= mass_scale
	var body := get_node_or_null(body_path)
	if body == null:
		return
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		_register(mi as MeshInstance3D)
	_vehicle.impact.connect(_on_impact)
	_vehicle.vehicle_reset.connect(repair)


func _register(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var surfaces: Array = []
	var offsets: Array = []
	var mats: Array = []
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		surfaces.append(arrays)
		var off := PackedVector3Array()
		off.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		offsets.append(off)
		mats.append(mi.get_active_material(i))
	# Own copy so other cars sharing the model aren't affected.
	var copy := src.duplicate() as ArrayMesh
	mi.mesh = copy
	for i in mats.size():
		if mi.get_surface_override_material(i) == null and mats[i]:
			mi.set_surface_override_material(i, mats[i])
	_meshes.append(mi)
	_originals.append(surfaces)
	_offsets.append(offsets)
	_materials.append(mats)


func _process(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)


func _on_impact(strength: float, world_pos: Vector3, _normal: Vector3) -> void:
	if strength < min_impulse or _cooldown > 0.0:
		return
	_cooldown = 0.08
	var t := clampf((strength - min_impulse) / (full_impulse - min_impulse), 0.0, 1.0)
	var depth := lerpf(0.07, max_dent, t)
	var radius := lerpf(0.5, 1.1, t)
	total_damage = minf(total_damage + t * 12.0 + 2.0, 100.0)
	for m in _meshes.size():
		_dent(m, world_pos, depth, radius)
	damage_changed.emit(total_damage)


func _dent(m: int, world_pos: Vector3, depth: float, radius: float) -> void:
	var mi := _meshes[m]
	var inv := mi.global_transform.affine_inverse()
	var p := inv * world_pos
	var center := Vector3(0.0, 0.35, 0.0)
	var push := center - p
	push.y *= 0.3
	if push.length() < 0.01:
		return
	push = push.normalized()
	var mesh := mi.mesh as ArrayMesh
	mesh.clear_surfaces()
	var r2 := radius * radius
	var surfaces: Array = _originals[m]
	for s in surfaces.size():
		var arrays: Array = (surfaces[s] as Array).duplicate()
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var off: PackedVector3Array = _offsets[m][s]
		var verts := base.duplicate()
		for i in verts.size():
			var v := base[i] + off[i]
			var d2 := v.distance_squared_to(p)
			if d2 < r2:
				var f := 1.0 - sqrt(d2) / radius
				var o := off[i] + push * depth * f * f
				if o.length() > max_total_dent:
					o = o.normalized() * max_total_dent
				off[i] = o
			verts[i] = base[i] + off[i]
		_offsets[m][s] = off
		arrays[Mesh.ARRAY_VERTEX] = verts
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, _materials[m][s])


func repair() -> void:
	total_damage = 0.0
	for m in _meshes.size():
		var mesh := _meshes[m].mesh as ArrayMesh
		mesh.clear_surfaces()
		var surfaces: Array = _originals[m]
		for s in surfaces.size():
			var zero := PackedVector3Array()
			zero.resize((_offsets[m][s] as PackedVector3Array).size())
			_offsets[m][s] = zero
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
			mesh.surface_set_material(s, _materials[m][s])
	damage_changed.emit(total_damage)
