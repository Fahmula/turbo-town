class_name GraphicsQuality
extends RefCounted
## Graphics presets for the Settings menu. Ultra is the full look for a
## desktop GPU; High is tuned for the Steam Deck (the same materials, grass
## and trees, without the heaviest lighting); Medium and Low trade shadows,
## ambient occlusion, anti-aliasing and render resolution for frame rate.
## Measured with `--perfsweep` (ART_BIBLE.md §27).

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const ULTRA := 3


static func apply(level: int, viewport: Viewport, world: Node) -> void:
	var env_node := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	var env := env_node.environment if env_node else null

	if env:
		env.ssao_enabled = level >= HIGH
		env.glow_enabled = level >= MEDIUM
		# Ultra only: on the Steam Deck these took High from 60 to about 30 fps,
		# and SDFGI (bounce light, sky occlusion) caused the worst drops while
		# driving, because it re-voxelises as the camera moves. SSIL adds little
		# without SDFGI and cost ~6 ms on a Deck-class GPU while driving.
		env.ssil_enabled = level >= ULTRA
		env.sdfgi_enabled = level >= ULTRA
		# Without SDFGI the ambient is the sky's colour plus DayNight's: too
		# much sky turns shadows blue (ART_BIBLE.md §9), so lean on DayNight's.
		env.ambient_light_sky_contribution = 0.6 if level >= ULTRA else 0.3
		env.ssr_enabled = level >= ULTRA
		env.volumetric_fog_enabled = level >= ULTRA
	if sun:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if level >= MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = [140.0, 200.0, 260.0, 260.0][level]
		# Low's coarser shadow map stripes the ground under a low sun (acne).
		sun.shadow_normal_bias = [4.0, 2.0, 2.0, 2.0][level]
		# The sun's real size (PCSS): shadows sharp at the contact, softer
		# further out. Up to 10 ms on a Deck-class GPU, so Ultra only.
		sun.light_angular_distance = 0.6 if level >= ULTRA else 0.0
	# World shaders drop their detail texture samples on Low
	# (world_common.gdshaderinc); Ultra uses the same materials as High.
	RenderingServer.global_shader_parameter_set("quality", mini(level, HIGH))
	# Ambient occlusion: the low preset on High (Deck), medium on Ultra.
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM if level >= ULTRA else RenderingServer.ENV_SSAO_QUALITY_LOW,
		true, 0.5, 2, 50.0, 300.0)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 4096][level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][level])

	viewport.msaa_3d = Viewport.MSAA_DISABLED if level == LOW else Viewport.MSAA_2X
	if level == LOW:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = 0.75
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0

	# Downtown MegaKit buildings (experiment): on Medium and Low a building
	# near the camera casts its shadow from its far-LOD proxy (a shadows-only
	# copy, DowntownBlock) instead of every window frame and cornice; High
	# and Ultra cast from the full mesh.
	var tree := world.get_tree() if world and world.is_inside_tree() else null
	if tree:
		var full := level >= HIGH
		for n in tree.get_nodes_in_group(&"megakit_near"):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if full \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for n in tree.get_nodes_in_group(&"megakit_shadow_proxy"):
			(n as GeometryInstance3D).visible = not full
