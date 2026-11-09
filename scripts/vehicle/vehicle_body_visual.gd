class_name VehicleBodyVisual
extends Node3D
## Cosmetic only. Put this on the node that holds the body model (not the
## wheels). It:
##   * adds exaggerated body roll/pitch from the car's acceleration
##     (stylized "weight transfer");
##   * swaps the model's imported materials (found by their contract names,
##     ART_BIBLE.md §13) for the vehicle shaders in assets/shaders/vehicle/:
##     car paint, glass, lamps, trim, cabin and tyres (apply_vehicle_materials);
##   * drives the lamps: brake, reverse, indicators / hazards (`indicator`,
##     set by TrafficDriver), broken lamps (VehicleDamage);
##   * collects road grime while driving on dirt (`dirt`, in the paint and
##     tyre shaders);
##   * draws a soft contact shadow under the car, so it sits on the road even
##     in shade.
## A mesh named "Stripes" (material "Stripe") is the optional racing
## stripes: hidden unless `stripes` is on (only the player's garage choice
## turns it on, never traffic).

const PAINT_SHADER := preload("res://assets/shaders/vehicle/car_paint.gdshader")
const PAINT_CUSTOM_SHADER := preload("res://assets/shaders/vehicle/car_paint_custom.gdshader")
## Side graphics (PartsCatalog.DECALS rows) and race-number digits, from
## tools/textures/make_decals.py.
const DECAL_ATLAS := preload("res://assets/textures/vehicle/decals.png")
const DIGITS := preload("res://assets/textures/vehicle/digits.png")
const GLASS_SHADER := preload("res://assets/shaders/vehicle/vehicle_glass.gdshader")
const GLASS_OPAQUE_SHADER := preload("res://assets/shaders/vehicle/vehicle_glass_opaque.gdshader")
const LAMP_SHADER := preload("res://assets/shaders/vehicle/vehicle_lamp.gdshader")
const TRIM_SHADER := preload("res://assets/shaders/vehicle/vehicle_trim.gdshader")
const TYRE_SHADER := preload("res://assets/shaders/vehicle/vehicle_tyre.gdshader")
const SHADOW_SHADER := preload("res://assets/shaders/vehicle/contact_shadow.gdshader")
const INTERIOR_SHADER := preload("res://assets/shaders/vehicle/vehicle_interior.gdshader")
const NAV_SHADER := preload("res://assets/shaders/vehicle/nav_light.gdshader")
const PROP_SHADER := preload("res://assets/shaders/vehicle/prop_blur.gdshader")

## Indicator states.
enum Blinker { OFF, LEFT, RIGHT, HAZARD }

@export var paint_color := Color(0.784, 0.137, 0.106)
## Colours the traffic spawner picks from for this vehicle, uniformly (empty =
## the weighted PaintPalette.TRAFFIC mix).
@export var paint_palette: Array[Color] = []
@export var stripes := false
## Road grime on the lower body and tyres, 0 = clean, 1 = filthy. Driving on
## dirt adds to it; off-road vehicles start a little dusty.
@export_range(0.0, 1.0) var dirt := 0.0
## Object-space height (m above the wheel centres) where grime stops.
@export var dirt_top := 0.3
@export var roll_per_g := 3.5
@export var pitch_per_g := 2.2
@export var max_angle := 6.0
@export var response := 7.0

## Turn signals / hazard lights (Blinker); TrafficDriver sets it.
var indicator := Blinker.OFF
## The merged far mesh of a traffic car (CarLod): gets the paint, grime and
## lamp states too, as instance uniforms.
var far_lods: Array[GeometryInstance3D] = []

var _vehicle: Vehicle
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO
## Per-car materials, by role: "paint", "stripe", "head", "tail", "reverse",
## "tyre" (missing roles are absent).
var _mats := {}
var _stripe_meshes: Array[MeshInstance3D] = []
var _rear_broken := false
var _front_broken := false
var _brake_on := -1.0
var _reverse_on := -1.0
var _blink_t := 0.0
var _blink_out := Vector2(-1.0, -1.0)
var _dirt_shown := -1.0
var _shadow: MeshInstance3D
var _shadow_strength := 0.0
var _glass_meshes: Array[MeshInstance3D] = []
var _dirt_timer := 0.0
var _cracked: ShaderMaterial
## The garage paint style (Loadout.paint_style(); {} = plain paint).
var _paint_style := {}

