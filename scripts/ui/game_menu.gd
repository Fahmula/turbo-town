class_name GameMenu
extends CanvasLayer
## Title screen, pause menu, settings and controls pages, all navigable with
## keyboard, gamepad (D-pad/stick + A/B) and mouse. Emits `action` with what
## the player chose; Game decides what that means.

## "drive", "garage", "resume", "title", "quit", "update" (restart into the
## downloaded update), "race:<index>", "end_race",
## "join:<player 1's device>:<player 2's device>" (a second player pressed A
## on the 2 PLAYERS page; -1 = the keyboard) or "remove_player".
signal action(name: String)

## The title screen's cards start this far from the left edge (px).
const TITLE_LEFT := 64

## Controls page, two columns: driving, then on foot and anywhere.
const CONTROLS := [
	["Gas", "W / Up", "RT"],
	["Brake / reverse", "S / Down", "LT"],
	["Steer", "A D / Left Right", "Left stick"],
	["Handbrake (drift!)", "Space", "A"],
	["Air: spin", "A / D", "Left stick"],
	["Air: flip / barrel roll", "Space + W S / A D", "A + RT LT / stick"],
	["Flip car upright", "R", "Y"],
	["Get out", "F", "B"],
	["Horn", "E", "L3 (press left stick)"],
	["Instant replay", "P", "X"],
	["Camera view", "C", "RB"],
	["Look back", "Q", "LB"],
	["Assists on/off (drift mode)", "T", ""],
	["km/h / mph", "U", ""],
]
const CONTROLS_FOOT := [
	["Walk / run", "W A S D", "Left stick"],
	["Sprint", "Shift (hold)", "L3 (click)"],
	["Walk slowly", "Ctrl (hold)", "Push the stick gently"],
	["Jump", "Space", "A"],
	["Get in a vehicle / ride along", "F", "B"],
	["Camera distance", "C", "RB"],
]
const CONTROLS_FLYING := [
	["Power (hold)", "Shift", "RT"],
	["Slow down / brakes", "Ctrl", "LT"],
	["Bank left / right, steer", "A / D", "Left stick"],
	["Nose up / down", "S / W", "Left stick back / forward"],
	["Loop the loop", "Hold S", "Hold the stick back"],
	["Barrel roll", "Space + A / D", "A + left stick"],
	["Help! Level the plane", "R", "Y"],
	["Get out (after landing)", "F", "B"],
	["Camera view / cockpit", "C", "RB"],
	["Flying assists on/off", "T", ""],
]
const CONTROLS_HELI := [
	["Go up (hold)", "Shift", "RT"],
	["Go down / land", "Ctrl", "LT"],
	["Fly forward / back", "W / S", "Left stick forward / back"],
	["Turn left / right", "A / D", "Left stick"],
	["Flip", "Space + W / S", "A + stick forward / back"],
	["Roll", "Space + A / D", "A + stick left / right"],
	["Help! Stop and level out", "R", "Y"],
	["Get out (after landing)", "F", "B"],
	["Camera view / cockpit", "C", "RB"],
	["Flying assists on/off", "T", ""],
]
const CONTROLS_ANYWHERE := [
	["Look around", "Mouse", "Right stick"],
	["Garage: vehicle, paint, wheels", "V", "D-pad down"],
	["Back to spawn point", "Backspace", "View"],
	["Teleport", "1-9, Tab", "D-pad right"],
	["Traffic on/off", "G", "D-pad up"],
	["Map", "M", "D-pad left"],
	["Help", "H / F1", ""],
	["Pause", "Esc", "Menu"],
	["2 players: go to the other one", "0", "X"],
]

