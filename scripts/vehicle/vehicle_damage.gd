class_name VehicleDamage
extends Node
## Crash damage.
##   * Dents the body around impact points (smooth falloff; the shading bends
##     with the dent so it reads in the light).
##   * Loose parts (bumpers, spoiler) lose health from nearby hits and fall
##     off as debris.
##   * Lights break at the end that was hit; the glass cracks once the car is
##     badly smashed (with a shower of glass bits).
##   * A smashed front pulls the steering to the damaged side and costs
##     engine power, and the engine smokes.
## Resetting the car (R / respawn / the garage) repairs everything.

signal damage_changed(total: float)
signal part_lost(part_name: String)
## A crash got worse; severity 0..1 (1 = a really big hit).
signal crashed(severity: float)

## Node whose MeshInstance3D descendants get deformed (the body model).
@export var body_path: NodePath = ^"../Body"
## Contact impulse below which a touch is ignored altogether (scrapes).
@export var min_impulse := 3500.0
## How hard a crash is = how much the car's velocity changed (m/s) within a
## quarter of a second. Below DV_MIN nothing happens; DV_MIN + DV_RANGE is a
## full-strength hit (about a 55 km/h wall crash).
@export var dv_min := 4.0
@export var dv_range := 14.0
@export var max_dent := 0.32
@export var max_total_dent := 0.5

## Model parts (by mesh name) that can come off.
const DETACHABLE := ["FrontBumper", "RearBumper", "Spoiler"]
const PART_NAMES := {"FrontBumper": "FRONT BUMPER", "RearBumper": "REAR BUMPER", "Spoiler": "SPOILER"}

## 0..100, rough "how smashed is it" value for UI.
var total_damage := 0.0
## 0..1 damage to the front corners and the rear.
var front_left := 0.0
var front_right := 0.0
var rear_damage := 0.0
var headlights_broken := false
var taillights_broken := false
var glass_broken := false

var _vehicle: Vehicle
var _body_visual: VehicleBodyVisual
var _meshes: Array[MeshInstance3D] = []
var _originals: Array = []  # per mesh: Array of surface arrays
var _offsets: Array = []    # per mesh: Array of PackedVector3Array (per surface)
var _materials: Array = []  # per mesh: Array of Material
## name -> {"mesh", "parent", "xform", "health", "debris"}
var _parts := {}
var _vel_history := PackedVector3Array()
var _event_dv := 0.0
var _since_impact := 1.0
var _smoke: GPUParticles3D
var _glass_burst: GPUParticles3D
var _headlights_were_on := false

static var _broken_light: StandardMaterial3D
static var _cracked_glass: StandardMaterial3D


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	min_impulse *= maxf(_vehicle.mass / 1300.0, 1.0)
	var body := get_node_or_null(body_path)
	if body == null:
		return
	_body_visual = body as VehicleBodyVisual
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		_register(mi as MeshInstance3D)
	if _broken_light == null:
		_broken_light = StandardMaterial3D.new()
		_broken_light.albedo_color = Color(0.18, 0.18, 0.2)
		_broken_light.roughness = 0.9
		_cracked_glass = StandardMaterial3D.new()
		_cracked_glass.albedo_color = Color(0.72, 0.78, 0.84)
		_cracked_glass.roughness = 0.75
	_vehicle.impact.connect(_on_impact)
	_vehicle.vehicle_reset.connect(repair)
	_make_particles()


