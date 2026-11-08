class_name UiKit
extends RefCounted
## Shared look for menus and overlays, so everything built in code matches:
## dark panels and slate cards, yellow accents, the condensed italic display
## font, slanted (skewed) buttons and tabs, speed stripes (ART_BIBLE §20).

const ACCENT := Color(1.0, 0.84, 0.29)
const PANEL_BG := Color(0.05, 0.08, 0.15, 0.88)
const OUTLINE := Color(0.05, 0.08, 0.2)
const DARK_TEXT := Color(0.08, 0.1, 0.18)
## A full-screen page drawn over the paused world (the garage, settings).
const PAGE_BG := Color(0.05, 0.07, 0.12, 0.95)
## Tiles and cards on a panel or page, and their hover colour.
const CARD := Color(0.15, 0.19, 0.27, 0.95)
const CARD_HOVER := Color(0.21, 0.26, 0.36, 0.97)
## Secondary text: subtitles, hints, stat names.
const MUTED := Color(0.78, 0.82, 0.9)
## How far the arcade shapes lean (StyleBoxFlat.skew): about the angle of
## the display font's italic.
const SKEW := 0.2
const DISPLAY_FONT := "res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf"

static var _theme: Theme
static var _display: FontVariation


## The display face for headings, buttons, tabs and tile titles: Barlow
## Condensed ExtraBold Italic (SIL OFL, assets/fonts) with +1 px tracking for
## ALL CAPS. Body text keeps the default font (ART_BIBLE §21).
static func display_font() -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = load(DISPLAY_FONT)
		_display.spacing_glyph = 1
		_display.fallbacks = [ThemeDB.fallback_font]
	return _display


static func box(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


## Leans `sb` like the italic display font (a parallelogram).
static func slant(sb: StyleBoxFlat, amount := SKEW) -> StyleBoxFlat:
	sb.skew = Vector2(amount, 0.0)
	return sb


static func panel(margin := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL_BG, 18, margin))
	return p


## A full page over the paused world (settings, the garage).
static func page_panel(margin := 26) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PAGE_BG, 20, margin))
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


