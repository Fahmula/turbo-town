class_name Hud
extends CanvasLayer
## In-game overlay: speedometer, controls help, location toasts, stunt popups
## and the "flip your car" hint. Built in code so it has no layout files.

@export var vehicle: Vehicle

const HELP_TEXT := """[b]CONTROLS[/b]
[color=#ffd54a]W / S[/color]   gas / brake + reverse
[color=#ffd54a]A / D[/color]   steer
[color=#ffd54a]Space[/color]   handbrake (drift!)
[color=#ffd54a]R[/color]   flip car upright
[color=#ffd54a]Backspace[/color]   back to spawn point
[color=#ffd54a]1 - 6 / Tab[/color]   teleport: City, Highway,
      Stunt Park, Mountain, Dirt Fields, Beach
[color=#ffd54a]C[/color]   camera view     [color=#ffd54a]Q[/color]   look back
[color=#ffd54a]Mouse[/color]   look around
[color=#ffd54a]T[/color]   assists on/off (drift mode)
[color=#ffd54a]G[/color]   traffic on/off
[color=#ffd54a]E[/color]   horn     [color=#ffd54a]U[/color]   km/h / mph
[color=#ffd54a]H / F1[/color]   hide this help     [color=#ffd54a]Esc[/color]   pause"""

var speedometer: Speedometer
var _help: PanelContainer
var _toast: Label
var _toast_time := 0.0
var _popup: Label
var _popup_time := 0.0
var _hint: Label
var _pause_panel: PanelContainer
var _help_timer := 14.0
var _damage_label: Label
var _damage: VehicleDamage


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	speedometer = Speedometer.new()
	speedometer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speedometer.size = Vector2(260, 260)
	speedometer.position = Vector2(-280, -280)
	root.add_child(speedometer)

	_help = _make_panel()
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(360, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_font_size_override("bold_font_size", 20)
	rt.text = HELP_TEXT
	_help.add_child(rt)
	_help.position = Vector2(20, 20)
	root.add_child(_help)

	_toast = _make_label(40, Color(1, 1, 1))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 40)
	_toast.size = Vector2(600, 60)
	root.add_child(_toast)

	_popup = _make_label(54, Color(1.0, 0.85, 0.25))
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.position = Vector2(-400, -200)
	_popup.size = Vector2(800, 80)
	root.add_child(_popup)

	_hint = _make_label(30, Color(1, 1, 1))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-400, -140)
	_hint.size = Vector2(800, 50)
	_hint.text = "Upside down? Press R to flip your car!"
	_hint.visible = false
	root.add_child(_hint)

	_pause_panel = _make_panel()
	var pl := _make_label(36, Color.WHITE)
	pl.text = "PAUSED\n\nEsc - resume\nF10 - quit game"
	_pause_panel.add_child(pl)
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.position = Vector2(-200, -140)
	_pause_panel.visible = false
	root.add_child(_pause_panel)

	_damage_label = _make_label(18, Color(1, 0.75, 0.6))
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_damage_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_damage_label.position = Vector2(-280, -312)
	_damage_label.size = Vector2(250, 30)
	root.add_child(_damage_label)
	if vehicle:
		_damage = vehicle.get_node_or_null("Damage") as VehicleDamage

	var tip := _make_label(15, Color(1, 1, 1, 0.6))
	tip.text = "H = help"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip.position = Vector2(16, -34)
	root.add_child(tip)


func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.15, 0.72)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _make_label(font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.2))
	l.add_theme_constant_override("outline_size", maxi(font_size / 6, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func toggle_help() -> void:
	_help.visible = not _help.visible
	_help_timer = -1.0


func set_paused(p: bool) -> void:
	_pause_panel.visible = p


func show_toast(text: String, duration := 2.5) -> void:
	_toast.text = text
	_toast_time = duration
	_toast.modulate.a = 1.0


func show_popup(text: String, duration := 1.8) -> void:
	_popup.text = text
	_popup_time = duration
	_popup.modulate.a = 1.0
	_popup.scale = Vector2(1.25, 1.25)
	_popup.pivot_offset = _popup.size * 0.5


func _process(dt: float) -> void:
	if _help_timer > 0.0:
		_help_timer -= dt
		if _help_timer <= 0.0:
			_help.visible = false
	_toast_time -= dt
	_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
	_popup_time -= dt
	_popup.modulate.a = clampf(_popup_time / 0.4, 0.0, 1.0)
	_popup.scale = _popup.scale.lerp(Vector2.ONE, 1.0 - exp(-10.0 * dt))

	if vehicle == null:
		return
	speedometer.speed_kmh = vehicle.speed_kmh
	speedometer.rpm_fraction = vehicle.engine_rpm / vehicle.redline_rpm
	speedometer.gear_text = "R" if vehicle.gear < 0 else str(vehicle.gear)
	speedometer.assists_on = vehicle.traction_control
	_hint.visible = vehicle.upside_down_time > 1.5
	if _damage:
		var d := int(_damage.total_damage)
		_damage_label.text = "" if d <= 0 else "DAMAGE %d%%" % d