static var _shared := {}
## Vehicle scene -> its measured body lines (body_lines()).
static var _lines_cache := {}


func _ready() -> void:
	_vehicle = get_parent() as Vehicle
	var roots: Array[Node] = [self]
	if _vehicle:
		for child in _vehicle.get_children():
			if child is VehicleWheel:
				roots.append(child)
	_mats = apply_vehicle_materials(roots, paint_color, false, dirt_top)
	for mi in find_children("Stripes", "MeshInstance3D", true, false):
		_stripe_meshes.append(mi as MeshInstance3D)
	for mi in find_children("*", "MeshInstance3D", true, false):
		if _has_material(mi as MeshInstance3D, "Glass"):
			_glass_meshes.append(mi as MeshInstance3D)
	set_stripes(stripes)
	set_dirt(dirt)
	if _vehicle:
		_vehicle.vehicle_reset.connect(func() -> void:
			_acc = Vector3.ZERO
			_prev_vel = Vector3.ZERO)


## Swaps the imported vehicle materials under `roots` for the vehicle
## shaders, by contract name (ART_BIBLE.md §13). Paint, lamps and tyres get
## materials of their own (returned by role: "paint", "stripe", "head",
## "tail", "reverse", "tyre"; pass `made` to reuse a car's own); trim and
## intact glass are shared. `parked` cars keep their lamps dark. Used by
## vehicles and the parked-car props.
static func apply_vehicle_materials(roots: Array[Node], paint: Color, parked: bool, dirt_top := 0.3, made: Variant = null) -> Dictionary:
	if made == null:
		made = {}
	for root in roots:
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			meshes.append(root)
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat == null:
					continue
				var m := _material_for(mat, paint, parked, dirt_top, made)
				if m:
					mi.set_surface_override_material(i, m)
	return made


static func _material_for(mat: Material, paint: Color, parked: bool, dirt_top: float, made: Dictionary) -> Material:
	if mat is ShaderMaterial:
		return null  # already swapped
	var m := _swap_for(mat, paint, parked, dirt_top, made)
	if m and m.resource_name.is_empty():
		m.resource_name = mat.resource_name  # the contract name stays
	return m


static func _swap_for(mat: Material, paint: Color, parked: bool, dirt_top: float, made: Dictionary) -> Material:
	match String(mat.resource_name):
		"Paint":
			if not made.has("paint"):
				made["paint"] = paint_material(paint)
				(made["paint"] as ShaderMaterial).set_shader_parameter("dirt_top", dirt_top)
				(made["paint"] as ShaderMaterial).set_shader_parameter("dirt_bottom", dirt_top - 0.6)
			return made["paint"]
		"Stripe":
			if not made.has("stripe"):
				made["stripe"] = paint_material(PaintPalette.stripe_color(paint), true)
			return made["stripe"]
		"Glass":
			var opaque := (mat as BaseMaterial3D) != null and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			return _shared_material("glass_opaque" if opaque else "glass", GLASS_OPAQUE_SHADER if opaque else GLASS_SHADER)
		"Trim":
			return _shared_material("trim", TRIM_SHADER)
		"Interior":
			return _shared_material("interior", INTERIOR_SHADER)
		"Headlight", "TailLight", "ReverseLight":
			var role: String = {"Headlight": "head", "TailLight": "tail", "ReverseLight": "reverse"}[String(mat.resource_name)]
			if parked:
				var key := "parked_" + role
				if not _shared.has(key):
					var pm := _lamp_material(role)
					pm.set_shader_parameter("lights", 0.0)
					_shared[key] = pm
				return _shared[key]
			if not made.has(role):
				made[role] = _lamp_material(role)
			return made[role]
		"Tire":
			if parked:
				return _shared_material("tyre", TYRE_SHADER)
			if not made.has("tyre"):
				var tm := ShaderMaterial.new()
				tm.shader = TYRE_SHADER
				made["tyre"] = tm
			return made["tyre"]
		"NavLight":
			# A plane's position lights, strobes and beacon (dark when parked).
			if parked:
				if not _shared.has("parked_nav"):
					var nm := ShaderMaterial.new()
					nm.shader = NAV_SHADER
					nm.set_shader_parameter("lights", 0.0)
					_shared["parked_nav"] = nm
				return _shared["parked_nav"]
			if not made.has("nav"):
				var nm := ShaderMaterial.new()
				nm.shader = NAV_SHADER
				made["nav"] = nm
			return made["nav"]
		"PropBlur", "RotorBlur", "TailBlur":
			# A propeller's or rotor's blur disc (Aircraft / Helicopter set its
			# size and fade it in).
			var role: String = {"PropBlur": "prop", "RotorBlur": "rotor", "TailBlur": "tail_rotor"}[String(mat.resource_name)]
			if not made.has(role):
				var pm := ShaderMaterial.new()
				pm.shader = PROP_SHADER
				made[role] = pm
			return made[role]
	return null


