class_name Speedometer
extends Control
## Round speedometer drawn with _draw(): speed arc + needle, digital readout,
## gear and a small RPM arc. Flying, there's no gear and the RPM arc shows
## the engine power (the HUD shows the height above it).

@export var max_speed := 240.0
@export var use_mph := false

var speed_kmh := 0.0
var rpm_fraction := 0.0
var gear_text := "1"
var assists_on := true
## Flying a plane: no gear.
var flying := false

var _font: Font
var _shown_speed := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(260, 260)


func _process(dt: float) -> void:
	_shown_speed = lerpf(_shown_speed, speed_kmh, 1.0 - exp(-12.0 * dt))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	var units_max := max_speed if not use_mph else 150.0
	var shown := _shown_speed if not use_mph else _shown_speed * 0.621371
	var frac := clampf(shown / units_max, 0.0, 1.0)

	draw_circle(c, r, Color(0.06, 0.08, 0.14, 0.72))
	draw_arc(c, r - 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 3.0, true)
	# Speed band.
	draw_arc(c, r - 16.0, start, start + sweep, 64, Color(1, 1, 1, 0.12), 14.0, true)
	var band_col := Color(0.25, 0.8, 1.0).lerp(Color(1.0, 0.35, 0.25), clampf((frac - 0.5) * 2.0, 0.0, 1.0))
	if frac > 0.002:
		draw_arc(c, r - 16.0, start, start + sweep * frac, 64, band_col, 14.0, true)
	# Ticks and labels.
	var step := 20.0 if not use_mph else 10.0
	var v := 0.0
	while v <= units_max + 0.1:
		var a := start + sweep * (v / units_max)
		var dir := Vector2(cos(a), sin(a))
		var major := int(v) % int(step * 2.0) == 0
		draw_line(c + dir * (r - 30.0), c + dir * (r - (40.0 if major else 35.0)), Color(1, 1, 1, 0.8), 2.0, true)
		if major:
			var txt := str(int(v))
			var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
			draw_string(_font, c + dir * (r - 56.0) - Vector2(ts.x * 0.5, -5.0), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1, 1, 1, 0.85))
		v += step
	# RPM arc (inner).
	var rpm_col := Color(1.0, 0.8, 0.2) if rpm_fraction < 0.9 else Color(1.0, 0.25, 0.2)
	draw_arc(c, r - 78.0, start, start + sweep, 48, Color(1, 1, 1, 0.1), 6.0, true)
	draw_arc(c, r - 78.0, start, start + sweep * clampf(rpm_fraction, 0.0, 1.0), 48, rpm_col, 6.0, true)
	# Needle.
	var na := start + sweep * frac
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 12.0, c + nd * (r - 22.0), Color(1.0, 0.3, 0.2), 4.0, true)
	draw_circle(c, 9.0, Color(1.0, 0.3, 0.2))
	# Digital readout.
	var s := str(int(round(shown)))
	var big := 40
	var ss := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, big)
	draw_string(_font, c + Vector2(-ss.x * 0.5, 80.0), s, HORIZONTAL_ALIGNMENT_CENTER, -1, big, Color.WHITE)
	var unit := "km/h" if not use_mph else "mph"
	var us := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
	draw_string(_font, c + Vector2(-us.x * 0.5, 98.0), unit, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1, 1, 1, 0.7))
	if not flying:
		# Gear.
		var gs := _font.get_string_size(gear_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
		draw_circle(c + Vector2(0, -44), 21.0, Color(1, 1, 1, 0.12))
		draw_string(_font, c + Vector2(-gs.x * 0.5, -33.0), gear_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color(1.0, 0.85, 0.3))
	if not assists_on:
		var t := "DRIFT"
		var dts := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(_font, c + Vector2(-dts.x * 0.5, 40.0), t, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.0, 0.5, 0.9))