## Page currently shown ("" when the menu is closed).
var page := ""
var _pages := {}
var _back_stack: Array[String] = []
var _first_focus := {}
var _dim: ColorRect
var _ride_label: Label
var _setting_widgets := {}
## The settings page's line about the focused setting.
var _settings_help: Label
var _records_text: RichTextLabel
var _races_list: VBoxContainer
var _end_race_button: UiKit.MenuItem
var _races_button: UiKit.MenuItem
var _player2_button: UiKit.MenuItem
## The pause menu's "Your ride" line.
var _pause_ride: Label
var _note: Label
var _join_p1_label: Label
var _join_p2_label: Label
var _join_note: Label
var _title_quit: Button
## The title screen's update box and the WHAT'S NEW page (Updates).
var _update_box: PanelContainer
var _update_title: Label
var _update_status: Label
var _update_bar: ProgressBar
var _update_restart: Button
var _update_notes: Button
var _news_title: Label
var _news_text: RichTextLabel
var _news_restart: Button
## The title screen's column of cards and its big heading.
var _title_col: VBoxContainer
var _title_label: Label
## Page -> [its row of button hints, the hints] (see _refresh_hints).
var _hint_rows := {}
## The device that pressed a button last (a gamepad id, -1 = keyboard/mouse).
var _last_device := -1
## 2 PLAYERS page: player 1's device (the one that opened the page).
var _join_p1 := -1

## Set by Game: the races (RaceCatalog dictionaries) and whether one is running.
var races: Array = []
var racing := false
## Set by Game: two players are playing (split-screen).
var two_players := false


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
	_add_page(root, "controls_flying", _build_controls_flying())
	_add_page(root, "controls_heli", _build_controls_heli())
	_add_page(root, "records", _build_records())
	_add_page(root, "races", _build_races())
	_add_page(root, "credits", _build_credits())
	_add_page(root, "join", _build_join())
	_add_page(root, "whats_new", _build_whats_new())


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
	# The title screen and the pause drawer let the world show through;
	# other pages dim it.
	var dim := {"title": 0.15, "pause": 0.3}
	_dim.color = Color(0.02, 0.03, 0.08, dim.get(page_name, 0.55))
	_refresh_hints()
	if page_name == "settings":
		_refresh_settings()
	elif page_name == "records":
		_refresh_records()
	elif page_name == "races":
		_refresh_races()
	elif page_name == "title":
		_fit_title()
		_refresh_update()
	elif page_name == "whats_new":
		_refresh_news()
	elif page_name == "pause":
		_end_race_button.visible = racing
		_races_button.visible = not two_players
		# (No adding a player mid-race; and the page must fit 800 px.)
		_player2_button.visible = two_players or not racing
		_player2_button.text = "PLAYER 2: LEAVE" if two_players else "ADD PLAYER 2"
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


## The GARAGE tile's line names the vehicle you'll play with.
func set_ride_name(ride: String) -> void:
	_ride_label.text = "Your ride: %s" % ride
	_pause_ride.text = "Your ride: %s" % ride


func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		var was_pad := _last_device >= 0
		if event is InputEventJoypadButton:
			_last_device = event.device
		elif event is InputEventKey or event is InputEventMouseButton:
			_last_device = -1
		if (_last_device >= 0) != was_pad:
			_refresh_hints()
	if page == "join":
		_join_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if page == "":
		return
	if event.is_action_pressed("ui_cancel") or (page == "pause" and event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		_back()
	elif page == "whats_new" and (event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true)):
		get_viewport().set_input_as_handled()
		_news_text.get_v_scroll_bar().value += 66.0 * (1.0 if event.is_action_pressed("ui_down", true) else -1.0)


## One page back. The rest of the trail is kept, so pages two deep (CONTROLS
## > FLYING) still lead back to the menu they were opened from.
func _back() -> void:
	if not _back_stack.is_empty():
		var previous: String = _back_stack.pop_back()
		var trail := _back_stack.duplicate()
		show_page(previous)
		_back_stack = trail
	elif page == "pause":
		action.emit("resume")


# --- Pages ---------------------------------------------------------------

