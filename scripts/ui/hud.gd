class_name Hud
extends CanvasLayer
## In-game overlay: speedometer, controls help, location toasts, stunt popups
## and the "flip your car" hint. Built in code so it has no layout files.

@export var vehicle: Vehicle

const HELP_TEXT := """[b]CONTROLS[/b]
[color=#ffd54a]W / S[/color]   gas / brake + reverse
[color=#ffd54a]A / D[/color]   steer
[color=#ffd54a]Space[/color]   handbrake (drift!)
[color=#ffd54a]In the air[/color]   A/D spin,
      Space + W/S flip, Space + A/D barrel roll
[color=#ffd54a]R[/color]   flip car upright
[color=#ffd54a]V[/color]   garage: change vehicle / paint
[color=#ffd54a]Backspace[/color]   back to spawn point
[color=#ffd54a]1 - 9 / Tab[/color]   teleport: City, Highway, Stunt Park,
      Mountain, Dirt Fields, Beach, Airfield, Harbour, Lighthouse
[color=#ffd54a]C[/color]   camera view     [color=#ffd54a]Q[/color]   look back
[color=#ffd54a]Mouse[/color]   look around
[color=#ffd54a]T[/color]   assists on/off (drift mode)
[color=#ffd54a]G[/color]   traffic on/off     [color=#ffd54a]M[/color]   map
[color=#ffd54a]E[/color]   horn     [color=#ffd54a]U[/color]   km/h / mph
[color=#ffd54a]H / F1[/color]   hide this help     [color=#ffd54a]Esc[/color]   menu"""

var speedometer: Speedometer
var minimap: Minimap
var big_map: BigMap
var _help: PanelContainer
var _toast: Label
var _toast_time := 0.0
var _popup: Label
var _popup_time := 0.0
var _hint: Label
var _help_timer := 14.0
var _damage_label: Label
var _damage: VehicleDamage
var _score_label: Label
var _combo_box: VBoxContainer
var _combo_lines: Array[Label] = []
var _combo_total: Label
var _combo_fade := 0.0
var _race_label: Label
## Set by Game: shows its status line while a race is on.
var race: RaceManager


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

	_damage_label = _make_label(18, Color(1, 0.75, 0.6))
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_damage_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_damage_label.position = Vector2(-280, -312)
	_damage_label.size = Vector2(250, 30)
	root.add_child(_damage_label)
	if vehicle:
		_damage = vehicle.get_node_or_null("Damage") as VehicleDamage

	var race_panel := _make_panel()
	race_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	race_panel.position = Vector2(-330, 100)
	race_panel.custom_minimum_size = Vector2(660, 0)
	_race_label = _make_label(28, Color(1, 1, 1))
	race_panel.add_child(_race_label)
	race_panel.visible = false
	root.add_child(race_panel)

	_score_label = _make_label(24, Color(1, 1, 1, 0.9))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.position = Vector2(-320, 16)
	_score_label.size = Vector2(300, 36)
	root.add_child(_score_label)
	set_score(0)

	# Current stunt combo: the tricks so far and the running total.
	_combo_box = VBoxContainer.new()
	_combo_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_combo_box.position = Vector2(28, 20)
	_combo_box.size = Vector2(460, 190)
	_combo_box.alignment = BoxContainer.ALIGNMENT_END
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_combo_box)
	for i in 4:
		var l := _make_label(22, Color(1, 1, 1))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_combo_box.add_child(l)
		_combo_lines.append(l)
	_combo_total = _make_label(34, Color(1.0, 0.85, 0.25))
	_combo_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_combo_box.add_child(_combo_total)
	_combo_box.modulate.a = 0.0

	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.position = Vector2(20, -250)
	minimap.size = Vector2(230, 230)
	minimap.vehicle = vehicle
	root.add_child(minimap)

	var tip := _make_label(15, Color(1, 1, 1, 0.6))
	tip.text = "H = help"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip.position = Vector2(262, -34)
	root.add_child(tip)

	big_map = BigMap.new()
	big_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map.visible = false
	big_map.vehicle = vehicle
	root.add_child(big_map)


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


## Gives the minimap and big map their picture and what to show on it.
func setup_map(map: WorldMap, traffic: TrafficManager, spots: Array) -> void:
	minimap.set_map(map)
	minimap.traffic = traffic
	big_map.set_map(map)
	big_map.traffic = traffic
	big_map.spots = spots


func toggle_big_map() -> void:
	big_map.visible = not big_map.visible


## Points the speedometer, damage readout and maps at a different vehicle.
func set_vehicle(v: Vehicle) -> void:
	vehicle = v
	minimap.vehicle = v
	big_map.vehicle = v
	_damage = v.get_node_or_null("Damage") as VehicleDamage if v else null


func toggle_help() -> void:
	_help.visible = not _help.visible
	_help_timer = -1.0


static func format_points(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func set_score(points: int) -> void:
	_score_label.text = "SCORE %s" % format_points(points)


## Shows the stunt combo in progress (empty `tricks` hides it after a moment).
func show_combo(tricks: Array, multiplier: int, total: int) -> void:
	if tricks.is_empty():
		_combo_fade = 0.6
		return
	var first := maxi(tricks.size() - _combo_lines.size(), 0)
	for i in _combo_lines.size():
		var k := first + i
		if k < tricks.size():
			var t: Array = tricks[k]
			_combo_lines[i].text = "%s  +%s" % [t[0], format_points(t[1])]
			_combo_lines[i].modulate.a = 1.0 if k == tricks.size() - 1 else 0.75
		else:
			_combo_lines[i].text = ""
	_combo_total.text = "x%d   %s" % [multiplier, format_points(total)] if multiplier > 1 else format_points(total)
	_combo_box.modulate.a = 1.0
	_combo_fade = 0.0


## Shows the controls help, hiding it again after `seconds`.
func show_help_for(seconds: float) -> void:
	_help.visible = true
	_help_timer = seconds


func show_toast(text: String, duration := 2.5) -> void:
	_toast.text = text
	_toast_time = duration
	_toast.modulate.a = 1.0


func show_popup(text: String, duration := 1.8, color := Color(1.0, 0.85, 0.25)) -> void:
	_popup.add_theme_color_override("font_color", color)
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
	if _combo_fade > 0.0:
		_combo_fade -= dt
		_combo_box.modulate.a = clampf(_combo_fade / 0.6, 0.0, 1.0)

	var race_text := race.status_text() if race else ""
	_race_label.get_parent().visible = race_text != ""
	_race_label.text = race_text

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
