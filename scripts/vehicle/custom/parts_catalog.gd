class_name PartsCatalog
extends RefCounted
## Everything the garage can change on a vehicle, as data: the tabs, the
## slots (one garage row each) and the options in each slot. A Loadout holds
## one vehicle's choices and puts them on the vehicle; the garage
## (VehiclePicker) builds its tabs and rows from this file.
##
## To add customization:
##   * an option in an existing slot: add an entry to its list below (models
##     come from a committed generator, e.g. tools/blender/make_wheels.py);
##   * a slot: add it to SLOTS and to a tab in TABS, give it a stock value in
##     Loadout._stock_values() and put it on the vehicle in Loadout.apply();
##   * a tab: add it to TABS. `focus` is what the garage camera looks at
##     ("car" or "wheel").

## Garage tabs, left to right. "car" is the vehicle choice itself.
const TABS := [
	{"id": "car", "name": "CAR", "slots": [], "focus": "car"},
	{"id": "paint", "name": "PAINT", "slots": ["paint", "stripes"], "focus": "car"},
	{"id": "wheels", "name": "WHEELS", "slots": ["rims", "rim_color", "tyres", "tyre_stripe", "calipers"], "focus": "wheel"},
]

## Slot id -> how the garage shows it. Kinds: "choice" (named options,
## left/right steps through them), "swatch" (a grid of coloured options),
## "toggle" (on/off). Values: paint is a Color, toggles are bools, every
## other slot holds an option id.
const SLOTS := {
	"paint": {"name": "PAINT", "kind": "swatch"},
	"stripes": {"name": "RACING STRIPES", "kind": "toggle"},
	"rims": {"name": "RIMS", "kind": "choice"},
	"rim_color": {"name": "RIM COLOUR", "kind": "swatch"},
	"tyres": {"name": "TYRES", "kind": "choice"},
	"tyre_stripe": {"name": "TYRE STRIPE", "kind": "swatch"},
	"calipers": {"name": "BRAKES", "kind": "swatch"},
}

## Rims (assets/models/wheels/rim_<id>.glb, make_wheels.py). Every rim is
## built to one standard fit (bead radius 0.243, width 0.254) and WheelKit
## scales it to the tyre. `open` rims show a brake disc and get a caliper.
## `color` is the rim's own finish (the "Stock" rim colour swatch).
const RIMS := [
	{"id": "sport5", "name": "Sport Five", "open": true, "color": Color(0.72, 0.73, 0.75)},
	{"id": "six", "name": "Six Spoke", "open": true, "color": Color(0.7, 0.71, 0.73)},
	{"id": "star5", "name": "Deep Star", "open": true, "color": Color(0.72, 0.73, 0.75)},
	{"id": "ten", "name": "Ten Spoke", "open": true, "color": Color(0.72, 0.73, 0.75)},
	{"id": "mesh", "name": "Mesh", "open": true, "color": Color(0.72, 0.73, 0.75)},
	{"id": "twist", "name": "Twister", "open": true, "color": Color(0.72, 0.73, 0.75)},
	{"id": "turbine", "name": "Turbine", "open": true, "color": Color(0.8, 0.81, 0.82)},
	{"id": "dish", "name": "Retro Dish", "open": false, "color": Color(0.85, 0.85, 0.84)},
	{"id": "steel", "name": "Steelie", "open": false, "color": Color(0.78, 0.78, 0.76)},
	{"id": "beadlock", "name": "Beadlock", "open": false, "color": Color(0.2, 0.21, 0.22)},
]

## Tyres (assets/models/wheels/tyre_<id>.glb), all 0.37 m round like every
## wheel model: `bead` is the rim radius they fit, `width` their width.
const TYRES := [
	{"id": "sport", "name": "Sport", "bead": 0.243, "width": 0.254},
	{"id": "road", "name": "Road", "bead": 0.222, "width": 0.235},
	{"id": "allterrain", "name": "All-Terrain", "bead": 0.222, "width": 0.27},
	{"id": "offroad", "name": "Off-Road", "bead": 0.21, "width": 0.30},
	{"id": "heavy", "name": "Heavy Duty", "bead": 0.205, "width": 0.26},
]

## Rim finishes (ART_BIBLE.md §13: bare metal is metallic 1, paint 0).
## "stock" keeps each rim's own finish; "body" matches the paint.
const RIM_COLORS := [
	{"id": "stock", "name": "Stock"},
	{"id": "silver", "name": "Silver", "color": Color(0.74, 0.75, 0.77), "metal": 1.0, "rough": 0.32},
	{"id": "chrome", "name": "Chrome", "color": Color(0.86, 0.87, 0.88), "metal": 1.0, "rough": 0.08},
	{"id": "gunmetal", "name": "Gunmetal", "color": Color(0.4, 0.41, 0.43), "metal": 1.0, "rough": 0.35},
	{"id": "black", "name": "Black", "color": Color(0.12, 0.12, 0.13), "metal": 0.0, "rough": 0.45},
	{"id": "white", "name": "White", "color": Color(0.9, 0.9, 0.88), "metal": 0.0, "rough": 0.35},
	{"id": "gold", "name": "Gold", "color": Color(0.94, 0.78, 0.45), "metal": 1.0, "rough": 0.25},
	{"id": "bronze", "name": "Bronze", "color": Color(0.62, 0.45, 0.27), "metal": 1.0, "rough": 0.35},
	{"id": "red", "name": "Red", "color": Color(0.76, 0.11, 0.09), "metal": 0.0, "rough": 0.3},
	{"id": "blue", "name": "Blue", "color": Color(0.13, 0.32, 0.74), "metal": 0.0, "rough": 0.3},
	{"id": "lime", "name": "Lime", "color": Color(0.5, 0.76, 0.15), "metal": 0.0, "rough": 0.3},
	{"id": "body", "name": "Body Colour"},
]