func _build_title() -> Control:
	var page_root := Control.new()
	page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark fade on the left so the cards read well over a bright scene; the
	# right side stays open for your car.
	var fade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.gradient.colors = PackedColorArray([
		Color(0.02, 0.03, 0.08, 0.8), Color(0.02, 0.03, 0.08, 0.55), Color(0.02, 0.03, 0.08, 0.0)])
	grad.fill_to = Vector2(1, 0)
	fade.texture = grad
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_bottom = 1.0
	fade.offset_right = 1150
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(fade)

	# The cards, in a column down the left (width set by _fit_title).
	var col := VBoxContainer.new()
	col.anchor_bottom = 1.0
	col.offset_left = TITLE_LEFT
	col.offset_top = 24
	col.offset_bottom = -24
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(col)
	_title_col = col

	var head := UiKit.panel(24)
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	head.add_child(hrow)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hv)
	hv.add_child(UiKit.badge("TURBO TOWN", 24))
	_title_label = UiKit.heading("READY TO RIDE?", 64)
	hv.add_child(_title_label)
	hv.add_child(UiKit.text("Your island. Your cars. Your adventures.", 22))
	var stripes := UiKit.Stripes.new(76, 5)
	stripes.size_flags_vertical = Control.SIZE_SHRINK_END
	hrow.add_child(stripes)

	var play := UiKit.Tile.new("primary", false, Vector2(24, 18))
	play.box.add_theme_constant_override("separation", 16)
	play.box.add_child(UiIcon.new("play", 42, UiKit.DARK_TEXT))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 0)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play.box.add_child(pv)
	pv.add_child(UiKit.heading("PLAY NOW", 46, UiKit.DARK_TEXT))
	pv.add_child(UiKit.text("Jump into your world", 20, UiKit.DARK_TEXT))
	# "Go" chevrons, lit up in turn while PLAY NOW has the focus.
	var go := UiKit.Chevrons.new(40)
	play.box.add_child(go)
	play.lit_changed.connect(func(lit: bool) -> void: go.animate = lit)
	play.pressed.connect(func() -> void: action.emit("drive"))
	col.add_child(play)
	_first_focus["title"] = play.button

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	_title_tile(grid, "players", "2 PLAYERS", "Play together", _open_join)
	_ride_label = _title_tile(grid, "wrench", "GARAGE", "Customise your ride", func() -> void: action.emit("garage"))
	_title_tile(grid, "flag", "RACES", "Beat your best time", func() -> void: show_page("races", true))
	_title_tile(grid, "trophy", "RECORDS", "Your biggest stunts", func() -> void: show_page("records", true))

	var foot := UiKit.panel(8)
	(foot.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(14)
	col.add_child(foot)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 6)
	foot.add_child(fh)
	_footer_button(fh, "gear", "Settings", func() -> void: show_page("settings", true))
	_footer_button(fh, "gamepad", "Controls", func() -> void: show_page("controls", true))
	_footer_button(fh, "info", "Credits", func() -> void: show_page("credits", true))
	_title_quit = _footer_button(fh, "exit", "Quit", func() -> void: action.emit("quit"))

	# Bottom right: the update box (when there's a new version) above the version.
	var corner := VBoxContainer.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.add_theme_constant_override("separation", 8)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	page_root.add_child(corner)
	corner.add_child(_build_update_box())
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	var ver := UiKit.label("v" + version if version != "" else "dev build", 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT)
	ver.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(ver)
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	return page_root


