class_name PedestrianLook
extends RefCounted
## What pedestrians look like (ART_BIBLE.md §34, "Pedestrians"): the people in
## pedestrians.glb (tools/blender/make_pedestrians.py) and the colours they
## wear. build() makes one person's model; dress() turns it into someone new:
## a look, a height, skin, hair and clothes colours (instance uniforms of
## pedestrian.gdshader, so the whole crowd shares one material).
##
## Clothes are everyday, medium-to-low saturation colours: the world is
## naturalistic (§0 rule 2), and the players' own shirts (red-orange, player
## 2's blue) must still stand out in a crowd. Albedo stays within sRGB
## 0.11-0.94.

const SCENE := preload("res://assets/models/character/pedestrians.glb")
const SHADER := preload("res://assets/shaders/pedestrian.gdshader")

## The people (mesh "Ped_<name>"). fem: a woman (heights); top/bottom: the
## garments (their roughness, and whether a skirt or dress takes the "dress"
## colours); formal: chance of the formal walk; jog: chance of jogging; old:
## chance of grey hair; cap/zip: what the accent colour is.
const LOOKS := [
	{"name": "tee_jeans_m", "fem": false, "top": "tee", "bottom": "jeans", "formal": 0.05, "jog": 0.1, "old": 0.12},
	{"name": "long_chinos_m", "fem": false, "top": "long", "bottom": "chinos", "formal": 0.3, "jog": 0.0, "old": 0.2},
	{"name": "tee_shorts_heavy", "fem": false, "top": "tee", "bottom": "shorts", "formal": 0.0, "jog": 0.0, "old": 0.25, "cap": true},
	{"name": "jacket_m", "fem": false, "top": "jacket", "bottom": "chinos", "formal": 0.7, "jog": 0.0, "old": 0.45, "zip": true},
	{"name": "tee_jeans_f", "fem": true, "top": "tee", "bottom": "jeans", "formal": 0.1, "jog": 0.1, "old": 0.1},
	{"name": "dress_f", "fem": true, "top": "dress", "bottom": "", "formal": 0.5, "jog": 0.0, "old": 0.15},
	{"name": "long_skirt_f", "fem": true, "top": "long", "bottom": "skirt", "formal": 0.6, "jog": 0.0, "old": 0.35},
	{"name": "tank_shorts_f", "fem": true, "top": "tank", "bottom": "shorts", "formal": 0.0, "jog": 0.5, "old": 0.0},
]

## Skin tones, light to deep.
const SKINS := [Color(0.92, 0.77, 0.66), Color(0.86, 0.68, 0.55), Color(0.76, 0.56, 0.44),
	Color(0.64, 0.45, 0.33), Color(0.50, 0.34, 0.24), Color(0.36, 0.24, 0.17)]
const HAIR := [Color(0.12, 0.10, 0.09), Color(0.21, 0.14, 0.10), Color(0.33, 0.21, 0.13),
	Color(0.46, 0.24, 0.13), Color(0.70, 0.55, 0.32), Color(0.53, 0.39, 0.24)]
const HAIR_OLD := [Color(0.60, 0.59, 0.58), Color(0.78, 0.77, 0.75), Color(0.44, 0.42, 0.40)]
const TOPS := [Color(0.86, 0.85, 0.82), Color(0.20, 0.22, 0.27), Color(0.18, 0.24, 0.38),
	Color(0.52, 0.54, 0.56), Color(0.45, 0.52, 0.36), Color(0.55, 0.22, 0.26), Color(0.80, 0.65, 0.26),
	Color(0.25, 0.50, 0.52), Color(0.80, 0.58, 0.62), Color(0.56, 0.68, 0.80), Color(0.22, 0.40, 0.29),
	Color(0.68, 0.58, 0.46), Color(0.45, 0.34, 0.55), Color(0.90, 0.80, 0.48)]
## Dresses and skirts: a few brighter, summery ones as well.
const DRESSES := [Color(0.18, 0.24, 0.38), Color(0.55, 0.22, 0.26), Color(0.80, 0.58, 0.62),
	Color(0.25, 0.50, 0.52), Color(0.86, 0.72, 0.40), Color(0.45, 0.34, 0.55), Color(0.22, 0.40, 0.29),
	Color(0.84, 0.82, 0.76), Color(0.62, 0.74, 0.82), Color(0.20, 0.20, 0.22)]
const DENIM := [Color(0.21, 0.30, 0.46), Color(0.15, 0.19, 0.29), Color(0.42, 0.52, 0.66), Color(0.13, 0.13, 0.14)]
const CHINOS := [Color(0.66, 0.58, 0.42), Color(0.42, 0.43, 0.45), Color(0.17, 0.20, 0.32),
	Color(0.38, 0.40, 0.28), Color(0.38, 0.28, 0.20), Color(0.13, 0.13, 0.14)]
const SHOES := [Color(0.88, 0.87, 0.84), Color(0.88, 0.87, 0.84), Color(0.15, 0.15, 0.16),
	Color(0.55, 0.55, 0.56), Color(0.20, 0.24, 0.36), Color(0.62, 0.48, 0.34)]