static func _shared_material(key: String, shader: Shader) -> ShaderMaterial:
	if not _shared.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader
		_shared[key] = m
	return _shared[key]


static func _lamp_material(role: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LAMP_SHADER
	m.set_shader_parameter("lamp", {"head": 0, "tail": 1, "reverse": 2}[role])
	return m


## Car paint (ART_BIBLE.md §13): `col` with the clear coat, metallic if
## PaintPalette lists it so (car_paint.gdshader). Parked-car props use it too,
## so all paint matches. `plain` = stripes (no flakes or flop).
static func paint_material(col: Color, plain := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("paint_color", col)
	m.set_shader_parameter("metallic_amount", 0.0 if plain else PaintPalette.metallic_of(col))
	m.set_shader_parameter("plain", plain)
	return m


static func _has_material(mi: MeshInstance3D, mat_name: String) -> bool:
	if mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m and m.resource_name == mat_name:
			return true
	return false


## Gives wheel models fitted after _ready (garage wheels, WheelKit) this
## car's vehicle materials: its own tyre material, so dust and the tyre
## stripe show on them too.
func adopt_meshes(roots: Array[Node]) -> void:
	apply_vehicle_materials(roots, paint_color, false, dirt_top, _mats)


## A coloured band on the tyre sidewalls (garage tyre stripe), between two
## radii in wheel-model space (0.37 m round); equal radii = none.
func set_tyre_stripe(col: Color, radii: Vector2) -> void:
	if _mats.has("tyre"):
		var m := _mats["tyre"] as ShaderMaterial
		m.set_shader_parameter("stripe_color", col)
		m.set_shader_parameter("stripe_radii", radii)


## True if this model has optional racing stripes (works before _ready).
func has_stripes() -> bool:
	if not _stripe_meshes.is_empty():
		return true
	return not find_children("Stripes", "MeshInstance3D", true, false).is_empty()


## Shows or hides the racing stripes (if the model has them).
func set_stripes(on: bool) -> void:
	stripes = on
	for mi in _stripe_meshes:
		mi.visible = on


## The car's own paint material (dents swap meshes, not materials).
## This vehicle's own material for `role` ("paint", "nav", "prop", "head"...),
## or null if its model has none.
func material(role: String) -> ShaderMaterial:
	return _mats.get(role) as ShaderMaterial


func paint() -> ShaderMaterial:
	return _mats.get("paint")


## Smashed tail and reverse lamps stay dark (VehicleDamage).
func set_rear_lights_broken(broken: bool) -> void:
	_rear_broken = broken
	for role in ["tail", "reverse"]:
		if _mats.has(role):
			(_mats[role] as ShaderMaterial).set_shader_parameter("broken", 1.0 if broken else 0.0)


## Smashed headlights (and front indicators) go dark (VehicleDamage).
func set_front_lights_broken(broken: bool) -> void:
	_front_broken = broken
	if _mats.has("head"):
		(_mats["head"] as ShaderMaterial).set_shader_parameter("broken", 1.0 if broken else 0.0)


func front_lights_broken() -> bool:
	return _front_broken


## Cracks the glass in a spiderweb centred on `world_pos` (moved to the
## nearest glass vertex by VehicleDamage), or mends it (`on` false).
func set_glass_cracked(on: bool, world_pos := Vector3.ZERO) -> void:
	for mi in _glass_meshes:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null or src.resource_name != "Glass":
				continue
			if not on:
				var opaque := (src as BaseMaterial3D) != null and (src as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				mi.set_surface_override_material(i, _shared_material("glass_opaque" if opaque else "glass", GLASS_OPAQUE_SHADER if opaque else GLASS_SHADER))
				continue
			var shared := mi.get_surface_override_material(i) as ShaderMaterial
			if _cracked == null and shared:
				_cracked = shared.duplicate() as ShaderMaterial
				_cracked.resource_name = "Glass"
			if _cracked:
				_cracked.set_shader_parameter("crack", 1.0)
				_cracked.set_shader_parameter("crack_center", mi.global_transform.affine_inverse() * world_pos)
				mi.set_surface_override_material(i, _cracked)


## Repaints the car (works before or after it enters the tree).
func set_paint_color(c: Color) -> void:
	paint_color = c
	_apply_finish()
	if _mats.has("stripe"):
		(_mats["stripe"] as ShaderMaterial).set_shader_parameter("paint_color", PaintPalette.stripe_color(c))
	_far("paint_color", c)
	_far("paint_metallic", PaintPalette.metallic_of(c))


## CarLod's far mesh for this car: it gets this car's paint and grime now, and
## its lamp states from the next frame on.
func add_far_lod(gi: GeometryInstance3D) -> void:
	far_lods.append(gi)
	_far("paint_color", paint_color)
	_far("paint_metallic", PaintPalette.metallic_of(paint_color))
	_far("dirt", dirt)
	_brake_on = -1.0
	_reverse_on = -1.0
	_blink_out = Vector2(-1.0, -1.0)


func _far(param: StringName, value: Variant) -> void:
	for gi in far_lods:
		if is_instance_valid(gi):
			gi.set_instance_shader_parameter(param, value)


## The garage paint: finish, two-tone, side decal and race number (a
## Loadout.paint_style() Dictionary; {} = the plain paint every car has).
## Only a car that needs it gets the custom paint shader.
func set_paint_style(style: Dictionary) -> void:
	_paint_style = style
	var m := _mats.get("paint") as ShaderMaterial
	if m == null:
		return
	var custom := not style.is_empty()
	var want: Shader = PAINT_CUSTOM_SHADER if custom else PAINT_SHADER
	if m.shader != want:
		var keep := {}
		for u: Dictionary in m.shader.get_shader_uniform_list():
			keep[u["name"]] = m.get_shader_parameter(u["name"])
		m.shader = want
		for k: String in keep:
			if keep[k] != null:
				m.set_shader_parameter(k, keep[k])
	_apply_finish()
	if not custom:
		return
	var lines := body_lines()
	m.set_shader_parameter("body_lines", lines["lines"])
	m.set_shader_parameter("body_ends", lines["ends"])
	m.set_shader_parameter("tone_mode", style["tone_mode"])
	m.set_shader_parameter("tone_color", style["tone_color"])
	var row: int = style["decal_row"]
	var decal: Dictionary = PartsCatalog.DECALS[0]
	for o: Dictionary in PartsCatalog.DECALS:
		if o["row"] == row:
			decal = o
	m.set_shader_parameter("decal_row", row)
	m.set_shader_parameter("decal_rows", PartsCatalog.DECALS.size() - 1)
	m.set_shader_parameter("decal_mode", decal.get("mode", 0))
	m.set_shader_parameter("decal_color", style["decal_color"])
	m.set_shader_parameter("decal_atlas", DECAL_ATLAS)
	var dc: Color = style["decal_color"]
	m.set_shader_parameter("number", style["number"])
	m.set_shader_parameter("number_color", Color(0.11, 0.11, 0.12) if dc.get_luminance() > 0.6 else dc)
	m.set_shader_parameter("number_place", lines["number"])
	m.set_shader_parameter("number_y", lines["number_y"])
	m.set_shader_parameter("side_bottom", lines["side_bottom"])
	m.set_shader_parameter("digits", DIGITS)


## Puts the paint finish on the paint material: the colour's own (solid or
## metallic, PaintPalette) unless the garage picked one.
func _apply_finish() -> void:
	var m := _mats.get("paint") as ShaderMaterial
	if m == null:
		return
	var f: Dictionary = _paint_style.get("finish", {})
	var c := paint_color
	var custom := not _paint_style.is_empty()
	if f.is_empty() or f["id"] == "stock":
		m.set_shader_parameter("paint_color", c)
		m.set_shader_parameter("metallic_amount", PaintPalette.metallic_of(c))
		m.set_shader_parameter("solid_roughness", 0.13)
		m.set_shader_parameter("metallic_roughness", 0.2)
		m.set_shader_parameter("clearcoat_amount", 0.6)
		if custom:
			m.set_shader_parameter("pearl", 0.0)
			m.set_shader_parameter("flakes", 1.0)
		return
	var chrome: float = f.get("chrome", 0.0)
	# Chrome is a tinted mirror: metal reflects its albedo, so lighten it.
	m.set_shader_parameter("paint_color", c.lerp(Color(0.94, 0.94, 0.95), 0.55) if chrome > 0.0 else c)
	m.set_shader_parameter("metallic_amount", f["metal"])
	m.set_shader_parameter("solid_roughness", f["rough"])
	m.set_shader_parameter("metallic_roughness", f["rough"])
	m.set_shader_parameter("clearcoat_amount", f["coat"])
	m.set_shader_parameter("flakes", 0.0 if chrome > 0.0 else 1.0)
	var pearl: float = f.get("pearl", 0.0)
	m.set_shader_parameter("pearl", pearl)
	if pearl > 0.0:
		# A lighter tint a little further round the colour wheel.
		m.set_shader_parameter("pearl_color", Color.from_hsv(fposmod(c.h + 0.06, 1.0), c.s * 0.6, minf(c.v * 1.2 + 0.2, 1.0)))


## Lines on this vehicle's body, in model space, for the custom paint:
## "lines" = (belt, roof, windscreen base z, rear window base z), "ends" =
## (underbody y, nose z, tail z), "number" = the race-number places
## (door roundel centre z and diameter, bonnet roundel centre z and
## diameter or 0). Measured from the stock model's glass and shell (once
## per vehicle scene).
func body_lines() -> Dictionary:
	var key := _vehicle.scene_file_path if _vehicle else ""
	if key != "" and _lines_cache.has(key):
		return _lines_cache[key]
	var all := AABB()
	var glass := AABB()
	var side := AABB()  # side windows only (windscreens can dip much lower)
	var painted := AABB()  # the paint (a monster truck's chassis hangs far below it)
	var have := [false, false, false, false]
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or String(get_path_to(mi)).begins_with("Kit/") or mi.name == "Stripes":
			continue
		var xf := _transform_to(mi, self)
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var arrays := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var is_glass := src != null and src.resource_name == "Glass"
			var is_paint := src != null and src.resource_name == "Paint"
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if is_glass else PackedVector3Array()
			for k in verts.size():
				var p := xf * verts[k]
				all = _grow(all, p, have, 0)
				if is_paint:
					painted = _grow(painted, p, have, 3)
				if is_glass:
					glass = _grow(glass, p, have, 1)
					if k < normals.size() and absf((xf.basis * normals[k]).normalized().x) > 0.7:
						side = _grow(side, p, have, 2)
	if not have[2]:
		side = glass
		have[2] = have[1]
	var floor_y := all.position.y
	var nose := all.position.z
	var tail := all.end.z
	var roof := glass.end.y if have[1] else all.end.y + 10.0
	# Glass doors (bus, truck cab) reach far lower than the windows: never
	# put the belt below 42% of the way up to the roof.
	var belt := side.position.y if have[2] else lerpf(all.position.y, all.end.y, 0.45)
	belt = maxf(belt, lerpf(floor_y, minf(roof, all.end.y), 0.42))
	var ws := glass.position.z if have[1] else lerpf(nose, tail, 0.3)
	var rw := glass.end.z if have[1] else tail
	# Side graphics and numbers go on the painted side, sill to belt.
	var y0 := (painted.position.y if have[3] else floor_y) + 0.07
	var h := maxf(belt - 0.03 - y0, 0.1)
	var door_d := minf(h * 0.85, 0.62)
	var door_y := y0 + h * 0.5
	var z0 := side.position.z if have[2] else nose
	var z1 := side.end.z if have[2] else tail
	var door_z := lerpf(z0, z1, 0.3) if have[2] else lerpf(nose, tail, 0.4)
	# Slide the door roundel clear of a wheel it would overlap: toward the
	# middle of the car if that stays along the windows, else the other way.
	if _vehicle:
		for w in _vehicle.wheels:
			var gap := w.radius + door_d * 0.5 + 0.05
			if absf(w.position.z - door_z) >= gap or door_y - door_d * 0.5 > w.position.y + w.radius:
				continue
			var inward := w.position.z - signf(w.position.z) * gap
			if inward >= z0 - 0.1 and inward <= z1 + 0.1:
				door_z = inward
				continue
			# No room toward the middle (a cab-over truck's door is right
			# over the wheel): fit it, smaller, on the flat side between
			# the wheel and the end of the body.
			var arch := w.position.z + signf(w.position.z) * (w.radius + 0.05)
			var end := (nose + 0.35) if w.position.z < 0.0 else (tail - 0.35)
			door_d = clampf(absf(arch - end), 0.24, door_d)
			door_z = (arch + end) * 0.5
	var hood := ws - nose
	var hood_d := minf(hood * 0.36, 0.55) if hood > 0.9 else 0.0
	var out := {
		"lines": Vector4(belt, roof, ws, rw),
		"ends": Vector3(floor_y, nose, tail),
		"side_bottom": y0,
		"number": Vector4(door_z, door_d, lerpf(nose, ws, 0.55), hood_d),
		"number_y": door_y,
	}
	if key != "":
		_lines_cache[key] = out
	return out


static func _grow(box: AABB, p: Vector3, have: Array, k: int) -> AABB:
	if not have[k]:
		have[k] = true
		return AABB(p, Vector3.ZERO)
	return box.expand(p)


## `n`'s transform relative to `root` (one of its ancestors).
static func _transform_to(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


## Sets the road grime (0 clean .. 1 filthy) on the paint and tyres.
func set_dirt(amount: float) -> void:
	dirt = clampf(amount, 0.0, 1.0)
	if absf(dirt - _dirt_shown) < 0.01:
		return
	_dirt_shown = dirt
	if _mats.has("paint"):
		(_mats["paint"] as ShaderMaterial).set_shader_parameter("dirt", dirt)
	if _mats.has("tyre"):
		(_mats["tyre"] as ShaderMaterial).set_shader_parameter("dust", clampf(dirt * 1.3, 0.0, 1.0))
	_far("dirt", dirt)


func _physics_process(dt: float) -> void:
	if _vehicle == null:
		return
	var v := _vehicle.linear_velocity
	var acc := (v - _prev_vel) / dt
	_prev_vel = v
	var local := _vehicle.global_basis.inverse() * acc
	if _vehicle.grounded_wheels < 3:
		local = Vector3.ZERO
	# Ignore spikes from impacts/landings.
	local = local.limit_length(20.0)
	_acc = _acc.lerp(local, 1.0 - exp(-response * dt))
	var roll := clampf(roll_per_g * _acc.x / 9.81, -max_angle, max_angle)
	var pitch := clampf(-pitch_per_g * _acc.z / 9.81, -max_angle, max_angle)
	rotation = Vector3(deg_to_rad(pitch), 0.0, deg_to_rad(roll))


# Lamps, grime and the contact shadow only change what's drawn: once per
# frame is enough (physics ticks twice as often).
func _process(dt: float) -> void:
	if _vehicle == null:
		return
	_update_lamps(dt)
	_dirt_timer -= dt
	if _dirt_timer <= 0.0:
		_dirt_timer = 0.25
		_update_dirt(0.25, _vehicle.linear_velocity.length())
	_update_shadow(dt)


func _update_lamps(dt: float) -> void:
	var brake := 1.0 if _vehicle.is_braking else 0.0
	if brake != _brake_on and _mats.has("tail"):
		_brake_on = brake
		(_mats["tail"] as ShaderMaterial).set_shader_parameter("brake", brake)
		_far("brake", brake)
	var rev := 1.0 if _vehicle.gear == -1 else 0.0
	if rev != _reverse_on and _mats.has("reverse"):
		_reverse_on = rev
		(_mats["reverse"] as ShaderMaterial).set_shader_parameter("reverse", rev)
		_far("reverse", rev)
	# Indicators: about 85 flashes a minute, a quick bulb ramp on and off.
	var out := Vector2.ZERO
	if indicator != Blinker.OFF:
		_blink_t = fmod(_blink_t + dt, 0.7)
		var lit := smoothstep(0.0, 0.04, _blink_t) * (1.0 - smoothstep(0.36, 0.42, _blink_t))
		out = Vector2(lit if indicator != Blinker.RIGHT else 0.0, lit if indicator != Blinker.LEFT else 0.0)
	else:
		_blink_t = 0.0
	if not out.is_equal_approx(_blink_out):
		_blink_out = out
		for role in ["head", "tail"]:
			if _mats.has(role):
				var m := _mats[role] as ShaderMaterial
				m.set_shader_parameter("blink_left", out.x)
				m.set_shader_parameter("blink_right", out.y)
		_far("blink", out)


## Driving on dirt slowly dusts the car up (never washes off by itself).
func _update_dirt(dt: float, speed: float) -> void:
	if speed < 3.0 or not _mats.has("paint"):
		return
	var on_dirt := 0
	for w in _vehicle.wheels:
		if w.grounded and w.surface_grip < 0.95:
			on_dirt += 1
	if on_dirt > 0:
		set_dirt(dirt + dt * 0.012 * (on_dirt / 4.0) * clampf(speed / 12.0, 0.3, 1.5))


## A soft dark patch under the car on the ground, fading out in the air.
func _update_shadow(dt: float) -> void:
	if _shadow == null:
		_make_shadow()
	var y := 0.0
	var n := 0
	for w in _vehicle.wheels:
		if w.grounded:
			# The suspension ray runs straight down the body's up axis.
			y += w.position.y - (w.suspension_travel + w.radius - w.compression)
			n += 1
	if n > 0:
		_shadow.position.y = y / n + 0.03
	var want := float(n) / maxf(_vehicle.wheels.size(), 1.0)
	var s := move_toward(_shadow_strength, want, dt * 4.0)
	if s != _shadow_strength:
		_shadow_strength = s
		_shadow.set_instance_shader_parameter("strength", s)
		_shadow.visible = s > 0.01


func _make_shadow() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	var quad := PlaneMesh.new()
	quad.size = Vector2(_vehicle.body_half_width * 2.0 + 0.3, _vehicle.body_length() + 0.35)
	var m := _shared_material("contact_shadow", SHADOW_SHADER)
	quad.material = m
	_shadow.mesh = quad
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.layers = Vehicle.VISUAL_LAYER
	_shadow.visibility_range_end = 90.0
	_shadow.position = Vector3(0.0, -_vehicle.ride_height(), (_vehicle.body_rear - _vehicle.body_front) * 0.5)
	_vehicle.add_child(_shadow)
