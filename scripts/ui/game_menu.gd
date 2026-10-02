class_name GameMenu
extends CanvasLayer
## Title screen, pause menu, settings and controls pages, all navigable with
## keyboard, gamepad (D-pad/stick + A/B) and mouse. Emits `action` with what
## the player chose; Game decides what that means.

## "drive", "garage", "resume", "title", "quit", "race:<index>" or "end_race".
signal action(name: String)

const CONTROLS := [
	["Gas", "W / Up", "RT"],
	["Brake / reverse", "S / Down", "LT"],
	["Steer", "A D / Left Right", "Left stick"],
	["Handbrake (drift!)", "Space", "A"],
	["Air: spin", "A / D", "Left stick"],
	["Air: flip / barrel roll", "Space + W S / A D", "A + RT LT / stick"],
	["Flip car upright", "R", "Y"],
	["Horn", "E", "L3 (press left stick)"],
	["Garage: change vehicle", "V", "D-pad down"],
	["Instant replay", "P", "X"],
	["Back to spawn point", "Backspace", "View"],
	["Teleport", "1-9, Tab", "D-pad right"],
	["Camera view", "C", "RB"],
	["Look back", "Q", "LB"],
	["Look around", "Mouse", "Right stick"],
	["Assists on/off (drift mode)", "T", ""],
	["Traffic on/off", "G", "D-pad up"],
	["Map", "M", "D-pad left"],
	["km/h / mph", "U", ""],
	["Help", "H / F1", ""],
	["Pause", "Esc", "Menu"],
]

## Page currently shown ("" when the menu is closed).
var page := ""
var _pages := {}
var _back_stack: Array[String] = []
var _first_focus := {}
var _dim: ColorRect
var _ride_label: Label
var _setting_widgets := {}
var _volume_label: Label
var _records_text: RichTextLabel
var _races_list: VBoxContainer
var _end_race_button: Button
## Set by Game: the races (RaceCatalog dictionaries) and whether one is running.
var races: Array = []
var racing := false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.menu_theme()
	add_child(root)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)
	_add_page(root, "title", _build_title())
	_add_page(root, "pause", _build_pause())
	_add_page(root, "settings", _build_settings())
	_add_page(root, "controls", _build_controls())
	_add_page(root, "records", _build_records())
	_add_page(root, "races", _build_races())
	_add_page(root, "credits", _build_credits())


func _add_page(root: Control, page_name: String, node: Control) -> void:
	node.visible = false
	root.add_child(node)
	_pages[page_name] = node


func show_page(page_name: String, remember_current := false) -> void:
	if remember_current and page != "":
		_back_stack.append(page)
	elif not remember_current:
		_back_stack.clear()
	page = page_name
	visible = true
	for k: String in _pages:
		(_pages[k] as Control).visible = k == page_name
	# The title screen lets the world show through; other pages dim it.
	_dim.color = Color(0.02, 0.03, 0.08, 0.15 if page_name == "title" else 0.55)
	if page_name == "settings":
		_refresh_settings()
	elif page_name == "records":
		_refresh_records()
	elif page_name == "races":
		_refresh_races()
	elif page_name == "pause":
		_end_race_button.visible = racing
	var first: Control = _first_focus.get(page_name)
	if first:
		first.grab_focus.call_deferred()


func close() -> void:
	page = ""
	visible = false
	_back_stack.clear()
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()


func set_ride_name(ride: String) -> void:
	_ride_label.text = "Your ride: %s" % ride


