class_name VehiclePicker
extends CanvasLayer
## Garage menu: browse the drivable vehicles on a spinning turntable, pick a
## paint colour and drive off. Works with keyboard, gamepad and mouse.
## Game pauses the world while it's open and does the actual vehicle swap.

signal picked(index: int, color: Color)
signal cancelled

const ACCENT := Color(1.0, 0.84, 0.29)
const HINT_TEXT := "[center][color=#ffd54a]Left / Right[/color]  vehicle      [color=#ffd54a]Up / Down[/color]  paint      [color=#ffd54a]Enter[/color] or [color=#ffd54a](A)[/color]  drive!      [color=#ffd54a]Esc[/color] or [color=#ffd54a](B)[/color]  back[/center]"

var is_open := false
var index := 0
var color_index := 0

var _opened_frame := -1
var _viewport: SubViewport
var _turntable: Node3D
var _platform: MeshInstance3D
var _camera: Camera3D
var _car: Vehicle
var _name_label: Label
var _count_label: Label
var _blurb_label: Label
var _weight_label: Label
## Per stat: the five bar segments.
var _stat_cells: Array[Array] = []
var _swatches: Array[Panel] = []


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
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.08, 0.15, 0.88), 18, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	var title := _label("GARAGE", 28, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_count_label = _label("", 20, Color(1, 1, 1, 0.7))
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
	hints.add_theme_font_size_override("normal_font_size", 17)
	hints.text = HINT_TEXT
	col.add_child(hints)


func _make_preview() -> Control:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(600, 370)
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
	_camera.fov = 30.0
	_camera.current = true
	_viewport.add_child(_camera)
	return frame


func _make_info() -> Control:
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(350, 0)
	info.add_theme_constant_override("separation", 8)
	_name_label = _label("", 40, Color.WHITE)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(_name_label)
	_blurb_label = _label("", 19, Color(1, 1, 1, 0.9))
	_blurb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_label.custom_minimum_size = Vector2(350, 52)
	info.add_child(_blurb_label)
	_weight_label = _label("", 17, Color(1, 1, 1, 0.65))
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(_weight_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	info.add_child(grid)
	for stat: Array in VehicleCatalog.STATS:
		var l := _label(stat[1], 16, Color(1, 1, 1, 0.85))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(l)
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

	var paint := _label("PAINT", 16, Color(1, 1, 1, 0.85))
	paint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(paint)
	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 5
	swatch_grid.add_theme_constant_override("h_separation", 10)
	swatch_grid.add_theme_constant_override("v_separation", 10)
	info.add_child(swatch_grid)
	for i in VehicleCatalog.COLORS.size():
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(40, 40)
		sw.mouse_filter = Control.MOUSE_FILTER_STOP
		sw.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_set_color(i))
		swatch_grid.add_child(sw)
		_swatches.append(sw)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	var drive := Button.new()
	drive.text = "DRIVE!"
	drive.focus_mode = Control.FOCUS_NONE
	drive.custom_minimum_size = Vector2(0, 52)
	drive.add_theme_font_size_override("font_size", 26)
	drive.add_theme_color_override("font_color", Color(0.08, 0.1, 0.18))
	drive.add_theme_color_override("font_hover_color", Color(0.08, 0.1, 0.18))
	drive.add_theme_color_override("font_pressed_color", Color(0.08, 0.1, 0.18))
	drive.add_theme_stylebox_override("normal", _box(ACCENT, 12, 6))
	drive.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.25), 12, 6))
	drive.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.15), 12, 6))
	drive.pressed.connect(_confirm)
	info.add_child(drive)
	return info


func _arrow_button(dir: int) -> Button:
	var b := ArrowButton.new()
	b.dir = dir
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 0)
	var flat := _box(Color(1, 1, 1, 0.0), 10, 0)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.08), 10, 0))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.16), 10, 0))
	b.pressed.connect(func() -> void: _step(dir))
	return b


func open(current: int, paint: Color) -> void:
	index = clampi(current, 0, VehicleCatalog.count() - 1)
	color_index = VehicleCatalog.closest_color(paint)
	is_open = true
	visible = true
	# Ignore the key press that opened the garage.
	_opened_frame = Engine.get_process_frames()
	_turntable.rotation.y = 2.4
	_show_vehicle()


