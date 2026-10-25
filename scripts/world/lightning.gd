class_name Lightning
extends Node3D
## Lightning in a thunderstorm (Weather turns it on): every so often a bolt
## 0.4-1 km from player 1's camera, somewhere in front of it, drawn for a
## moment as a jagged glowing ribbon, with the clouds round its top lit up
## (a big soft glow) and the ambient light lifted a little. Never a
## full-screen flash (ART_BIBLE.md §23, photosensitivity): one bolt with at
## most one flicker. `struck` fires as it strikes; thunder follows it at the
## speed of sound.

signal struck(distance: float)

## Seconds between bolts (min, max).
const GAP := [7.0, 18.0]
## How high the bolt starts (m, the cloud base).
const CLOUD_BASE := 420.0
## On/off times (s from the strike) and the light's fade-out time.
const PULSES := [[0.0, 0.07], [0.13, 0.26]]
const FADE := 0.3

## Brighter than white, so the bolt blooms (glow on Medium and up).
const BOLT_SHADER := preload("res://assets/shaders/lightning.gdshader")

var active := false
var day_night: DayNight

var _wait := 4.0
var _t := -1.0
var _bolt: MeshInstance3D
var _glow: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = BOLT_SHADER
	_bolt = MeshInstance3D.new()
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_mat.disable_fog = true
	_glow_mat.albedo_texture = _glow_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(900.0, 600.0)
	quad.material = _glow_mat
	_glow = MeshInstance3D.new()
	_glow.mesh = quad
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	add_child(_glow)


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	if _t >= 0.0:
		_t += dt
		var on := 0.0
		for p: Array in PULSES:
			if _t >= p[0] and _t < p[1]:
				on = 1.0
		var light := on
		var last: Array = PULSES[PULSES.size() - 1]
		if _t >= last[1]:
			light = 1.0 - clampf((_t - last[1]) / FADE, 0.0, 1.0)
		_bolt.visible = on > 0.0
		_glow.visible = light > 0.0
		_glow_mat.albedo_color = Color(0.75, 0.8, 1.0, 0.55 * light)
		if day_night:
			day_night.set_flash(light)
		if light <= 0.0 and _t > last[1]:
			_t = -1.0
		return
	if not active:
		_wait = maxf(_wait, 3.0)
		return
	_wait -= dt
	if _wait <= 0.0:
		_wait = _rng.randf_range(GAP[0], GAP[1])
		_strike()


func _strike() -> void:
	var cam := Views.camera(self, 0)
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	var yaw := atan2(fwd.x, fwd.z) + _rng.randf_range(-1.0, 1.0)
	var dist := _rng.randf_range(400.0, 1000.0)
	var base := cam.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * dist
	base.y = 0.0
	# The ribbon faces the camera (it's only up for a fraction of a second).
	var to_cam := cam.global_position - base
	to_cam.y = 0.0
	var side := Vector3.UP.cross(to_cam.normalized())
	_bolt.mesh = _bolt_mesh(side, dist)
	_bolt.global_position = base
	_glow.global_position = base + Vector3.UP * CLOUD_BASE
	_t = 0.0
	struck.emit(cam.global_position.distance_to(base + Vector3.UP * CLOUD_BASE * 0.5))


## A jagged channel from the cloud base to the ground, with a couple of
## branches; ribbons in the plane across the view, `side` being sideways.
func _bolt_mesh(side: Vector3, dist: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# About two pixels wide at this distance, with a wide faint halo.
	var width := dist * 0.0035
	var main := _channel(Vector3(0.0, CLOUD_BASE, 0.0), 0.0, 26, CLOUD_BASE / 26.0, side)
	_ribbon(st, main, side, width, Color(0.95, 0.95, 1.0))
	_ribbon(st, main, side, width * 6.0, Color(0.35, 0.4, 0.75, 0.35))
	for b in _rng.randi_range(1, 3):
		var from: Vector3 = main[_rng.randi_range(3, 14)]
		var branch := _channel(from, from.y * _rng.randf_range(0.35, 0.7), 10, from.y * 0.04, side)
		_ribbon(st, branch, side, width * 0.6, Color(0.85, 0.87, 1.0, 0.8))
	return st.commit()


## Points down from `top` to height `bottom`, wandering sideways.
func _channel(top: Vector3, bottom: float, steps: int, jitter: float, side: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = [top]
	var drift := _rng.randf_range(-0.4, 0.4)
	var p := top
	for i in steps:
		var dy := (top.y - bottom) / steps
		p += Vector3.DOWN * dy + side * (drift + _rng.randf_range(-1.0, 1.0)) * jitter
		pts.append(p)
	return pts


func _ribbon(st: SurfaceTool, pts: Array[Vector3], side: Vector3, width: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ha := side * width * 0.5
		st.set_color(col)
		st.add_vertex(a - ha)
		st.add_vertex(a + ha)
		st.add_vertex(b + ha)
		st.add_vertex(a - ha)
		st.add_vertex(b + ha)
		st.add_vertex(b - ha)
	st.set_material(_bolt_mat)


## A soft round glow (white in the middle, fading out).
func _glow_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex
