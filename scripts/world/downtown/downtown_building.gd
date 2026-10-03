@tool
class_name DowntownBuilding
extends RefCounted
## One downtown building assembled from Downtown City MegaKit modules the way
## the kit's own example buildings are put together (Quaternius' Small_1,
## Medium_2 and Large_2): a base of shopfronts or a masonry ground floor
## under a sign band, a middle of window bays (pilasters on some styles), and
## a top of a cornice or a slate mansard. Corners are wrapped brick corners
## or stone quoin columns; cornices mitre round dressed corners.
##
## Sides are walked like BuildingKit: south (+Z), east (+X), north (-Z),
## west (-X); a side's left end (seen from outside) is the corner before it.
## A side is a street frontage (dressed with modules) or a party / courtyard
## wall: plain brick quads, like the blank walls you see above lower
## neighbours in a real city, at 2 triangles instead of hundreds.
##
## Kit module frame on a wall with outward normal n: Basis(UP x n, UP, n),
## outside face at z = 0, x = metres along the wall to the right.
## Heights: a 4 m ground floor (3 m modules + a 1 m band) and 3 m floors.

const GROUND := 4.0
const FLOOR := 3.0
const BAY := 2.0
const QUOIN := 0.97  # how far a corner column reaches along each wall

## Facade styles, after the kit's example buildings. Keys:
##   corner   "plain" (wrapped brick corner) or "quoin" (corner column)
##   base     "metal" (dark cast-iron shopfronts), "trim" (stone shopfronts
##            with columns), "brick" (masonry ground floor with windows)
##   wide     4 m window modules for the upper floors ([] = 2 m bays only)
##   narrow   2 m window modules
##   top      2 m window for the top floor ("" = the same as below)
##   pilaster "" none, "half" brick pilasters, "column" brick-and-stone piers
##   cornice  "trim" (stone, mitred), "metal" (sheet metal), "brick"
##   roof     "flat" or "mansard"
##   ac       chance of a window air conditioner in a 2 m window
##   palettes MegaKit.PALETTES rows the style is painted in
const STYLES := {
	"loft": {"corner": "plain", "base": "metal", "wide": ["Brick_Inset_Window_Curved"],
		"narrow": ["Brick_Window_Square_Single"], "top": "Brick_Window_Square_Single", "pilaster": "",
		"cornice": "metal", "roof": "flat", "ac": 0.1, "fire_escape": 0.5, "palettes": [0, 1, 7, 4]},
	# (warehouse below may also carry one)
	"hotel": {"corner": "quoin", "base": "trim", "wide": [], "narrow": ["Brick_Window_Trim"],
		"top": "Brick_Window_Trim_Single", "pilaster": "half", "cornice": "trim", "roof": "flat",
		"ac": 0.0, "palettes": [1, 3, 4, 8]},
	"commercial": {"corner": "plain", "base": "metal", "wide": ["Metal_Window"], "narrow": ["Metal_Window_Half"],
		"top": "", "pilaster": "", "cornice": "metal", "roof": "flat", "ac": 0.0, "palettes": [0, 2, 8, 1]},
	"mansard": {"corner": "quoin", "base": "trim", "wide": ["Brick_RedWhite_DoubleWindow"], "narrow": ["Brick_Window_Trim_Single"],
		"top": "", "pilaster": "", "cornice": "trim", "roof": "mansard", "ac": 0.0, "palettes": [3, 4, 6, 8]},
	"tenement": {"corner": "plain", "base": "brick", "wide": [], "narrow": ["Brick_Window_Square_Single"],
		"top": "Brick_Window_Trim_Single", "pilaster": "", "cornice": "brick", "roof": "flat", "ac": 0.18,
		"fire_escape": 0.85, "palettes": [2, 5, 6, 7]},
	"warehouse": {"corner": "plain", "base": "brick", "wide": ["Brick_Window_CurvedDouble"],
		"narrow": ["Brick_Window_Square_Single"], "top": "", "pilaster": "column", "cornice": "brick",
		"roof": "flat", "ac": 0.0, "fire_escape": 0.35, "palettes": [0, 7, 2, 4]},
}