func _register(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var surfaces: Array = []
	var offsets: Array = []
	var mats: Array = []
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		surfaces.append(arrays)
		var off := PackedVector3Array()
		off.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		offsets.append(off)
		mats.append(mi.get_active_material(i))
	# Own copy so other cars sharing the model aren't affected.
	var copy := src.duplicate() as ArrayMesh
	mi.mesh = copy
	for i in mats.size():
		if mi.get_surface_override_material(i) == null and mats[i]:
			mi.set_surface_override_material(i, mats[i])
	_meshes.append(mi)
	_originals.append(surfaces)
	_offsets.append(offsets)
	_materials.append(mats)
	if String(mi.name) in DETACHABLE:
		_parts[String(mi.name)] = {"mesh": mi, "parent": mi.get_parent(), "xform": mi.transform, "health": 1.0, "debris": null}


func _physics_process(dt: float) -> void:
	_vel_history.append(_vehicle.linear_velocity)
	if _vel_history.size() > 30:
		_vel_history.remove_at(0)
	_since_impact += dt
	if _since_impact > 0.4:
		_event_dv = 0.0


func _on_impact(strength: float, world_pos: Vector3, _normal: Vector3) -> void:
	if strength < min_impulse:
		return
	_since_impact = 0.0
	# A crash shows up as several impacts over a few physics steps; damage is
	# applied as its severity grows, so the total matches the whole crash.
	var dv := 0.0
	for past in _vel_history:
		dv = maxf(dv, (past - _vehicle.linear_velocity).length())
	if dv <= maxf(_event_dv, dv_min) + 0.3:
		return
	var t := clampf((dv - maxf(_event_dv, dv_min)) / dv_range, 0.0, 1.0)
	_event_dv = dv
	var depth := lerpf(0.07, max_dent, t)
	var radius := lerpf(0.5, 1.1, t)
	total_damage = minf(total_damage + t * 35.0 + 3.0, 100.0)
	for m in _meshes.size():
		if _meshes[m].get_parent() is RigidBody3D:
			continue  # already fallen off
		_dent(m, world_pos, depth, radius)

	# Where on the car was it hit?
	var local := _vehicle.global_transform.affine_inverse() * world_pos
	var hit := t * 0.5 + 0.1
	if local.z < -_vehicle.body_front * 0.45:
		if local.x < 0.0:
			front_left = minf(front_left + hit, 1.0)
		else:
			front_right = minf(front_right + hit, 1.0)
		if t > 0.3 or front_left + front_right > 0.9:
			_break_headlights()
	elif local.z > _vehicle.body_rear * 0.45:
		rear_damage = minf(rear_damage + hit, 1.0)
		if t > 0.3 or rear_damage > 0.6:
			_break_taillights()
	if total_damage > 55.0 and not glass_broken:
		_break_glass(world_pos)

	# Loose parts near the hit take a knock and may fall off.
	for part_name: String in _parts:
		var p: Dictionary = _parts[part_name]
		if p["debris"] != null:
			continue
		var mi: MeshInstance3D = p["mesh"]
		var center := _vehicle.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb().get_center())
		if center.distance_to(local) < 1.7:
			p["health"] = float(p["health"]) - (t * 1.4 + 0.25)
			if float(p["health"]) <= 0.0:
				_detach(part_name)
	_update_driving()
	damage_changed.emit(total_damage)
	crashed.emit(t)


## Steering pull and power loss from a smashed front; engine smoke.
func _update_driving() -> void:
	var front := maxf(front_left, front_right)
	# A gentle pull (kids should still be able to drive it home).
	_vehicle.damage_steer_bias = clampf((front_right - front_left) * 0.1, -0.06, 0.06)
	_vehicle.damage_power = 1.0 - 0.5 * clampf((front_left + front_right) * 0.6, 0.0, 1.0)
	if _smoke:
		_smoke.emitting = front > 0.45
		_smoke.amount_ratio = clampf((front - 0.3) * 1.5, 0.2, 1.0)


