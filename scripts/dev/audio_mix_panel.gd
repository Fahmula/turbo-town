extends CanvasLayer
## Developer audio mix panel (autoload "AudioMixPanel"): tune the AudioMix
## buses live while driving, then save. Not part of the player UI.
##
## Open / close: F8, or hold both sticks in (L3 + R3) for a second (hard to do
## by accident; the horn sounds meanwhile). On the Steam Deck use the
## touchscreen: the panel never takes gamepad focus, so the controls keep
## driving the car.
## Save: user://audio_mix.cfg (only what differs from the defaults; loaded on
## every normal start). "Save as game defaults" writes
## res://assets/audio/mix.cfg (running from the project folder only); to make
## Deck-tuned values the defaults, copy the Deck's audio_mix.cfg over (path
## shown after saving) or send it over.
##
## Remove for a release: set turbo_town/dev/audio_mix_panel=false in
## project.godot (or delete the autoload and this file; nothing else uses it).

const SETTING := "turbo_town/dev/audio_mix_panel"
const HOLD_TIME := 1.0
const WIDTH := 480.0
## Meter rows: bus, fader key.
const FADERS := [
	["Master", "master.gain_db"], ["Player", "player.volume_db"], ["Engine", "engine.volume_db"],
	["Tyres", "tyres.volume_db"], ["Surface", "surface.volume_db"], ["Skid", "skid.volume_db"],
	["Impacts", "impacts.volume_db"], ["Environment", "environment.volume_db"], ["Signals", "signals.volume_db"],
	["Traffic", "traffic.volume_db"], ["TrafficEngine", "traffic_engine.volume_db"], ["UI", "ui.volume_db"],
]
## Buses that solo / mute between each other (the leaves of the mix).
const LEAVES: Array[String] = ["Engine", "Tyres", "Surface", "Skid", "Impacts", "Environment", "Signals", "Traffic", "TrafficEngine", "UI"]

var _root: PanelContainer
var _status: Label
var _profile_label: Label
var _clip_label: Label
var _rows := {}  # key -> {slider, value_label}
var _meters := {}  # bus -> {bar, text, hold, hold_t}
var _solo := {}  # bus -> bool
var _mute := {}  # bus -> bool
var _hold_t := 0.0
var _hold_fired := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _clips := 0
var _master_max := -80.0
var _syncing := false


func _ready() -> void:
	if not ProjectSettings.get_setting(SETTING, false) or DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func toggle() -> void:
	if _root == null:
		return
	_root.visible = not _root.visible
	if _root.visible:
		AudioMix.ensure()
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sync()
	elif not get_tree().paused:
		Input.mouse_mode = _prev_mouse


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F8:
		toggle()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	# Hold both sticks in to open / close.
	var held := false
	for pad in Input.get_connected_joypads():
		held = held or (Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_STICK) and Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_STICK))
	_hold_t = _hold_t + dt if held else 0.0
	if not held:
		_hold_fired = false
	elif _hold_t >= HOLD_TIME and not _hold_fired:
		_hold_fired = true
		toggle()
	if not is_open():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # the game captures it on clicks
	_update_meters(dt)


# ---------------------------------------------------------------- meters --

func _update_meters(dt: float) -> void:
	for bus: String in _meters:
		var idx := AudioServer.get_bus_index(StringName(bus))
		if idx < 0:
			continue
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
		var m: Dictionary = _meters[bus]
		var bar: ProgressBar = m.bar
		bar.value = maxf(db, bar.value - dt * 30.0)  # falls 30 dB/s
		if db > m.hold or m.hold_t <= 0.0:
			m.hold = db
			m.hold_t = 1.5
		m.hold_t -= dt
		(m.text as Label).text = "%5.1f" % maxf(m.hold, -80.0)
		bar.modulate = Color(1.0, 0.35, 0.3) if m.hold > -1.5 else (Color(1.0, 0.85, 0.3) if m.hold > -6.0 else Color.WHITE)
		if bus == "Master":
			_master_max = maxf(_master_max, db)
			if db > -1.05:
				_clips += 1
			_clip_label.text = "master max %.1f dBFS, %d frames at the limiter" % [_master_max, _clips]


# ------------------------------------------------------------------- build --

