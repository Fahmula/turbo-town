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
	for i in 6:
		_bind("teleport_%d" % (i + 1), [KEY_1 + i], [], [])
	_bind("change_vehicle", [KEY_V], [JOY_BUTTON_DPAD_DOWN], [])

	# Menus (the garage). Sticks need a firm push so they don't drift.
	_bind("menu_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], 0.5)
	_bind("menu_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], 0.5)
	_bind("menu_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]], 0.5)
	_bind("menu_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]], 0.5)
	_bind("menu_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A], [])
	_bind("menu_back", [KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B], [])


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
