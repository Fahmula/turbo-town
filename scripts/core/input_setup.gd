extends Node
## Registers the default input bindings (keyboard + gamepad) at startup.
##
## Actions that already exist in Project Settings > Input Map are left alone,
## so any binding can be overridden there without touching this file.
## To add a new control, add one line to _enter_tree().

const DEADZONE := 0.15


func _enter_tree() -> void:
	# Driving
	_bind("accelerate", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_A], [])
	_bind("horn", [KEY_E], [JOY_BUTTON_LEFT_STICK], [])
	_bind("toggle_traction_control", [KEY_T], [], [])

	# On foot (the same keys and sticks as driving: only one is in use at a time)
	_bind("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("sprint", [KEY_SHIFT], [], [])
	_bind("sprint_toggle", [], [JOY_BUTTON_LEFT_STICK], [])  # click: sprint until you stop
	_bind("walk", [KEY_CTRL], [], [])
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_A], [])
	# Flying (planes): the stick is the nose and the bank, the triggers power.
	# Pull back (S, stick down) = nose up; Settings > Flying controls swaps it.
	_bind("fly_nose_up", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("fly_nose_down", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("fly_bank_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("fly_bank_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("fly_power", [KEY_SHIFT], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("fly_slow", [KEY_CTRL], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("fly_trick", [KEY_SPACE], [JOY_BUTTON_A], [])  # + stick: roll all the way round

	# Get in / out of a vehicle, use things.
	_bind("interact", [KEY_F], [JOY_BUTTON_B], [])

	# Vehicle recovery
	_bind("reset_vehicle", [KEY_R], [JOY_BUTTON_Y], [])
	_bind("respawn", [KEY_BACKSPACE], [JOY_BUTTON_BACK], [])

	# Camera
	_bind("camera_cycle", [KEY_C], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("look_back", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
	_bind("camera_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("camera_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("camera_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("camera_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])

	# Game
	_bind("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_bind("toggle_help", [KEY_F1, KEY_H], [], [])
	_bind("toggle_units", [KEY_U], [], [])
	_bind("toggle_traffic", [KEY_G], [JOY_BUTTON_DPAD_UP], [])
	_bind("teleport_next", [KEY_TAB], [JOY_BUTTON_DPAD_RIGHT], [])
	for i in 9:
		_bind("teleport_%d" % (i + 1), [KEY_1 + i], [], [])
	_bind("change_vehicle", [KEY_V], [JOY_BUTTON_DPAD_DOWN], [])
	_bind("toggle_map", [KEY_M], [JOY_BUTTON_DPAD_LEFT], [])
	_bind("instant_replay", [KEY_P], [JOY_BUTTON_X], [])

	# Menus (the garage). Sticks need a firm push so they don't drift.
	_bind("menu_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], 0.5)
	_bind("menu_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], 0.5)
	_bind("menu_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]], 0.5)
	_bind("menu_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]], 0.5)
	_bind("menu_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A], [])
	_bind("menu_back", [KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B], [])
	_bind("menu_extra", [KEY_X], [JOY_BUTTON_Y], [])  # garage: surprise me (random setup)
	_bind("menu_tab_prev", [KEY_Q, KEY_PAGEUP], [JOY_BUTTON_LEFT_SHOULDER], [])  # garage tabs
	_bind("menu_tab_next", [KEY_E, KEY_PAGEDOWN], [JOY_BUTTON_RIGHT_SHOULDER], [])

	# Menu buttons use Godot's built-in ui_* actions. Up/down/left/right come
	# with the D-pad and stick, but accept and cancel are keyboard-only, so
	# add A / B or a gamepad can move between buttons but not press them.
	_add_button("ui_accept", JOY_BUTTON_A)
	_add_button("ui_cancel", JOY_BUTTON_B)


## Adds a gamepad button (any controller, like Godot's own ui_* bindings) to
## an existing action, unless it already has it.
func _add_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventJoypadButton.new()
	ev.device = -1  # all devices
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _bind(action: StringName, keys: Array, buttons: Array, axes: Array, deadzone := DEADZONE) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for key: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button: JoyButton in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
	for axis_def: Array in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis_def[0]
		ev.axis_value = axis_def[1]
		InputMap.action_add_event(action, ev)
