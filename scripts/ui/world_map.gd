class_name WorldMap
extends SubViewport
## A top-down picture of the whole island (terrain colours, city blocks, the
## stunt park and every road), drawn once when the game starts. The minimap
## and the big map (M) show parts of `get_texture()`.

const SIZE := 1024
const HALF := MapLayout.TERRAIN_HALF_SIZE

const BLOCK_COLORS := {
	"buildings": Color(0.72, 0.74, 0.8),
	"park": Color(0.42, 0.68, 0.32),
	"plaza": Color(0.86, 0.82, 0.74),
	"parking": Color(0.6, 0.62, 0.66),
}
const ROAD_COLOR := Color(0.27, 0.29, 0.34)
const ROAD_EDGE := Color(0.14, 0.15, 0.19)
const WATER := Color(0.24, 0.52, 0.82)

var world: WorldBuilder
var _terrain_tex: ImageTexture


func _init(w: WorldBuilder) -> void:
	world = w


func _ready() -> void:
	size = Vector2i(SIZE, SIZE)
	disable_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_terrain_tex = ImageTexture.create_from_image(_terrain_image())
	var canvas := Node2D.new()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(canvas)
	canvas.draw.connect(_draw_map.bind(canvas))


## Map texture coordinates (0..1) of a world position. North (-Z) is up.
static func to_uv(p: Vector3) -> Vector2:
	return Vector2((p.x + HALF) / (2.0 * HALF), (p.z + HALF) / (2.0 * HALF))


static func _px(p: Vector3) -> Vector2:
	return to_uv(p) * SIZE


## Terrain colours at the heightmap's 4 m resolution (the same colouring as
## the 3D terrain), with water below sea level.
func _terrain_image() -> Image:
	var t := world.terrain
	var cell := MapLayout.TERRAIN_CELL
	var n := int(2.0 * HALF / cell)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		var z := -HALF + (j + 0.5) * cell
		for i in n:
			hs[j * n + i] = t.height_at(-HALF + (i + 0.5) * cell, z)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		var z := -HALF + (j + 0.5) * cell
		for i in n:
			var x := -HALF + (i + 0.5) * cell
			var h := hs[j * n + i]
			var c: Color
			if h < MapLayout.SEA_LEVEL:
				c = WATER.darkened(clampf((MapLayout.SEA_LEVEL - h) * 0.04, 0.0, 0.3))
			else:
				var dx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
				var dz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
				var slope := Vector2(dx, dz).length() / (2.0 * cell)
				c = t._color_for(x, z, h, 1.0 / sqrt(1.0 + slope * slope), t.road_weight_at(x, z))
				c = c.darkened(clampf(slope * 0.4, 0.0, 0.25))
			img.set_pixel(i, j, c)
	return img


func _draw_map(c: Node2D) -> void:
	c.draw_texture_rect(_terrain_tex, Rect2(0, 0, SIZE, SIZE), false)
	var px_per_m := SIZE / (2.0 * HALF)

	# Stunt park ground.
	var pmin := _px(Vector3(MapLayout.PARK_MIN.x, 0, MapLayout.PARK_MIN.y))
	var pmax := _px(Vector3(MapLayout.PARK_MAX.x, 0, MapLayout.PARK_MAX.y))
	c.draw_rect(Rect2(pmin, pmax - pmin), Color(0.78, 0.76, 0.7))

	# City blocks.
	var g := MapLayout.CITY_GRID
	var hw := MapLayout.CITY_ROAD_WIDTH * 0.5
	for row in g.size() - 1:
		for col in g.size() - 1:
			var kind: String = MapLayout.BLOCK_TYPES[row][col]
			var a := _px(Vector3(g[col] + hw, 0, g[row] + hw))
			var b := _px(Vector3(g[col + 1] - hw, 0, g[row + 1] - hw))
			c.draw_rect(Rect2(a, b - a), BLOCK_COLORS.get(kind, Color.GRAY))

	# Roads: dark edge, then the surface.
	for pass_i in 2:
		for r in world.roads.roads:
			var pts := PackedVector2Array()
			for p in r.points:
				pts.append(_px(p))
			if r.closed:
				pts.append(pts[0])
			var w := r.width * px_per_m + (2.0 if pass_i == 0 else 0.0)
			c.draw_polyline(pts, ROAD_EDGE if pass_i == 0 else ROAD_COLOR, w, true)
		# City intersections (the road pieces stop at their edges).
		for it in world.roads.intersections:
			var q := _px(Vector3(it.x, 0, it.y))
			var s := (MapLayout.CITY_ROAD_WIDTH + (2.0 if pass_i == 0 else 0.0) / px_per_m) * px_per_m
			c.draw_rect(Rect2(q - Vector2(s, s) * 0.5, Vector2(s, s)), ROAD_EDGE if pass_i == 0 else ROAD_COLOR)
	# Highway centre line, so it reads as the big road.
	var hwy := world.roads.highway
	var line := PackedVector2Array()
	for p in hwy.points:
		line.append(_px(p))
	line.append(line[0])
	c.draw_polyline(line, Color(0.95, 0.8, 0.2), 1.5, true)