## A title screen tile: icon, title and a line under it. Returns that line.
func _title_tile(grid: GridContainer, icon: String, title: String, line: String, on_press: Callable) -> Label:
	var t := UiKit.Tile.new("tile", true, Vector2(22, 18))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.box.add_theme_constant_override("separation", 4)
	t.box.add_child(UiIcon.new(icon, 32, UiKit.ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	t.box.add_child(gap)
	t.box.add_child(UiKit.heading(title, 32))
	var sub := UiKit.text(line, 20)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.box.add_child(sub)
	t.pressed.connect(on_press)
	grid.add_child(t)
	return sub


## A small flat button for the title screen's bottom bar: icon and word.
func _footer_button(parent: Control, icon: String, text: String, on_press: Callable) -> Button:
	var t := UiKit.Tile.new("flat", false, Vector2(14, 10), 10)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.box.alignment = BoxContainer.ALIGNMENT_CENTER
	t.box.add_theme_constant_override("separation", 10)
	t.box.add_child(UiIcon.new(icon, 24, Color.WHITE))
	t.box.add_child(UiKit.heading(text, 24))
	t.pressed.connect(on_press)
	parent.add_child(t)
	return t.button


## The title screen's update box (see Updates): a newer version downloading,
## ready to install, or failed. Hidden when there's nothing new.
func _build_update_box() -> Control:
	_update_box = UiKit.panel(18)
	_update_box.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(340, 0)
	_update_box.add_child(col)
	_update_title = UiKit.heading("", 24, UiKit.ACCENT)
	col.add_child(_update_title)
	_update_status = UiKit.panel_label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_status.custom_minimum_size = Vector2(340, 0)
	col.add_child(_update_status)
	_update_bar = ProgressBar.new()
	_update_bar.show_percentage = false
	_update_bar.max_value = 1.0
	_update_bar.step = 0.001
	_update_bar.custom_minimum_size = Vector2(0, 14)
	col.add_child(_update_bar)
	_update_restart = _button(col, "RESTART TO UPDATE", func() -> void: action.emit("update"))
	_update_notes = _button(col, "WHAT'S NEW?", func() -> void: show_page("whats_new", true))
	Updates.changed.connect(_refresh_update)
	_refresh_update.call_deferred()
	return _update_box


func _refresh_update() -> void:
	var u := Updates
	_update_box.visible = u.has_news()
	if _update_box.visible:
		_update_title.text = "NEW VERSION %s" % u.latest
		_update_bar.visible = u.state in [u.State.DOWNLOADING, u.State.VERIFYING]
		_update_bar.value = u.progress
		_update_restart.visible = u.state == u.State.READY
		_update_notes.visible = u.notes != ""
		match u.state:
			u.State.DOWNLOADING:
				_update_status.text = "Downloading... %d%%" % roundi(u.progress * 100.0)
			u.State.VERIFYING:
				_update_status.text = "Checking the download..."
			u.State.READY:
				_update_status.text = "Ready! Restart the game to play it."
			_:
				_update_status.text = "Couldn't download it. Trying again soon."
	_wire_update_focus()
	if page == "whats_new":
		_refresh_news()


## D-pad between QUIT and the update box's buttons (down / right from QUIT).
func _wire_update_focus() -> void:
	var targets: Array[Button] = []
	for b: Button in [_update_restart, _update_notes]:
		if _update_box.visible and b.visible:
			targets.append(b)
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused and not focused.is_visible_in_tree() and page == "title":
		_title_quit.grab_focus.call_deferred()   # its button just went away
	if targets.is_empty():
		_title_quit.focus_neighbor_bottom = NodePath()
		_title_quit.focus_neighbor_right = NodePath()
		return
	_title_quit.focus_neighbor_bottom = _title_quit.get_path_to(targets[0])
	_title_quit.focus_neighbor_right = _title_quit.get_path_to(targets[0])
	for i in targets.size():
		var b := targets[i]
		b.focus_neighbor_left = b.get_path_to(_title_quit)
		b.focus_neighbor_top = b.get_path_to(_title_quit if i == 0 else targets[i - 1])
		b.focus_neighbor_bottom = b.get_path_to(targets[i + 1] if i + 1 < targets.size() else b)


## WHAT'S NEW: the new version's release notes, scrolled with up / down.
func _build_whats_new() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(760, 0)
	p.add_child(col)
	_news_title = UiKit.heading("WHAT'S NEW", 32, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_news_title)
	_news_text = RichTextLabel.new()
	_news_text.bbcode_enabled = true
	_news_text.scroll_active = true
	_news_text.custom_minimum_size = Vector2(760, 420)
	_news_text.add_theme_font_size_override("normal_font_size", 22)
	_news_text.add_theme_font_size_override("bold_font_size", 26)
	_news_text.add_theme_constant_override("paragraph_separation", 8)
	col.add_child(_news_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	_news_restart = _button(buttons, "RESTART TO UPDATE", func() -> void: action.emit("update"))
	var back := _button(buttons, "BACK", _back)
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["whats_new"] = back
	return center


func _refresh_news() -> void:
	_news_title.text = "WHAT'S NEW IN %s" % Updates.latest
	_news_text.text = Updates.notes
	_news_restart.visible = Updates.state == Updates.State.READY


## Sizes the title column to the screen (narrower on the Steam Deck's
## 1280 px, so the car stays in view), shrinks the big heading on short
## screens, and slides the cards in.
func _fit_title() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(vp.x * 0.46, 560.0, 720.0)
	_title_col.offset_right = TITLE_LEFT + w
	_title_label.add_theme_font_size_override("font_size", 56 if vp.y < 880.0 else 64)
	_title_col.modulate.a = 0.0
	_title_col.position.x = TITLE_LEFT - 32.0
	var tw := _title_col.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_title_col, "modulate:a", 1.0, 0.22)
	tw.tween_property(_title_col, "position:x", float(TITLE_LEFT), 0.22)


## The pause menu: a drawer down the left side (the paused world shows on
## the right) with a list of slanted buttons. The order (RESUME, END RACE,
## RACES, GARAGE, SETTINGS, CONTROLS, RECORDS, CREDITS, ADD PLAYER 2,
## MAIN MENU, QUIT GAME) is what the D-pad walks through.
func _build_pause() -> Control:
	var page_root := Control.new()
	page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drawer := PanelContainer.new()
	# The right edge leans like the buttons; the left one is off screen.
	var sb := UiKit.slant(UiKit.box(UiKit.PAGE_BG, 0, 0), 0.06)
	sb.expand_margin_left = 120
	sb.content_margin_left = TITLE_LEFT
	sb.content_margin_right = 76
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	drawer.add_theme_stylebox_override("panel", sb)
	drawer.anchor_bottom = 1.0
	drawer.offset_right = 560
	page_root.add_child(drawer)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	drawer.add_child(col)
	col.add_child(UiKit.badge("TURBO TOWN", 22))
	col.add_child(UiKit.page_title("PAUSED", 58))
	_pause_ride = UiKit.text("", 20)
	col.add_child(_pause_ride)
	col.add_child(_gap(12))
	var resume := _menu_item(col, "play", "RESUME", func() -> void: action.emit("resume"))
	_end_race_button = _menu_item(col, "close", "END RACE", func() -> void: action.emit("end_race"))
	col.add_child(_gap(8))
	_races_button = _menu_item(col, "flag", "RACES", func() -> void: show_page("races", true))
	_menu_item(col, "wrench", "GARAGE", func() -> void: action.emit("garage"))
	_menu_item(col, "gear", "SETTINGS", func() -> void: show_page("settings", true))
	_menu_item(col, "gamepad", "CONTROLS", func() -> void: show_page("controls", true))
	_menu_item(col, "trophy", "RECORDS", func() -> void: show_page("records", true))
	_menu_item(col, "info", "CREDITS", func() -> void: show_page("credits", true))
	_player2_button = _menu_item(col, "players", "ADD PLAYER 2", func() -> void:
		if two_players:
			action.emit("remove_player")
		else:
			_open_join())
	col.add_child(_gap(8))
	_menu_item(col, "home", "MAIN MENU", func() -> void: action.emit("title"))
	_menu_item(col, "exit", "QUIT GAME", func() -> void: action.emit("quit"))
	_note = UiKit.text("", 20, UiKit.ACCENT)
	_note.visible = false
	col.add_child(_note)
	col.add_child(_gap(8))
	col.add_child(_hint_row("pause", [[["A"], ["Enter"], "Select"], [["B"], ["Esc"], "Resume"]]))
	_first_focus["pause"] = resume.button
	return page_root


func _menu_item(parent: Control, icon: String, text: String, on_press: Callable) -> UiKit.MenuItem:
	var m := UiKit.MenuItem.new(icon, text, 26)
	m.pressed.connect(on_press)
	parent.add_child(m)
	return m


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## A row of button hints for a page, shown for the device in use.
func _hint_row(page_name: String, hints: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_rows[page_name] = [row, hints]
	return row


## Fills the shown page's hint row for the last device used (gamepad or
## keyboard).
func _refresh_hints() -> void:
	var entry: Array = _hint_rows.get(page, [])
	if not entry.is_empty():
		UiKit.fill_hints(entry[0], entry[1], _last_device >= 0)


## A line under the pause menu's buttons ("" hides it).
func set_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


# --- 2 PLAYERS ---------------------------------------------------------------

## Split-screen: whoever opened the page is player 1 (with the device they
## pressed the button with); player 2 joins by pressing A on another gamepad
## (or Enter on the keyboard). B / Esc goes back.
func _build_join() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(620, 0)
	p.add_child(col)
	col.add_child(UiKit.page_title("2 PLAYERS", 44, UiKit.ACCENT, true))
	col.add_child(UiKit.label("Two players, one screen: player 1 on top, player 2 below.", 20, Color(1, 1, 1, 0.85)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)
	_join_p1_label = _join_slot(row, "PLAYER 1", LocalPlayer.COLORS[0])
	_join_p2_label = _join_slot(row, "PLAYER 2", LocalPlayer.COLORS[1])
	_join_note = UiKit.label("", 20, UiKit.ACCENT)
	col.add_child(_join_note)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	back.focus_mode = Control.FOCUS_NONE  # A on this page means "join"
	return center


func _join_slot(parent: Control, title: String, col: Color) -> Label:
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.14, 0.24, 0.9), 14, 18))
	slot.custom_minimum_size = Vector2(280, 130)
	parent.add_child(slot)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	slot.add_child(v)
	var t := UiKit.label(title, 28, col)
	t.add_theme_constant_override("outline_size", 0)
	v.add_child(t)
	var l := UiKit.label("", 22, Color.WHITE)
	l.add_theme_constant_override("outline_size", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	v.add_child(l)
	return l


func _open_join() -> void:
	_join_p1 = _last_device
	_join_p1_label.text = _device_name(_join_p1)
	_join_p2_label.text = "Press A on your controller\n(or Enter on the keyboard)" if _join_p1 >= 0 else "Press A on your controller"
	# Only one gamepad and it's player 1's: say what player 2 needs.
	var pads := Input.get_connected_joypads()
	_join_note.text = "Connect a second controller!" if _join_p1 >= 0 and pads.size() < 2 else ""
	show_page("join", true)


## A short name for a device (-1 = keyboard and mouse).
static func _device_name(device: int) -> String:
	if device < 0:
		return "Keyboard and mouse"
	var n := Input.get_joy_name(device)
	return n if n != "" and n.length() <= 26 else "Controller %d" % (device + 1)


## On the 2 PLAYERS page: A (Enter / Space on the keyboard) from a device
## that isn't player 1's makes it player 2's, and play starts.
func _join_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var device := -2
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
		device = event.device
	elif event is InputEventKey and (event as InputEventKey).physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		device = -1
	if device == -2:
		return
	get_viewport().set_input_as_handled()
	if device == _join_p1:
		_join_note.text = "That's player 1's. Player 2: use another controller!"
		return
	action.emit("join:%d:%d" % [_join_p1, device])


## A line about each setting, shown under the rows while it's focused.
const SETTING_HELP := {
	"traffic_density": "How many cars drive around town.",
	"assists": "On: the car (or plane) helps you steer. Off: drift mode, it's all you!",
	"graphics": "Lower runs smoother. Higher looks nicer.",
	"flight_invert": "Which way to push the stick to make a plane climb.",
	"time_of_day": "Day, sunset, night, or a day that keeps changing.",
	"weather": "Sunny, cloudy, rain or a thunderstorm, or weather that keeps changing.",
	"vibration": "The controller rumbles when you crash.",
	"units_mph": "Show your speed in km/h or mph.",
	"crash_cam": "A slow-motion replay of your biggest crashes.",
	"minimap": "The little map in the corner while you drive.",
	"speakers": "Louder engines on small speakers. Auto: on for a Steam Deck.",
	"fullscreen": "Fill the whole screen with the game.",
	"master_volume": "How loud the whole game is.",
}


func _build_settings() -> Control:
	var center := _centered()
	var p := UiKit.page_panel(28)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	col.add_child(head)
	head.add_child(UiKit.page_title("SETTINGS", 52))
	head.add_child(UiKit.text("Set up the game your way", 20))
	# Two columns of rows (each row is one button: its name and its value),
	# so the page fits the Steam Deck's 800-pixel-high screen. Rows fill left
	# then right; up / down run down the left column and on into the right
	# one (left / right change a value).
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)

	var left: Array[Control] = []
	var right: Array[Control] = []
	left.append(_cycle_row(grid, "Traffic", "traffic_density", Settings.TRAFFIC_LABELS))
	# (Cars: traction and stability control; planes: the flying assists.)
	right.append(_cycle_row(grid, "Assists", "assists", ["Off (drift mode)", "On"]))
	left.append(_cycle_row(grid, "Graphics", "graphics", Settings.GRAPHICS_LABELS))
	right.append(_cycle_row(grid, "Flying controls", "flight_invert", ["Pull back to climb", "Push up to climb"]))
	left.append(_cycle_row(grid, "Time of day", "time_of_day", Settings.TIME_LABELS))
	right.append(_cycle_row(grid, "Vibration", "vibration", ["Off", "On"]))
	left.append(_cycle_row(grid, "Weather", "weather", Settings.WEATHER_LABELS))
	right.append(_cycle_row(grid, "Crash cam", "crash_cam", ["Off", "On"]))
	left.append(_cycle_row(grid, "Speed units", "units_mph", ["km/h", "mph"]))
	# Auto: on for the Steam Deck's own speakers (engines carry on them).
	right.append(_cycle_row(grid, "Speaker boost", "speakers", Settings.SPEAKER_LABELS))
	left.append(_cycle_row(grid, "Minimap", "minimap", ["Off", "On"]))
	var volume := UiKit.LevelButton.new("Volume")
	volume.value_changed.connect(func(v: float) -> void: Settings.set_value("master_volume", v))
	volume.focus_entered.connect(_show_help.bind("master_volume"))
	grid.add_child(volume)
	_setting_widgets["master_volume"] = volume
	right.append(volume)
	left.append(_cycle_row(grid, "Fullscreen", "fullscreen", ["Off", "On"]))

	# What the focused setting does.
	var help := PanelContainer.new()
	help.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.04), 12, 12))
	col.add_child(help)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	help.add_child(hrow)
	hrow.add_child(UiIcon.new("info", 26, UiKit.ACCENT))
	_settings_help = UiKit.text("", 20, Color.WHITE)
	hrow.add_child(_settings_help)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 22)
	col.add_child(bottom)
	var back := _button(bottom, "BACK", _back)
	back.custom_minimum_size = Vector2(200, 0)
	back.focus_entered.connect(func() -> void: _settings_help.text = "Back to the menu.")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	bottom.add_child(_hint_row("settings", [
		[["dpad_v"], ["up", "down"], "Pick"], [["dpad_h"], ["left", "right"], "Change"], [["B"], ["Esc"], "Back"]]))
	# One chain: down the left column, on to the top of the right one, BACK.
	var chain: Array[Control] = left + right
	chain.append(back)
	for i in chain.size():
		var c := chain[i]
		if i > 0:
			c.focus_neighbor_top = c.get_path_to(chain[i - 1])
			c.focus_previous = c.focus_neighbor_top
		if i < chain.size() - 1:
			c.focus_neighbor_bottom = c.get_path_to(chain[i + 1])
			c.focus_next = c.focus_neighbor_bottom
	_first_focus["settings"] = left[0]
	return center