func close() -> void:
	is_open = false
	visible = false
	if _car:
		_turntable.remove_child(_car)
		_car.queue_free()
		_car = null


func _process(dt: float) -> void:
	if not is_open:
		return
	_turntable.rotation.y += dt * 0.5
	if Engine.get_process_frames() == _opened_frame:
		return
	if Input.is_action_just_pressed("menu_left"):
		_step(-1)
	elif Input.is_action_just_pressed("menu_right"):
		_step(1)
	elif Input.is_action_just_pressed("menu_up"):
		_set_color(color_index - 1)
	elif Input.is_action_just_pressed("menu_down"):
		_set_color(color_index + 1)
	elif Input.is_action_just_pressed("menu_accept"):
		_confirm()
	elif Input.is_action_just_pressed("menu_back") or Input.is_action_just_pressed("pause"):
		close()
		cancelled.emit()


func _step(dir: int) -> void:
	index = wrapi(index + dir, 0, VehicleCatalog.count())
	_show_vehicle()


func _set_color(i: int) -> void:
	color_index = wrapi(i, 0, VehicleCatalog.COLORS.size())
	if _car:
		var body := _car.get_node_or_null("Body") as VehicleBodyVisual
		if body:
			body.set_paint_color(VehicleCatalog.COLORS[color_index])
	_refresh_swatches()


func _confirm() -> void:
	var i := index
	var c := VehicleCatalog.COLORS[color_index]
	close()
	picked.emit(i, c)


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
	var body := car.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.paint_color = VehicleCatalog.COLORS[color_index]
	for child in car.get_children():
		if child is VehicleWheel:
			(child as VehicleWheel).pose_at_rest(car.mass / 4.0)
	car.position.y = car.ride_height()
	_turntable.add_child(car)
	_car = car

	# Frame it so the whole vehicle stays in view while it spins.
	var half_len := maxf(car.body_front, car.body_rear)
	var radius := sqrt(half_len * half_len + car.body_half_width * car.body_half_width)
	_platform.scale = Vector3(radius + 0.5, 1.0, radius + 0.5)
	var dist := radius * 3.1 + 2.0
	var look := Vector3(0.0, (car.ride_height() + car.body_top) * 0.4, 0.0)
	_camera.position = look + Vector3(0.0, dist * 0.3, dist)
	_camera.look_at(look)

	var e: Dictionary = VehicleCatalog.ENTRIES[index]
	_name_label.text = String(e["name"]).to_upper()
	_blurb_label.text = e["blurb"]
	_weight_label.text = "Weight: %.1f tonnes" % (car.mass / 1000.0)
	_count_label.text = "%d / %d" % [index + 1, VehicleCatalog.count()]
	for s in VehicleCatalog.STATS.size():
		var value: int = e[VehicleCatalog.STATS[s][0]]
		var cells: Array = _stat_cells[s]
		for k in cells.size():
			var on := k < value
			(cells[k] as Panel).add_theme_stylebox_override("panel",
				_box(ACCENT if on else Color(1, 1, 1, 0.12), 4, 0))
	_refresh_swatches()


func _refresh_swatches() -> void:
	for i in _swatches.size():
		var sb := _box(VehicleCatalog.COLORS[i], 20, 0)
		var selected := i == color_index
		sb.set_border_width_all(4 if selected else 2)
		sb.border_color = Color.WHITE if selected else Color(1, 1, 1, 0.25)
		_swatches[i].add_theme_stylebox_override("panel", sb)
		_swatches[i].scale = Vector2.ONE * (1.12 if selected else 1.0)
		_swatches[i].pivot_offset = _swatches[i].custom_minimum_size * 0.5


func _box(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.2))
	l.add_theme_constant_override("outline_size", maxi(font_size / 6, 3))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A flat button that draws a big triangle (the default font has no arrow glyphs).
class ArrowButton extends Button:
	var dir := 1

	func _draw() -> void:
		var c := size * 0.5
		var col := Color.WHITE if is_hovered() else Color(1.0, 0.84, 0.29)
		var pts := PackedVector2Array([
			c + Vector2(-12.0 * dir, -24.0), c + Vector2(14.0 * dir, 0.0), c + Vector2(-12.0 * dir, 24.0)])
		draw_colored_polygon(pts, col)
