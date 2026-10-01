class_name GraphicsQuality
extends RefCounted
## Graphics presets for the Settings menu. High is how the game was tuned;
## Medium and Low trade shadows, ambient occlusion, anti-aliasing and render
## resolution for frame rate (useful on the Steam Deck's battery).

const LOW := 0
const MEDIUM := 1
const HIGH := 2


static func apply(level: int, viewport: Viewport, world: Node) -> void:
	var env_node := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	var env := env_node.environment if env_node else null

	if env:
		env.ssao_enabled = level >= HIGH
		env.glow_enabled = level >= MEDIUM
	if sun:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if level >= MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = [140.0, 200.0, 260.0][level]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][level])

	viewport.msaa_3d = Viewport.MSAA_DISABLED if level == LOW else Viewport.MSAA_2X
	if level == LOW:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = 0.75
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