var batch: MegaKit.Batch
var rng: RandomNumberGenerator
## Box colliders: Array of [Transform3D, Vector3 size].
var colliders: Array = []
## Shop sign spots on the sign band for the street dressing: Array of
## [Transform3D (wall frame, origin at the band's centre), width m].
var sign_spots: Array = []
var top_height := 0.0
var fire_escapes := 0
## The roof deck (for roof clutter): rectangle and height.
var roof_rect := Rect2()
var roof_y := 0.0
## Older styles get timber water tanks on the roof.
var water_tank := false

var _style: Dictionary
var _floors := 0
var _top := 0.0


func _init(target: MegaKit.Batch, random: RandomNumberGenerator) -> void:
	batch = target
	rng = random


static func height_of(floors: int) -> float:
	return GROUND + FLOOR * floors


## Builds a building on `fp` (x/z rectangle, sizes multiples of 2 m) standing
## on `base_y`, with `floors` floors above the ground floor. `front` = which
## sides face a street (south, east, north, west); the entrance goes on the
## first frontage. `back` = sides that face open ground inside the block (a
## car park, an alley): dressed with windows over a plain masonry ground
## floor, no shops.
func build(fp: Rect2, base_y: float, floors: int, front: Array[bool], style_name: String,
		back: Array[bool] = [false, false, false, false]) -> void:
	_style = STYLES[style_name]
	_floors = floors
	_top = height_of(floors)
	top_height = _top + (3.0 if _style["roof"] == "mansard" else 1.0)
	var c := _corners(fp, base_y)
	var quoin: bool = _style["corner"] == "quoin"
	var entrance_side := front.find(true)
	var dressed: Array[bool] = []
	for k in 4:
		dressed.append(front[k] or back[k])
	for k in 4:
		var o: Vector3 = c[k]
		var n: Vector3 = _normal(k)
		var length := o.distance_to(c[(k + 1) % 4])
		var prev_front: bool = dressed[(k + 3) % 4]
		var next_front: bool = dressed[(k + 1) % 4]
		if dressed[k]:
			_dressed_wall(o, n, length, quoin, prev_front, next_front, k == entrance_side, not front[k])
		else:
			var s0 := QUOIN if quoin and prev_front else 0.0
			var s1 := length
			if next_front:
				s1 -= QUOIN if quoin else BAY
			_plain_wall(o, n, s0, s1, 0.0, _top + (0.0 if _style["roof"] == "mansard" else 1.0))
	_roof(fp, base_y, front)
	colliders.append([Transform3D(Basis.IDENTITY, Vector3(fp.get_center().x, base_y + _top * 0.5, fp.get_center().y)),
		Vector3(fp.size.x, _top, fp.size.y)])


static func _corners(fp: Rect2, y: float) -> Array[Vector3]:
	return [Vector3(fp.position.x, y, fp.end.y), Vector3(fp.end.x, y, fp.end.y),
		Vector3(fp.end.x, y, fp.position.y), Vector3(fp.position.x, y, fp.position.y)]


static func _normal(k: int) -> Vector3:
	return [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT][k]


## The wall before this one (walking S, E, N, W) has its normal turned -90 deg.
static func _prev_normal(n: Vector3) -> Vector3:
	return Vector3(-n.z, 0.0, n.x)


## Transform of a module on the wall whose left end (seen from outside) is
## `origin`, `along` metres to the right, `y` up.
static func _xf(origin: Vector3, n: Vector3, along: float, y: float) -> Transform3D:
	var xa := Vector3.UP.cross(n)
	return Transform3D(Basis(xa, Vector3.UP, n), origin + xa * along + Vector3.UP * y)


# ------------------------------------------------------------------ walls ---