func _build() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -WIDTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	_root.add_theme_stylebox_override("panel", bg)
	add_child(_root)
	var outer := VBoxContainer.new()
	_root.add_child(outer)

	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := _label("Audio mix (dev)  F8 / hold L3+R3", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("X", toggle))

	var prof := HBoxContainer.new()
	outer.add_child(prof)
	_profile_label = _label("", 15)
	_profile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof.add_child(_profile_label)
	for p in AudioMix.PROFILES:
		prof.add_child(_button(p.capitalize(), func() -> void:
			AudioMix.set_profile(p)
			_sync()))

	var actions := HBoxContainer.new()
	outer.add_child(actions)
	actions.add_child(_button("Save", _save))
	var defaults := _button("Save as game defaults", _save_defaults)
	defaults.disabled = not AudioMix.can_save_defaults()
	actions.add_child(defaults)
	actions.add_child(_button("Reset profile", func() -> void:
		AudioMix.reset_profile()
		_sync()
		_status.text = "%s profile back to the defaults (not saved yet)" % AudioMix.profile()))
	_status = _label("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	_clip_label = _label("", 13)
	outer.add_child(_clip_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_label("Faders and meters (peak dBFS, post-fader)", 15))
	var fader_keys := {}
	for f: Array in FADERS:
		fader_keys[f[1]] = true
		list.add_child(_meter_row(f[0]))
		list.add_child(_param_row(_spec(f[1])))
	# Processing, one fold per group.
	var groups := {}
	var order: Array[String] = []
	for spec: Array in AudioMix.SPECS:
		if fader_keys.has(spec[0]):
			continue
		var g: String = (spec[0] as String).get_slice(".", 0)
		if not groups.has(g):
			groups[g] = []
			order.append(g)
		groups[g].append(spec)
	for g in order:
		var box := VBoxContainer.new()
		box.visible = false
		var fold := _button("+ %s processing" % g.capitalize().replace("_", " "), func() -> void:
			box.visible = not box.visible)
		fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(fold)
		list.add_child(box)
		for spec: Array in groups[g]:
			box.add_child(_param_row(spec))


func _spec(key: String) -> Array:
	for spec: Array in AudioMix.SPECS:
		if spec[0] == key:
			return spec
	return [key, key, -24.0, 12.0, 0.5]


func _meter_row(bus: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := _label(bus, 14)
	name_label.custom_minimum_size = Vector2(108, 0)
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.min_value = -60.0
	bar.max_value = 0.0
	bar.value = -60.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var text := _label("", 13)
	text.custom_minimum_size = Vector2(44, 0)
	row.add_child(text)
	_meters[bus] = {"bar": bar, "text": text, "hold": -80.0, "hold_t": 0.0}
	if bus in LEAVES:
		var mute := _toggle("M", func(on: bool) -> void:
			_mute[bus] = on
			_apply_solo_mute())
		var solo := _toggle("S", func(on: bool) -> void:
			_solo[bus] = on
			_apply_solo_mute())
		row.add_child(mute)
		row.add_child(solo)
	return row


func _param_row(spec: Array) -> Control:
	var key: String = spec[0]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := _label(spec[1], 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	var value_label := _label("", 13)
	value_label.custom_minimum_size = Vector2(76, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(value_label)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var slider := HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(0, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = _format(key, v)
		if not _syncing:
			AudioMix.set_value(key, v)
			_status.text = "changed (not saved yet)")
	bottom.add_child(slider)
	bottom.add_child(_button("default", func() -> void:
		slider.value = AudioMix.default_value(key)))
	_rows[key] = {"slider": slider, "value_label": value_label}
	return box


func _format(key: String, v: float) -> String:
	if key.ends_with("_on"):
		return "on" if v > 0.5 else "off"
	if key.ends_with("_hz"):
		return "%d Hz" % roundi(v)
	if key.ends_with("ratio"):
		return "%.1f:1" % v
	if key.ends_with("shape"):
		return "%.2f" % v
	return "%+.1f dB" % v


func _sync() -> void:
	_syncing = true
	for key: String in _rows:
		var slider: HSlider = _rows[key].slider
		slider.value = AudioMix.value(key)
		(_rows[key].value_label as Label).text = _format(key, slider.value)
	_syncing = false
	_profile_label.text = "Profile: %s%s" % [AudioMix.profile(), "  (Steam Deck)" if AudioMix.is_steam_deck() else ""]
	_apply_solo_mute()


func _apply_solo_mute() -> void:
	var any_solo := _solo.values().has(true)
	for bus in LEAVES:
		var idx := AudioServer.get_bus_index(StringName(bus))
		if idx >= 0:
			var off: bool = _mute.get(bus, false) or (any_solo and not _solo.get(bus, false))
			AudioServer.set_bus_mute(idx, off)


func _save() -> void:
	var err := AudioMix.save_user()
	_status.text = "Saved to %s" % AudioMix.user_file_path() if err == OK else "Save failed (%s)" % error_string(err)


func _save_defaults() -> void:
	var err := AudioMix.save_defaults()
	_status.text = "Wrote %s (commit it)" % AudioMix.DEFAULTS_PATH if err == OK else "Save failed (%s)" % error_string(err)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(on_press)
	return b


func _toggle(text: String, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 26)
	b.add_theme_font_size_override("font_size", 13)
	b.toggled.connect(on_toggle)
	return b
