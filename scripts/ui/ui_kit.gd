class_name UiKit
extends RefCounted
## Shared look for menus and overlays (dark rounded panels, yellow accents,
## outlined text) so everything built in code matches.

const ACCENT := Color(1.0, 0.84, 0.29)
const PANEL_BG := Color(0.05, 0.08, 0.15, 0.88)
const OUTLINE := Color(0.05, 0.08, 0.2)
const DARK_TEXT := Color(0.08, 0.1, 0.18)
## A full-screen page drawn over the paused world (the garage).
const PAGE_BG := Color(0.05, 0.07, 0.12, 0.95)
## Tiles and cards on a panel or page, and their hover colour.
const CARD := Color(0.15, 0.19, 0.27, 0.95)
const CARD_HOVER := Color(0.21, 0.26, 0.36, 0.97)
## Secondary text: subtitles, hints, stat names.
const MUTED := Color(0.78, 0.82, 0.9)

static var _theme: Theme
static var _bold: FontVariation


## The heavy weight for headings, buttons and tile titles: the default font
## made bolder, with a little extra letter spacing for ALL CAPS
## (ART_BIBLE §21; no font file until the owner picks one).
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.75
		_bold.spacing_glyph = 1
	return _bold


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


## A label for text inside a panel: like `label`, without the outline
## (ART_BIBLE §20: outlines are for text over the 3D world).
static func panel_label(text: String, font_size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, font_size, col, align)
	l.add_theme_constant_override("outline_size", 0)
	return l


## A heading inside a panel or card: heavy, no outline, left-aligned.
static func heading(text: String, font_size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := panel_label(text, font_size, col, align)
	l.add_theme_font_override("font", bold_font())
	return l


## Secondary text inside a panel or card: muted, left-aligned.
static func text(text: String, font_size := 20, col := MUTED, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return panel_label(text, font_size, col, align)


## A focus ring: `col` border `width` px, drawn `outside` px beyond the box.
static func ring(col: Color, radius: int, width := 3, outside := 0) -> StyleBoxFlat:
	var sb := box(Color(0, 0, 0, 0), radius + outside, 0)
	sb.draw_center = false
	sb.set_border_width_all(width)
	sb.border_color = col
	sb.set_expand_margin_all(outside)
	return sb


## Styles a Button as a tile: "tile" (a slate card with a yellow focus ring),
## "primary" (a yellow card with a white ring) or "flat" (no fill until
## hovered).
static func style_tile(b: Button, style: String, radius := 14) -> void:
	var normal: Color
	var hover: Color
	var focus: StyleBoxFlat
	match style:
		"primary":
			normal = ACCENT
			hover = ACCENT.lightened(0.14)
			focus = ring(Color.WHITE, radius, 3, 4)
		"flat":
			normal = Color(1, 1, 1, 0.0)
			hover = Color(1, 1, 1, 0.09)
			focus = ring(ACCENT, radius)
		_:
			normal = CARD
			hover = CARD_HOVER
			focus = ring(ACCENT, radius)
	b.add_theme_stylebox_override("normal", box(normal, radius, 0))
	b.add_theme_stylebox_override("hover", box(hover, radius, 0))
	b.add_theme_stylebox_override("pressed", box(hover.lightened(0.08), radius, 0))
	b.add_theme_stylebox_override("hover_pressed", box(hover.lightened(0.08), radius, 0))
	b.add_theme_stylebox_override("disabled", box(normal, radius, 0))
	b.add_theme_stylebox_override("focus", focus)


## A button prompt (ART_BIBLE §22). Gamepad (`pad`): A / B / X / Y as white
## letters in dark circles, LB / RB as dark rounded tabs, "dpad_h" / "dpad_v"
## as a D-pad with that axis lit. Keyboard: light key caps with dark text;
## "left" / "right" / "up" / "down" are drawn as arrows.
static func prompt(key: String, pad: bool) -> Control:
	if pad and key.begins_with("dpad"):
		return UiIcon.new(key, 32, Color.WHITE)
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb: StyleBoxFlat
	if pad:
		var face := key.length() == 1
		sb = box(Color(0.1, 0.12, 0.18), 16 if face else 9, 0)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.75)
		sb.content_margin_left = 0 if face else 9
		sb.content_margin_right = 0 if face else 9
		cap.custom_minimum_size = Vector2(32, 32)
	else:
		sb = box(Color(0.92, 0.93, 0.95), 7, 0)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		cap.custom_minimum_size = Vector2(32, 32)
	cap.add_theme_stylebox_override("panel", sb)
	var ink := Color.WHITE if pad else DARK_TEXT
	if key in ["left", "right", "up", "down"]:
		var icon := UiIcon.new("chevron_" + key, 18, ink)
		icon.stroke = 3.0
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cap.add_child(icon)
	else:
		cap.add_child(heading(key, 18, ink, HORIZONTAL_ALIGNMENT_CENTER))
	return cap


## A big focusable button made of other controls (icons, two lines of text):
## the title screen's tiles, the garage's DRIVE button. A plain Button
## underneath takes focus and clicks and draws the look (`style_tile`);
## `box` holds the content, drawn over it.
class Tile extends PanelContainer:
	signal pressed
	var button: Button
	var box: BoxContainer

	func _init(style: String, vertical := false, pad := Vector2(22, 18), radius := 14) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		button = Button.new()
		UiKit.style_tile(button, style, radius)
		button.pressed.connect(func() -> void: pressed.emit())
		add_child(button)
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_constant_override("margin_left", int(pad.x))
		m.add_theme_constant_override("margin_right", int(pad.x))
		m.add_theme_constant_override("margin_top", int(pad.y))
		m.add_theme_constant_override("margin_bottom", int(pad.y))
		add_child(m)
		box = VBoxContainer.new() if vertical else HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(box)


## Theme for menus: focusable buttons with a clear yellow focus ring (for
## gamepad/keyboard navigation), sliders, and default label sizes.
static func menu_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var normal := box(CARD, 12, 10)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = CARD_HOVER
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
		t.set_font("font", type, bold_font())
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
	# Progress bars (the update download): the same track and fill.
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_font_size("font_size", "ProgressBar", 18)
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
