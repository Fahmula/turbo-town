class_name VehicleEffects
extends Node
## Tire smoke, off-road dust, skid marks and impact sparks for a Vehicle.
## Add as a child of the vehicle; everything it spawns lives in world space.

@export var skid_mark_count := 1600
@export var smoke_threshold := 0.35
@export var mark_threshold := 0.3

var _vehicle: Vehicle
var _smoke: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _last_mark: Array[Vector3] = []
var _marks: MultiMesh
var _mark_index := 0
var _mark_total := 0
var _sparks: GPUParticles3D
var _fx_root: Node3D


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	set_physics_process(false)
	# Children are ready before their parent; wait until the vehicle has
	# collected its wheels.
	if not _vehicle.is_node_ready():
		await _vehicle.ready
	_fx_root = Node3D.new()
	_fx_root.name = "VehicleFX"
	_fx_root.top_level = true
	_fx_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_fx_root)
	var smoke_mat := _puff_material(Color(0.95, 0.95, 0.95, 0.55))
	var dust_mat := _puff_material(Color(0.72, 0.58, 0.40, 0.5))
	for w in _vehicle.wheels:
		_smoke.append(_make_puffs(smoke_mat, 2.2, 1.6))
		_dust.append(_make_puffs(dust_mat, 1.6, 1.2))
		_last_mark.append(Vector3.INF)
	_build_marks()
	_build_sparks()
	# Vehicle layer: the player's reflection probe doesn't capture them.
	for gi in _fx_root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = Vehicle.VISUAL_LAYER
	_vehicle.impact.connect(_on_impact)
	_vehicle.vehicle_reset.connect(func() -> void:
		for i in _last_mark.size():
			_last_mark[i] = Vector3.INF)
	set_physics_process(true)


func _puff_material(col: Color) -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = col
	return m


func _make_puffs(mat: StandardMaterial3D, size: float, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
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
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	p.amount = 40
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 20, 40))
	_fx_root.add_child(p)
	return p


func _build_marks() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.26, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	quad.material = mat
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.mesh = quad
	_marks.instance_count = skid_mark_count
	_marks.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _marks
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mmi)


func _build_sparks() -> void:
	_sparks = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.6, 1))
	ramp.set_color(1, Color(1.0, 0.35, 0.05, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_sparks.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	_sparks.draw_pass_1 = mesh
	pm.particle_flag_align_y = false
	_sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_sparks.amount = 36
	_sparks.lifetime = 0.7
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(_sparks)


func _on_impact(strength: float, pos: Vector3, _normal: Vector3) -> void:
	if strength < 6000.0:
		return
	_sparks.global_position = pos
	_sparks.amount_ratio = clampf(strength / 40000.0, 0.3, 1.0)
	_sparks.restart()
	_sparks.emitting = true


func _physics_process(_dt: float) -> void:
	var speed := _vehicle.linear_velocity.length()
	for i in _vehicle.wheels.size():
		var w := _vehicle.wheels[i]
		var smoke := _smoke[i]
		var dust := _dust[i]
		var on_ground := w.grounded
		var is_dirt := w.surface_grip < 0.95
		var skid := w.skid if on_ground else 0.0
		var want_smoke := on_ground and not is_dirt and skid > smoke_threshold
		var want_dust := on_ground and is_dirt and (speed > 6.0 or skid > 0.2)
		# Only touch the particle nodes when something is (or was) emitting.
		if want_smoke or smoke.emitting:
			smoke.global_position = w.contact_point + Vector3.UP * 0.15
			smoke.emitting = want_smoke
			smoke.amount_ratio = clampf(skid, 0.2, 1.0)
		if want_dust or dust.emitting:
			dust.global_position = w.contact_point + Vector3.UP * 0.15
			dust.emitting = want_dust
			dust.amount_ratio = clampf(maxf(speed / 30.0, skid), 0.2, 1.0)
		if on_ground and not is_dirt and skid > mark_threshold:
			if w.contact_point.distance_to(_last_mark[i]) > 0.35:
				_add_mark(w.contact_point + w.contact_normal * 0.02, w.contact_normal)
				_last_mark[i] = w.contact_point
		elif _last_mark[i] != Vector3.INF:
			_last_mark[i] = Vector3.INF


func _add_mark(pos: Vector3, normal: Vector3) -> void:
	var fwd := _vehicle.linear_velocity
	fwd = (fwd - normal * fwd.dot(normal))
	if fwd.length() < 0.1:
		fwd = -_vehicle.global_basis.z
	fwd = fwd.normalized()
	var right := fwd.cross(normal).normalized()
	var b := Basis(right, normal, -fwd)
	_marks.set_instance_transform(_mark_index, Transform3D(b, pos))
	_mark_index = (_mark_index + 1) % skid_mark_count
	_mark_total = mini(_mark_total + 1, skid_mark_count)
	_marks.visible_instance_count = _mark_total
