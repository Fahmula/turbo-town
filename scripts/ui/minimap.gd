class_name Minimap
extends Control
## Round, heading-up minimap in the corner of the HUD: roads and terrain from
## the WorldMap, the player arrow in the middle, traffic as dots and any
## markers the game adds (race checkpoints). Zooms out at speed. On foot it
## follows the character, turns with the camera and marks the player's
## vehicle (pinned to the edge when it's off the map).

const BASE_RANGE := 110.0  ## metres from the middle to the edge when slow
const FAST_RANGE := 210.0

var map: WorldMap
## What the map is centred on: the player's vehicle or character.
var target: Node3D
## Heading-up follows this node's view (the on-foot camera); null = the target's heading.
var heading: Node3D
## The player's vehicle while they're on foot (null when driving it).
var car: Vehicle
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
	if target == null or not is_instance_valid(target) or map == null:
		return
	var t := target.get_global_transform_interpolated()
	var fwd := -t.basis.z
	if heading and is_instance_valid(heading):
		fwd = -heading.global_basis.z
	var speed := 0.0
	if target is RigidBody3D:
		speed = (target as RigidBody3D).linear_velocity.length()
	elif target is CharacterBody3D:
		speed = (target as CharacterBody3D).velocity.length()
	if Vector2(fwd.x, fwd.z).length() > 0.2:
		_angle = lerp_angle(_angle, atan2(fwd.x, -fwd.z), 1.0 - exp(-8.0 * dt))
	var want := lerpf(BASE_RANGE, FAST_RANGE, clampf(speed / 35.0, 0.0, 1.0))
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
	if target == null or not is_instance_valid(target):
		return
	var origin := target.global_position
	var half := size * 0.5
	if traffic:
		for v in traffic.vehicles:
			if v == target or v == car or not is_instance_valid(v):
				continue
			var s: Array = _to_screen(v.global_position, origin)
			if s[1]:
				_overlay.draw_circle(s[0], 3.6, Color(0.05, 0.08, 0.15))
				_overlay.draw_circle(s[0], 2.6, Color(1, 1, 1, 0.9))
	for m in markers:
		var s: Array = _to_screen(m["pos"], origin)
		var pos: Vector2 = s[0]
		if not s[1]:
			if not m.get("pin", false):
				continue
			# Off the map: pin it to the edge so you can see which way to go.
			pos = half + (pos - half).normalized() * half.x * 0.86
		var r := 7.0 if m.get("big", false) else 5.0
		_overlay.draw_circle(pos, r + 2.0, Color(0.05, 0.08, 0.15))
		_overlay.draw_circle(pos, r, m.get("color", Color(1, 0.85, 0.25)))
	# The player's vehicle while on foot: a key-coloured rounded square.
	if car and is_instance_valid(car):
		var s: Array = _to_screen(car.global_position, origin)
		var pos: Vector2 = s[0]
		if not s[1]:
			pos = half + (pos - half).normalized() * half.x * 0.86
		_overlay.draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), Color(0.05, 0.08, 0.15))
		_overlay.draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), UiKit.ACCENT)
	# Player arrow, always pointing up.
	var pts := PackedVector2Array([half + Vector2(0, -10), half + Vector2(7, 8), half + Vector2(0, 4), half + Vector2(-7, 8)])
	_overlay.draw_colored_polygon(pts, Color(1.0, 0.3, 0.25))
	_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1), 1.5, true)
	# North marker on the ring.
	var north := half + Vector2(-sin(_angle), -cos(_angle)) * half.x * 0.915
	_overlay.draw_circle(north, 9.0, Color(0.05, 0.08, 0.15))
	_overlay.draw_string(ThemeDB.fallback_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
