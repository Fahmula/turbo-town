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
const KEY := "[color=#ffd54a]%s[/color]"
## Turntable angle that shows the vehicle's left side with the front turned
## a little toward the camera (the wheel view).
const WHEEL_VIEW_ANGLE := 2.0
const SWATCH := 36

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
var _hints: RichTextLabel


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

	var panel := UiKit.panel()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	var title := UiKit.label("GARAGE", 28, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	title.custom_minimum_size = Vector2(150, 0)
	top.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tabs)
	tabs.add_child(_prompt_chip("LB"))
	for t in PartsCatalog.TABS.size():
		var b := Button.new()
		b.text = PartsCatalog.TABS[t]["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(124, 40)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void: _set_tab(t))
		tabs.add_child(b)
		_tab_buttons.append(b)
	tabs.add_child(_prompt_chip("RB"))
	_count_label = UiKit.label("", 20, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label.custom_minimum_size = Vector2(150, 0)
	top.add_child(_count_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_arrow_button(-1))
	row.add_child(_make_preview())
	row.add_child(_arrow_button(1))
	row.add_child(_make_info())

	var hints := RichTextLabel.new()
	hints.bbcode_enabled = true
	hints.fit_content = true
	hints.scroll_active = false
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_font_size_override("normal_font_size", 18)
	col.add_child(hints)
	_hints = hints


func _make_preview() -> Control:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	# As tall as the longest tab, so the panel keeps its size between tabs.
	frame.custom_minimum_size = Vector2(600, 550)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	mat.albedo_color = Color(0.22, 0.28, 0.4)
	mat.roughness = 0.55
	_platform.material_override = mat
	_platform.position.y = -0.08
	_turntable.add_child(_platform)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 47.0
	_camera.current = true
	_viewport.add_child(_camera)
	return frame


func _make_info() -> Control:
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(390, 0)
	info.add_theme_constant_override("separation", 8)
	_name_label = UiKit.label("", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
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
	var drive := Button.new()
	drive.text = "DRIVE!"
	drive.focus_mode = Control.FOCUS_NONE
	drive.custom_minimum_size = Vector2(0, 52)
	drive.add_theme_font_size_override("font_size", 26)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		drive.add_theme_color_override(c, UiKit.DARK_TEXT)
	drive.add_theme_stylebox_override("normal", UiKit.box(ACCENT, 12, 6))
	drive.add_theme_stylebox_override("hover", UiKit.box(ACCENT.lightened(0.25), 12, 6))
	drive.add_theme_stylebox_override("pressed", UiKit.box(ACCENT.darkened(0.15), 12, 6))
	drive.pressed.connect(_confirm)
	info.add_child(drive)
	return info


func _fill_car_page(page: VBoxContainer) -> void:
	_blurb_label = UiKit.label("", 20, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_label.custom_minimum_size = Vector2(390, 56)
	page.add_child(_blurb_label)
	_weight_label = UiKit.label("", 18, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
	page.add_child(_weight_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	for stat: Array in VehicleCatalog.STATS:
		grid.add_child(UiKit.label(stat[1], 18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT))
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
		var cells: Array[Panel] = []
		for k in 5:
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(30, 16)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_child(cell)
			cells.append(cell)
		grid.add_child(bar)
		_stat_cells.append(cells)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	page.add_child(gap)
	var tip := UiKit.label("Make it yours! Change the paint and the wheels on the next tabs.", 20, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(390, 0)
	page.add_child(tip)


func _prompt_chip(text: String) -> Label:
	var l := UiKit.label(text, 18, UiKit.DARK_TEXT)
	l.remove_theme_constant_override("outline_size")
	var sb := UiKit.box(Color(0.92, 0.93, 0.95), 10, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	l.add_theme_stylebox_override("normal", sb)
	return l


func _arrow_button(dir: int) -> Button:
	var b := ArrowButton.new()
	b.dir = dir
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 0)
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
			b.add_theme_stylebox_override(st, UiKit.box(ACCENT if on else Color(1, 1, 1, 0.1 if st == "normal" else 0.18), 10, 4))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, UiKit.DARK_TEXT if on else Color.WHITE)
	for i in _pages.size():
		_pages[i].visible = i == tab
	var on_car := _rows[tab].is_empty()
	for a in _arrows:
		a.disabled = not on_car
		a.modulate.a = 1.0 if on_car else 0.0
	var hint := (KEY % "Left / Right") + "  vehicle" if on_car else \
		(KEY % "Up / Down") + "  pick      " + (KEY % "Left / Right") + "  change"
	_hints.text = "[center]%s      %s or %s  %s      %s or %s  surprise me!      %s or %s  drive!      %s or %s  back[/center]" % [
		hint, KEY % "Q / E", KEY % "(LB) / (RB)", "customise" if on_car else "tabs",
		KEY % "X", KEY % "(Y)", KEY % "Enter", KEY % "(A)", KEY % "Esc", KEY % "(B)"]
	_refresh_rows()


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
		_set_slot(r.slot, PartsCatalog.index_of(r.slot, loadout().get_value(r.slot)) + dir)


func _on_row_changed(slot: String, option_index: int) -> void:
	var rows: Array = _rows[tab]
	for i in rows.size():
		if (rows[i] as SlotRow).slot == slot:
			_row_focus[tab] = i
	_set_slot(slot, option_index)


## Sets a slot of the shown vehicle's setup and shows it on the turntable.
func _set_slot(slot: String, option_index: int) -> void:
	loadout().set_value(slot, PartsCatalog.value_at(slot, option_index))
	if _car:
		loadout().apply(_car)
	_refresh_rows()


## "Surprise me!": a random vehicle on the CAR tab, otherwise random
## choices for every row on this tab.
func _surprise() -> void:
	var rows: Array = _rows[tab]
	if rows.is_empty():
		_step(randi_range(1, VehicleCatalog.count() - 1))
		return
	var l := loadout()
	for r: SlotRow in rows:
		var n := PartsCatalog.options(r.slot).size()
		l.set_value(r.slot, PartsCatalog.value_at(r.slot, randi_range(0, n - 1)))
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
	_count_label.text = "%d / %d" % [index + 1, VehicleCatalog.count()]
	for s in VehicleCatalog.STATS.size():
		var value: int = e[VehicleCatalog.STATS[s][0]]
		var cells: Array = _stat_cells[s]
		for k in cells.size():
			(cells[k] as Panel).add_theme_stylebox_override("panel",
				UiKit.box(ACCENT if k < value else Color(1, 1, 1, 0.12), 4, 0))
	_refresh_rows()


## Spins the turntable (or turns it to the wheel view) and eases the camera
## to where the tab wants it.
func _update_view(dt: float) -> void:
	if _car == null:
		return
	var look: Vector3
	var pos: Vector3
	var wheel := _view_wheel() if PartsCatalog.TABS[tab]["focus"] == "wheel" else null
	if wheel:
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
		var dist := radius * 3.1 + 2.0
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
		var why := ""
		if _car is Aircraft and r.slot in Loadout.WHEEL_SLOTS:
			why = "Planes keep their own wheels"
		match r.slot:
			"stripes":
				if body == null or not body.has_stripes():
					why = "Not on this vehicle"
			"calipers":
				if why == "" and not PartsCatalog.option("rims", l.get_value("rims")).get("open", false):
					why = "Hidden by these rims"
		r.show_value(l, why)
	# Keep the focus on a row that can be changed.
	if not rows.is_empty() and not (rows[_row_focus[tab]] as SlotRow).enabled:
		for i in rows.size():
			if (rows[i] as SlotRow).enabled:
				_row_focus[tab] = i
				break
	for i in rows.size():
		(rows[i] as SlotRow).set_focused(i == _row_focus[tab])


## A flat button that draws a big triangle (the default font has no arrow glyphs).
class ArrowButton extends Button:
	var dir := 1
	var arrow := 24.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color.WHITE if is_hovered() else UiKit.ACCENT
		var h := arrow
		var pts := PackedVector2Array([
			c + Vector2(-h * 0.5 * dir, -h), c + Vector2(h * 0.58 * dir, 0.0), c + Vector2(-h * 0.5 * dir, h)])
		draw_colored_polygon(pts, col)


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
	## Index of the current value in PartsCatalog.options(slot).
	var _current := 0

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
		var title := UiKit.label(PartsCatalog.slot_name(slot), 18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
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
				_value = UiKit.label("", 20, Color.WHITE)
				_value.custom_minimum_size = Vector2(150, 0)
				line.add_child(_value)
				line.add_child(_small_arrow(1))
			"toggle":
				_toggle = Button.new()
				_toggle.focus_mode = Control.FOCUS_NONE
				_toggle.custom_minimum_size = Vector2(96, 34)
				_toggle.add_theme_font_size_override("font_size", 18)
				_toggle.pressed.connect(func() -> void:
					clicked.emit(self)
					changed.emit(slot, 0 if _toggle.text == "ON" else 1))
				line.add_child(_toggle)
				_value = UiKit.label("", 18, Color(1, 1, 1, 0.6))
				_value.visible = false
				col.add_child(_value)
			"swatch":
				_value = UiKit.label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
				line.add_child(_value)
				line.move_child(_value, 1)
				var grid := GridContainer.new()
				grid.columns = 8
				grid.add_theme_constant_override("h_separation", 8)
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
				var opts := PartsCatalog.options(slot)
				changed.emit(slot, wrapi(_current + dir, 0, opts.size())))
		return b

	## Shows `l`'s value for this slot; a non-empty `why_not` greys the row
	## out (it can't be changed on this vehicle right now) and says why.
	func show_value(l: Loadout, why_not: String) -> void:
		enabled = why_not.is_empty()
		modulate.a = 1.0 if enabled else 0.45
		var v: Variant = l.get_value(slot)
		_current = PartsCatalog.index_of(slot, v)
		var opts := PartsCatalog.options(slot)
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
		var sb := UiKit.box(Color(1, 1, 1, 0.07 if on else 0.0), 12, 8)
		sb.set_border_width_all(3)
		sb.border_color = UiKit.ACCENT if on else Color(0, 0, 0, 0)
		add_theme_stylebox_override("panel", sb)