func _dressed_wall(o: Vector3, n: Vector3, length: float, quoin: bool, prev_front: bool, next_front: bool,
		entrance: bool, secondary := false) -> void:
	# Bay run between the corners: quoins take 1 m at both ends; a brick
	# corner takes 2 m at the left end, and the next wall's corner piece
	# wraps over our last 2 m when that wall is dressed too.
	var r0 := 1.0 if quoin else BAY
	var r1 := length - (1.0 if quoin else (BAY if next_front else 0.0))
	var bays := _plan_bays(r1 - r0)

	# Ground floor and its sign band.
	var x := r0
	var door_bay := bays.size() / 2 if entrance else -1
	var shop_x0 := r0
	var base: String = "brick" if secondary else _style["base"]
	for i in bays.size():
		var w: float = bays[i]
		for j in int(roundf(w / BAY)):
			_ground_module(o, n, x + BAY * (j + 0.5), i == door_bay and j == 0, base)
		x += w
	if base != "brick" and r1 - shop_x0 > 3.0:
		sign_spots.append([_xf(o, n, (shop_x0 + r1) * 0.5, 3.5), r1 - shop_x0])

	# Upper floors.
	for f in _floors:
		var y := GROUND + FLOOR * f
		var top_floor := f == _floors - 1
		x = r0
		for i in bays.size():
			var w: float = bays[i]
			_window(o, n, x + w * 0.5, y, w, top_floor)
			x += w
		if _style["pilaster"] != "":
			x = r0
			for i in range(1, bays.size()):
				x += bays[i - 1]
				_pilaster(o, n, x, y, f)

	# A fire escape on some street frontages of older walk-ups, over the
	# joint between two bays away from the door.
	if not secondary and _floors >= 2 and bays.size() >= 3 and rng.randf() < _style.get("fire_escape", 0.0):
		var j := 1 if bays.size() / 2 != 1 else bays.size() - 2
		var jx := r0
		for i in j:
			jx += bays[i]
		_fire_escape(o, n, jx)
		fire_escapes += 1

	# Corners.
	if quoin:
		_quoin(o + Vector3.UP.cross(n) * length, n)
		if not prev_front:
			_quoin(o, _prev_normal(n))
	else:
		_brick_corner(o, n)
	if _style["roof"] != "mansard":  # the mansard pieces carry their own cornice
		_cornice(o, n, length, prev_front, next_front)


