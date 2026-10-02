class_name VehicleDamage
extends Node
## Crash damage.
##   * Dents the body around impact points (smooth falloff; the shading bends
##     with the dent so it reads in the light).
##   * Loose parts (bumpers, spoiler) lose health from nearby hits and fall
##     off as debris.
##   * Paint damage follows the dents: scuffs, primer and bare metal round
##     each hit, and streaks where bodywork slides along something (vertex
##     colours read by car_paint.gdshader).
##   * Lights break at the end that was hit; the glass cracks in a spiderweb
##     at the nearest window once the car is badly smashed (with a shower of
##     glass bits).
##   * A smashed front pulls the steering to the damaged side and costs
##     engine power, and the engine smokes.
## Resetting the car (R / respawn / the garage) repairs everything.

signal damage_changed(total: float)
signal part_lost(part_name: String)
## A crash got worse; severity 0..1 (1 = a really big hit).
signal crashed(severity: float)
## Lamps or glass broke ("headlights", "taillights", "glass"), for sounds.
signal broke(what: String, world_position: Vector3)
## A part came off (as debris), for sounds.
signal detached(debris: RigidBody3D)

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
## Paint scrapes from bodywork sliding along things: at most this often (s),
## while sliding faster than SCRAPE_SPEED (m/s).
const SCRAPE_INTERVAL := 0.2
const SCRAPE_SPEED := 4.0

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
var _sources: Array[ArrayMesh] = []  # per mesh: the model's own (shared) mesh
var _originals: Array = []  # per mesh: Array of surface arrays
var _offsets: Array = []    # per mesh: Array of PackedVector3Array (per surface), empty until dented
var _current: Array = []    # per mesh: per surface [positions, normals, colours] as shown, empty until dented
var _materials: Array = []  # per mesh: Array of Material
## name -> {"mesh", "parent", "xform", "health", "debris"}
var _parts := {}
var _vel_history := PackedVector3Array()
var _event_dv := 0.0
var _since_impact := 1.0
var _smoke: GPUParticles3D
var _glass_burst: GPUParticles3D
var _headlights_were_on := false
var _scrape_timer := 0.0

## Surface arrays per model mesh, read once and shared by every vehicle using
## it: reading them back from the GPU takes milliseconds.
static var _arrays_cache := {}
## Per model mesh: each surface's bounding box, to skip far surfaces quickly.
static var _bounds_cache := {}


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	min_impulse *= maxf(_vehicle.mass / 1300.0, 1.0)
	var body := get_node_or_null(body_path)
	if body == null:
		return
	_body_visual = body as VehicleBodyVisual
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		_register(mi as MeshInstance3D)
	_vehicle.impact.connect(_on_impact)
	_vehicle.vehicle_reset.connect(repair)
	_make_particles()