## A heading inside a panel or card: the display font, no outline,
## left-aligned. Keep it ≥ 20 px (the condensed face reads small).
static func heading(text: String, font_size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := panel_label(text, font_size, col, align)
	l.add_theme_font_override("font", display_font())
	return l


## Secondary text inside a panel or card: muted, left-aligned.
static func text(text: String, font_size := 20, col := MUTED, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return panel_label(text, font_size, col, align)


## A page title: a heading followed by speed stripes.
static func page_title(text: String, font_size := 48, col := Color.WHITE, centered := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 16)
	if centered:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(heading(text, font_size, col))
	h.add_child(Stripes.new(font_size * 0.62))
	return h


## A slanted plate with heavy text (the TURBO TOWN logo plate, chips).
static func badge(text: String, font_size := 22, bg := ACCENT, fg := DARK_TEXT) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := slant(box(bg, 5, 0))
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(heading(text, font_size, fg, HORIZONTAL_ALIGNMENT_CENTER))
	return p


## A focus ring: `col` border `width` px, drawn `outside` px beyond the box.
static func ring(col: Color, radius: int, width := 3, outside := 0) -> StyleBoxFlat:
	var sb := box(Color(0, 0, 0, 0), radius + outside, 0)
	sb.draw_center = false
	sb.set_border_width_all(width)
	sb.border_color = col
	sb.set_expand_margin_all(outside)
	return sb


## Styles a Button as a tile: "tile" (a slate card; focus lightens it and
## adds a yellow ring), "primary" (a yellow card with a white ring), "flat"
## (no fill until hovered) or "list" (a slanted slate bar that turns yellow
## when focused or hovered: menu lists).
static func style_tile(b: Button, style: String, radius := 14) -> void:
	var normal: Color
	var hover: Color
	var focus: StyleBoxFlat
	var lean := 0.0
	match style:
		"primary":
			normal = ACCENT
			hover = ACCENT.lightened(0.14)
			focus = ring(Color.WHITE, radius, 3, 4)
		"flat":
			normal = Color(1, 1, 1, 0.0)
			hover = Color(1, 1, 1, 0.09)
			focus = ring(ACCENT, radius)
		"list":
			normal = CARD
			hover = ACCENT
			lean = SKEW
			focus = slant(box(ACCENT, radius, 0))
		_:
			normal = CARD
			hover = CARD_HOVER
			focus = ring(ACCENT, radius)
			focus.draw_center = true
			focus.bg_color = Color(1, 1, 1, 0.05)
	b.add_theme_stylebox_override("normal", slant(box(normal, radius, 0), lean))
	b.add_theme_stylebox_override("hover", slant(box(hover, radius, 0), lean))
	b.add_theme_stylebox_override("pressed", slant(box(hover.darkened(0.06) if style == "list" else hover.lightened(0.08), radius, 0), lean))
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.add_theme_stylebox_override("disabled", slant(box(normal, radius, 0), lean))
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
		cap.add_child(heading(key, 20, ink, HORIZONTAL_ALIGNMENT_CENTER))
	return cap


## A row of hints: each [gamepad keys, keyboard keys, what it does], shown
## for `pad` (true = the gamepad's buttons). Fills `row`, replacing what's
## there.
static func fill_hints(row: HBoxContainer, hints: Array, pad: bool) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	for h: Array in hints:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k: String in (h[0] if pad else h[1]):
			item.add_child(prompt(k, pad))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(2, 0)
		item.add_child(gap)
		item.add_child(text(h[2], 20, Color.WHITE))
		row.add_child(item)


## Theme for menus: slanted slate buttons that turn yellow when focused or
## hovered (gamepad first: the focus is always plain to see), sliders,
## progress bars and default label sizes.
static func menu_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var normal := slant(box(CARD, 8, 10))
	normal.content_margin_left = 26
	normal.content_margin_right = 26
	var lit := normal.duplicate() as StyleBoxFlat
	lit.bg_color = ACCENT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT.darkened(0.08)
	for type in ["Button"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, lit)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, lit)
		t.set_stylebox("disabled", type, normal)
		t.set_font_size("font_size", type, 28)
		t.set_font("font", type, display_font())
		t.set_color("font_color", type, Color.WHITE)
		for c in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, type, DARK_TEXT)
	# Sliders and progress bars: a chunky track with a yellow fill.
	var track := box(Color(1, 1, 1, 0.15), 6, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := box(ACCENT, 6, 0)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", ring(ACCENT, 12))
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_font_size("font_size", "ProgressBar", 18)
	t.set_font_size("font_size", "Label", 20)
	_theme = t
	return t


## Speed stripes: slanted bars fading out to the right, the arcade accent
## beside headings.
class Stripes extends Control:
	var color := UiKit.ACCENT
	var count := 4

	func _init(h := 30.0, n := 4, col := UiKit.ACCENT) -> void:
		count = n
		color = col
		custom_minimum_size = Vector2(n * h * 0.42 + h * 0.5, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var h := size.y
		var w := h * 0.24
		var lean := h * 0.5
		for i in count:
			var x := i * h * 0.42
			var a := 1.0 - 0.8 * float(i) / count
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + lean, 0), Vector2(x + lean + w, 0), Vector2(x + w, h), Vector2(x, h)]),
				Color(color, color.a * a))


