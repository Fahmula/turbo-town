class_name BoatEffects
extends Node
## Wake, spray and splashes for a Boat. A child named "Effects" of the boat;
## what it makes lives in world space.
##
## * Wake: a ribbon on the sea behind the transom (one draw call, rebuilt
##   each frame from up to MAX_POINTS points laid every STEP metres). Each
##   point remembers when and how fast the boat passed; the ribbon widens
##   there with age (the V of a real wake) and fades over WAKE_LIFE seconds
##   (boat_wake.gdshader draws the foam). The ribbon breaks where the stern
##   left the water (a jump).
## * Bow spray: white mist thrown out to both sides once it's going fast.
## * Prop wash: foam boiling up behind the motor under throttle, and a
##   rooster tail of spray thrown up behind it flat out.
## * Splash: a burst of spray when it lands from a jump, or hits the water
##   hard nose first.
## The particles only run near a camera (ART_BIBLE.md §23: emitters stop
## beyond ~80 m, at most 40 each); Low graphics uses half as many.

const WAKE_SHADER := preload("res://assets/shaders/vehicle/boat_wake.gdshader")
const FOAM := preload("res://assets/textures/terrain/sea_foam.png")
const WAKE_LIFE := 7.0
const STEP := 1.3
const MAX_POINTS := 90
## Particles run only this close to a camera (m).
const RANGE := 90.0

var _boat: Boat
var _root: Node3D
var _wake: MeshInstance3D
var _mesh: ImmediateMesh
## Wake points: [position, right (unit), time laid, speed 0..1, starts a new piece].
var _points: Array = []
var _time := 0.0
var _last_stamp := Vector3.INF
var _was_wet := false
var _spray: Array[GPUParticles3D] = []
var _wash: GPUParticles3D
var _rooster: GPUParticles3D
var _splash: GPUParticles3D
var _low := false


func _ready() -> void:
	_boat = get_parent() as Boat
	if _boat == null:
		set_physics_process(false)
		set_process(false)
		return
	_low = GraphicsQuality.current <= GraphicsQuality.LOW
	_root = Node3D.new()
	_root.name = "BoatFX"
	_root.top_level = true
	_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_root)
	_make_wake()
	var drops := _mist_material(0.55, 0.9)
	var foam := _mist_material(0.75, 0.7)
	for side: float in [-1.0, 1.0]:
		_spray.append(_make_spray(drops, side))
	_wash = _make_wash(foam)
	_rooster = _make_rooster(drops)
	_splash = _make_splash(drops)
	for gi in _root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = Vehicle.VISUAL_LAYER
	_boat.landed.connect(_on_landed)
	_boat.vehicle_reset.connect(func() -> void:
		_points.clear()
		_last_stamp = Vector3.INF)


func _make_wake() -> void:
	_mesh = ImmediateMesh.new()
	_wake = MeshInstance3D.new()
	_wake.name = "Wake"
	_wake.mesh = _mesh
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake.visibility_range_end = 260.0
	var m := ShaderMaterial.new()
	m.shader = WAKE_SHADER
	m.render_priority = 1
	m.set_shader_parameter("foam_tex", FOAM)
	_wake.material_override = m
	_root.add_child(_wake)


## Soft white blobs: `core` = how much of the radius is solid (droplets
## harder, foam softer), `alpha` their opacity.
func _mist_material(core: float, alpha: float) -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(core * 0.6, Color(1, 1, 1, 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Lit per vertex: grey under clouds, dark at night.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = Color(0.97, 0.98, 0.99, alpha)
	m.render_priority = 2
	return m


func _particles(mat: StandardMaterial3D, size: float, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	p.amount = maxi(amount / (2 if _low else 1), 4)
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-25, -6, -25), Vector3(50, 20, 50))
	_root.add_child(p)
	return p


## Spray peeling off one side of the hull where it meets the water: thrown
## out, up and back, falling straight back in.
func _make_spray(mat: StandardMaterial3D, side: float) -> GPUParticles3D:
	var p := _particles(mat, 0.3, 40, 0.45)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(side * 0.8, 1.0, 0.35)
	pm.spread = 18.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.8
	pm.inherit_velocity_ratio = 0.8
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.04, 0.04, 0.8)
	return p


## Foam boiling up behind the motor.
func _make_wash(mat: StandardMaterial3D) -> GPUParticles3D:
	var p := _particles(mat, 0.65, 30, 0.8)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 0.6, 1.0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	return p


## The rooster tail: a plume of spray thrown up and back behind the motor.
func _make_rooster(mat: StandardMaterial3D) -> GPUParticles3D:
	var p := _particles(mat, 0.36, 40, 0.75)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 1.0, 0.9)
	pm.spread = 8.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 6.0
	pm.inherit_velocity_ratio = 0.7
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	return p


## A burst of spray all round the hull.
func _make_splash(mat: StandardMaterial3D) -> GPUParticles3D:
	var p := _particles(mat, 1.4, 40, 1.1)
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.1, 0.1, 2.6)
	return p


func _on_landed(airtime: float) -> void:
	if Views.nearest_distance(self, _boat.global_position) > RANGE:
		return
	_splash.global_transform = Transform3D(_boat.global_basis.orthonormalized(), Vector3(_boat.global_position.x, MapLayout.SEA_LEVEL + 0.1, _boat.global_position.z))
	_splash.amount_ratio = clampf(airtime / 1.5, 0.35, 1.0)
	_splash.restart()
	_splash.emitting = true


