class_name VehiclePicker
extends CanvasLayer
## The garage: pick a vehicle on a spinning turntable, set it up the way you
## like and drive off. Works with keyboard, gamepad and mouse.
##
## Tabs come from PartsCatalog.TABS (LB / RB or Q / E switch them). CAR picks
## the vehicle with left/right; every other tab is a list of PartsCatalog
## slots: up/down picks a row, left/right changes it, and the camera looks
## where the tab says (the WHEELS tab zooms in on a front wheel). X / (Y)
## is "surprise me": a random vehicle, or random choices on the tab.
##
## Each vehicle keeps its own setup (Loadout). Changes stick even when you
## back out: Game saves `loadouts` either way, and does the vehicle swap
## when you drive off. Game pauses the world while the garage is open.

signal picked(index: int)
signal cancelled

const ACCENT := UiKit.ACCENT
## Turntable angle that shows the vehicle's left side with the front turned
## a little toward the camera (the wheel view).
const WHEEL_VIEW_ANGLE := 2.0
## Colour swatches: 12 to a row, so a palette takes one line.
const SWATCH := 32

var is_open := false
## The vehicle shown (index into VehicleCatalog.ENTRIES).
var index := 0
## The tab shown (index into PartsCatalog.TABS).
var tab := 0
## Vehicle id -> Loadout: every vehicle looked at since the garage opened,
## with the changes made to it.
var loadouts := {}

var _opened_frame := -1
var _viewport: SubViewport
var _turntable: Node3D
var _platform: MeshInstance3D
var _camera: Camera3D
var _car: Vehicle
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _snap_camera := true
var _name_label: Label
var _count_label: Label
var _blurb_label: Label
var _weight_label: Label
## Per stat: the five bar segments.
var _stat_cells: Array[Array] = []
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
## Per tab: its SlotRows.
var _rows: Array[Array] = []
## Per tab: the focused row.
var _row_focus: Array[int] = []
var _arrows: Array[Button] = []
var _hints: HBoxContainer
## The tab strip's prompts (LB / RB or Q / E).
var _tab_prompts: Array[Container] = []
var _panel: Control
var _drive_label: Label
## The last input came from a gamepad: prompts show its buttons.
var _pad := false
var _horn: AudioStreamPlayer
var _horn_left := 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PAGE_BG, 20, 22))
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	center.add_child(panel)
	_panel = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	# Header: the page title, and which vehicle of how many on the right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	titles.add_child(UiKit.heading("MY GARAGE", 32))
	titles.add_child(UiKit.text("Build your perfect ride", 20))
	var count := PanelContainer.new()
	var chip := UiKit.box(UiKit.CARD, 12, 8)
	chip.content_margin_left = 16
	chip.content_margin_right = 16
	count.add_theme_stylebox_override("panel", chip)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(count)
	_count_label = UiKit.heading("", 24, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	count.add_child(_count_label)

	# Tabs, the full width, between their LB / RB (Q / E) prompts.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	_tab_prompts.append(_prompt_slot(tabs))
	for t in PartsCatalog.TABS.size():
		var b := Button.new()
		b.text = PartsCatalog.TABS[t]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_override("font", UiKit.bold_font())
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void: _set_tab(t))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_tab_prompts.append(_prompt_slot(tabs))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	row.add_child(_make_preview_card())
	row.add_child(_make_info())

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 26)
	_hints.custom_minimum_size = Vector2(0, 34)
	col.add_child(_hints)


## A holder for a prompt that changes with the device (see _refresh_hints).
func _prompt_slot(parent: Control) -> Container:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## The preview card: the turntable on a showroom backdrop, between the
## left / right arrows.
func _make_preview_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.CARD, 16, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	card.add_child(row)
	row.add_child(_arrow_button(-1))
	row.add_child(_make_preview())
	row.add_child(_arrow_button(1))
	return card