func _unhandled_input(event: InputEvent) -> void:
	if page == "":
		return
	if event.is_action_pressed("ui_cancel") or (page == "pause" and event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	if not _back_stack.is_empty():
		show_page(_back_stack.pop_back())
		_back_stack.clear()
	elif page == "pause":
		action.emit("resume")


# --- Pages ---------------------------------------------------------------

func _build_title() -> Control:
	var page_root := Control.new()
	page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark fade on the left so the menu column reads well over a bright scene.
	var fade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.02, 0.03, 0.08, 0.8))
	grad.gradient.set_color(1, Color(0.02, 0.03, 0.08, 0.0))
	grad.fill_to = Vector2(1, 0)
	fade.texture = grad
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_bottom = 1.0
	fade.offset_right = 760
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(fade)
	var col := VBoxContainer.new()
	col.position = Vector2(80, 60)
	col.add_theme_constant_override("separation", 14)
	page_root.add_child(col)
	var title := UiKit.label("TURBO TOWN", 92, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	title.add_theme_constant_override("outline_size", 22)
	col.add_child(title)
	col.add_child(UiKit.label("A driving sandbox. Crash, jump and explore!", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	col.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.custom_minimum_size = Vector2(340, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(buttons)
	var drive := _button(buttons, "DRIVE!", func() -> void: action.emit("drive"))
	drive.add_theme_font_size_override("font_size", 32)
	_button(buttons, "RACES", func() -> void: show_page("races", true))
	_button(buttons, "GARAGE", func() -> void: action.emit("garage"))
	_button(buttons, "SETTINGS", func() -> void: show_page("settings", true))
	_button(buttons, "RECORDS", func() -> void: show_page("records", true))
	_button(buttons, "CONTROLS", func() -> void: show_page("controls", true))
	_button(buttons, "CREDITS", func() -> void: show_page("credits", true))
	_button(buttons, "QUIT", func() -> void: action.emit("quit"))
	_first_focus["title"] = drive
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap2)
	_ride_label = UiKit.label("", 20, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(_ride_label)

	var version: String = ProjectSettings.get_setting("application/config/version", "")
	var ver := UiKit.label("v" + version if version != "" else "dev build", 16, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-216, -40)
	ver.size = Vector2(200, 30)
	page_root.add_child(ver)
	return page_root


func _build_pause() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(340, 0)
	p.add_child(col)
	col.add_child(UiKit.label("PAUSED", 40, UiKit.ACCENT))
	var resume := _button(col, "RESUME", func() -> void: action.emit("resume"))
	_end_race_button = _button(col, "END RACE", func() -> void: action.emit("end_race"))
	_button(col, "RACES", func() -> void: show_page("races", true))
	_button(col, "GARAGE", func() -> void: action.emit("garage"))
	_button(col, "SETTINGS", func() -> void: show_page("settings", true))
	_button(col, "CONTROLS", func() -> void: show_page("controls", true))
	_button(col, "RECORDS", func() -> void: show_page("records", true))
	_button(col, "CREDITS", func() -> void: show_page("credits", true))
	_button(col, "MAIN MENU", func() -> void: action.emit("title"))
	_button(col, "QUIT GAME", func() -> void: action.emit("quit"))
	_first_focus["pause"] = resume
	return center


func _build_settings() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	col.add_child(UiKit.label("SETTINGS", 40, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)

	var first := _cycle_row(grid, "Traffic", "traffic_density", Settings.TRAFFIC_LABELS)
	_cycle_row(grid, "Graphics", "graphics", Settings.GRAPHICS_LABELS)
	_cycle_row(grid, "Time of day", "time_of_day", Settings.TIME_LABELS)
	_cycle_row(grid, "Speed units", "units_mph", ["km/h", "mph"])
	_cycle_row(grid, "Driving assists", "assists", ["Off (drift mode)", "On"])
	_cycle_row(grid, "Vibration", "vibration", ["Off", "On"])
	_cycle_row(grid, "Minimap", "minimap", ["Off", "On"])
	_cycle_row(grid, "Crash cam", "crash_cam", ["Off", "On"])
	_cycle_row(grid, "Fullscreen", "fullscreen", ["Off", "On"])

	grid.add_child(UiKit.label("Volume", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(200, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value("master_volume", v)
		_volume_label.text = "%d%%" % roundi(v * 100.0))
	vol_row.add_child(slider)
	_volume_label = UiKit.label("", 20, Color.WHITE)
	_volume_label.custom_minimum_size = Vector2(60, 0)
	vol_row.add_child(_volume_label)
	grid.add_child(vol_row)
	_setting_widgets["master_volume"] = slider

	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["settings"] = first
	return center


func _cycle_row(grid: GridContainer, text: String, key: String, options: Array) -> Control:
	grid.add_child(UiKit.label(text, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	var b := UiKit.CycleButton.new(options, 0)
	b.value_changed.connect(func(i: int) -> void:
		var default: Variant = Settings.DEFAULTS[key]
		Settings.set_value(key, bool(i) if default is bool else i))
	grid.add_child(b)
	_setting_widgets[key] = b
	return b


func _refresh_settings() -> void:
	for key: String in _setting_widgets:
		var w: Control = _setting_widgets[key]
		var v: Variant = Settings.get_value(key)
		if w is UiKit.CycleButton:
			var b := w as UiKit.CycleButton
			b.index = int(v)
			b._refresh()
		elif w is HSlider:
			(w as HSlider).set_value_no_signal(v)
			_volume_label.text = "%d%%" % roundi(float(v) * 100.0)


func _build_controls() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	col.add_child(UiKit.label("CONTROLS", 40, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	for h in ["", "Keyboard", "Gamepad"]:
		grid.add_child(UiKit.label(h, 18, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT))
	for row: Array in CONTROLS:
		grid.add_child(UiKit.label(row[0], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiKit.label(row[1], 18, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiKit.label(row[2], 18, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["controls"] = back
	return center


## Third-party sounds and their licences (ASSET_MANIFEST.md has the full
## list; CC BY needs this attribution in the game).
const CREDITS := "[b]TURBO TOWN[/b]\n\n" \
	+ "[color=#ffd54a]Engine sounds[/color]  by CryHam (Stunt Rally 3), recorded with Engine Simulator. CC BY 4.0\n" \
	+ "[color=#ffd54a]Crash and metal sounds[/color]  by Halleck (freesound.org), edited by CryHam (Stunt Rally 3). CC BY 4.0\n\n" \
	+ "Sounds changed for Turbo Town (looped, filtered, mixed, levels).\n" \
	+ "CC BY 4.0: creativecommons.org/licenses/by/4.0\n" \
	+ "Everything else is made for this game."


func _build_credits() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(760, 0)
	p.add_child(col)
	col.add_child(UiKit.label("CREDITS", 40, UiKit.ACCENT))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_font_size_override("bold_font_size", 24)
	text.text = CREDITS
	col.add_child(text)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["credits"] = back
	return center


func _build_records() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(620, 0)
	p.add_child(col)
	col.add_child(UiKit.label("RECORDS", 40, UiKit.ACCENT))
	_records_text = RichTextLabel.new()
	_records_text.bbcode_enabled = true
	_records_text.fit_content = true
	_records_text.scroll_active = false
	_records_text.add_theme_font_size_override("normal_font_size", 20)
	_records_text.add_theme_font_size_override("bold_font_size", 22)
	col.add_child(_records_text)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["records"] = back
	return center


func _refresh_records() -> void:
	var y := "[color=#ffd54a]%s[/color]"
	var t := "[b]BEST COMBOS[/b]\n"
	if Records.best_combos.is_empty():
		t += "  None yet: jump, flip, drift and squeeze past traffic!\n"
	for i in Records.best_combos.size():
		var c: Dictionary = Records.best_combos[i]
		var tricks: String = c.get("tricks", "")
		if tricks.length() > 42:
			tricks = tricks.substr(0, 40) + "..."
		t += "  %d.  %s  %s  [color=#ffffffa0]%s[/color]\n" % [i + 1, y % Hud.format_points(int(c["points"])), c.get("vehicle", ""), tricks]
	t += "\n"
	t += "Biggest air:  %s\n" % (y % ("%.1f s" % Records.best_air))
	t += "Longest drift:  %s\n" % (y % ("%.1f s" % Records.best_drift))
	t += "Most flips + rolls in one jump:  %s\n" % (y % str(Records.most_flips))
	t += "Near misses:  %s\n" % (y % str(Records.near_misses))
	t += "Total stunt points:  %s" % (y % Hud.format_points(Records.total_score))
	_records_text.text = t


func _build_races() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(700, 0)
	p.add_child(col)
	col.add_child(UiKit.label("RACES", 40, UiKit.ACCENT))
	col.add_child(UiKit.label("Drive into a green circle in the world to start a race, or pick one:", 18, Color(1, 1, 1, 0.8)))
	_races_list = VBoxContainer.new()
	_races_list.add_theme_constant_override("separation", 8)
	col.add_child(_races_list)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["races"] = back
	return center


func _refresh_races() -> void:
	for c in _races_list.get_children():
		c.queue_free()
	var first: Button = null
	for i in races.size():
		var r: Dictionary = races[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var b := _button(row, String(r["name"]).to_upper(), func() -> void: action.emit("race:%d" % i))
		b.custom_minimum_size = Vector2(280, 0)
		var info := Label.new()
		var best: Variant = Records.best_times.get(r["id"])
		var medals: Array = r["medals"]
		if best == null:
			info.text = "gold %s" % RaceCatalog.format_time(medals[0])
			info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		else:
			var m := RaceCatalog.medal_for(r, best)
			info.text = "best %s  %s" % [RaceCatalog.format_time(best), RaceCatalog.MEDAL_NAMES[m] if m >= 0 else ""]
			info.add_theme_color_override("font_color", RaceCatalog.MEDAL_COLORS[m] if m >= 0 else Color.WHITE)
		info.add_theme_font_size_override("font_size", 20)
		info.add_theme_color_override("font_outline_color", UiKit.OUTLINE)
		info.add_theme_constant_override("outline_size", 4)
		row.add_child(info)
		_races_list.add_child(row)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _centered() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