func _cycle_row(grid: GridContainer, text: String, key: String, options: Array) -> Control:
	var b := UiKit.CycleButton.new(options, 0, text)
	b.value_changed.connect(func(i: int) -> void:
		var default: Variant = Settings.DEFAULTS[key]
		Settings.set_value(key, bool(i) if default is bool else i))
	b.focus_entered.connect(_show_help.bind(key))
	grid.add_child(b)
	_setting_widgets[key] = b
	return b


func _show_help(key: String) -> void:
	_settings_help.text = SETTING_HELP.get(key, "")


func _refresh_settings() -> void:
	for key: String in _setting_widgets:
		var w: Control = _setting_widgets[key]
		var v: Variant = Settings.get_value(key)
		if w is UiKit.CycleButton:
			var b := w as UiKit.CycleButton
			b.index = int(v)
			b._refresh()
		elif w is UiKit.LevelButton:
			(w as UiKit.LevelButton).set_value_no_signal(v)


func _build_controls() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	col.add_child(UiKit.page_title("CONTROLS", 44, UiKit.ACCENT, true))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	col.add_child(columns)
	var left := VBoxContainer.new()
	columns.add_child(left)
	_controls_grid(left, "DRIVING", CONTROLS)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	columns.add_child(right)
	_controls_grid(right, "ON FOOT", CONTROLS_FOOT)
	_controls_grid(right, "ANYWHERE", CONTROLS_ANYWHERE)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	col.add_child(buttons)
	var back := _button(buttons, "BACK", _back)
	back.custom_minimum_size = Vector2(200, 0)
	var fly := _button(buttons, "FLYING", func() -> void: show_page("controls_flying", true))
	fly.custom_minimum_size = Vector2(200, 0)
	var heli := _button(buttons, "HELICOPTER", func() -> void: show_page("controls_heli", true))
	heli.custom_minimum_size = Vector2(200, 0)
	_first_focus["controls"] = back
	return center