## Coloured sidewall bands. `band` is from/to as fractions of the sidewall
## height (0 = rim, 1 = tread); the swatch draws `ring` px of colour round a
## tyre-black middle.
const TYRE_STRIPES := [
	{"id": "none", "name": "None", "color": Color(0.11, 0.11, 0.12)},
	{"id": "whitewall", "name": "White Wall", "color": Color(0.9, 0.9, 0.87), "band": Vector2(0.3, 0.78), "ring": 9},
	{"id": "white", "name": "White Line", "color": Color(0.9, 0.9, 0.87), "band": Vector2(0.6, 0.7), "ring": 4},
	{"id": "red", "name": "Red Line", "color": Color(0.78, 0.12, 0.1), "band": Vector2(0.6, 0.7), "ring": 4},
	{"id": "blue", "name": "Blue Line", "color": Color(0.15, 0.38, 0.85), "band": Vector2(0.6, 0.7), "ring": 4},
	{"id": "yellow", "name": "Yellow Line", "color": Color(0.95, 0.76, 0.12), "band": Vector2(0.6, 0.7), "ring": 4},
]

## Brake caliper colours (only seen behind open rims).
const CALIPER_COLORS := [
	{"id": "red", "name": "Red", "color": Color(0.78, 0.09, 0.06)},
	{"id": "yellow", "name": "Yellow", "color": Color(0.93, 0.7, 0.08)},
	{"id": "orange", "name": "Orange", "color": Color(0.9, 0.4, 0.08)},
	{"id": "green", "name": "Green", "color": Color(0.25, 0.62, 0.2)},
	{"id": "blue", "name": "Blue", "color": Color(0.13, 0.32, 0.78)},
	{"id": "silver", "name": "Silver", "color": Color(0.7, 0.71, 0.72)},
	{"id": "grey", "name": "Grey", "color": Color(0.3, 0.3, 0.31)},
	{"id": "black", "name": "Black", "color": Color(0.14, 0.14, 0.15)},
]

static var _paint_options: Array = []


static func slot_name(slot: String) -> String:
	return SLOTS[slot]["name"]


static func kind(slot: String) -> String:
	return SLOTS[slot]["kind"]


## The options of a slot, in garage order: Dictionaries with "id" and "name"
## (swatches also have "color"; paint options also "paint", the Color value).
static func options(slot: String) -> Array:
	match slot:
		"paint":
			if _paint_options.is_empty():
				for i in PaintPalette.GARAGE.size():
					var c := PaintPalette.GARAGE[i]
					_paint_options.append({"id": str(i), "name": PaintPalette.GARAGE_NAMES[i], "color": c, "paint": c})
			return _paint_options
		"stripes":
			return [{"id": "off", "name": "Off"}, {"id": "on", "name": "On"}]
		"rims":
			return RIMS
		"rim_color":
			return RIM_COLORS
		"tyres":
			return TYRES
		"tyre_stripe":
			return TYRE_STRIPES
		"calipers":
			return CALIPER_COLORS
	return []


## The option with this id ({} if there is none).
static func option(slot: String, id: String) -> Dictionary:
	for o: Dictionary in options(slot):
		if o["id"] == id:
			return o
	return {}


## Index in options(slot) of a slot value (paint: the closest colour).
static func index_of(slot: String, value: Variant) -> int:
	match slot:
		"paint":
			return closest_color(PaintPalette.GARAGE, value)
		"stripes":
			return 1 if value else 0
	var opts := options(slot)
	for i in opts.size():
		if opts[i]["id"] == value:
			return i
	return 0


## The slot value of options(slot)[index].
static func value_at(slot: String, index: int) -> Variant:
	var opts := options(slot)
	var o: Dictionary = opts[wrapi(index, 0, opts.size())]
	match slot:
		"paint":
			return o["paint"]
		"stripes":
			return o["id"] == "on"
	return o["id"]


## Index of the colour in `colors` nearest to `c`.
static func closest_color(colors: Array, c: Color) -> int:
	var best := 0
	var best_d := INF
	for i in colors.size():
		var o: Color = colors[i]
		var d := Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


static func rim_scene(id: String) -> String:
	return "res://assets/models/wheels/rim_%s.glb" % id


static func tyre_scene(id: String) -> String:
	return "res://assets/models/wheels/tyre_%s.glb" % id