func _make_preview() -> Control:
	# The stage: a rounded showroom backdrop (a soft spotlight) that also
	# clips the 3D view to its corners.
	var stage := Panel.new()
	stage.add_theme_stylebox_override("panel", UiKit.box(Color(0.12, 0.15, 0.22), 12, 0))
	stage.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	# As tall as the longest tab, so the panel keeps its size between tabs.
	stage.custom_minimum_size = Vector2(580, 500)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.36, 0.43, 0.57))
	grad.gradient.set_color(1, Color(0.12, 0.15, 0.22))
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.12, 0.45)
	glow.texture = grad
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(glow)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(frame)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	frame.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.88, 1.0)
	env.ambient_light_energy = 0.75
	# Same tone mapping as the world (world.tscn) so paint looks the same here.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_contrast = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	# Metal rims, chrome and metallic paint need something to reflect (with
	# nothing they go black): a soft studio sky, used for reflections only.
	# A light studio floor, so wheel faces (which mostly see the floor in the
	# wheel view) show their metal finishes.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.4, 0.55)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sky_mat.ground_horizon_color = Color(0.66, 0.68, 0.71)
	sky_mat.ground_bottom_color = Color(0.4, 0.41, 0.43)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	fill.light_energy = 0.4
	_viewport.add_child(fill)

	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_platform = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.16
	disc.radial_segments = 64
	_platform.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.23, 0.3)
	mat.roughness = 0.45
	_platform.material_override = mat
	_platform.position.y = -0.08
	_turntable.add_child(_platform)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 47.0
	_camera.current = true
	_viewport.add_child(_camera)
	return stage


func _make_info() -> Control:
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(460, 0)
	info.add_theme_constant_override("separation", 8)
	_name_label = UiKit.heading("", 36)
	info.add_child(_name_label)

	for t in PartsCatalog.TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		info.add_child(page)
		_pages.append(page)
		var rows: Array[SlotRow] = []
		if PartsCatalog.TABS[t]["id"] == "car":
			_fill_car_page(page)
		for slot: String in PartsCatalog.TABS[t]["slots"]:
			var r := SlotRow.new(slot, SWATCH)
			r.changed.connect(_on_row_changed)
			r.clicked.connect(func(rr: SlotRow) -> void: _focus_row(rows.find(rr)))
			page.add_child(r)
			rows.append(r)
		_rows.append(rows)
		_row_focus.append(0)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	var drive := UiKit.Tile.new("primary", false, Vector2(18, 12), 12)
	drive.button.focus_mode = Control.FOCUS_NONE
	drive.box.alignment = BoxContainer.ALIGNMENT_CENTER
	drive.box.add_theme_constant_override("separation", 12)
	drive.box.add_child(UiIcon.new("play", 30, UiKit.DARK_TEXT))
	_drive_label = UiKit.heading("DRIVE!", 26, UiKit.DARK_TEXT)
	drive.box.add_child(_drive_label)
	drive.pressed.connect(_confirm)
	info.add_child(drive)
	return info


func _fill_car_page(page: VBoxContainer) -> void:
	_blurb_label = UiKit.text("", 20, Color.WHITE)
	_blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_label.custom_minimum_size = Vector2(460, 56)
	page.add_child(_blurb_label)
	_weight_label = UiKit.text("", 18)
	page.add_child(_weight_label)
	var gap0 := Control.new()
	gap0.custom_minimum_size = Vector2(0, 6)
	page.add_child(gap0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	page.add_child(grid)
	for stat: Array in VehicleCatalog.STATS:
		grid.add_child(UiKit.heading(stat[1], 18, UiKit.MUTED))
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 5)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cells: Array[Panel] = []
		for k in 5:
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(0, 12)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_child(cell)
			cells.append(cell)
		grid.add_child(bar)
		_stat_cells.append(cells)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	page.add_child(gap)
	var tip := UiKit.text("Make it yours! Change the paint and the wheels on the next tabs.", 20, ACCENT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(460, 0)
	page.add_child(tip)


func _arrow_button(dir: int) -> Button:
	var b := ArrowButton.new()
	b.dir = dir
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 0)
	b.add_theme_stylebox_override("normal", UiKit.box(Color(1, 1, 1, 0.0), 10, 0))
	b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.08), 10, 0))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color(1, 1, 1, 0.16), 10, 0))
	b.add_theme_stylebox_override("disabled", UiKit.box(Color(1, 1, 1, 0.0), 10, 0))
	b.pressed.connect(func() -> void: _step(dir))
	_arrows.append(b)
	return b