const CAPS := [Color(0.18, 0.24, 0.38), Color(0.58, 0.20, 0.20), Color(0.14, 0.14, 0.15),
	Color(0.86, 0.85, 0.82), Color(0.84, 0.68, 0.22), Color(0.22, 0.40, 0.29)]
const ZIP := Color(0.70, 0.70, 0.72)
## Roughness of each top and bottom (cotton, nylon, denim...).
const TOP_ROUGH := {"tee": 0.85, "long": 0.85, "jacket": 0.55, "tank": 0.85, "dress": 0.75}
const BOTTOM_ROUGH := {"jeans": 0.8, "chinos": 0.8, "shorts": 0.8, "skirt": 0.78, "": 0.8}
## The model is this tall (m); people are scaled from it.
const MODEL_HEIGHT := 1.82
const MEN_HEIGHT := Vector2(1.70, 1.90)
const WOMEN_HEIGHT := Vector2(1.58, 1.76)

static var _meshes := {}
static var _material: ShaderMaterial


## Fills the shared mesh table and material (once).
static func _prepare() -> void:
	if _material != null:
		return
	var inst := SCENE.instantiate()
	var tex: Texture2D = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		_meshes[String(mi.name).trim_prefix("Ped_")] = m
		var src := m.surface_get_material(0) as BaseMaterial3D
		if src and src.albedo_texture:
			tex = src.albedo_texture
	inst.free()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("palette", tex)


## A person's model under `parent`: {"model", "skeleton", "mesh", "anim"}.
## Dress it before showing it.
static func build(parent: Node3D) -> Dictionary:
	_prepare()
	var model := Node3D.new()
	model.name = "Model"
	model.rotation.y = PI          # the model faces +Z; pedestrians face -Z
	parent.add_child(model)
	var inst := SCENE.instantiate() as Node3D
	inst.name = "Person"
	model.add_child(inst)
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var keep: MeshInstance3D = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if keep == null:
			keep = mi as MeshInstance3D
		else:
			mi.free()
	keep.name = "Body"
	keep.material_override = _material
	keep.layers = Vehicle.VISUAL_LAYER
	keep.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return {"model": model, "skeleton": sk, "mesh": keep, "anim": anim}


## Makes `mesh` someone new; returns who: {"look", "height", "formal", "jog", "fem"}.
static func dress(mesh: MeshInstance3D, model: Node3D, rng: RandomNumberGenerator, only := "") -> Dictionary:
	_prepare()
	var look: Dictionary = LOOKS[rng.randi() % LOOKS.size()]
	if only != "":
		for lk: Dictionary in LOOKS:
			if lk["name"] == only:
				look = lk
	mesh.mesh = _meshes[look["name"]]
	var fem: bool = look["fem"]
	var hr: Vector2 = WOMEN_HEIGHT if fem else MEN_HEIGHT
	var height := rng.randf_range(hr.x, hr.y)
	model.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	var old := rng.randf() < float(look["old"])
	var top_kind: String = look["top"]
	var bottom_kind: String = look["bottom"]
	var top: Color = _pick(DRESSES if top_kind == "dress" else TOPS, rng)
	var bottom: Color
	match bottom_kind:
		"jeans":
			bottom = _pick(DENIM, rng)
		"skirt":
			bottom = _pick(DRESSES, rng)
		"shorts":
			bottom = _pick(DENIM if rng.randf() < 0.5 else CHINOS, rng)
		_:
			bottom = _pick(CHINOS, rng)
	if bottom.is_equal_approx(top):
		bottom = bottom.darkened(0.35)
	var accent := ZIP
	if look.get("cap", false):
		accent = _pick(CAPS, rng)
	mesh.set_instance_shader_parameter("skin_color", _jitter(_pick(SKINS, rng), rng, 0.02))
	mesh.set_instance_shader_parameter("hair_color", _jitter(_pick(HAIR_OLD if old else HAIR, rng), rng, 0.02))
	mesh.set_instance_shader_parameter("top_color", _jitter(top, rng, 0.03))
	mesh.set_instance_shader_parameter("bottom_color", _jitter(bottom, rng, 0.03))
	mesh.set_instance_shader_parameter("shoe_color", _pick(SHOES, rng))
	mesh.set_instance_shader_parameter("accent_color", accent)
	mesh.set_instance_shader_parameter("cloth_rough", Vector2(TOP_ROUGH.get(top_kind, 0.85), BOTTOM_ROUGH.get(bottom_kind, 0.8)))
	return {"look": look["name"], "height": height, "fem": fem, "old": old,
		"formal": rng.randf() < float(look["formal"]), "jog": rng.randf() < float(look["jog"]) and not old}


static func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return list[rng.randi() % list.size()]


## A colour a little lighter or darker (and stays within sRGB 0.11-0.94).
static func _jitter(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var k := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + k, 0.11, 0.94), clampf(c.g + k, 0.11, 0.94), clampf(c.b + k, 0.11, 0.94))
