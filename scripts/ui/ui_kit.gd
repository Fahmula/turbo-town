class_name UiKit
extends RefCounted
## Shared look for menus and overlays (dark rounded panels, yellow accents,
## outlined text) so everything built in code matches.

const ACCENT := Color(1.0, 0.84, 0.29)
const PANEL_BG := Color(0.05, 0.08, 0.15, 0.88)
const OUTLINE := Color(0.05, 0.08, 0.2)
const DARK_TEXT := Color(0.08, 0.1, 0.18)

static var _theme: Theme


static func box(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


static func panel(margin := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL_BG, 18, margin))
	return p


static func label(text: String, font_size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(font_size / 6, 3))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Theme for menus: focusable buttons with a clear yellow focus ring (for
## gamepad/keyboard navigation), sliders, and default label sizes.
static func menu_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var normal := box(Color(1, 1, 1, 0.08), 12, 10)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.16)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT
	var focus := box(Color(0, 0, 0, 0), 12, 0)
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = ACCENT
	for type in ["Button"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, normal)
		t.set_font_size("font_size", type, 24)
		t.set_color("font_color", type, Color.WHITE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, DARK_TEXT)
		t.set_color("font_hover_pressed_color", type, DARK_TEXT)
	# Sliders: a chunky track with a yellow fill.
	var track := box(Color(1, 1, 1, 0.15), 6, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := box(ACCENT, 6, 0)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", focus)
	t.set_font_size("font_size", "Label", 20)
	_theme = t
	return t


## A button that steps through a list of values: left/right (keys, D-pad,
## stick) while focused, or click/A to go to the next one.
class CycleButton extends Button:
	signal value_changed(index: int)
	var options: Array = []
	var index := 0

	func _init(opts: Array, start: int) -> void:
		options = opts
		index = clampi(start, 0, opts.size() - 1)
		custom_minimum_size = Vector2(240, 0)
		_refresh()
		pressed.connect(func() -> void: step(1))

	func step(d: int) -> void:
		index = wrapi(index + d, 0, options.size())
		_refresh()
		value_changed.emit(index)

	func _refresh() -> void:
		text = "<   %s   >" % str(options[index])

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left"):
			step(-1)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			step(1)
			accept_event()
