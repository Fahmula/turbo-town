class_name PlayerInput
extends RefCounted
## One player's controls: which devices are theirs and reading the actions
## from those devices only. With one player it reads the normal actions
## ("accelerate"...) from every device, as before split-screen existed. In
## split-screen each player has their own copy of the gameplay actions
## (InputSetup.make_player_actions: "p1_accelerate", "p2_accelerate"...)
## bound to just their gamepad (and the keyboard and mouse for one of them),
## so two players can share the same buttons without driving each other's
## cars.

## Action prefix: "" = the shared actions (one player), "p1_" / "p2_" in
## split-screen.
var prefix := ""
## The keyboard and mouse belong to this player.
var keyboard := true
## This player's gamepads (device ids). Only used in split-screen; with one
## player every gamepad is theirs.
var pads: Array[int] = []
## Last input came from a gamepad (prompts show its buttons).
var using_pad := false
## The gamepad this player used last (rumble goes there), -1 = none yet.
var last_pad := -1

var _names := {}


## A player using the shared actions (one player on this machine).
static func shared() -> PlayerInput:
	return PlayerInput.new()


## A split-screen player: actions `prefix`*, `pad` (-1 = none), keyboard or not.
static func for_player(action_prefix: String, pad: int, with_keyboard: bool) -> PlayerInput:
	var p := PlayerInput.new()
	p.prefix = action_prefix
	p.keyboard = with_keyboard
	if pad >= 0:
		p.pads.append(pad)
		p.last_pad = pad
		p.using_pad = true
	return p


func is_split() -> bool:
	return prefix != ""


## The name of `action` for this player.
func act(action: StringName) -> StringName:
	if prefix == "":
		return action
	var n: Variant = _names.get(action)
	if n == null:
		n = StringName(prefix + action)
		_names[action] = n
	return n


func strength(action: StringName) -> float:
	return Input.get_action_strength(act(action))


func pressed(action: StringName) -> bool:
	return Input.is_action_pressed(act(action))


func axis(negative: StringName, positive: StringName) -> float:
	return Input.get_axis(act(negative), act(positive))


func vector(neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName) -> Vector2:
	return Input.get_vector(act(neg_x), act(pos_x), act(neg_y), act(pos_y))


## True if `event` presses this player's `action`.
func event_pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(act(action))


## True if `event` comes from one of this player's devices.
func owns(event: InputEvent) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return prefix == "" or pads.has(event.device)
	if event is InputEventKey or event is InputEventMouse:
		return keyboard
	return true


## Keeps track of the device in use (call with this player's events).
func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		using_pad = true
		last_pad = event.device
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


## Vibrates this player's gamepad (with one player: every connected one).
func rumble(weak: float, strong: float, duration: float) -> void:
	var w := clampf(weak, 0.0, 1.0)
	var s := clampf(strong, 0.0, 1.0)
	if prefix == "":
		for pad in Input.get_connected_joypads():
			Input.start_joy_vibration(pad, w, s, duration)
	else:
		for pad in pads:
			Input.start_joy_vibration(pad, w, s, duration)
