class_name BigMap
extends Control
## Full-screen island map (M / D-pad left), north up: where you are, the
## traffic, race markers and the numbered teleport spots (keys 1-9). On foot
## it also marks the player's vehicle.

var map: WorldMap
## The player: their vehicle or character.
var target: Node3D
## The player's vehicle while they're on foot (null when driving it).
var car: Vehicle
var traffic: TrafficManager
## [{"name": String, "pos": Vector3}] — numbered in order (teleport keys).
var spots: Array = []
var markers: Array[Dictionary] = []
## Split-screen: the other players, [{"node": Node3D, "color": Color, "label": String}].
var friends: Array[Dictionary] = []
## The player's own arrow.
var arrow_color := Color(1.0, 0.3, 0.25)

var _tex: TextureRect
var _overlay: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout)
	_layout()


func set_map(m: WorldMap) -> void:
	map = m
	_tex.texture = map.get_texture()


func _layout() -> void:
	var side := minf(size.x, size.y) - 70.0
	var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	_tex.position = r.position
	_tex.size = r.size
	_overlay.position = r.position
	_overlay.size = r.size


func _process(_dt: float) -> void:
	if visible:
		_overlay.queue_redraw()


## An arrow at `node`, pointing the way it faces.
func _draw_arrow(node: Node3D, col: Color) -> void:
	var t := node.global_transform
	var c := _to_px(t.origin)
	var fwd := -t.basis.z
	if node is PlayerCharacter:
		var a := (node as PlayerCharacter).facing
		fwd = Vector3(-sin(a), 0.0, -cos(a))
	var f := Vector2(fwd.x, fwd.z).normalized()
	var r := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([c + f * 13.0, c - f * 9.0 + r * 9.0, c - f * 4.0, c - f * 9.0 - r * 9.0])
	_overlay.draw_colored_polygon(pts, col)
	_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE, 2.0, true)


func _to_px(p: Vector3) -> Vector2:
	return WorldMap.to_uv(p) * _overlay.size


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(0.05, 0.08, 0.15), false, 4.0)
	if traffic:
		for v in traffic.vehicles:
			if v != target and v != car and is_instance_valid(v):
				_overlay.draw_circle(_to_px(v.global_position), 3.0, Color(1, 1, 1, 0.85))
	for m in markers:
		var q := _to_px(m["pos"])
		_overlay.draw_circle(q, 9.0, Color(0.05, 0.08, 0.15))
		_overlay.draw_circle(q, 7.0, m.get("color", Color(1, 0.85, 0.25)))
	for i in spots.size():
		var q := _to_px(spots[i]["pos"])
		var label: String = spots[i]["name"]
		_overlay.draw_circle(q, 13.0, Color(0.05, 0.08, 0.15))
		_overlay.draw_circle(q, 11.0, UiKit.ACCENT)
		_overlay.draw_string(font, q + Vector2(-5, 6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.DARK_TEXT)
		_overlay.draw_string_outline(font, q + Vector2(17, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, UiKit.OUTLINE)
		_overlay.draw_string(font, q + Vector2(17, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if car and is_instance_valid(car):
		var q := _to_px(car.global_position)
		_overlay.draw_rect(Rect2(q - Vector2(9, 9), Vector2(18, 18)), Color(0.05, 0.08, 0.15))
		_overlay.draw_rect(Rect2(q - Vector2(7, 7), Vector2(14, 14)), UiKit.ACCENT)
	for fr in friends:
		var node: Node3D = fr.get("node")
		if node and is_instance_valid(node) and node.is_inside_tree():
			_draw_arrow(node, fr.get("color", Color.WHITE))
			var q := _to_px(node.global_position)
			var label: String = fr.get("label", "")
			_overlay.draw_string_outline(font, q + Vector2(15, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, UiKit.OUTLINE)
			_overlay.draw_string(font, q + Vector2(15, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, fr.get("color", Color.WHITE))
	if target and is_instance_valid(target):
		_draw_arrow(target, arrow_color)
	var hint := "1-9 teleport     M close"
	_overlay.draw_string_outline(font, Vector2(12, _overlay.size.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, UiKit.OUTLINE)
	_overlay.draw_string(font, Vector2(12, _overlay.size.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
