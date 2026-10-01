class_name VehicleBodyVisual
extends Node3D
## Cosmetic only: adds exaggerated body roll/pitch from the car's acceleration
## (stylized "weight transfer"), recolours the paint and drives brake/reverse
## lights. Put this on the node that holds the body model (not the wheels).
## Materials are found by name in the imported model: "Paint", "TailLight",
## "ReverseLight".

@export var paint_color := Color(0.93, 0.22, 0.14)
## Colours the traffic spawner picks from for this vehicle (empty = its default mix).
@export var paint_palette: Array[Color] = []
@export var roll_per_g := 3.5
@export var pitch_per_g := 2.2
@export var max_angle := 6.0
@export var response := 7.0

var _vehicle: Vehicle
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _paint_mats: Array[BaseMaterial3D] = []
var _brake_mats: Array[BaseMaterial3D] = []
var _reverse_mats: Array[BaseMaterial3D] = []
var _rear_broken := false


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	for mi in find_children("*", "MeshInstance3D", true, false):
		_prepare_materials(mi as MeshInstance3D)
	if _vehicle:
		_vehicle.vehicle_reset.connect(func() -> void:
			_acc = Vector3.ZERO
			_prev_vel = Vector3.ZERO)


func _prepare_materials(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as BaseMaterial3D
		if mat == null:
			continue
		match mat.resource_name:
			"Paint":
				var m := paint_material(mat, paint_color)
				mi.set_surface_override_material(i, m)
				_paint_mats.append(m)
			"TailLight":
				var m := mat.duplicate() as BaseMaterial3D
				m.emission_enabled = true
				mi.set_surface_override_material(i, m)
				_brake_mats.append(m)
			"ReverseLight":
				var m := mat.duplicate() as BaseMaterial3D
				m.emission_enabled = true
				m.emission = Color(1, 1, 1)
				mi.set_surface_override_material(i, m)
				_reverse_mats.append(m)


## Car paint (ART_BIBLE.md §13): the model's "Paint" material in `col` with
## a glossy clear coat. Parked-car props use it too, so all paint matches.
static func paint_material(base: BaseMaterial3D, col: Color) -> BaseMaterial3D:
	var m := base.duplicate() as BaseMaterial3D
	m.albedo_color = col
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	return m


## Smashed tail lights stay dark (VehicleDamage).
func set_rear_lights_broken(broken: bool) -> void:
	_rear_broken = broken
	for m in _brake_mats + _reverse_mats:
		m.albedo_color = Color(0.2, 0.18, 0.18) if broken else Color(1, 1, 1)


## Repaints the car (works before or after it enters the tree).
func set_paint_color(c: Color) -> void:
	paint_color = c
	for m in _paint_mats:
		m.albedo_color = c


func _physics_process(dt: float) -> void:
	if _vehicle == null:
		return
	var v := _vehicle.linear_velocity
	var acc := (v - _prev_vel) / dt
	_prev_vel = v
	var local := _vehicle.global_basis.inverse() * acc
	if _vehicle.grounded_wheels < 3:
		local = Vector3.ZERO
	# Ignore spikes from impacts/landings.
	local = local.limit_length(20.0)
	_acc = _acc.lerp(local, 1.0 - exp(-response * dt))
	var roll := clampf(roll_per_g * _acc.x / 9.81, -max_angle, max_angle)
	var pitch := clampf(-pitch_per_g * _acc.z / 9.81, -max_angle, max_angle)
	rotation = Vector3(deg_to_rad(pitch), 0.0, deg_to_rad(roll))

	var braking := _vehicle.is_braking and not _rear_broken
	for m in _brake_mats:
		m.emission_energy_multiplier = 0.0 if _rear_broken else (4.0 if braking else 0.8)
	var reversing := _vehicle.gear == -1 and not _rear_broken
	for m in _reverse_mats:
		m.emission_energy_multiplier = 2.5 if reversing else 0.0
