class_name Underglow
extends Node3D
## Neon under the car (garage EXTRAS, Loadout.apply): thin glowing tubes
## under the sills and a soft pool of coloured light on the ground under the
## car (an additive quad, underglow.gdshader, that follows the ground the
## wheels stand on and fades out in the air, like the contact shadow). Only
## the player's vehicle gets one. No real light: it costs the same on every
## quality level (ART_BIBLE.md §12, §27).

const SHADER := preload("res://assets/shaders/vehicle/underglow.gdshader")
## Glow on the ground: stronger at night, when it's the point.
const DAY_ENERGY := 0.55
const NIGHT_ENERGY := 1.2

var color := Color.WHITE
var _vehicle: Vehicle
var _pool: MeshInstance3D
var _mat: ShaderMaterial
var _tube_mat: StandardMaterial3D
var _strength := 1.0


## Puts underglow in colour `o` (a PartsCatalog.UNDERGLOW option) on `v`,
## or takes it off ("off").
static func fit(v: Vehicle, o: Dictionary) -> void:
	var old := v.get_node_or_null("Underglow")
	var on: bool = not o.is_empty() and o["id"] != "off" and not (v is Aircraft)
	if not on:
		if old:
			v.remove_child(old)
			old.queue_free()
		return
	var u := old as Underglow
	if u == null:
		u = Underglow.new()
		u.name = "Underglow"
		u._build(v)
		v.add_child(u)
	u.set_color(o["color"])


func set_color(c: Color) -> void:
	color = c
	if _mat:
		_mat.set_shader_parameter("glow_color", c)
	if _tube_mat:
		_tube_mat.albedo_color = c
		_tube_mat.emission = c


func _build(v: Vehicle) -> void:
	_vehicle = v
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	var ends := Vector3(-0.24, -v.body_front, v.body_rear)
	if body:
		ends = body.body_lines()["ends"]
	var floor_y: float = ends.x
	var nose: float = ends.y
	var tail: float = ends.z
	var half_w := v.footprint_half_width
	var length := tail - nose

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("energy", DAY_ENERGY)
	var quad := PlaneMesh.new()
	quad.size = Vector2(half_w * 2.0 + 1.3, length + 1.4)
	quad.material = _mat
	_pool = MeshInstance3D.new()
	_pool.name = "Glow"
	_pool.mesh = quad
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.layers = Vehicle.VISUAL_LAYER
	_pool.visibility_range_end = 90.0
	_pool.position = Vector3(0.0, -v.ride_height() + 0.035, (nose + tail) * 0.5)
	add_child(_pool)

	_tube_mat = StandardMaterial3D.new()
	_tube_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tube_mat.emission_enabled = true
	_tube_mat.emission_energy_multiplier = 2.0
	var tube := CapsuleMesh.new()
	tube.radius = 0.014
	tube.height = length * 0.62
	tube.radial_segments = 6
	tube.rings = 1
	for sx in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.material_override = _tube_mat
		mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		mi.position = Vector3(sx * (half_w - 0.16), floor_y - 0.005, (nose + tail) * 0.5)
		mi.layers = Vehicle.VISUAL_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _ready() -> void:
	# DayNight switches the "night_lights" group; ask it once for now.
	add_to_group("night_lights")
	var dn := get_tree().root.find_children("*", "DayNight", true, false)
	set_night(not dn.is_empty() and (dn[0] as DayNight).is_night)


func set_night(on: bool) -> void:
	if _mat:
		_mat.set_shader_parameter("energy", NIGHT_ENERGY if on else DAY_ENERGY)


## Keeps the pool on the ground the wheels stand on, fading it in the air.
func _process(dt: float) -> void:
	if _vehicle == null or _pool == null:
		return
	var y := 0.0
	var n := 0
	for w in _vehicle.wheels:
		if w.grounded:
			y += w.position.y - (w.suspension_travel + w.radius - w.compression)
			n += 1
	if n > 0:
		_pool.position.y = y / n + 0.035
	var want := float(n) / maxf(_vehicle.wheels.size(), 1.0)
	var s := move_toward(_strength, want, dt * 4.0)
	if s != _strength:
		_strength = s
		_pool.set_instance_shader_parameter("strength", s)
		_pool.visible = s > 0.01