## A New York fire escape centred on `x` metres along the wall: a landing
## at every upper floor (grating, railings, brackets into the wall), stair
## flights between them, and a drop ladder above the sidewalk. Kit painted
## metal (the dark band of the metal / concrete slice, coloured by the
## palette's metal slot), thin boxes. Far away only the landings remain.
func _fire_escape(o: Vector3, n: Vector3, x: float) -> void:
	var xa := Vector3.UP.cross(n)
	var b := Basis(xa, Vector3.UP, n)
	var L := MegaKit.LAYER_METAL
	var S := MegaKit.SLOT_METAL
	var uv := Vector2(0.37, 0.09)  # the painted metal band of the slice
	var w := 3.6
	var d := 1.0
	var box := func(c: Vector3, size: Vector3, far_too := false) -> void:
		batch.add_box(Transform3D(b, o + xa * (x + c.x) + Vector3.UP * c.y + n * c.z), size, L, S, uv, far_too)
	for f in _floors:
		var y := GROUND + FLOOR * f + 0.35  # landing at sill height
		# Grating, edge beams, brackets into the wall.
		box.call(Vector3(0.0, y, 0.1 + d * 0.5), Vector3(w, 0.04, d), true)
		box.call(Vector3(0.0, y - 0.06, 0.1 + d), Vector3(w, 0.12, 0.05))
		for sx: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
			box.call(Vector3(sx, y - 0.4, 0.1 + d * 0.45), Vector3(0.05, 0.05, d * 1.05))
			var brace := Basis(xa, deg_to_rad(-38.0)) * b
			batch.add_box(Transform3D(brace, o + xa * (x + sx) + Vector3.UP * (y - 0.42) + n * (0.1 + d * 0.5)),
				Vector3(0.04, 0.04, 1.15), L, S, uv)
		# Railing: top rail, mid rail, balusters on the front and ends.
		for ry: float in [1.0, 0.5]:
			box.call(Vector3(0.0, y + ry, 0.1 + d), Vector3(w, 0.04, 0.04))
			for sx: float in [-w * 0.5, w * 0.5]:
				box.call(Vector3(sx, y + ry, 0.1 + d * 0.5), Vector3(0.04, 0.04, d))
		var bx := -w * 0.5
		while bx <= w * 0.5 + 0.01:
			box.call(Vector3(bx, y + 0.5, 0.1 + d), Vector3(0.025, 1.0, 0.025))
			bx += 0.3
		for sx: float in [-w * 0.5, w * 0.5]:
			box.call(Vector3(sx, y + 0.5, 0.1 + d * 0.5), Vector3(0.025, 1.0, 0.025))
		# Stairs down to the landing below (alternating direction), along the front.
		if f > 0:
			var dir := 1.0 if f % 2 == 0 else -1.0
			var y0 := y - FLOOR
			var run := 2.4
			var steps := 11
			var zc := 0.1 + d * 0.62
			var x_top := -dir * (w * 0.5 - 0.45)
			var x_bot := x_top + dir * run
			var mid := Vector3((x_top + x_bot) * 0.5, (y + y0) * 0.5, zc)
			var ang := atan2(FLOOR, run)
			var sb := Basis(n, -dir * ang) * b
			for side: float in [-0.32, 0.32]:
				batch.add_box(Transform3D(sb, o + xa * (x + mid.x) + Vector3.UP * mid.y + n * (zc + side)),
					Vector3(sqrt(run * run + FLOOR * FLOOR), 0.1, 0.03), L, S, uv)
				batch.add_box(Transform3D(sb, o + xa * (x + mid.x) + Vector3.UP * (mid.y + 0.85) + n * (zc + side)),
					Vector3(sqrt(run * run + FLOOR * FLOOR), 0.035, 0.035), L, S, uv)
			for k in steps:
				var t := (float(k) + 0.5) / float(steps)
				box.call(Vector3(lerpf(x_top, x_bot, t), lerpf(y, y0, t), zc), Vector3(0.2, 0.025, 0.62))
	# Drop ladder from the lowest landing toward the sidewalk.
	var y1 := GROUND + 0.35
	var lx := w * 0.5 - 0.5
	for side: float in [-0.22, 0.22]:
		box.call(Vector3(lx + side, y1 - 1.0, 0.1 + d - 0.12), Vector3(0.04, 2.0, 0.04))
	var ry := y1 - 1.9
	while ry < y1:
		box.call(Vector3(lx, ry, 0.1 + d - 0.12), Vector3(0.44, 0.03, 0.03))
		ry += 0.3


## Splits a bay run into 4 m and 2 m bays, symmetric about the middle.
func _plan_bays(run: float) -> Array[float]:
	var out: Array[float] = []
	var n2 := int(roundf(run / BAY))
	var wide: Array = _style["wide"]
	if wide.is_empty():
		for i in n2:
			out.append(BAY)
		return out
	for i in n2 / 2:
		out.append(BAY * 2.0)
	if n2 % 2 == 1:
		out.insert(out.size() / 2, BAY)
	return out


func _ground_module(o: Vector3, n: Vector3, cx: float, door: bool, base: String) -> void:
	match base:
		"metal":
			if door:
				batch.add("DoorFrame_Metal_Single", _xf(o, n, cx, 0.0))
				batch.add("Door_2", _xf(o, n, cx + 0.5, 0.0))
			else:
				batch.add("Metal_FirstFloor_Window", _xf(o, n, cx, 0.0))
			batch.add("Metal_FirstFloor_Wall_1", _xf(o, n, cx, 2.99))
		"trim":
			if door:
				batch.add("DoorFrame_Trim", _xf(o, n, cx, 0.0))
				batch.add("Door_1", _xf(o, n, cx + 0.5, 0.0))
			else:
				batch.add("Trim_FirstFloor_Window_001", _xf(o, n, cx, 0.0))
				batch.add("Trim_FirstFloor_Window_Columns", _xf(o, n, cx, 0.0))
			batch.add("Brick_Plain_1", _xf(o, n, cx, 3.0))
		_:
			if door:
				batch.add("DoorFrame_Wooden", _xf(o, n, cx, 0.0))
				batch.add("Door_1", _xf(o, n, cx + 0.5, 0.0))
			else:
				batch.add("Brick_Window_Trim_Single", _xf(o, n, cx, 0.0))
			batch.add("Brick_Plain_1", _xf(o, n, cx, 3.0))


