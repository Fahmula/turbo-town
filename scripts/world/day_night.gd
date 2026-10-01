class_name DayNight
extends Node
## Time of day: moves the sun (and a moon at night), recolours the sky, fog
## and ambient light, lights building windows, shows stars, and switches the
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
	[8.5, Color(0.239, 0.486, 0.788), Color(0.839, 0.89, 0.925), Color(1.0, 0.95, 0.86), 1.4, Color(0.62, 0.74, 0.95), 0.65, Color(0.8, 0.86, 0.92)],
	[16.5, Color(0.239, 0.486, 0.788), Color(0.839, 0.89, 0.925), Color(1.0, 0.95, 0.86), 1.4, Color(0.62, 0.74, 0.95), 0.65, Color(0.8, 0.86, 0.92)],
	[17.9, Color(0.227, 0.29, 0.549), Color(0.949, 0.651, 0.42), Color(1.0, 0.6, 0.35), 1.2, Color(0.55, 0.55, 0.75), 0.5, Color(0.92, 0.66, 0.5)],
	[19.8, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
	[24.0, Color(0.027, 0.043, 0.102), Color(0.102, 0.133, 0.22), Color(0.55, 0.65, 1.0), 0.22, Color(0.3, 0.38, 0.62), 0.35, Color(0.07, 0.09, 0.15)],
]
## Colour of the ground half of the sky (what car paint and glass reflect
## below the horizon): earthy, scaled by how bright the light is.
const GROUND_BOUNCE := Color(0.38, 0.38, 0.35)

var hour := 13.0
var cycling := false
var is_night := false

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _buildings: ShaderMaterial
var _clouds: BaseMaterial3D
var _cloud_day := Color.WHITE
var _cloud_glow := Color.BLACK
var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D


func setup(world: Node) -> void:
	_sun = world.get_node_or_null("Sun") as DirectionalLight3D
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env.sky:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_buildings = load("res://assets/materials/building.tres") as ShaderMaterial
	_clouds = load("res://assets/materials/cloud.tres") as BaseMaterial3D
	if _clouds:
		_cloud_day = _clouds.albedo_color
		_cloud_glow = _clouds.emission
	_make_stars()


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
	if _sun:
		# The sun crosses from east to west; below the horizon a moon takes over.
		var az := deg_to_rad(lerpf(-100.0, 100.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0)))
		var light_elev := elev
		if elev < 4.0:
			az = deg_to_rad(-30.0)
			light_elev = lerpf(4.0, 38.0, smoothstep(4.0, -10.0, elev))
		# Arc through the southern (+Z) sky, like the hand-placed daytime sun.
		var dir := Vector3(sin(az) * cos(deg_to_rad(light_elev)), sin(deg_to_rad(light_elev)), cos(az) * cos(deg_to_rad(light_elev)) * 0.6)
		_sun.global_basis = Basis.looking_at(-dir.normalized(), Vector3.UP)
		_sun.light_color = k[2]
		_sun.light_energy = k[3]
	if _sky:
		_sky.sky_top_color = k[0]
		_sky.sky_horizon_color = k[1]
		_sky.ground_horizon_color = k[1]
		_sky.ground_bottom_color = (k[1] as Color).lerp(GROUND_BOUNCE * clampf(k[3] / 1.4, 0.1, 1.0), 0.75)
	if _env:
		_env.ambient_light_color = k[4]
		_env.ambient_light_energy = k[5]
		_env.fog_light_color = k[6]
	var night_amount := smoothstep(3.0, -6.0, elev)
	if _buildings:
		_buildings.set_shader_parameter("night", night_amount)
	if _clouds:
		# Clouds pick up the sky's colour: grey-blue at night, pink at sunset.
		_clouds.albedo_color = _cloud_day.lerp(Color(0.12, 0.14, 0.22), night_amount).lerp((k[1] as Color) * 1.15, 0.25 * (1.0 - night_amount) * smoothstep(20.0, 2.0, absf(elev)))
		_clouds.emission = _cloud_glow.lerp(Color(0.02, 0.025, 0.05), night_amount)
	if _stars:
		_stars.visible = night_amount > 0.05
		_star_mat.albedo_color = Color(1, 1, 1, night_amount)
	var night := elev < 1.5
	if night != is_night:
		is_night = night
		get_tree().call_group("night_lights", "set_night", night)
		night_changed.emit(night)


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
