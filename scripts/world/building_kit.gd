@tool
class_name BuildingKit
extends RefCounted
## Buildings (ART_BIBLE.md §15).
## Every building has a base (plinth, shopfronts or a lobby, a fascia and a
## string course), a middle (window bays drawn by facade.gdshader) and a top
## (cornice or coping, parapet, roof clutter). Downtown towers stand on a
## stone podium and step back.
##
## Output: walls and trim in `facade` (facade.gdshader), roof clutter and
## awnings in `clutter` (street_props.gdshader), contact-shadow aprons in
## `ground` (paving.gdshader), box colliders on `body`.

enum Style { STUCCO, LIMESTONE, BRICK, CURTAIN, RIBBON }
const SHOPS := 8
## Facade style of flat roofs (facade.gdshader: roof membrane and ballast).
const ROOF_STYLE := 5
## Facade style of shop sign boards (facade.gdshader draws the word).
const SIGN_STYLE := 6
const SIGN_V0 := 3.725  # sign board: metres above the base, height, margin in bays
const SIGN_H := 0.5
const SIGN_MARGIN := 0.12
const GROUND_FLOOR := 4.6
const FLOOR := 3.4
const BAY := [3.0, 3.2, 2.9, 3.0, 3.0]
## Props shader material classes (street_props.gdshader).
const PAINTED := 0.0
const METAL := 1.0 / 15.0
const CONCRETE := 2.0 / 15.0
const RUBBER := 4.0 / 15.0
const GLASS := 5.0 / 15.0
const FABRIC := 12.0 / 15.0

var facade := MeshBuilder.new()
var clutter := MeshBuilder.new()
var ground: MeshBuilder
var body: StaticBody3D
var rng := RandomNumberGenerator.new()


func _init(ground_builder: MeshBuilder, collision: StaticBody3D) -> void:
	ground = ground_builder
	body = collision


## A complete building. `look` keys: style (Style), wall, trim, stone (Color),
## shops (bool), seed (0-1), podium (floors of limestone base, towers),
## tiers (Array of [inset m, height m] setbacks on top), tank (bool).
func add_building(fp: Rect2, base_y: float, height: float, look: Dictionary) -> void:
	var style: int = look["style"]
	var wall: Color = look["wall"]
	var trim: Color = look["trim"]
	var stone: Color = look.get("stone", ArtPalette.CONCRETE)
	var seed: float = look["seed"]
	var shops: bool = look.get("shops", false)
	var podium: int = look.get("podium", 0)
	var top := base_y + height
	var modern := style == Style.CURTAIN or style == Style.RIBBON

	# Walls: a stone podium under towers, then the main style.
	var podium_top := 0.0
	if podium > 0:
		podium_top = GROUND_FLOOR + FLOOR * (podium - 1)
		_walls(fp, base_y, 0.0, podium_top, stone, Style.LIMESTONE + (SHOPS if shops else 0), seed)
	_walls(fp, base_y, podium_top, height, wall, style + (SHOPS if shops and podium == 0 else 0), seed)
	_collider(fp, base_y, top)

	# Base: plinth all round, fascia over shopfronts, string course.
	var base_col := stone.darkened(0.12)
	_ring(fp, base_y, base_y + 0.45, 0.06, Color(base_col, 0.0), 0.03)
	if shops:
		_ring(fp, base_y + 3.55, base_y + 4.4, 0.14, Color(look.get("fascia", trim.darkened(0.35)), 0.0), 0.03)
		_signs(fp, base_y, seed, Style.LIMESTONE if podium > 0 else style)
	if podium > 0:
		_ring(fp, base_y + podium_top - 0.1, base_y + podium_top + 0.35, 0.22, Color(stone.lightened(0.05), 0.0), 0.05)
	elif not modern:
		_ring(fp, base_y + GROUND_FLOOR - 0.05, base_y + GROUND_FLOOR + 0.22, 0.08, Color(trim, 0.0), 0.03)
	if shops and rng.randf() < 0.7:
		_awnings(fp, base_y, look.get("awning", Color(0.55, 0.2, 0.17)))

	# Top: cornice or metal coping, parapet, clutter.
	var roof_fp := fp
	var roof_y := _top(fp, top, wall, trim, modern)
	_aprons(fp, base_y)
	if not modern and height < 28.0:
		_downpipes(fp, base_y, top, wall, seed, shops)
	var tiers: Array = look.get("tiers", [])
	var tier_base := height
	for t: Array in tiers:
		var inset: float = t[0]
		var th: float = t[1]
		var tfp := roof_fp.grow(-inset)
		if tfp.size.x < 8.0 or tfp.size.y < 8.0:
			break
		_walls(tfp, base_y, tier_base + 0.0, tier_base + th, wall.lightened(0.03), style, seed + 0.31)
		_roof(roof_fp, roof_y, tfp)
		_collider(tfp, base_y + tier_base, base_y + tier_base + th)
		tier_base += th
		roof_fp = tfp
		roof_y = _top(tfp, base_y + tier_base, wall, trim, modern)
	_roof(roof_fp, roof_y, Rect2())
	_roof_clutter(roof_fp, roof_y, look.get("tank", false), modern and tier_base > 30.0)