func _dent(m: int, world_pos: Vector3, depth: float, radius: float) -> void:
	var mi := _meshes[m]
	var inv := mi.global_transform.affine_inverse()
	var p := inv * world_pos
	var center := inv * (_vehicle.global_transform * Vector3(0.0, 0.35, 0.0))
	var push := center - p
	push.y *= 0.3
	if push.length() < 0.01:
		return
	push = push.normalized()
	var mesh := mi.mesh as ArrayMesh
	mesh.clear_surfaces()
	var r2 := radius * radius
	var surfaces: Array = _originals[m]
	for s in surfaces.size():
		var arrays: Array = (surfaces[s] as Array).duplicate()
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var off: PackedVector3Array = _offsets[m][s]
		var verts := base.duplicate()
		var norms := base_n.duplicate()
		for i in verts.size():
			var v := base[i] + off[i]
			var d2 := v.distance_squared_to(p)
			if d2 < r2:
				# Smoothstep falloff: no crease at the dent's edge.
				var f := smoothstep(radius, 0.0, sqrt(d2))
				var o := off[i] + push * depth * f
				if o.length() > max_total_dent:
					o = o.normalized() * max_total_dent
				off[i] = o
			verts[i] = base[i] + off[i]
			var dent_amount := off[i].length()
			if dent_amount > 0.001 and i < norms.size():
				# Tilt the normal into the dent so it shows in the lighting.
				norms[i] = (base_n[i] + off[i].normalized() * dent_amount * 2.5).normalized()
		_offsets[m][s] = off
		arrays[Mesh.ARRAY_VERTEX] = verts
		if not norms.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = norms
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, _materials[m][s])
		var override := mi.get_surface_override_material(s)
		if override == null:
			mi.set_surface_override_material(s, _materials[m][s])


func _surfaces_named(mat_name: String) -> Array:
	var out := []
	for mi in _meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			var orig_name := ""
			var m := _meshes.find(mi)
			if m >= 0 and i < (_materials[m] as Array).size() and _materials[m][i]:
				orig_name = (_materials[m][i] as Material).resource_name
			if orig_name == mat_name or (mat and mat.resource_name == mat_name):
				out.append([mi, i])
	return out


func _break_headlights() -> void:
	if headlights_broken:
		return
	headlights_broken = true
	for s: Array in _surfaces_named("Headlight"):
		(s[0] as MeshInstance3D).set_surface_override_material(s[1], _broken_light)
	var real := _vehicle.get_node_or_null("Headlights") as Node3D
	if real:
		_headlights_were_on = real.visible
		real.visible = false
	_burst_glass(_vehicle.global_transform * Vector3(0, 0.3, -_vehicle.body_front))


func _break_taillights() -> void:
	if taillights_broken:
		return
	taillights_broken = true
	if _body_visual:
		_body_visual.set_rear_lights_broken(true)
	_burst_glass(_vehicle.global_transform * Vector3(0, 0.4, _vehicle.body_rear))


func _break_glass(at: Vector3) -> void:
	glass_broken = true
	for s: Array in _surfaces_named("Glass"):
		(s[0] as MeshInstance3D).set_surface_override_material(s[1], _cracked_glass)
	_burst_glass(at)


func _detach(part_name: String) -> void:
	var p: Dictionary = _parts[part_name]
	var mi: MeshInstance3D = p["mesh"]
	var world := mi.global_transform
	var aabb := mi.get_aabb()
	var debris := RigidBody3D.new()
	debris.name = "Debris" + part_name
	debris.mass = 25.0
	debris.collision_layer = 4
	debris.collision_mask = 0b111
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.08)
	cs.shape = box
	cs.position = aabb.get_center()
	debris.add_child(cs)
	_vehicle.get_parent().add_child(debris)
	debris.global_transform = world
	mi.get_parent().remove_child(mi)
	debris.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	debris.linear_velocity = _vehicle.linear_velocity * 0.8 + Vector3(randf_range(-2, 2), randf_range(2, 4), randf_range(-2, 2))
	debris.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	p["debris"] = debris
	# Lies around for a while, then is tidied away (the part stays missing
	# until the car is repaired). If this car is gone by then, only the
	# debris' own queue_free runs.
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.one_shot = true
	timer.autostart = true
	debris.add_child(timer)
	timer.timeout.connect(_debris_expired.bind(part_name, debris))
	timer.timeout.connect(debris.queue_free)
	part_lost.emit(PART_NAMES.get(part_name, part_name))


func _debris_expired(part_name: String, debris: RigidBody3D) -> void:
	if _parts[part_name]["debris"] == debris:
		_reattach(part_name, false)


