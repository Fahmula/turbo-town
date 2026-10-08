class_name PlayerCharacterController
extends Node
## Feeds player input into the PlayerCharacter, relative to the camera: up on
## the stick (or W) walks away from the camera. A gentle push on the stick
## walks, a full push runs; Shift (held) or a click of the left stick sprints
## (the click lasts until you stop); Ctrl walks on the keyboard.
##
## The Possession gives it a character only while the player is on foot
## (control(null) otherwise), so it never moves the character while driving.

## Off while menus are open: the character just stands there.
var enabled := true
var character: PlayerCharacter
## Movement is relative to this camera's heading.
var camera: Camera3D
## Whose controls move it (split-screen: one player's devices).
var input := PlayerInput.shared()

var _sprint_latched := false


func _ready() -> void:
	# Run before the character so it sees this tick's input.
	process_physics_priority = -10


## Takes control of `pawn` (a PlayerCharacter), or lets go with null.
func control(pawn: Node3D) -> void:
	if character and character != pawn:
		_clear(character)
	character = pawn as PlayerCharacter
	_sprint_latched = false


func _clear(c: PlayerCharacter) -> void:
	c.move_input = Vector3.ZERO
	c.walk_input = false
	c.sprint_input = false
	c.jump_input = false


func _physics_process(_dt: float) -> void:
	if character == null:
		return
	if not enabled:
		_clear(character)
		_sprint_latched = false
		return
	var stick := input.vector("move_left", "move_right", "move_forward", "move_back")
	var yaw := 0.0
	if camera:
		var f := -camera.global_basis.z
		yaw = atan2(-f.x, -f.z)
	var dir := Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, yaw)
	character.move_input = dir.limit_length(1.0)
	if stick.length() < 0.2:
		_sprint_latched = false
	character.sprint_input = input.pressed("sprint") or _sprint_latched
	character.walk_input = input.pressed("walk")


func _unhandled_input(event: InputEvent) -> void:
	if character == null or not enabled:
		return
	if input.event_pressed(event, "jump"):
		character.jump_input = true
	elif input.event_pressed(event, "sprint_toggle"):
		_sprint_latched = not _sprint_latched