## Opens on vehicle `current`, which is wearing `setup` right now.
func open(current: int, setup: Loadout = null) -> void:
	index = clampi(current, 0, VehicleCatalog.count() - 1)
	loadouts.clear()
	if setup:
		loadouts[setup.vehicle_id] = setup.copy()
	tab = 0
	for t in _row_focus.size():
		_row_focus[t] = 0
	is_open = true
	visible = true
	# Ignore the key press that opened the garage.
	_opened_frame = Engine.get_process_frames()
	_turntable.rotation.y = 2.4
	_snap_camera = true
	_show_vehicle()
	_set_tab(0)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.97, 0.97)
	var tw := _panel.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.18)


## Tracks whether the last input was a gamepad (even while closed, so the
## prompts are right when the garage opens).
func _input(event: InputEvent) -> void:
	var pad := _pad
	if event is InputEventJoypadButton and event.is_pressed():
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pad = true
	elif (event is InputEventKey and event.is_pressed()) or event is InputEventMouseButton:
		pad = false
	if pad != _pad:
		_pad = pad
		if is_open:
			_refresh_hints()


func close() -> void:
	is_open = false
	visible = false
	if _car:
		_turntable.remove_child(_car)
		_car.queue_free()
		_car = null


## The setup being edited for the vehicle shown.
func loadout() -> Loadout:
	var id: String = VehicleCatalog.ENTRIES[index]["id"]
	if not loadouts.has(id):
		loadouts[id] = Loadout.saved(id)
	return loadouts[id]


func _process(dt: float) -> void:
	if _horn and _horn.playing:
		_horn_left -= dt
		if _horn_left <= 0.0 or not is_open:
			_horn.stop()
	if not is_open:
		return
	_update_view(dt)
	if Engine.get_process_frames() == _opened_frame:
		return
	var on_car := _rows[tab].is_empty()
	if Input.is_action_just_pressed("menu_tab_prev"):
		_set_tab(tab - 1)
	elif Input.is_action_just_pressed("menu_tab_next"):
		_set_tab(tab + 1)
	elif Input.is_action_just_pressed("menu_left"):
		if on_car:
			_step(-1)
		else:
			_change_row(-1)
	elif Input.is_action_just_pressed("menu_right"):
		if on_car:
			_step(1)
		else:
			_change_row(1)
	elif Input.is_action_just_pressed("menu_up") and not on_car:
		_move_focus(-1)
	elif Input.is_action_just_pressed("menu_down") and not on_car:
		_move_focus(1)
	elif Input.is_action_just_pressed("menu_extra"):
		_surprise()
	elif Input.is_action_just_pressed("menu_accept"):
		_confirm()
	elif Input.is_action_just_pressed("menu_back") or Input.is_action_just_pressed("pause"):
		close()
		cancelled.emit()


func _step(dir: int) -> void:
	index = wrapi(index + dir, 0, VehicleCatalog.count())
	_show_vehicle()


func _set_tab(t: int) -> void:
	tab = wrapi(t, 0, PartsCatalog.TABS.size())
	for i in _tab_buttons.size():
		var on := i == tab
		var b := _tab_buttons[i]
		for st in ["normal", "hover", "pressed"]:
			var bg := ACCENT if on else (UiKit.CARD if st == "normal" else UiKit.CARD_HOVER)
			b.add_theme_stylebox_override(st, UiKit.box(bg, 10, 4))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, UiKit.DARK_TEXT if on else Color.WHITE)
	for i in _pages.size():
		_pages[i].visible = i == tab
	var on_car := _rows[tab].is_empty()
	for a in _arrows:
		a.disabled = not on_car
		a.modulate.a = 1.0 if on_car else 0.0
	_refresh_hints()
	_refresh_rows()