## Four walls with bays fitted to each wall's length. `v0`/`v1` are metres
## above the building's base, which is what the facade shader's floors use.
func _walls(fp: Rect2, base_y: float, v0: float, v1: float, col: Color, style: int, seed: float) -> void:
	facade.set_uv2(Vector2(seed, style))
	var corners := [Vector2(fp.position.x, fp.position.y), Vector2(fp.end.x, fp.position.y),
		Vector2(fp.end.x, fp.end.y), Vector2(fp.position.x, fp.end.y)]
	var target: float = BAY[style % 8]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		# Corners go clockwise seen from above (x east, z south), so walking
		# a -> b the outside is on the left; the shader wants u to grow to the
		# right seen from outside, i.e. from b to a.
		var length := a.distance_to(b)
		var bays := maxf(roundf(length / target), 1.0)
		# COLOR.a carries the bay width for the shader (room and window sizes):
		# 0.5 + 0.5 * (width - 2 m) / 4 m. Below 0.5 means plain surface.
		var bay_w := length / bays
		var c := Color(col, 0.5 + 0.5 * clampf((bay_w - 2.0) / 4.0, 0.0, 1.0))
		var pa := Vector3(b.x, base_y + v0, b.y)
		var pb := Vector3(a.x, base_y + v0, a.y)
		var up := Vector3.UP * (v1 - v0)
		facade.add_quad(pa, pb, pb + up, pa + up, c,
			Vector2(0.0, v0), Vector2(bays, v0), Vector2(bays, v1), Vector2(0.0, v1))


## A band around the footprint from y0 to y1, standing `out` metres proud of
## the walls (plinths, string courses, cornices, fascias).
func _ring(fp: Rect2, y0: float, y1: float, out: float, col: Color, bevel: float) -> void:
	var r := fp.grow(out)
	var h := y1 - y0
	var t := out + 0.15  # depth: back into the wall a little
	var cy := (y0 + y1) * 0.5
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, cy, r.position.y + t * 0.5)), Vector3(r.size.x, h, t), bevel, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, cy, r.end.y - t * 0.5)), Vector3(r.size.x, h, t), bevel, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(r.position.x + t * 0.5, cy, r.get_center().y)), Vector3(t, h, r.size.y - 2.0 * t + 0.02), bevel, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(r.end.x - t * 0.5, cy, r.get_center().y)), Vector3(t, h, r.size.y - 2.0 * t + 0.02), bevel, col)


## Cornice (classic) or coping (modern) and a parapet. Returns the roof deck height.
func _top(fp: Rect2, top: float, wall: Color, trim: Color, modern: bool) -> float:
	var deck := top
	if modern:
		_parapet(fp, top, 0.9, Color(wall, 0.0))
		_ring(fp, top + 0.85, top + 1.05, 0.05, Color(0.24, 0.25, 0.26, 0.0), 0.02)
	else:
		_ring(fp, top - 0.75, top - 0.5, 0.15, Color(trim, 0.0), 0.03)
		_ring(fp, top - 0.5, top, 0.38, Color(trim, 0.0), 0.06)
		_parapet(fp.grow(-0.05), top, 0.8, Color(wall, 0.0))
		_ring(fp.grow(-0.05), top + 0.75, top + 0.9, 0.06, Color(trim, 0.0), 0.02)
	return deck


func _parapet(fp: Rect2, y: float, h: float, col: Color) -> void:
	var t := 0.3
	var cy := y + h * 0.5
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(fp.get_center().x, cy, fp.position.y + t * 0.5)), Vector3(fp.size.x, h, t), 0.02, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(fp.get_center().x, cy, fp.end.y - t * 0.5)), Vector3(fp.size.x, h, t), 0.02, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(fp.position.x + t * 0.5, cy, fp.get_center().y)), Vector3(t, h, fp.size.y - 2.0 * t), 0.02, col)
	facade.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(fp.end.x - t * 0.5, cy, fp.get_center().y)), Vector3(t, h, fp.size.y - 2.0 * t), 0.02, col)


