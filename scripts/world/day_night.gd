class_name DayNight
extends Node
## Time of day: moves the sun (and a moon at night), crossfades the real
## photographed skies (SKY_KEYS, SkyCatalog), recolours the fog and ambient
## light, lights building windows, shows stars, and switches the
## "night_lights" group (street lamps, the lighthouse beam...) on after dark.
## Settings: Day / Sunset / Night, or Cycle (a whole day in DAY_MINUTES).

signal night_changed(is_night: bool)

const DAY_MINUTES := 12.0
## Fixed times for the non-cycling settings.
const PRESET_HOURS := [15.0, 17.75, 23.0]

## Palette keyframes by hour: [hour, sky top, sky horizon, light colour,
## light energy, ambient colour, ambient energy, fog colour]
## Warm sun, cool sky-blue ambient (so shadows read cool), fog close to the
## horizon colour so distance fades into haze. See ART_BIBLE.md §9 and §11.
const KEYS := [
	[0.0, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
	[5.0, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
	[6.5, Color(0.25, 0.32, 0.58), Color(0.95, 0.68, 0.5), Color(1.0, 0.62, 0.38), 0.9, Color(0.58, 0.56, 0.72), 0.5, Color(0.88, 0.7, 0.6)],
	[8.5, Color(0.239, 0.486, 0.788), Color(0.839, 0.89, 0.925), Color(1.0, 0.95, 0.86), 1.4, Color(0.86, 0.88, 0.92), 0.9, Color(0.8, 0.86, 0.92)],
	[16.5, Color(0.239, 0.486, 0.788), Color(0.839, 0.89, 0.925), Color(1.0, 0.95, 0.86), 1.4, Color(0.86, 0.88, 0.92), 0.9, Color(0.8, 0.86, 0.92)],
	[17.9, Color(0.227, 0.29, 0.549), Color(0.949, 0.651, 0.42), Color(1.0, 0.6, 0.35), 1.2, Color(0.55, 0.55, 0.75), 0.5, Color(0.92, 0.66, 0.5)],
	[19.8, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
	[24.0, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
]
## Colour of the ground half of the sky (what car paint and glass reflect
## below the horizon): earthy, scaled by how bright the light is.
const GROUND_BOUNCE := Color(0.38, 0.38, 0.35)
## Real skies (assets/textures/sky/sky_<name>.jpg, SkyCatalog) through the
## day: [hour, sky, median brightness (linear)]. Between two keys the skies
## crossfade; at a key the sun (or moon) is as high as in that photo, and the
## photo is turned so its sun is where the light comes from.
const SKY_KEYS := [
	[0.0, "night", 0.07],
	[5.2, "night", 0.07],
	[6.4, "dawn", 0.22],
	[8.5, "morning", 0.42],
	[11.0, "day", 0.45],
	[16.5, "day", 0.45],
	[17.75, "sunset", 0.34],
	[18.6, "dusk", 0.13],
	[19.8, "night", 0.07],
	[24.0, "night", 0.07],
]

var hour := 13.0
var cycling := false
var is_night := false

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var _sky_tex := {}


func setup(world: Node) -> void:
	_sun = world.get_node_or_null("Sun") as DirectionalLight3D
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	_make_stars()
	# Bulk-instanced things (trees, shrubs, scattered rocks) stay out of the
	# bounce-light volume (SDFGI on High): alpha-tested leaves voxelised into
	# it darken the canopies from the inside. They still receive its light.
	for mmi in world.find_children("*", "MultiMeshInstance3D", true, false):
		(mmi as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func set_mode(mode: int) -> void:
	cycling = mode >= PRESET_HOURS.size()
	hour = 9.0 if cycling else PRESET_HOURS[mode]
	_apply()


func _process(dt: float) -> void:
	if cycling and not get_tree().paused:
		hour = fposmod(hour + dt * 24.0 / (DAY_MINUTES * 60.0), 24.0)
		_apply()
	if _stars and _stars.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_stars.global_position = cam.global_position


## Sun height in degrees (negative = below the horizon).
func sun_elevation() -> float:
	return sin((hour - 6.0) / 12.0 * PI) * 62.0


func _apply() -> void:
	var k := _palette()
	var elev := sun_elevation()
	var sk := _sky_blend()
	var a: Dictionary = SkyCatalog.SKIES[sk[0]]
	var b: Dictionary = SkyCatalog.SKIES[sk[1]]
	var t: float = sk[2]
	# The sun crosses from east to west; below the horizon a moon takes over.
	# Its height comes from the photographed skies.
	var az := deg_to_rad(lerpf(-100.0, 100.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0)))
	if elev < 4.0:
		az = deg_to_rad(-30.0)
	var light_elev := deg_to_rad(maxf(lerpf(a["sun_el"], b["sun_el"], t), 3.0))
	# Arc through the southern (+Z) sky, like the hand-placed daytime sun.
	var dir := Vector3(sin(az) * cos(light_elev), sin(light_elev), cos(az) * cos(light_elev) * 0.6).normalized()
	if _sun:
		_sun.global_basis = Basis.looking_at(-dir, Vector3.UP)
		_sun.light_color = k[2]
		_sun.light_energy = k[3]
	var horizon: Color = (a["horizon"] as Color) * float(sk[3]) * (1.0 - t) + (b["horizon"] as Color) * float(sk[4]) * t
	if _sky:
		# Turn each photo so its sun lines up with the light.
		var light_az := atan2(dir.x, -dir.z)
		_sky.set_shader_parameter("sky_a", _sky_texture(sk[0]))
		_sky.set_shader_parameter("sky_b", _sky_texture(sk[1]))
		_sky.set_shader_parameter("sky_mix", t)
		_sky.set_shader_parameter("energy_a", a["energy"] * sk[3])
		_sky.set_shader_parameter("energy_b", b["energy"] * sk[4])
		_sky.set_shader_parameter("rot_a", float(a["sun_az"]) - light_az)
		_sky.set_shader_parameter("rot_b", float(b["sun_az"]) - light_az)
		var ground := (GROUND_BOUNCE.srgb_to_linear() * clampf(k[3] / 1.4, 0.1, 1.0))
		_sky.set_shader_parameter("ground_bottom", Vector3(ground.r, ground.g, ground.b))
		_sky.set_shader_parameter("disc", 0.0)
		_sky.set_shader_parameter("haze", Vector3(minf(horizon.r, 1.0), minf(horizon.g, 1.0), minf(horizon.b, 1.0)))
	if _env:
		_env.ambient_light_color = k[4]
		_env.ambient_light_energy = k[5]
		# Haze takes the colour of the sky at the horizon.
		var fog := Color(minf(horizon.r, 1.0), minf(horizon.g, 1.0), minf(horizon.b, 1.0)).linear_to_srgb()
		_env.fog_light_color = fog
	var night_amount := smoothstep(3.0, -6.0, elev)
	RenderingServer.global_shader_parameter_set("night", night_amount)
	if _stars:
		_stars.visible = night_amount > 0.05
		_star_mat.albedo_color = Color(1, 1, 1, night_amount)
	var night := elev < 1.5
	if night != is_night:
		is_night = night
		get_tree().call_group("night_lights", "set_night", night)
		night_changed.emit(night)


## The two skies to show now: [sky a, sky b, mix 0-1, brightness a, brightness b].
func _sky_blend() -> Array:
	for i in SKY_KEYS.size() - 1:
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if hour >= a[0] and hour <= b[0]:
			var t := smoothstep(a[0], b[0], hour) if a[1] != b[1] else 0.0
			return [a[1], b[1], t, a[2], b[2]]
	return ["day", "day", 0.0, 0.45, 0.45]


func _sky_texture(sky_name: String) -> Texture2D:
	if not _sky_tex.has(sky_name):
		_sky_tex[sky_name] = load("res://assets/textures/sky/sky_%s.jpg" % sky_name)
	return _sky_tex[sky_name]


## Colours for the current hour, blended between keyframes.
func _palette() -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if hour >= a[0] and hour <= b[0]:
			var t := smoothstep(a[0], b[0], hour)
			var out := []
			for j in range(1, a.size()):
				if a[j] is Color:
					out.append((a[j] as Color).lerp(b[j], t))
				else:
					out.append(lerpf(a[j], b[j], t))
			return out
	return KEYS[0].slice(1)


func _make_stars() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(6.0, 6.0)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.disable_fog = true
	mesh.material = _star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 500
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.08, 1.0), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.5, 1.4)), d * 2200.0))
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.visible = false
	add_child(_stars)
