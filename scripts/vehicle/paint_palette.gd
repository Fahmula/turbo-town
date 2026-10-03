class_name PaintPalette
extends RefCounted
## Car paint colours (ART_BIBLE.md §5 and §13): the garage choices and the
## weighted mix traffic is painted from. Metallic paints carry a metallic
## amount; the rest are solid. VehicleBodyVisual looks the finish up by
## colour, so a saved colour keeps its finish.

## Garage colours: believable car paints, with a few fun brighter ones.
## Swatches show in this order, six per row.
const GARAGE: Array[Color] = [
	Color(0.784, 0.137, 0.106),  # red
	Color(0.878, 0.4, 0.106),    # sunset orange
	Color(0.91, 0.71, 0.118),    # yellow
	Color(0.48, 0.74, 0.14),     # lime (fun)
	Color(0.1, 0.3, 0.18),       # racing green
	Color(0.114, 0.549, 0.561),  # teal
	Color(0.137, 0.333, 0.769),  # bright blue
	Color(0.32, 0.16, 0.5),      # midnight purple
	Color(0.86, 0.36, 0.56),     # pink (fun)
	Color(0.902, 0.902, 0.882),  # white
	Color(0.663, 0.678, 0.698),  # silver
	Color(0.165, 0.173, 0.188),  # graphite
]
## Finish for each GARAGE entry: 0 = solid paint, more = metallic.
const GARAGE_METALLIC: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.4, 0.35, 0.4, 0.45, 0.0, 0.0, 0.6, 0.5]
## Name shown in the garage for each GARAGE entry.
const GARAGE_NAMES: Array[String] = [
	"Red", "Sunset Orange", "Yellow", "Lime", "Racing Green", "Teal",
	"Bright Blue", "Midnight Purple", "Pink", "White", "Silver", "Graphite",
]

## Traffic: [colour, weight, metallic]. Mostly white, black, grey and silver;
## blue and red fairly common; everything else rare.
const TRAFFIC := [
	[Color(0.902, 0.902, 0.882), 22.0, 0.0],   # white
	[Color(0.105, 0.108, 0.118), 16.0, 0.35],  # black
	[Color(0.663, 0.678, 0.698), 16.0, 0.6],   # silver
	[Color(0.3, 0.31, 0.33), 8.0, 0.45],       # dark grey
	[Color(0.45, 0.46, 0.48), 6.0, 0.45],      # grey
	[Color(0.16, 0.29, 0.55), 5.0, 0.4],       # blue
	[Color(0.11, 0.16, 0.28), 4.0, 0.4],       # navy
	[Color(0.68, 0.11, 0.09), 5.0, 0.0],       # red
	[Color(0.45, 0.09, 0.09), 3.0, 0.35],      # dark red
	[Color(0.13, 0.25, 0.18), 3.0, 0.35],      # dark green
	[Color(0.72, 0.67, 0.56), 3.0, 0.4],       # champagne
	[Color(0.33, 0.24, 0.18), 2.0, 0.35],      # brown
	[Color(0.85, 0.66, 0.12), 1.5, 0.0],       # yellow
	[Color(0.82, 0.38, 0.1), 1.2, 0.0],        # orange
	[Color(0.11, 0.45, 0.47), 1.2, 0.35],      # teal
	[Color(0.3, 0.16, 0.45), 0.8, 0.4],        # purple
	[Color(0.48, 0.74, 0.14), 0.5, 0.0],       # lime
]


## Metallic amount for a paint colour (0 for solid or unknown colours).
static func metallic_of(c: Color) -> float:
	for i in GARAGE.size():
		if GARAGE[i].is_equal_approx(c):
			return GARAGE_METALLIC[i]
	for e: Array in TRAFFIC:
		if (e[0] as Color).is_equal_approx(c):
			return e[2]
	return 0.0


## A random traffic colour, weighted.
static func pick_traffic(rng: RandomNumberGenerator) -> Color:
	var total := 0.0
	for e: Array in TRAFFIC:
		total += e[1]
	var r := rng.randf() * total
	for e: Array in TRAFFIC:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return TRAFFIC[0][0]


## Racing stripes stand out: dark on light paint, white on everything else.
static func stripe_color(paint: Color) -> Color:
	return Color(0.12, 0.12, 0.13) if paint.get_luminance() > 0.55 else Color(0.93, 0.93, 0.91)