## Roof membrane over `fp` at `y`, leaving out `hole` (where a tier stands).
func _roof(fp: Rect2, y: float, hole: Rect2) -> void:
	# Roof deck: facade style 5 (membrane and ballast in facade.gdshader), keeping
	# the building's seed; the walls' UV2 comes back afterwards (tier trims follow).
	var walls_uv2 := facade.uv2
	facade.set_uv2(Vector2(walls_uv2.x, ROOF_STYLE))
	var col := Color(ArtPalette.ROOF, 0.0)
	var r := fp.grow(-0.29)
	var yy := y + 0.02
	if hole.has_area():
		# Four strips around the hole.
		_roof_quad(Rect2(r.position.x, r.position.y, r.size.x, hole.position.y - r.position.y), yy, col)
		_roof_quad(Rect2(r.position.x, hole.end.y, r.size.x, r.end.y - hole.end.y), yy, col)
		_roof_quad(Rect2(r.position.x, hole.position.y, hole.position.x - r.position.x, hole.size.y), yy, col)
		_roof_quad(Rect2(hole.end.x, hole.position.y, r.end.x - hole.end.x, hole.size.y), yy, col)
	else:
		_roof_quad(r, yy, col)
	facade.set_uv2(walls_uv2)


func _roof_quad(r: Rect2, y: float, col: Color) -> void:
	if r.size.x <= 0.01 or r.size.y <= 0.01:
		return
	facade.add_quad(Vector3(r.position.x, y, r.position.y), Vector3(r.position.x, y, r.end.y),
		Vector3(r.end.x, y, r.end.y), Vector3(r.end.x, y, r.position.y), col)


func _collider(fp: Rect2, y0: float, y1: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(fp.size.x, y1 - y0, fp.size.y)
	cs.shape = shape
	cs.position = Vector3(fp.get_center().x, (y0 + y1) * 0.5, fp.get_center().y)
	body.add_child(cs)


## Contact shadow on the pavement around the walls (darkest at the wall).
func _aprons(fp: Rect2, y: float) -> void:
	var w := 0.9
	var inner := [Vector3(fp.position.x, y, fp.position.y), Vector3(fp.end.x, y, fp.position.y),
		Vector3(fp.end.x, y, fp.end.y), Vector3(fp.position.x, y, fp.end.y)]
	var o := fp.grow(w)
	var outer := [Vector3(o.position.x, y, o.position.y), Vector3(o.end.x, y, o.position.y),
		Vector3(o.end.x, y, o.end.y), Vector3(o.position.x, y, o.end.y)]
	var dark := Color(ArtPalette.SIDEWALK.darkened(0.32), 1.0)
	var lite := Color(ArtPalette.SIDEWALK, 1.0)
	var up := Vector3.UP
	var lift := Vector3.UP * 0.006
	for k in 4:
		var k1 := (k + 1) % 4
		ground.add_quad_ex(inner[k] + lift, outer[k] + lift, outer[k1] + lift, inner[k1] + lift, up, up, up, up, dark, lite, lite, dark)


## One or two rain downpipes down the corners of low and mid-rise buildings
## (clutter mesh, street_props.gdshader): a round pipe with a few collars,
## painted like the wall or dark metal.
func _downpipes(fp: Rect2, base_y: float, top: float, wall: Color, seed: float, shops: bool) -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = int(seed * 100000.0) + 91
	var corners := [Vector2(fp.position.x, fp.position.y), Vector2(fp.end.x, fp.position.y),
		Vector2(fp.end.x, fp.end.y), Vector2(fp.position.x, fp.end.y)]
	var k0 := prng.randi_range(0, 3)
	var painted := prng.randf() < 0.5
	var col := Color(wall.darkened(0.12), PAINTED) if painted else Color(0.27, 0.28, 0.29, METAL)
	var length := top - base_y - 0.85
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.0)])
	for h: float in [0.35, length * 0.5, length - 0.4]:
		profile.append_array(PackedVector2Array([Vector2(0.05, h - 0.03), Vector2(0.068, h - 0.03), Vector2(0.068, h + 0.03), Vector2(0.05, h + 0.03)]))
	profile.append_array(PackedVector2Array([Vector2(0.05, length), Vector2(0.0, length)]))
	for n in 1 + prng.randi_range(0, 1):
		var k := (k0 + n * 2) % 4
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var dir := (b - a).normalized()
		var out2 := Vector2(dir.y, -dir.x)  # outside of a clockwise ring
		var p2 := a + dir * (0.14 if shops else 0.15 + prng.randf() * 0.4) + out2 * 0.07
		clutter.add_lathe(Transform3D(Basis.IDENTITY, Vector3(p2.x, base_y + 0.1, p2.y)), profile, 6, PackedColorArray([col]), 25.0)