## The plane's controls (their own page: the CONTROLS page is full).
func _build_controls_flying() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	col.add_child(UiKit.page_title("FLYING", 44, UiKit.ACCENT, true))
	_controls_grid(col, "PLANES (at the Airfield, 7, or in the garage)", CONTROLS_FLYING)
	var tip := UiKit.label("Take off: full power, then pull back at 80 km/h.\nLand: slow down low over the runway and let go.", 20,
		Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(tip)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["controls_flying"] = back
	return center


## The helicopter's controls (a page of their own, like the plane's).
func _build_controls_heli() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	col.add_child(UiKit.page_title("HELICOPTER", 44, UiKit.ACCENT, true))
	_controls_grid(col, "HELICOPTER (in the garage, or at the Airfield's helipad, 7)", CONTROLS_HELI)
	var tip := UiKit.label("Take off: wait for the rotor, then hold up.\nLand anywhere flat: go down gently and it settles on its skids.", 20,
		Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	col.add_child(tip)
	var back := _button(col, "BACK", _back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(200, 0)
	_first_focus["controls_heli"] = back
	return center


func _controls_grid(parent: Control, title: String, rows: Array) -> void:
	parent.add_child(UiKit.heading(title, 26, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)
	for h in ["", "Keyboard", "Gamepad"]:
		grid.add_child(UiKit.label(h, 18, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT))
	for row: Array in rows:
		grid.add_child(UiKit.label(row[0], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiKit.label(row[1], 18, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(UiKit.label(row[2], 18, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))


## Third-party sounds and their licences (ASSET_MANIFEST.md has the full
## list; CC BY needs this attribution in the game).
const CREDITS := "[b]TURBO TOWN[/b]\n\n" \
	+ "[color=#ffd54a]Engine sounds[/color]  by CryHam (Stunt Rally 3), recorded with Engine Simulator. CC BY 4.0\n" \
	+ "[color=#ffd54a]Crash and metal sounds[/color]  by Halleck (freesound.org), edited by CryHam (Stunt Rally 3). CC BY 4.0\n" \
	+ "[color=#ffd54a]Tyre squeal[/color]  by Iwan \"qubodup\" Gabovitch from a recording by Tom Haigh (audible-edge). CC BY 3.0\n" \
	+ "[color=#ffd54a]Air Break, Window Shattering[/color]  by Mike Koenig (SoundBible.com). CC BY 3.0\n" \
	+ "[color=#ffd54a]CC0 sounds[/color]  by Kenney, cognito perceptu, 15HPanska_Ruttner_Jan, HarveyHenkelmann, X5DragonFire, TinyWorlds / Till Behrend, rubberduck, blacklodgegames\n\n" \
	+ "[color=#ffd54a]Skies, textures, rock models[/color]  from Poly Haven and ambientCG. CC0\n" \
	+ "[color=#ffd54a]Character and animations[/color]  from the Universal Animation Library by Quaternius. CC0\n" \
	+ "[color=#ffd54a]Barlow Condensed font[/color]  by The Barlow Project Authors. SIL OFL 1.1\n\n" \
	+ "Sounds changed for Turbo Town (looped, filtered, mixed, levels).\n" \
	+ "CC BY: creativecommons.org/licenses/by/4.0 and /by/3.0\n" \
	+ "Everything else is made for this game."


func _build_credits() -> Control:
	var center := _centered()
	var p := UiKit.panel(30)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(760, 0)
	p.add_child(col)
	col.add_child(UiKit.page_title("CREDITS", 44, UiKit.ACCENT, true))
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
	col.add_child(UiKit.page_title("RECORDS", 44, UiKit.ACCENT, true))
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
	col.add_child(UiKit.page_title("RACES", 44, UiKit.ACCENT, true))
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


## A menu button (theme: slanted, yellow while focused or hovered).
## Hovering with the mouse moves the focus to it, so only one is lit.
func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	b.mouse_entered.connect(func() -> void:
		if b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())
	parent.add_child(b)
	return b