## Puts a fallen part back on the car (or just hides it if not `show`).
func _reattach(part_name: String, show := true) -> void:
	var p: Dictionary = _parts[part_name]
	var debris: Variant = p["debris"]
	var mi: MeshInstance3D = p["mesh"]
	if not is_instance_valid(mi):
		return
	if debris != null and is_instance_valid(debris):
		(debris as Node).remove_child(mi)
		(debris as Node).queue_free()
	if mi.get_parent() == null:
		(p["parent"] as Node).add_child(mi)
	mi.transform = p["xform"]
	mi.visible = show
	p["debris"] = null


func repair() -> void:
	# (A teleport also lands here: forget the old speed so it isn't a "crash".)
	_vel_history.clear()
	_event_dv = 0.0
	total_damage = 0.0
	front_left = 0.0
	front_right = 0.0
	rear_damage = 0.0
	for m in _meshes.size():
		var mi := _meshes[m]
		var mesh := mi.mesh as ArrayMesh
		mesh.clear_surfaces()
		var surfaces: Array = _originals[m]
		for s in surfaces.size():
			var zero := PackedVector3Array()
			zero.resize((_offsets[m][s] as PackedVector3Array).size())
			_offsets[m][s] = zero
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
			mesh.surface_set_material(s, _materials[m][s])
	for part_name: String in _parts:
		_reattach(part_name, true)
		_parts[part_name]["health"] = 1.0
	if headlights_broken:
		headlights_broken = false
		for s: Array in _surfaces_named("Headlight"):
			var m := _meshes.find(s[0])
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], _materials[m][s[1]])
		var real := _vehicle.get_node_or_null("Headlights") as Node3D
		if real:
			real.visible = _headlights_were_on
	if taillights_broken:
		taillights_broken = false
		if _body_visual:
			_body_visual.set_rear_lights_broken(false)
	if glass_broken:
		glass_broken = false
		for s: Array in _surfaces_named("Glass"):
			var m := _meshes.find(s[0])
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], _materials[m][s[1]])
	_update_driving()
	damage_changed.emit(total_damage)


# --- Particles -------------------------------------------------------------------

func _make_particles() -> void:
	# Engine smoke from under the bonnet.
	_smoke = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.7))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	_smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
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
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.35, 0.35, 0.38, 0.6)
	quad.material = mat
	_smoke.draw_pass_1 = quad
	_smoke.amount = 24
	_smoke.lifetime = 2.2
	_smoke.local_coords = false
	_smoke.emitting = false
	_smoke.position = Vector3(0, _vehicle.body_top * 0.5 + 0.3, -_vehicle.body_front * 0.6)
	_vehicle.add_child.call_deferred(_smoke)
	# Glass bits.
	_glass_burst = GPUParticles3D.new()
	var gm := ParticleProcessMaterial.new()
	gm.direction = Vector3(0, 1, 0)
	gm.spread = 80.0
	gm.initial_velocity_min = 2.0
	gm.initial_velocity_max = 5.0
	gm.gravity = Vector3(0, -9.8, 0)
	gm.scale_min = 0.5
	gm.scale_max = 1.0
	_glass_burst.process_material = gm
	var bit := BoxMesh.new()
	bit.size = Vector3(0.06, 0.02, 0.05)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.metallic = 0.6
	bm.roughness = 0.1
	bit.material = bm
	_glass_burst.draw_pass_1 = bit
	_glass_burst.amount = 40
	_glass_burst.lifetime = 1.4
	_glass_burst.one_shot = true
	_glass_burst.explosiveness = 0.95
	_glass_burst.emitting = false
	_glass_burst.local_coords = false
	_vehicle.add_child.call_deferred(_glass_burst)


func _burst_glass(at: Vector3) -> void:
	if _glass_burst == null or not _glass_burst.is_inside_tree():
		return
	_glass_burst.global_position = at
	_glass_burst.restart()
	_glass_burst.emitting = true