func _window(o: Vector3, n: Vector3, cx: float, y: float, w: float, top_floor: bool) -> void:
	var top: String = _style["top"]
	if w > BAY + 0.1:
		if top_floor and top != "":
			# Two small windows instead of a wide one on the top floor.
			_window2(o, n, cx - 1.0, y, top)
			_window2(o, n, cx + 1.0, y, top)
		else:
			var wide: Array = _style["wide"]
			batch.add(wide[rng.randi() % wide.size()], _xf(o, n, cx, y))
		return
	var narrow: Array = _style["narrow"]
	_window2(o, n, cx, y, top if top_floor and top != "" else narrow[rng.randi() % narrow.size()])


func _window2(o: Vector3, n: Vector3, cx: float, y: float, mod: String) -> void:
	batch.add(mod, _xf(o, n, cx, y))
	if _style["ac"] > 0.0 and rng.randf() < _style["ac"] and mod.ends_with("Single"):
		# A window air conditioner on the sill, sticking out of the wall.
		batch.add("Prop_ACUnit", _xf(o, n, cx - 0.04, y + 0.52))


func _pilaster(o: Vector3, n: Vector3, x: float, y: float, f: int) -> void:
	match _style["pilaster"]:
		"half":
			var mod := "Brick_HalfColumn_Center"
			if f == 0:
				mod = "Brick_HalfColumn_Bottom"
			elif f == _floors - 1:
				mod = "Brick_HalfColumn_Top"
			batch.add(mod, _xf(o, n, x, y))
		"column":
			batch.add("Brick_Column_TrimBricks", _xf(o, n, x - 0.19, y))


## Wrapped brick corner at this wall's left end (covers 2 m of this wall and
## 2 m of the wall before it): the kit's corner pieces, with two 1 m brick
## pieces for the sign band of the 4 m ground floor.
func _brick_corner(o: Vector3, n: Vector3) -> void:
	batch.add("Brick_Corner_Plain", _xf(o, n, 1.0, 0.0))
	var pn := _prev_normal(n)
	batch.add("Brick_Plain_1", _xf(o, n, 1.0, 3.0))
	batch.add("Brick_Plain_1", _xf(o, pn, -1.0, 3.0))
	for f in _floors:
		batch.add("Brick_TopTrim_Corner" if f == _floors - 1 else "Brick_Corner_Plain", _xf(o, n, 1.0, GROUND + FLOOR * f))


## Stone corner column at the corner `p` where the wall with normal n meets
## the wall to its right: base, shaft and a capital under the cornice.
func _quoin(p: Vector3, n: Vector3) -> void:
	var b := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	batch.add("Brick_CornerColumn_Bottom", Transform3D(b, p))
	# 4 m ground floor: the shaft runs 3 -> top - 3 in 2 m and 3 m pieces.
	var y := 3.0
	var gap := _top - 3.0 - y
	while gap > 0.01:
		if absf(gap - 2.0) < 0.01 or absf(gap - 4.0) < 0.01:
			batch.add("Brick_CornerColumn_Center_Half", Transform3D(b, p + Vector3.UP * y))
			y += 2.0
		else:
			batch.add("Brick_CornerColumn_Center", Transform3D(b, p + Vector3.UP * y))
			y += 3.0
		gap = _top - 3.0 - y
	batch.add("Brick_CornerColumn_Top", Transform3D(b, p + Vector3.UP * (_top - 3.0)))
	batch.add("Brick_CornerColumn_Cap", Transform3D(b, p + Vector3.UP * (_top - 3.0)))