func _register(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var surfaces: Array = _arrays_cache.get(src, [])
	if surfaces.is_empty():
		for i in src.get_surface_count():
			surfaces.append(src.surface_get_arrays(i))
		_arrays_cache[src] = surfaces
		var bounds: Array[AABB] = []
		for arrays: Array in surfaces:
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var box := AABB(vs[0], Vector3.ZERO) if vs.size() > 0 else AABB()
			for v in vs:
				box = box.expand(v)
			bounds.append(box)
		_bounds_cache[src] = bounds
	var mats: Array = []
	for i in src.get_surface_count():
		mats.append(mi.get_active_material(i))
	# The model's mesh stays shared until the first dent (see _dent).
	for i in mats.size():
		if mi.get_surface_override_material(i) == null and mats[i]:
			mi.set_surface_override_material(i, mats[i])
	_meshes.append(mi)
	_sources.append(src)
	_originals.append(surfaces)
	_offsets.append([])
	_current.append([])
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
	_scrape_timer -= dt
	if _vehicle.scrape_speed > SCRAPE_SPEED and _scrape_timer <= 0.0:
		_scrape_timer = SCRAPE_INTERVAL
		scrape(_vehicle.scrape_point, clampf(_vehicle.scrape_speed / 20.0, 0.15, 0.6))


## Paint scraped off where bodywork slides along something (no dent).
func scrape(world_pos: Vector3, amount: float) -> void:
	for m in _meshes.size():
		if _meshes[m].get_parent() is RigidBody3D:
			continue
		_dent(m, world_pos, 0.0, 0.45, amount, 0.0)


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
		_dent(m, world_pos, depth, radius, 0.35 + 0.5 * t, 0.25 + 0.9 * t)

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


## Dents mesh `m` round `world_pos` (`depth` m at the centre, smooth falloff
## to `radius`) and marks the paint: `scrape` and `loss` (0..1 at the centre)
## become the scuff/primer/bare-metal mask in the vertex colours
## (car_paint.gdshader; stored inverted, white = clean).
func _dent(m: int, world_pos: Vector3, depth: float, radius: float, scrape := 0.0, loss := 0.0) -> void:
	var mi := _meshes[m]
	var inv := mi.global_transform.affine_inverse()
	var p := inv * world_pos
	var center := inv * (_vehicle.global_transform * Vector3(0.0, 0.35, 0.0))
	var push := center - p
	push.y *= 0.3
	if push.length() < 0.01:
		return
	push = push.normalized()
	var r2 := radius * radius
	var surfaces: Array = _originals[m]
	if (_offsets[m] as Array).is_empty():
		for s in surfaces.size():
			var arrays: Array = surfaces[s]
			var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var zero := PackedVector3Array()
			zero.resize(count)
			_offsets[m].append(zero)
			var white := PackedColorArray()
			white.resize(count)
			white.fill(Color.WHITE)
			_current[m].append([(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
				(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate(), white])
	# Only vertices inside the dent change; everything else keeps the
	# position and normal it already has (in _current), so a dent costs
	# little more than the vertices it actually moves.
	var bounds: Array = _bounds_cache.get(_sources[m], [])
	var reach := radius + max_total_dent
	var changed := false
	for s in surfaces.size():
		if s < bounds.size() and not (bounds[s] as AABB).grow(reach).has_point(p):
			continue
		var base: PackedVector3Array = (surfaces[s] as Array)[Mesh.ARRAY_VERTEX]
		var base_n: PackedVector3Array = (surfaces[s] as Array)[Mesh.ARRAY_NORMAL]
		var off: PackedVector3Array = _offsets[m][s]
		var verts: PackedVector3Array = _current[m][s][0]
		var norms: PackedVector3Array = _current[m][s][1]
		var cols: PackedColorArray = _current[m][s][2]
		var hit := false
		for i in verts.size():
			var d2 := verts[i].distance_squared_to(p)
			if d2 >= r2:
				continue
			# Smoothstep falloff: no crease at the dent's edge.
			var f := smoothstep(radius, 0.0, sqrt(d2))
			if depth > 0.0:
				var o := off[i] + push * depth * f
				if o.length() > max_total_dent:
					o = o.normalized() * max_total_dent
				off[i] = o
				verts[i] = base[i] + o
				if i < norms.size():
					# Tilt the normal into the dent so it shows in the lighting.
					norms[i] = (base_n[i] + o * 2.5).normalized() if o.length() > 0.001 else base_n[i]
			var c := cols[i]
			c.g = maxf(c.g - scrape * f, 0.0)
			c.b = maxf(c.b - loss * f * f, 0.0)
			cols[i] = c
			hit = true
		if hit:
			_offsets[m][s] = off
			_current[m][s] = [verts, norms, cols]
			changed = true
	if not changed:
		return
	# A new mesh for this car only (others share the model's), swapped in
	# whole so the surface material overrides (paint, broken lights) stay.
	var mesh := ArrayMesh.new()
	for s in surfaces.size():
		var arrays: Array = (surfaces[s] as Array).duplicate()
		arrays[Mesh.ARRAY_VERTEX] = _current[m][s][0]
		if not (_current[m][s][1] as PackedVector3Array).is_empty():
			arrays[Mesh.ARRAY_NORMAL] = _current[m][s][1]
		arrays[Mesh.ARRAY_COLOR] = _current[m][s][2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, _materials[m][s])
	_swap_mesh(mi, mesh)


## Gives `mi` another mesh with the same surfaces, keeping its overrides.
func _swap_mesh(mi: MeshInstance3D, mesh: ArrayMesh) -> void:
	var overrides := []
	for s in mesh.get_surface_count():
		overrides.append(mi.get_surface_override_material(s))
	mi.mesh = mesh
	for s in overrides.size():
		mi.set_surface_override_material(s, overrides[s])


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
	if _body_visual:
		_body_visual.set_front_lights_broken(true)
	var real := _vehicle.get_node_or_null("Headlights") as Node3D
	if real:
		_headlights_were_on = real.visible
		real.visible = false
	var at := _vehicle.global_transform * Vector3(0, 0.3, -_vehicle.body_front)
	_burst_glass(at)
	broke.emit("headlights", at)


func _break_taillights() -> void:
	if taillights_broken:
		return
	taillights_broken = true
	if _body_visual:
		_body_visual.set_rear_lights_broken(true)
	var at := _vehicle.global_transform * Vector3(0, 0.4, _vehicle.body_rear)
	_burst_glass(at)
	broke.emit("taillights", at)


func _break_glass(at: Vector3) -> void:
	glass_broken = true
	var crack_at := _nearest_glass(at)
	if _body_visual:
		_body_visual.set_glass_cracked(true, crack_at)
	_burst_glass(crack_at)
	broke.emit("glass", crack_at)


## The glass vertex (world space) closest to `world_pos`: the web cracks
## the window nearest the hit, not thin air by the bumper.
func _nearest_glass(world_pos: Vector3) -> Vector3:
	var best := world_pos
	var best_d := INF
	for sf: Array in _surfaces_named("Glass"):
		var mi := sf[0] as MeshInstance3D
		var m := _meshes.find(mi)
		if m < 0:
			continue
		var p := mi.global_transform.affine_inverse() * world_pos
		var verts: PackedVector3Array = _current[m][sf[1]][0] if not (_current[m] as Array).is_empty() else (_originals[m][sf[1]] as Array)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var d := v.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = mi.global_transform * v
	return best


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
	detached.emit(debris)
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
		if _meshes[m].mesh != _sources[m]:
			_swap_mesh(_meshes[m], _sources[m])
		_offsets[m] = []
		_current[m] = []
	for part_name: String in _parts:
		_reattach(part_name, true)
		_parts[part_name]["health"] = 1.0
	if headlights_broken:
		headlights_broken = false
		if _body_visual:
			_body_visual.set_front_lights_broken(false)
		var real := _vehicle.get_node_or_null("Headlights") as Node3D
		if real:
			real.visible = _headlights_were_on
	if taillights_broken:
		taillights_broken = false
		if _body_visual:
			_body_visual.set_rear_lights_broken(false)
	if glass_broken:
		glass_broken = false
		if _body_visual:
			_body_visual.set_glass_cracked(false)
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
	_smoke.layers = Vehicle.VISUAL_LAYER
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
	_glass_burst.layers = Vehicle.VISUAL_LAYER
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
