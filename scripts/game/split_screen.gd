class_name SplitScreen
extends CanvasLayer
## Two players on one screen: player 1's view on top, player 2's below, each
## a SubViewport looking into the same world with its own camera and HUD
## (LocalPlayer.enter_view moves them in). The main viewport stops drawing
## the world while this is up (Game._start_split), so the world is drawn
## twice per frame, not three times; menus still cover the whole screen.
##
## Views don't take input themselves: the cameras get their mouse look and
## buttons from their LocalPlayer, so a mouse over the lower half can't steer
## player 2's camera.

## Gap between the two views (px), in the panel colour.
const GAP := 4

var views: Array[SubViewport] = []


func _init() -> void:
	name = "SplitScreen"
	layer = -1


## Builds `count` views stacked top to bottom.
func build(count: int) -> void:
	var bg := ColorRect.new()
	bg.color = Color(UiKit.PANEL_BG, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for i in count:
		var holder := ViewHolder.new()
		holder.name = "Holder%d" % (i + 1)
		holder.stretch = true
		holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var vp := SubViewport.new()
		vp.name = "View%d" % (i + 1)
		# Each view hears the world from its own camera.
		vp.audio_listener_enable_3d = true
		vp.gui_disable_input = true
		holder.add_child(vp)
		views.append(vp)


## The graphics preset's per-view settings (anti-aliasing, render scale).
func apply_graphics(level: int) -> void:
	for v in views:
		GraphicsQuality.apply_view(level, v)


## A view's frame on screen. Passes no input on: see the class comment.
class ViewHolder extends SubViewportContainer:
	func _propagate_input_event(_event: InputEvent) -> bool:
		return false