## The prompts along the bottom and beside the tabs, for the device in use:
## gamepad buttons, or keyboard keys.
func _refresh_hints() -> void:
	var on_car := _rows[tab].is_empty()
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	if on_car:
		_hint(["dpad_h"], ["left", "right"], "Vehicle")
	else:
		_hint(["dpad_v"], ["up", "down"], "Pick")
		_hint(["dpad_h"], ["left", "right"], "Change")
	_hint(["LB", "RB"], ["Q", "E"], "Customise" if on_car else "Tabs")
	_hint(["Y"], ["X"], "Surprise me!")
	_hint(["A"], ["Enter"], "Drive!")
	_hint(["B"], ["Esc"], "Back")
	for i in _tab_prompts.size():
		var slot := _tab_prompts[i]
		for c in slot.get_children():
			slot.remove_child(c)
			c.queue_free()
		var key: String = ["LB", "RB"][i] if _pad else ["Q", "E"][i]
		slot.add_child(UiKit.prompt(key, _pad))


## One hint: its prompts (gamepad `pad_keys` or keyboard `keys`) and a word.
func _hint(pad_keys: Array, keys: Array, what: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k: String in (pad_keys if _pad else keys):
		h.add_child(UiKit.prompt(k, _pad))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(2, 0)
	h.add_child(gap)
	h.add_child(UiKit.text(what, 20, Color.WHITE))
	_hints.add_child(h)


func _focus_row(i: int) -> void:
	var rows: Array = _rows[tab]
	if i < 0 or i >= rows.size() or not (rows[i] as SlotRow).enabled:
		return
	_row_focus[tab] = i
	_refresh_rows()


## Moves the row focus up or down, skipping rows that can't be changed.
func _move_focus(dir: int) -> void:
	var rows: Array = _rows[tab]
	var i: int = _row_focus[tab]
	for k in rows.size():
		i += dir
		if i < 0 or i >= rows.size():
			return
		if (rows[i] as SlotRow).enabled:
			_focus_row(i)
			return


func _change_row(dir: int) -> void:
	var rows: Array = _rows[tab]
	if rows.is_empty():
		return
	var r := rows[_row_focus[tab]] as SlotRow
	if r.enabled:
		var vid := loadout().vehicle_id
		_set_slot(r.slot, PartsCatalog.index_of(r.slot, loadout().get_value(r.slot), vid) + dir)


func _on_row_changed(slot: String, option_index: int) -> void:
	var rows: Array = _rows[tab]
	for i in rows.size():
		if (rows[i] as SlotRow).slot == slot:
			_row_focus[tab] = i
	_set_slot(slot, option_index)


## Sets a slot of the shown vehicle's setup (`option_index` into the
## options that fit it) and shows it on the turntable.
func _set_slot(slot: String, option_index: int) -> void:
	var l := loadout()
	l.set_value(slot, PartsCatalog.value_at(slot, option_index, l.vehicle_id))
	if _car:
		l.apply(_car)
	if slot == "horn":
		_play_horn(l.get_value("horn"))
	_refresh_rows()


## Plays a second of the horn picked (the shown vehicle's own for "stock").
func _play_horn(id: String) -> void:
	if _horn == null:
		_horn = AudioStreamPlayer.new()
		_horn.bus = &"Signals"
		add_child(_horn)
	var o := PartsCatalog.option("horn", id)
	var profile := VehicleCatalog.scene_value(index, "Audio", "profile", null) as VehicleSoundProfile
	if o.has("file"):
		_horn.stream = load(PartsCatalog.horn_stream(id))
		_horn.volume_db = o["db"]
		_horn.pitch_scale = o["pitch"]
	elif profile and profile.horn:
		_horn.stream = profile.horn
		_horn.volume_db = profile.horn_volume_db
		_horn.pitch_scale = profile.horn_pitch
	else:
		return
	_horn.play()
	_horn_left = 1.1


## "Surprise me!": a random vehicle on the CAR tab, otherwise random
## choices for every row on this tab.
func _surprise() -> void:
	var rows: Array = _rows[tab]
	if rows.is_empty():
		_step(randi_range(1, VehicleCatalog.count() - 1))
		return
	var l := loadout()
	for r: SlotRow in rows:
		if not r.enabled or r.slot == "horn":
			continue
		var n := PartsCatalog.options(r.slot, l.vehicle_id).size()
		l.set_value(r.slot, PartsCatalog.value_at(r.slot, randi_range(0, n - 1), l.vehicle_id))
	if _car:
		l.apply(_car)
	_refresh_rows()


func _confirm() -> void:
	var i := index
	close()
	picked.emit(i)


## Puts the selected vehicle on the turntable and updates the text.
func _show_vehicle() -> void:
	if _car:
		_turntable.remove_child(_car)
		_car.queue_free()
	var car := VehicleCatalog.scene(index).instantiate() as Vehicle
	# A frozen, silent display model: no sounds, effects, dents or physics.
	for n in ["Audio", "Effects", "Damage"]:
		var node := car.get_node_or_null(n)
		if node:
			car.remove_child(node)
			node.free()
	car.freeze = true
	car.process_mode = Node.PROCESS_MODE_DISABLED
	for child in car.get_children():
		if child is VehicleWheel:
			(child as VehicleWheel).pose_at_rest(car.mass / 4.0)
	car.position.y = car.ride_height()
	_turntable.add_child(car)
	_car = car
	loadout().apply(car)

	# Frame it so the whole vehicle stays in view while it spins.
	var half_len := maxf(car.body_front, car.body_rear)
	var radius := sqrt(half_len * half_len + car.body_half_width * car.body_half_width)
	_platform.scale = Vector3(radius + 0.5, 1.0, radius + 0.5)
	_update_view(0.0)

	var e: Dictionary = VehicleCatalog.ENTRIES[index]
	_name_label.text = String(e["name"]).to_upper()
	_blurb_label.text = e["blurb"]
	_weight_label.text = "Weight: %.1f tonnes" % (car.mass / 1000.0)
	_count_label.text = "%02d / %02d" % [index + 1, VehicleCatalog.count()]
	var noun: String = String(e["name"]).split(" ")[-1].to_upper()
	_drive_label.text = "FLY THIS PLANE" if e.get("air", false) else "DRIVE THIS %s" % noun
	for s in VehicleCatalog.STATS.size():
		var value: int = e[VehicleCatalog.STATS[s][0]]
		var cells: Array = _stat_cells[s]
		for k in cells.size():
			(cells[k] as Panel).add_theme_stylebox_override("panel",
				UiKit.box(ACCENT if k < value else Color(1, 1, 1, 0.13), 3, 0))
	_refresh_rows()


## Spins the turntable (or turns it to the wheel view) and eases the camera
## to where the tab wants it.
func _update_view(dt: float) -> void:
	if _car == null:
		return
	var look: Vector3
	var pos: Vector3
	var wheel := _view_wheel() if PartsCatalog.TABS[tab]["focus"] == "wheel" else null
	var view := _slot_view()
	if view != "" and VIEWS.has(view):
		# Turn the part toward the camera and frame the car a little closer.
		var v: Dictionary = VIEWS[view]
		var k := 1.0 if _snap_camera else 1.0 - exp(-5.0 * dt)
		_turntable.rotation.y = lerp_angle(_turntable.rotation.y, v["angle"], k)
		var half_len := maxf(_car.body_front, _car.body_rear)
		var radius := sqrt(half_len * half_len + _car.footprint_half_width * _car.footprint_half_width)
		var dist: float = (radius * 3.1 + 2.0) * v["dist"]
		look = Vector3(0.0, (_car.ride_height() + _car.body_top) * v["look"], 0.0)
		pos = look + Vector3(0.0, dist * v["height"], dist)
	elif wheel:
		var k := 1.0 if _snap_camera else 1.0 - exp(-6.0 * dt)
		_turntable.rotation.y = lerp_angle(_turntable.rotation.y, WHEEL_VIEW_ANGLE, k)
		var vis := wheel.get_node("Visual") as Node3D
		var centre := Basis(Vector3.UP, WHEEL_VIEW_ANGLE) * (_car.transform * (wheel.transform * vis.position))
		# A little toward the car, so the wheel sits in its arch on screen.
		look = centre + Vector3(0.35 * wheel.radius, 0.1 * wheel.radius, 0.0)
		pos = look + Vector3(0.15, 0.3, 1.0).normalized() * (wheel.radius * 5.2 + 0.5)
	else:
		_turntable.rotation.y += dt * 0.5
		var half_len := maxf(_car.body_front, _car.body_rear)
		var radius := sqrt(half_len * half_len + _car.footprint_half_width * _car.footprint_half_width)
		# Close enough to fill the stage, far enough to keep it all in view
		# as it spins.
		var dist := radius * 2.6 + 1.3
		look = Vector3(0.0, (_car.ride_height() + _car.body_top) * 0.4, 0.0)
		pos = look + Vector3(0.0, dist * 0.3, dist)
	if _snap_camera:
		_cam_look = look
		_cam_pos = pos
		_snap_camera = false
	else:
		var k := 1.0 - exp(-7.0 * dt)
		_cam_look = _cam_look.lerp(look, k)
		_cam_pos = _cam_pos.lerp(pos, k)
	_camera.position = _cam_pos
	_camera.look_at(_cam_look)


## Where the camera looks while a slot's row is picked (PartsCatalog
## SLOTS "view"): turntable angle (0 = rear toward the camera, PI = front),
## camera distance (x the whole-car distance), height (x distance) and the
## look-at height (x the car's height).
const VIEWS := {
	"front": {"angle": PI - 0.6, "dist": 0.8, "height": 0.2, "look": 0.3},
	"rear": {"angle": -0.6, "dist": 0.8, "height": 0.25, "look": 0.35},
	"side": {"angle": PI * 0.5 + 0.1, "dist": 0.85, "height": 0.18, "look": 0.35},
	"top": {"angle": PI - 0.75, "dist": 0.85, "height": 0.62, "look": 0.4},
	"low": {"angle": PI * 0.5 + 0.35, "dist": 0.85, "height": 0.06, "look": 0.15},
}


## The focused row's camera view ("" = the tab's own).
func _slot_view() -> String:
	if tab >= _rows.size() or _rows[tab].is_empty():
		return ""
	var r := _rows[tab][_row_focus[tab]] as SlotRow
	return PartsCatalog.SLOTS[r.slot].get("view", "")


## The front wheel on the side the wheel view shows (front left).
func _view_wheel() -> VehicleWheel:
	for child in _car.get_children():
		var w := child as VehicleWheel
		if w and w.position.x < 0.0 and w.position.z < 0.0:
			return w
	return null


func _refresh_rows() -> void:
	if tab >= _rows.size():
		return
	var l := loadout()
	var body := _car.get_node_or_null("Body") as VehicleBodyVisual if _car else null
	var rows: Array = _rows[tab]
	for r: SlotRow in rows:
		r.show_value(l, why_not(r.slot, l, _car))
	# Keep the focus on a row that can be changed.
	if not rows.is_empty() and not (rows[_row_focus[tab]] as SlotRow).enabled:
		for i in rows.size():
			if (rows[i] as SlotRow).enabled:
				_row_focus[tab] = i
				break
	for i in rows.size():
		(rows[i] as SlotRow).set_focused(i == _row_focus[tab])


## Why `slot` can't be changed on `car` right now ("" = it can).
static func why_not(slot: String, l: Loadout, car: Vehicle) -> String:
	var body := car.get_node_or_null("Body") as VehicleBodyVisual if car else null
	if car is Aircraft:
		if slot in Loadout.WHEEL_SLOTS:
			return "Planes keep their own wheels"
		if PartsCatalog.is_body_slot(slot) or slot in ["two_tone", "tone_color", "decal", "decal_color", "number", "underglow", "horn"]:
			return "Not on planes"
	match slot:
		"stripes":
			if body == null or not body.has_stripes():
				return "Not on this vehicle"
		"calipers":
			if not PartsCatalog.option("rims", l.get_value("rims")).get("open", false):
				return "Hidden by these rims"
		"tone_color":
			if l.get_value("two_tone") == "off":
				return "Pick a two-tone first"
		"decal_color":
			if l.get_value("decal") == "none" and l.get_value("number") == "none":
				return "Pick a decal or number first"
	if PartsCatalog.kind(slot) == "choice" and PartsCatalog.options(slot, l.vehicle_id).size() <= 1:
		return "Not on this vehicle"
	return ""


## A flat button that draws a chevron (ART_BIBLE §22: no font glyphs).
class ArrowButton extends Button:
	var dir := 1
	var arrow := 24.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color.WHITE if is_hovered() else UiKit.ACCENT
		var h := arrow
		var w := maxf(h * 0.22, 2.5)
		var pts := PackedVector2Array([
			c + Vector2(-h * 0.32 * dir, -h * 0.7), c + Vector2(h * 0.32 * dir, 0.0), c + Vector2(-h * 0.32 * dir, h * 0.7)])
		draw_polyline(pts, col, w, true)
		for p in pts:
			draw_circle(p, w * 0.5, col, true, -1.0, true)


## One garage row: a PartsCatalog slot and its current value, shown as
## arrows round a name ("choice"), a grid of swatches ("swatch") or an
## ON/OFF button ("toggle"). Clicks pick values; the garage moves the focus.
class SlotRow extends PanelContainer:
	signal changed(slot: String, option_index: int)
	signal clicked(row: SlotRow)

	var slot := ""
	var enabled := true
	var _kind := ""
	var _value: Label
	var _stock: Label
	var _swatches: Array[Panel] = []
	var _toggle: Button
	var _focused := false
	## Index of the current value in PartsCatalog.options(slot, _vehicle).
	var _current := 0
	var _vehicle := ""

	func _init(slot_id: String, swatch_size: int) -> void:
		slot = slot_id
		_kind = PartsCatalog.kind(slot)
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(self))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		add_child(col)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		col.add_child(line)
		var title := UiKit.heading(PartsCatalog.slot_name(slot), 18, UiKit.MUTED)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)
		_stock = UiKit.label("STOCK", 16, Color(1, 1, 1, 0.6))
		_stock.remove_theme_constant_override("outline_size")
		var chip := UiKit.box(Color(1, 1, 1, 0.1), 8, 0)
		chip.content_margin_left = 7
		chip.content_margin_right = 7
		_stock.add_theme_stylebox_override("normal", chip)
		line.add_child(_stock)
		match _kind:
			"choice":
				line.add_child(_small_arrow(-1))
				_value = UiKit.panel_label("", 20, Color.WHITE)
				_value.custom_minimum_size = Vector2(150, 0)
				line.add_child(_value)
				line.add_child(_small_arrow(1))
			"toggle":
				_toggle = Button.new()
				_toggle.focus_mode = Control.FOCUS_NONE
				_toggle.custom_minimum_size = Vector2(96, 34)
				_toggle.add_theme_font_size_override("font_size", 18)
				_toggle.add_theme_font_override("font", UiKit.bold_font())
				_toggle.pressed.connect(func() -> void:
					clicked.emit(self)
					changed.emit(slot, 0 if _toggle.text == "ON" else 1))
				line.add_child(_toggle)
				_value = UiKit.text("", 18, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
				_value.visible = false
				col.add_child(_value)
			"swatch":
				_value = UiKit.panel_label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
				line.add_child(_value)
				line.move_child(_value, 1)
				var grid := GridContainer.new()
				grid.columns = 12
				grid.add_theme_constant_override("h_separation", 4)
				grid.add_theme_constant_override("v_separation", 8)
				col.add_child(grid)
				var opts := PartsCatalog.options(slot)
				for i in opts.size():
					var frame := Panel.new()
					frame.custom_minimum_size = Vector2(swatch_size, swatch_size)
					frame.mouse_filter = Control.MOUSE_FILTER_STOP
					frame.tooltip_text = opts[i]["name"]
					frame.gui_input.connect(func(ev: InputEvent) -> void:
						if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and enabled:
							clicked.emit(self)
							changed.emit(slot, i))
					var inner := Panel.new()
					inner.set_anchors_preset(Control.PRESET_FULL_RECT)
					inner.offset_left = 4
					inner.offset_top = 4
					inner.offset_right = -4
					inner.offset_bottom = -4
					inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
					frame.add_child(inner)
					grid.add_child(frame)
					_swatches.append(frame)
		set_focused(false)

	func _small_arrow(dir: int) -> Button:
		var b := ArrowButton.new()
		b.dir = dir
		b.arrow = 11.0
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(30, 34)
		b.add_theme_stylebox_override("normal", UiKit.box(Color(1, 1, 1, 0.0), 8, 0))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.1), 8, 0))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(1, 1, 1, 0.2), 8, 0))
		b.pressed.connect(func() -> void:
			if enabled:
				clicked.emit(self)
				var opts := PartsCatalog.options(slot, _vehicle)
				changed.emit(slot, wrapi(_current + dir, 0, opts.size())))
		return b

	## Shows `l`'s value for this slot; a non-empty `why_not` greys the row
	## out (it can't be changed on this vehicle right now) and says why.
	func show_value(l: Loadout, why_not: String) -> void:
		enabled = why_not.is_empty()
		modulate.a = 1.0 if enabled else 0.45
		var v: Variant = l.get_value(slot)
		_vehicle = l.vehicle_id
		_current = PartsCatalog.index_of(slot, v, _vehicle)
		var opts := PartsCatalog.options(slot, _vehicle)
		var o: Dictionary = opts[_current]
		_stock.visible = enabled and l.is_stock(slot) and slot != "stripes" and o["id"] != "stock"
		match _kind:
			"choice":
				_value.text = o["name"]
			"toggle":
				_toggle.text = "ON" if v else "OFF"
				var on: bool = v
				for st in ["normal", "hover", "pressed", "disabled"]:
					_toggle.add_theme_stylebox_override(st, UiKit.box(UiKit.ACCENT if on else Color(1, 1, 1, 0.12), 10, 4))
				for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
					_toggle.add_theme_color_override(c, UiKit.DARK_TEXT if on else Color.WHITE)
				_toggle.disabled = not enabled
				_value.text = why_not
				_value.visible = not enabled
			"swatch":
				_value.text = o["name"] if enabled else why_not
				for i in _swatches.size():
					_style_swatch(_swatches[i], opts[i], l, i == _current and enabled)

	func _style_swatch(frame: Panel, o: Dictionary, l: Loadout, selected: bool) -> void:
		var col: Color = o.get("color", Color.WHITE)
		if slot == "rim_color":
			if o["id"] == "stock":
				col = PartsCatalog.option("rims", l.get_value("rims"))["color"]
			elif o["id"] == "body":
				col = l.get_value("paint")
		var half := int(frame.custom_minimum_size.x * 0.5)
		var ring := UiKit.box(Color(0, 0, 0, 0), half, 0)
		ring.draw_center = false
		ring.set_border_width_all(3 if selected else 1)
		ring.border_color = Color.WHITE if selected else Color(1, 1, 1, 0.25)
		frame.add_theme_stylebox_override("panel", ring)
		var fill := UiKit.box(col, half - 4, 0)
		if o.has("ring"):
			# Tyre stripes: a band of colour round a tyre-black middle.
			fill.bg_color = Color(0.11, 0.11, 0.12)
			fill.set_border_width_all(o["ring"])
			fill.border_color = col
		(frame.get_child(0) as Panel).add_theme_stylebox_override("panel", fill)

	func set_focused(on: bool) -> void:
		_focused = on
		var sb := UiKit.box(UiKit.CARD_HOVER if on else Color(1, 1, 1, 0.035), 12, 8)
		sb.set_border_width_all(3)
		sb.border_color = UiKit.ACCENT if on else Color(0, 0, 0, 0)
		add_theme_stylebox_override("panel", sb)
