class_name Minimap
extends Control
## Round, heading-up minimap in the corner of the HUD: roads and terrain from
## the WorldMap, the player arrow in the middle, traffic as dots and any
## markers the game adds (race checkpoints). Zooms out at speed.

const BASE_RANGE := 110.0  ## metres from the middle to the edge when slow
const FAST_RANGE := 210.0

var map: WorldMap
var vehicle: Vehicle
var traffic: TrafficManager
## World positions to mark: [{"pos": Vector3, "color": Color, "big": bool}].
var markers: Array[Dictionary] = []

var _rect: ColorRect
var _overlay: Control
var _mat: ShaderMaterial
var _range := BASE_RANGE
var _angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/minimap.gdshader")
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	if map:
		_mat.set_shader_parameter("map_tex", map.get_texture())


func set_map(m: WorldMap) -> void:
	map = m
	if _mat:
		_mat.set_shader_parameter("map_tex", map.get_texture())


func _process(dt: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or map == null:
		return
	var t := vehicle.get_global_transform_interpolated()
	var fwd := -t.basis.z
	if Vector2(fwd.x, fwd.z).length() > 0.2:
		_angle = lerp_angle(_angle, atan2(fwd.x, -fwd.z), 1.0 - exp(-8.0 * dt))
	var want := lerpf(BASE_RANGE, FAST_RANGE, clampf(vehicle.linear_velocity.length() / 35.0, 0.0, 1.0))
	_range = lerpf(_range, want, 1.0 - exp(-1.5 * dt))
	_mat.set_shader_parameter("center", WorldMap.to_uv(t.origin))
	_mat.set_shader_parameter("angle", _angle)
	_mat.set_shader_parameter("radius", _range / (2.0 * WorldMap.HALF))
	_overlay.queue_redraw()


## Screen position (in this control) of a world point, and whether it's inside.
func _to_screen(p: Vector3, origin: Vector3) -> Array:
	var rel := Vector2(p.x - origin.x, p.z - origin.z) / _range
	# Inverse of the shader's rotation.
	var q := Vector2(cos(_angle) * rel.x + sin(_angle) * rel.y, -sin(_angle) * rel.x + cos(_angle) * rel.y)
	var half := size * 0.5
	return [half + q * half.x, q.length() <= 0.9]


func _draw_overlay() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var origin := vehicle.global_position
	var half := size * 0.5
	if traffic:
		for v in traffic.vehicles:
			if v == vehicle or not is_instance_valid(v):
				continue
			var s: Array = _to_screen(v.global_position, origin)
			if s[1]:
				_overlay.draw_circle(s[0], 3.6, Color(0.05, 0.08, 0.15))
				_overlay.draw_circle(s[0], 2.6, Color(1, 1, 1, 0.9))
	for m in markers:
		var s: Array = _to_screen(m["pos"], origin)
		var pos: Vector2 = s[0]
		if not s[1]:
			# Off the map: pin it to the edge so you can see which way to go.
			pos = half + (pos - half).normalized() * half.x * 0.86
		var r := 7.0 if m.get("big", false) else 5.0
		_overlay.draw_circle(pos, r + 2.0, Color(0.05, 0.08, 0.15))
		_overlay.draw_circle(pos, r, m.get("color", Color(1, 0.85, 0.25)))
	# Player arrow, always pointing up.
	var pts := PackedVector2Array([half + Vector2(0, -10), half + Vector2(7, 8), half + Vector2(0, 4), half + Vector2(-7, 8)])
	_overlay.draw_colored_polygon(pts, Color(1.0, 0.3, 0.25))
	_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1), 1.5, true)
	# North marker on the ring.
	var north := half + Vector2(-sin(_angle), -cos(_angle)) * half.x * 0.915
	_overlay.draw_circle(north, 9.0, Color(0.05, 0.08, 0.15))
	_overlay.draw_string(ThemeDB.fallback_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
