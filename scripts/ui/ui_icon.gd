class_name UiIcon
extends Control
## A one-colour line icon drawn from simple shapes (ART_BIBLE §22: vector
## icons, never font glyphs). Shapes are laid out on a 24 x 24 grid with
## 2-unit strokes and round ends, and scale to the control's size.
##
## Shapes: play, players, wrench, flag, trophy, gear, gamepad, exit, info,
## home, close, star, dice, chevron_left / _right / _up / _down, dpad_h, dpad_v (a D-pad
## with left/right or up/down lit).

var shape := ""
var color := Color.WHITE:
	set(c):
		color = c
		queue_redraw()
## Stroke width in grid units.
var stroke := 2.0

var _k := 1.0


func _init(shape_name := "", px := 32.0, col := Color.WHITE) -> void:
	shape = shape_name
	color = col
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	_k = side / 24.0
	# Centre the 24-unit grid in the control.
	draw_set_transform(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5))
	match shape:
		"play":
			_circle(Vector2(12, 12), 10.0)
			_line([Vector2(10, 8.2), Vector2(15.8, 12), Vector2(10, 15.8)], true)
		"players":
			_circle(Vector2(8.5, 7.8), 3.5)
			_arc(Vector2(8.5, 21.5), 6.6, PI, TAU)
			_circle(Vector2(17.4, 9.6), 2.6)
			_arc(Vector2(17.6, 21.5), 4.9, PI * 1.5, TAU)
		"wrench":
			# An open jaw (gap toward the top right) and the handle.
			var c := Vector2(15.5, 8.5)
			_arc(c, 4.6, -PI * 0.25 + 0.95, PI * 1.75 - 0.95)
			var start := c + Vector2.from_angle(PI * 0.75) * 4.6
			var w := stroke
			stroke = w * 1.75
			_line([start, Vector2(5, 19)])
			stroke = w
		"flag":
			_line([Vector2(5, 21.5), Vector2(5, 3)])
			_line([Vector2(5, 4), Vector2(19, 4), Vector2(15.5, 8.5), Vector2(19, 13), Vector2(5, 13)])
		"trophy":
			var cup := PackedVector2Array([Vector2(17, 9), Vector2(17, 4), Vector2(7, 4), Vector2(7, 9)])
			cup.append_array(_arc_points(Vector2(12, 9), 5.0, PI, 0.0))
			_line(cup, true)
			_arc(Vector2(7, 7), 2.5, PI * 0.5, PI * 1.5)
			_arc(Vector2(17, 7), 2.5, -PI * 0.5, PI * 0.5)
			_line([Vector2(12, 14), Vector2(12, 20)])
			_line([Vector2(8, 20.5), Vector2(16, 20.5)])
		"gear":
			var pts := PackedVector2Array()
			for i in 8:
				var a := i * TAU / 8.0
				for p: Vector2 in [Vector2(a - 0.36, 7.0), Vector2(a - 0.2, 9.8), Vector2(a + 0.2, 9.8), Vector2(a + 0.36, 7.0)]:
					pts.append(Vector2(12, 12) + Vector2.from_angle(p.x) * p.y)
			_line(pts, true)
			_circle(Vector2(12, 12), 3.0)
		"gamepad":
			_line(_round_rect(Rect2(2.5, 6.5, 19, 11), 4.5), true)
			_line([Vector2(5.8, 12), Vector2(10.2, 12)])
			_line([Vector2(8, 9.8), Vector2(8, 14.2)])
			_dot(Vector2(15.5, 10.8), 1.25)
			_dot(Vector2(18, 13.4), 1.25)
		"exit":
			_line([Vector2(10, 4), Vector2(5, 4), Vector2(5, 20), Vector2(10, 20)])
			_line([Vector2(11, 12), Vector2(20, 12)])
			_line([Vector2(16.5, 8.5), Vector2(20, 12), Vector2(16.5, 15.5)])
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 10.0 if i % 2 == 0 else 4.4
				pts.append(Vector2(12, 12.8) + Vector2.from_angle(-PI * 0.5 + i * PI / 5.0) * r)
			_line(pts, true)
		"dice":
			_line(_round_rect(Rect2(3.5, 3.5, 17, 17), 3.5), true)
			for p: Vector2 in [Vector2(8.2, 8.2), Vector2(12, 12), Vector2(15.8, 15.8)]:
				_dot(p, 1.5)
		"home":
			_line([Vector2(3.5, 11.5), Vector2(12, 4), Vector2(20.5, 11.5)])
			_line([Vector2(6, 9.5), Vector2(6, 20), Vector2(18, 20), Vector2(18, 9.5)])
			_line([Vector2(10, 20), Vector2(10, 14.5), Vector2(14, 14.5), Vector2(14, 20)])
		"close":
			_line([Vector2(6, 6), Vector2(18, 18)])
			_line([Vector2(18, 6), Vector2(6, 18)])
		"info":
			_circle(Vector2(12, 12), 10.0)
			_line([Vector2(12, 11), Vector2(12, 16.5)])
			_dot(Vector2(12, 7.6), 1.4)
		"chevron_up":
			_line([Vector2(5.5, 15), Vector2(12, 8.5), Vector2(18.5, 15)])
		"chevron_down":
			_line([Vector2(5.5, 9), Vector2(12, 15.5), Vector2(18.5, 9)])
		"chevron_left":
			_line([Vector2(15, 5.5), Vector2(8.5, 12), Vector2(15, 18.5)])
		"chevron_right":
			_line([Vector2(9, 5.5), Vector2(15.5, 12), Vector2(9, 18.5)])
		"dpad_h", "dpad_v":
			_dpad(shape == "dpad_h")


## A D-pad: a filled cross with the two arms of one axis lit.
func _dpad(horizontal: bool) -> void:
	var dim := Color(color, color.a * 0.28)
	var w := 7.0
	var arms := {
		"left": Rect2(2, 12 - w * 0.5, 8, w), "right": Rect2(14, 12 - w * 0.5, 8, w),
		"up": Rect2(12 - w * 0.5, 2, w, 8), "down": Rect2(12 - w * 0.5, 14, w, 8),
	}
	draw_rect(_r(Rect2(12 - w * 0.5, 12 - w * 0.5, w, w)), dim)
	for k: String in arms:
		var lit := (k in ["left", "right"]) == horizontal
		draw_rect(_r(arms[k]), color if lit else dim)


func _r(r: Rect2) -> Rect2:
	return Rect2(r.position * _k, r.size * _k)


func _line(pts: PackedVector2Array, closed := false) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(v * _k)
	if closed:
		p.append(p[0])
	var w := stroke * _k
	draw_polyline(p, color, w, true)
	# Round joins and ends.
	for v in p:
		draw_circle(v, w * 0.5, color, true, -1.0, true)


func _arc_points(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var n := maxi(int(absf(a1 - a0) / TAU * 40.0), 6)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r)
	return pts


func _arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	_line(_arc_points(c, r, a0, a1))


func _circle(c: Vector2, r: float) -> void:
	draw_arc(c * _k, r * _k, 0.0, TAU, 48, color, stroke * _k, true)


func _dot(c: Vector2, r: float) -> void:
	draw_circle(c * _k, r * _k, color, true, -1.0, true)


## The outline of a rounded rectangle, clockwise from the top left.
func _round_rect(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(rad, rad), PI, PI * 1.5],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5, TAU],
		[r.end - Vector2(rad, rad), 0.0, PI * 0.5],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
	]
	for c: Array in corners:
		pts.append_array(_arc_points(c[0], rad, c[1], c[2]))
	return pts