## Sign boards on the fascia: one per pair of shop bays (the shader picks the
## word from the same hash as the shop interior behind the glass, so UV.x is
## the wall's bay coordinate and UV.y metres up from the base). `style` is the
## style the shop walls were built with (it sets the bay width).
func _signs(fp: Rect2, base_y: float, seed: float, style: int) -> void:
	var prev_uv2 := facade.uv2
	var srng := RandomNumberGenerator.new()
	srng.seed = int(seed * 100000.0) + 17
	facade.set_uv2(Vector2(seed, SIGN_STYLE))
	var corners := [Vector2(fp.position.x, fp.position.y), Vector2(fp.end.x, fp.position.y),
		Vector2(fp.end.x, fp.end.y), Vector2(fp.position.x, fp.end.y)]
	var target: float = BAY[style]
	var y0 := base_y + SIGN_V0
	var up := Vector3.UP * SIGN_H
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var bays := maxf(roundf(length / target), 1.0)
		var dir := (b - a) / length
		var out2 := Vector2(dir.y, -dir.x)  # outside of a clockwise ring
		var off := Vector3(out2.x, 0.0, out2.y) * 0.16  # a little proud of the fascia (0.14)
		for g in int(bays / 2.0):
			if srng.randf() < 0.15:
				continue  # not every shop has a sign
			var s0 := 2.0 * g + SIGN_MARGIN
			var s1 := 2.0 * g + 2.0 - SIGN_MARGIN
			var p0 := b + (a - b) * (s0 / bays)
			var p1 := b + (a - b) * (s1 / bays)
			var pa := Vector3(p0.x, y0, p0.y) + off
			var pb := Vector3(p1.x, y0, p1.y) + off
			facade.add_quad(pa, pb, pb + up, pa + up, Color(1, 1, 1, 0.9),
				Vector2(s0, SIGN_V0), Vector2(s1, SIGN_V0), Vector2(s1, SIGN_V0 + SIGN_H), Vector2(s0, SIGN_V0 + SIGN_H))
	facade.set_uv2(prev_uv2)


## Fabric awnings over a few shopfront bays on each street side.
func _awnings(fp: Rect2, base_y: float, col: Color) -> void:
	var stripe := Color(0.86, 0.84, 0.78)
	var corners := [Vector2(fp.position.x, fp.position.y), Vector2(fp.end.x, fp.position.y),
		Vector2(fp.end.x, fp.end.y), Vector2(fp.position.x, fp.end.y)]
	var plain := rng.randf() < 0.5
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var bays := maxi(int(roundf(length / 3.0)), 1)
		var bw := length / bays
		var dir := (b - a) / length
		var out2 := Vector2(dir.y, -dir.x)  # outside of a clockwise ring
		var out := Vector3(out2.x, 0.0, out2.y)
		var run_start := -1
		for i in bays + 1:
			var want := i < bays and i > 0 and i < bays - 1 and rng.randf() < 0.45
			if want and run_start < 0:
				run_start = i
			elif not want and run_start >= 0:
				_awning(a + dir * (run_start * bw + 0.15), a + dir * (i * bw - 0.15), out, base_y, col, stripe, plain)
				run_start = -1


func _awning(a2: Vector2, b2: Vector2, out: Vector3, base_y: float, col: Color, stripe: Color, plain: bool) -> void:
	var y_top := base_y + 3.5
	var depth := 1.3
	var drop := 0.65
	var valance := 0.22
	var a := Vector3(a2.x, y_top, a2.y)
	var b := Vector3(b2.x, y_top, b2.y)
	var stripes := maxi(int(a.distance_to(b) / 0.45), 1)
	for s in stripes:
		var p0 := a.lerp(b, float(s) / stripes)
		var p1 := a.lerp(b, float(s + 1) / stripes)
		var c := col if plain or s % 2 == 0 else stripe
		c = Color(c, FABRIC)
		var q0 := p0 + out * depth + Vector3.DOWN * drop
		var q1 := p1 + out * depth + Vector3.DOWN * drop
		clutter.add_quad(p1, p0, q0, q1, c)
		clutter.add_quad(p0, p1, q1, q0, Color(c.darkened(0.25), FABRIC))
		clutter.add_quad(q1, q0, q0 + Vector3.DOWN * valance, q1 + Vector3.DOWN * valance, c)
		clutter.add_quad(q0, q1, q1 + Vector3.DOWN * valance, q0 + Vector3.DOWN * valance, Color(c.darkened(0.25), FABRIC))
	# Side cheeks.
	for e: Array in [[a, -1.0], [b, 1.0]]:
		var p: Vector3 = e[0]
		var q := p + out * depth + Vector3.DOWN * drop
		var cc := Color(col, FABRIC)
		clutter.add_tri(p, q, q + Vector3.DOWN * valance, cc)
		clutter.add_tri(p, q + Vector3.DOWN * valance, q, cc)