func _cornice(o: Vector3, n: Vector3, length: float, prev_front: bool, next_front: bool) -> void:
	var family: String = {"trim": "Cornice_Trim", "metal": "Cornice_Metal", "brick": "Cornice_Brick"}[_style["cornice"]]
	# Mitred end pieces where the neighbouring wall is dressed too.
	batch.add(family + ("_L" if prev_front else "_Center"), _xf(o, n, 1.0, _top))
	batch.add(family + ("_R" if next_front else "_Center"), _xf(o, n, length - 1.0, _top))
	var x := 3.0
	while x < length - 2.0:
		batch.add(family + "_Center", _xf(o, n, x, _top))
		x += BAY


## A plain wall from s0 to s1 metres along, y0 to y1 up: one brick quad,
## grimy at the foot, plus a stone coping on top.
func _plain_wall(o: Vector3, n: Vector3, s0: float, s1: float, y0: float, y1: float) -> void:
	if s1 - s0 < 0.05:
		return
	var xa := Vector3.UP.cross(n)
	var p0 := o + xa * s0 + Vector3.UP * y0
	var p1 := o + xa * s1 + Vector3.UP * y0
	var up := Vector3.UP * (y1 - y0)
	# The kit's brick UVs: u = x / 2, v = -y / 2 (Brick_Plain_3).
	batch.add_quad([p0, p1, p1 + up, p0 + up],
		[Vector2(s0 * 0.5, -y0 * 0.5), Vector2(s1 * 0.5, -y0 * 0.5), Vector2(s1 * 0.5, -y1 * 0.5), Vector2(s0 * 0.5, -y1 * 0.5)],
		MegaKit.LAYER_BRICK, MegaKit.SLOT_BRICK, [0.2, 0.2, 1.0, 1.0])
	var d := -n * 0.3
	batch.add_quad([p0 + up + d, p1 + up + d, p1 + up, p0 + up],
		[Vector2(0.0, 0.03), Vector2((s1 - s0) * 0.5, 0.03), Vector2((s1 - s0) * 0.5, 0.12), Vector2(0.0, 0.12)],
		MegaKit.LAYER_TRIM, MegaKit.SLOT_TRIM)


# ------------------------------------------------------------------- roof ---

func _roof(fp: Rect2, base_y: float, front: Array[bool]) -> void:
	var y := base_y + _top - 0.2
	var r := fp.grow(-0.2)
	if _style["roof"] == "mansard":
		_mansard(fp, base_y, front)
		y = base_y + _top + 3.0
		r = fp.grow(-2.0)
	var p := [Vector3(r.position.x, y, r.end.y), Vector3(r.end.x, y, r.end.y),
		Vector3(r.end.x, y, r.position.y), Vector3(r.position.x, y, r.position.y)]
	var uv: Array[Vector2] = []
	for q: Vector3 in p:
		uv.append(Vector2(q.x, q.z) * 0.2)
	# Roof membrane: the kit's concrete, coloured per building (tar, grey or
	# silver coating) through the palette's flat-roof slot.
	batch.add_quad([p[0], p[1], p[2], p[3]], uv, MegaKit.LAYER_CONCRETE, MegaKit.SLOT_FLAT_ROOF)
	roof_rect = r
	roof_y = y
	water_tank = _style["cornice"] != "metal" and rng.randf() < 0.55


## A slate mansard storey on top of the walls (the kit's mansard pieces are
## 3 m tall and 2 m deep): corner pieces all round, dormers on frontages.
func _mansard(fp: Rect2, base_y: float, front: Array[bool]) -> void:
	var c := _corners(fp, base_y + _top)
	for k in 4:
		var o: Vector3 = c[k]
		var n := _normal(k)
		var length := o.distance_to(c[(k + 1) % 4])
		batch.add("Roof_SlateCornice_Corner", _xf(o, n, 1.0, 0.0))
		var x := 3.0
		var i := 0
		while x < length - 2.0:
			var dormer: bool = front[k] and i % 2 == 1
			batch.add("Roof_SlateCornice_Window_1" if dormer else "Roof_SlateCornice_Center", _xf(o, n, x, 0.0))
			x += BAY
			i += 1