func _physics_process(dt: float) -> void:
	_time += dt
	var b := _boat.global_basis.orthonormalized()
	var speed := absf(_boat.forward_speed)
	var wet := _boat.floating()
	var near := Views.nearest_distance(self, _boat.global_position) < RANGE
	# Wake: a point every STEP metres from the transom while it's in the water.
	var stern := _boat.global_position + b * Vector3(0.0, 0.0, _boat.body_rear - 0.75)
	stern.y = MapLayout.SEA_LEVEL
	if wet and speed > 1.2:
		if _last_stamp == Vector3.INF or stern.distance_to(_last_stamp) > STEP:
			var right := b.x
			right.y = 0.0
			right = right.normalized() if right.length() > 0.1 else Vector3.RIGHT
			_points.append([stern, right, _time, clampf(speed / 20.0, 0.0, 1.0), not _was_wet or _last_stamp == Vector3.INF])
			_last_stamp = stern
			if _points.size() > MAX_POINTS:
				_points.pop_front()
	elif not wet:
		_last_stamp = Vector3.INF
	_was_wet = wet
	while not _points.is_empty() and _time - float(_points[0][2]) > WAKE_LIFE:
		_points.pop_front()
	# Spray off the hull once it's quick (and not in the air).
	var fast := wet and near and speed > 7.0
	for i in _spray.size():
		var p := _spray[i]
		if fast or p.emitting:
			var side := -1.0 if i == 0 else 1.0
			var at := _boat.global_position + b * Vector3(side * 1.08, 0.0, -0.9)
			at.y = MapLayout.SEA_LEVEL + 0.05
			p.global_transform = Transform3D(b, at)
			p.emitting = fast
			p.amount_ratio = clampf((speed - 7.0) / 12.0, 0.2, 1.0) * clampf(_boat.wet * 1.5, 0.3, 1.0)
	# Prop wash under throttle.
	var push := maxf(_boat.throttle_input, _boat.brake_input if _boat.gear < 0 or speed > 1.0 else 0.0)
	var washing := near and _boat.prop_bite > 0.3 and push > 0.15
	if washing or _wash.emitting:
		var at := _boat.global_position + b * Vector3(0.0, 0.0, _boat.body_rear + 0.2)
		at.y = MapLayout.SEA_LEVEL + 0.05
		_wash.global_transform = Transform3D(b, at)
		_wash.emitting = washing
		_wash.amount_ratio = clampf(push, 0.3, 1.0)
	var rooster := washing and speed > 11.0 and _boat.throttle_input > 0.5 and _boat.gear > 0
	if rooster or _rooster.emitting:
		var at := _boat.global_position + b * Vector3(0.0, 0.0, _boat.body_rear + 0.1)
		at.y = MapLayout.SEA_LEVEL + 0.1
		_rooster.global_transform = Transform3D(b, at)
		_rooster.emitting = rooster
		_rooster.amount_ratio = clampf((speed - 11.0) / 8.0, 0.25, 1.0) * _boat.throttle_input


func _process(_dt: float) -> void:
	_build_wake()


## Rebuilds the ribbon: the laid points, then the transom now (so it's
## attached to the boat), each widened by its age. One triangle strip per
## piece (a jump breaks it), two vertices a point.
func _build_wake() -> void:
	_mesh.clear_surfaces()
	var pts := _points.duplicate()
	if not pts.is_empty() and _boat.floating() and absf(_boat.forward_speed) > 1.2:
		var b := _boat.global_basis.orthonormalized()
		var stern := _boat.global_position + b * Vector3(0.0, 0.0, _boat.body_rear - 0.75)
		stern.y = MapLayout.SEA_LEVEL
		var right := b.x
		right.y = 0.0
		pts.append([stern, right.normalized() if right.length() > 0.1 else Vector3.RIGHT, _time, clampf(absf(_boat.forward_speed) / 20.0, 0.0, 1.0), false])
	var n := pts.size()
	if n < 2:
		return
	# Pieces: [first, last] point indices, two points at least.
	var pieces: Array[Vector2i] = []
	var first := 0
	for i in range(1, n + 1):
		var cut := i == n or bool(pts[i][4]) or (pts[i][0] as Vector3).distance_to(pts[i - 1][0]) > STEP * 4.0
		if cut:
			if i - 1 > first:
				pieces.append(Vector2i(first, i - 1))
			first = i
	var half0 := _boat.body_half_width * 0.75
	var y := MapLayout.SEA_LEVEL + 0.03
	for piece in pieces:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_mesh.surface_set_normal(Vector3.UP)
		var along := 0.0
		for i in range(piece.x, piece.y + 1):
			var q: Array = pts[i]
			var pos: Vector3 = q[0]
			if i > piece.x:
				along += pos.distance_to(pts[i - 1][0])
			var secs := _time - float(q[2])
			var spd := float(q[3])
			# The V opens at about tan(19.5 deg) of the speed (a bit less: it reads better).
			var half := minf(half0 + 0.2 * spd * 20.0 * secs, 16.0)
			var side: Vector3 = (q[1] as Vector3) * half
			_mesh.surface_set_color(Color(secs / WAKE_LIFE, spd, 0.0))
			_mesh.surface_set_uv(Vector2(0.0, along))
			_mesh.surface_add_vertex(Vector3(pos.x - side.x, y, pos.z - side.z))
			_mesh.surface_set_uv(Vector2(1.0, along))
			_mesh.surface_add_vertex(Vector3(pos.x + side.x, y, pos.z + side.z))
		_mesh.surface_end()