## HVAC units, a stair housing, vents, maybe a water tank or an antenna mast.
func _roof_clutter(fp: Rect2, y: float, tank: bool, mast: bool) -> void:
	var area := fp.size.x * fp.size.y
	var r := fp.grow(-2.0)
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var grey := Color(0.74, 0.74, 0.72)
	# Stair / lift housing.
	var hs := Vector3(3.2, 3.0, 4.2)
	var hp := Vector3(r.position.x + hs.x * 0.5 + rng.randf() * maxf(r.size.x - hs.x, 0.0), y + hs.y * 0.5, r.position.y + hs.z * 0.5 + rng.randf() * maxf(r.size.y - hs.z, 0.0))
	clutter.add_bevel_box(Transform3D(Basis.IDENTITY, hp), hs, 0.05, Color(0.62, 0.6, 0.57, CONCRETE), Color(0.5, 0.49, 0.47, CONCRETE))
	clutter.add_bevel_box(Transform3D(Basis.IDENTITY, hp + Vector3(0, hs.y * 0.5 + 0.08, 0)), Vector3(hs.x + 0.2, 0.16, hs.z + 0.2), 0.03, Color(0.3, 0.31, 0.32, METAL))
	# HVAC units with a fan on top.
	var units := clampi(int(area / 260.0) + 1, 1, 6)
	for k in units:
		var size := Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(1.0, 1.5), rng.randf_range(1.4, 2.0))
		var p := Vector3(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), y + size.y * 0.5, rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
		if Vector2(p.x - hp.x, p.z - hp.z).length() < 3.6:
			continue
		var basis := Basis(Vector3.UP, PI * 0.5 * rng.randi_range(0, 1))
		clutter.add_bevel_box(Transform3D(basis, p), size, 0.05, Color(grey, PAINTED), Color(grey.darkened(0.25), PAINTED))
		var fan := Transform3D(basis, p + Vector3(0, size.y * 0.5, 0))
		clutter.add_lathe(fan, PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.42, 0.06), Vector2(0.0, 0.06)]), 8,
			PackedColorArray([Color(0.16, 0.16, 0.17, RUBBER)]))
	# Vents.
	for k in rng.randi_range(2, 5):
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), y, rng.randf_range(r.position.y, r.end.y))
		clutter.add_lathe(Transform3D(Basis.IDENTITY, p), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.14, 0.7), Vector2(0.22, 0.72), Vector2(0.22, 0.82), Vector2(0.0, 0.86)]), 6,
			PackedColorArray([Color(0.6, 0.61, 0.62, METAL)]))
	# Timber water tank on legs (older buildings).
	if tank:
		var p := Vector3(rng.randf_range(r.position.x + 2.0, r.end.x - 2.0), y, rng.randf_range(r.position.y + 2.0, r.end.y - 2.0))
		for lx: float in [-1.0, 1.0]:
			for lz: float in [-1.0, 1.0]:
				clutter.add_bevel_box(Transform3D(Basis.IDENTITY, p + Vector3(lx, 1.0, lz)), Vector3(0.18, 2.0, 0.18), 0.02, Color(0.25, 0.25, 0.26, METAL))
		var wood := Color(0.48, 0.36, 0.26, 13.0 / 15.0)
		clutter.add_lathe(Transform3D(Basis.IDENTITY, p + Vector3(0, 2.0, 0)), PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(1.5, 0.0), Vector2(1.55, 2.6), Vector2(1.62, 2.65), Vector2(0.15, 3.6), Vector2(0.0, 3.65)]), 10,
			PackedColorArray([wood.darkened(0.2), wood, wood, Color(0.3, 0.3, 0.31, METAL), Color(0.3, 0.3, 0.31, METAL)]), 25.0)
	if mast:
		var p := Vector3(fp.get_center().x, y, fp.get_center().y)
		clutter.add_lathe(Transform3D(Basis.IDENTITY, p), PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.12, 9.0), Vector2(0.05, 14.0), Vector2(0.0, 14.1)]), 8,
			PackedColorArray([Color(0.7, 0.71, 0.72, METAL)]))