## Three chevrons pointing right, brightening toward the tip. With `animate`
## a light runs through them (the "go" sign on the yellow buttons).
class Chevrons extends Control:
	var color := UiKit.DARK_TEXT
	var animate := false:
		set(on):
			animate = on
			_t = 0.0
			set_process(on)
			queue_redraw()
	var _t := 0.0

	func _init(h := 34.0, col := UiKit.DARK_TEXT) -> void:
		color = col
		custom_minimum_size = Vector2(h * 1.25, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		set_process(false)

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := h * 0.13
		var depth := h * 0.3
		var sweep := fmod(_t * 1.1, 1.0) * 1.8 - 0.4
		for i in 3:
			var a := 0.4 + 0.3 * i
			if animate:
				a = 0.35 + 0.65 * clampf(1.0 - absf(i * 0.5 - sweep) * 2.0, 0.0, 1.0)
			var x := i * h * 0.36 + w
			var pts := PackedVector2Array([Vector2(x, h * 0.18), Vector2(x + depth, h * 0.5), Vector2(x, h * 0.82)])
			var c := Color(color, color.a * a)
			draw_polyline(pts, c, w, true)
			for p in pts:
				draw_circle(p, w * 0.5, c, true, -1.0, true)


## A big focusable button made of other controls (icons, two lines of text):
## the title screen's tiles, menu list items, the garage's DRIVE button. A
## plain Button underneath takes focus and clicks and draws the look
## (`style_tile`); `box` holds the content, drawn over it. Hovering with the
## mouse moves the focus to it, so only one thing is lit at a time.
class Tile extends PanelContainer:
	signal pressed
	signal lit_changed(lit: bool)
	var button: Button
	var box: BoxContainer

	func _init(style: String, vertical := false, pad := Vector2(22, 18), radius := 14) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		button = Button.new()
		UiKit.style_tile(button, style, radius)
		button.pressed.connect(func() -> void: pressed.emit())
		button.mouse_entered.connect(func() -> void:
			if button.focus_mode != Control.FOCUS_NONE and button.is_visible_in_tree():
				button.grab_focus())
		for s: Signal in [button.focus_entered, button.focus_exited, button.mouse_entered, button.mouse_exited]:
			s.connect(func() -> void: lit_changed.emit(is_lit()))
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

	func is_lit() -> bool:
		return button.has_focus() or button.is_hovered()


## A menu list item: an icon and a word on a slanted bar ("list" style).
## Focused or hovered it turns yellow with dark text. `text` can change.
class MenuItem extends Tile:
	var text := "":
		set(v):
			text = v
			if _label:
				_label.text = v
	var _label: Label
	var _icon: UiIcon

	func _init(icon_name: String, label_text: String, font_size := 28) -> void:
		super("list", false, Vector2(26, 4), 8)
		box.add_theme_constant_override("separation", 14)
		_icon = UiIcon.new(icon_name, 26, UiKit.ACCENT)
		box.add_child(_icon)
		_label = UiKit.heading(label_text, font_size)
		box.add_child(_label)
		text = label_text
		lit_changed.connect(func(lit: bool) -> void:
			_label.add_theme_color_override("font_color", UiKit.DARK_TEXT if lit else Color.WHITE)
			_icon.color = UiKit.DARK_TEXT if lit else UiKit.ACCENT)


## A settings row that steps through a list of values: its title on the
## left, "‹ value ›" on the right with a pip per option. Left / right (keys,
## D-pad, stick) while focused; a click on the left half steps back, anywhere
## else forward (as does A / Enter). Without a title it's just the selector.
class CycleButton extends Button:
	signal value_changed(index: int)
	const VALUE_W := 250.0
	var options: Array = []
	var index := 0
	var title := ""
	var _click_x := -1.0

	func _init(opts: Array, start: int, title_text := "") -> void:
		options = opts
		title = title_text
		index = clampi(start, 0, opts.size() - 1)
		custom_minimum_size = Vector2(500.0 if title != "" else VALUE_W + 24.0, 60)
		pressed.connect(func() -> void:
			var back := _click_x >= 0.0 and _click_x < _value_left() + (size.x - 12.0 - _value_left()) * 0.5
			_click_x = -1.0
			step(-1 if back else 1))
		mouse_entered.connect(func() -> void:
			if focus_mode != Control.FOCUS_NONE:
				grab_focus())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func step(d: int) -> void:
		index = wrapi(index + d, 0, options.size())
		_refresh()
		value_changed.emit(index)

	func _refresh() -> void:
		queue_redraw()

	func _value_left() -> float:
		return size.x - VALUE_W - 12.0 if title != "" else 12.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_click_x = (event as InputEventMouseButton).position.x
		if event.is_action_pressed("ui_left"):
			step(-1)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			step(1)
			accept_event()

	func _draw() -> void:
		var lit := has_focus() or is_hovered()
		var ink := UiKit.DARK_TEXT if lit else Color.WHITE
		var accent := UiKit.DARK_TEXT if lit else UiKit.ACCENT
		var font := UiKit.display_font()
		var fs := 26
		var h := size.y
		var mid := (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		if title != "":
			draw_string(font, Vector2(26, h * 0.5 + mid), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var l := _value_left()
		var r := size.x - 12.0
		var cy := h * 0.42
		for d in [-1, 1]:
			var x: float = l + 14.0 if d < 0 else r - 14.0
			var pts := PackedVector2Array([Vector2(x - 4.0 * d, cy - 8.0), Vector2(x + 4.0 * d, cy), Vector2(x - 4.0 * d, cy + 8.0)])
			draw_polyline(pts, accent, 3.0, true)
		# Long values ("Pull back to climb") shrink to fit between the arrows.
		var value := str(options[index])
		var vs := fs
		while vs > 18 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x > r - l - 60.0:
			vs -= 1
		var vmid := (font.get_ascent(vs) - font.get_descent(vs)) * 0.5
		draw_string(font, Vector2(l + 28.0, cy + vmid), value, HORIZONTAL_ALIGNMENT_CENTER, r - l - 56.0, vs, ink)
		var n := options.size()
		for i in n:
			var p := Vector2((l + r) * 0.5 + (i - (n - 1) * 0.5) * 14.0, h - 10.0)
			draw_circle(p, 3.2, Color(accent, 1.0 if i == index else 0.3), true, -1.0, true)


## A settings row with a level bar (the volume): its title on the left,
## ten segments and a percentage on the right. Left / right steps it by
## `step_size`; clicking the bar sets it.
class LevelButton extends Button:
	signal value_changed(value: float)
	const BAR_W := 160.0
	var title := ""
	var value := 0.0
	var step_size := 0.05

	func _init(title_text: String) -> void:
		title = title_text
		custom_minimum_size = Vector2(500, 60)
		mouse_entered.connect(func() -> void:
			if focus_mode != Control.FOCUS_NONE:
				grab_focus())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func set_value_no_signal(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _change(v: float) -> void:
		var nv := snappedf(clampf(v, 0.0, 1.0), step_size)
		if nv != value:
			value = nv
			queue_redraw()
			value_changed.emit(value)

	func _bar_left() -> float:
		return size.x - CycleButton.VALUE_W - 12.0 + 14.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var x := (event as InputEventMouseButton).position.x - _bar_left()
			if x >= -8.0 and x <= BAR_W + 8.0:
				_change(x / BAR_W)
				accept_event()
		if event.is_action_pressed("ui_left", true):
			_change(value - step_size)
			accept_event()
		elif event.is_action_pressed("ui_right", true):
			_change(value + step_size)
			accept_event()

	func _draw() -> void:
		var lit := has_focus() or is_hovered()
		var ink := UiKit.DARK_TEXT if lit else Color.WHITE
		var accent := UiKit.DARK_TEXT if lit else UiKit.ACCENT
		var font := UiKit.display_font()
		var fs := 26
		var h := size.y
		var mid := (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		draw_string(font, Vector2(26, h * 0.5 + mid), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var x0 := _bar_left()
		var seg := BAR_W / 10.0
		var bar_h := 16.0
		var y := (h - bar_h) * 0.5
		for i in 10:
			var fill := clampf(value * 10.0 - i, 0.0, 1.0)
			var x := x0 + i * seg
			# Slanted segments, like the rest of the arcade shapes.
			var lean := bar_h * UiKit.SKEW
			var w := seg - 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(x + lean, y), Vector2(x + lean + w, y), Vector2(x + w, y + bar_h), Vector2(x, y + bar_h)]),
				Color(accent, 0.25))
			if fill > 0.0:
				var fw := w * fill
				draw_colored_polygon(PackedVector2Array([Vector2(x + lean, y), Vector2(x + lean + fw, y), Vector2(x + fw, y + bar_h), Vector2(x, y + bar_h)]),
					accent)
		draw_string(font, Vector2(x0 + BAR_W + 8.0, h * 0.5 + mid), "%d%%" % roundi(value * 100.0),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 18.0 - (x0 + BAR_W + 8.0), fs, ink)
