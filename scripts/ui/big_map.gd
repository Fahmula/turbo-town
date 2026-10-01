class_name BigMap
extends Control
## Full-screen island map (M / D-pad left), north up: where you are, the
## traffic, race markers and the numbered teleport spots (keys 1-9).

var map: WorldMap
var vehicle: Vehicle
var traffic: TrafficManager
## [{"name": String, "pos": Vector3}] — numbered in order (teleport keys).
var spots: Array = []
var markers: Array[Dictionary] = []

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


func _to_px(p: Vector3) -> Vector2:
	return WorldMap.to_uv(p) * _overlay.size


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(0.05, 0.08, 0.15), false, 4.0)
	if traffic:
		for v in traffic.vehicles:
			if v != vehicle and is_instance_valid(v):
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
	if vehicle and is_instance_valid(vehicle):
		var t := vehicle.global_transform
		var c := _to_px(t.origin)
		var f := Vector2(-t.basis.z.x, -t.basis.z.z).normalized()
		var r := Vector2(-f.y, f.x)
		var pts := PackedVector2Array([c + f * 13.0, c - f * 9.0 + r * 9.0, c - f * 4.0, c - f * 9.0 - r * 9.0])
		_overlay.draw_colored_polygon(pts, Color(1.0, 0.3, 0.25))
		_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE, 2.0, true)
	var hint := "1-9 teleport     M close"
	_overlay.draw_string_outline(font, Vector2(12, _overlay.size.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, UiKit.OUTLINE)
	_overlay.draw_string(font, Vector2(12, _overlay.size.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
