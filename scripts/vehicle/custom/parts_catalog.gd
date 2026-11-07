class_name PartsCatalog
extends RefCounted
## Everything the garage can change on a vehicle, as data: the tabs, the
## slots (one garage row each) and the options in each slot. A Loadout holds
## one vehicle's choices and puts them on the vehicle; the garage
## (VehiclePicker) builds its tabs and rows from this file.
##
## To add customization:
##   * an option in an existing slot: add an entry to its list below (models
##     come from a committed generator, e.g. tools/blender/make_wheels.py or
##     make_kits.py);
##   * a slot: add it to SLOTS and to a tab in TABS, give it a stock value in
##     Loadout._stock_values() and put it on the vehicle in Loadout.apply();
##   * a tab: add it to TABS. `focus` is what the garage camera looks at
##     ("car" or "wheel"; a slot's own `view` wins while its row is picked).
##
## An option with `on` (a list of VehicleCatalog ids) only fits those
## vehicles; options(slot, vehicle_id) leaves out the ones that don't fit.
## A row with nothing but its stock option on a vehicle is greyed out there.

## Garage tabs, left to right. "car" is the vehicle choice itself.
const TABS := [
	{"id": "car", "name": "CAR", "slots": [], "focus": "car"},
	{"id": "body", "name": "BODY", "slots": ["front", "rear", "skirts", "flares", "spoiler", "bonnet", "roof"], "focus": "car"},
	{"id": "paint", "name": "PAINT", "slots": ["paint", "finish", "two_tone", "tone_color", "stripes"], "focus": "car"},
	{"id": "decals", "name": "DECALS", "slots": ["decal", "decal_color", "number"], "focus": "car"},
	{"id": "wheels", "name": "WHEELS", "slots": ["rims", "rim_color", "tyres", "tyre_stripe", "calipers"], "focus": "wheel"},
	{"id": "extras", "name": "EXTRAS", "slots": ["underglow", "horn"], "focus": "car"},
]

## Slot id -> how the garage shows it. Kinds: "choice" (named options,
## left/right steps through them), "swatch" (a grid of coloured options),
## "toggle" (on/off). Values: paint is a Color, toggles are bools, every
## other slot holds an option id. `view`: where the garage camera looks
## while the row is picked ("front", "rear", "side", "top", "low").
const SLOTS := {
	"paint": {"name": "PAINT", "kind": "swatch"},
	"finish": {"name": "FINISH", "kind": "choice"},
	"two_tone": {"name": "TWO-TONE", "kind": "choice", "view": "top"},
	"tone_color": {"name": "SECOND COLOUR", "kind": "swatch", "view": "top"},
	"stripes": {"name": "RACING STRIPES", "kind": "toggle"},
	"decal": {"name": "DECAL", "kind": "choice", "view": "side"},
	"decal_color": {"name": "DECAL COLOUR", "kind": "swatch", "view": "side"},
	"number": {"name": "RACE NUMBER", "kind": "choice", "view": "side"},
	"front": {"name": "FRONT BUMPER", "kind": "choice", "view": "front"},
	"rear": {"name": "REAR BUMPER", "kind": "choice", "view": "rear"},
	"skirts": {"name": "SIDE SKIRTS", "kind": "choice", "view": "side"},
	"flares": {"name": "WHEEL ARCHES", "kind": "choice", "view": "front"},
	"spoiler": {"name": "SPOILER", "kind": "choice", "view": "rear"},
	"bonnet": {"name": "BONNET", "kind": "choice", "view": "top"},
	"roof": {"name": "ROOF", "kind": "choice", "view": "top"},
	"rims": {"name": "RIMS", "kind": "choice"},
	"rim_color": {"name": "RIM COLOUR", "kind": "swatch"},
	"tyres": {"name": "TYRES", "kind": "choice"},
	"tyre_stripe": {"name": "TYRE STRIPE", "kind": "swatch"},
	"calipers": {"name": "BRAKES", "kind": "swatch"},
	"underglow": {"name": "UNDERGLOW", "kind": "swatch", "view": "low"},
	"horn": {"name": "HORN", "kind": "choice"},
}

## The vehicles with full body kits (bumpers, skirts, arches).
const KIT_VEHICLES := ["sports_car", "sedan"]

## Body parts (assets/models/kits/<vehicle>_kit.glb, make_kits.py). The kit
## holds one node per part, named "<slot>_<id>". "stock" is the vehicle as it
## comes; "none" takes the stock part off. Bumpers and spoilers keep the
## names VehicleDamage knocks off (FrontBumper, RearBumper, Spoiler).
const BODY_PARTS := {
	"front": [
		{"id": "stock", "name": "Stock"},
		{"id": "sport", "name": "Sport", "on": KIT_VEHICLES},
		{"id": "race", "name": "Race Splitter", "on": KIT_VEHICLES},
	],
	"rear": [
		{"id": "stock", "name": "Stock"},
		{"id": "sport", "name": "Sport", "on": KIT_VEHICLES},
		{"id": "race", "name": "Race Diffuser", "on": KIT_VEHICLES},
	],
	"skirts": [
		{"id": "stock", "name": "Stock"},
		{"id": "sport", "name": "Sport", "on": KIT_VEHICLES},
		{"id": "race", "name": "Race", "on": KIT_VEHICLES},
	],
	"flares": [
		{"id": "stock", "name": "Stock"},
		# Arches push the wheels out by `track` (m) each side, to fill them.
		{"id": "overfenders", "name": "Bolt-On Flares", "on": KIT_VEHICLES, "track": 0.035},
		{"id": "widebody", "name": "Wide Body", "on": KIT_VEHICLES, "track": 0.045},
	],
	"spoiler": [
		{"id": "stock", "name": "Stock"},
		{"id": "none", "name": "None", "on": ["sports_car", "buggy"]},
		{"id": "lip", "name": "Lip", "on": ["sports_car", "sedan", "van", "box_truck", "bus"]},
		{"id": "ducktail", "name": "Ducktail", "on": ["sports_car", "sedan", "van", "box_truck", "bus"]},
		{"id": "wing", "name": "GT Wing"},
		{"id": "mega", "name": "Mega Wing"},
	],
	"bonnet": [
		{"id": "stock", "name": "Stock"},
		{"id": "vents", "name": "Vents", "on": ["sports_car", "sedan", "pickup", "monster_truck"]},
		{"id": "scoop", "name": "Scoop", "on": ["sports_car", "sedan", "pickup", "monster_truck"]},
		{"id": "blower", "name": "Supercharger", "on": ["sports_car", "sedan", "pickup", "monster_truck"]},
	],
	"roof": [
		{"id": "stock", "name": "Stock"},
		{"id": "scoop", "name": "Roof Scoop", "on": ["sports_car", "sedan"]},
		{"id": "rack", "name": "Roof Rack", "on": ["sports_car", "sedan", "van", "pickup"]},
		{"id": "lights", "name": "Light Bar", "on": ["sports_car", "sedan", "van", "pickup", "box_truck"]},
		{"id": "box", "name": "Roof Box", "on": ["sedan", "van", "pickup"]},
	],
}

## Paint finishes. "stock" keeps each colour's own (solid or metallic,
## PaintPalette). The rest set the paint shader (ART_BIBLE.md §13).
const FINISHES := [
	{"id": "stock", "name": "Stock"},
	{"id": "gloss", "name": "Gloss", "metal": 0.0, "rough": 0.13, "coat": 0.6},
	{"id": "metallic", "name": "Metallic", "metal": 0.45, "rough": 0.2, "coat": 0.6},
	{"id": "pearl", "name": "Pearl", "metal": 0.3, "rough": 0.16, "coat": 0.7, "pearl": 1.0},
	{"id": "matte", "name": "Matte", "metal": 0.0, "rough": 0.62, "coat": 0.0},
	{"id": "chrome", "name": "Chrome", "metal": 1.0, "rough": 0.14, "coat": 0.3, "chrome": 1.0},
]

## Where the second colour goes (`mode` is the paint shader's tone_mode).
const TWO_TONES := [
	{"id": "off", "name": "Off", "mode": 0},
	{"id": "roof", "name": "Roof", "mode": 1},
	{"id": "bonnet", "name": "Bonnet", "mode": 2},
	{"id": "both", "name": "Bonnet + Roof", "mode": 3},
	{"id": "lower", "name": "Lower Half", "mode": 4},
]

## Graphics on the sides (`row` in the decal atlas, make_decals.py). `mode`
## places the strip (4x as long as the side is high): 0 from the nose,
## 1 from the tail, 2 stretched nose to tail.
const DECALS := [
	{"id": "none", "name": "None", "row": -1},
	{"id": "flames", "name": "Flames", "row": 0, "mode": 0},
	{"id": "lightning", "name": "Lightning", "row": 1, "mode": 2},
	{"id": "stars", "name": "Stars", "row": 2, "mode": 1},
	{"id": "checker", "name": "Checkered", "row": 3, "mode": 1},
	{"id": "speed", "name": "Speed Lines", "row": 4, "mode": 2},
	{"id": "splash", "name": "Paint Splash", "row": 5, "mode": 1},
]

const DECAL_COLORS := [
	{"id": "white", "name": "White", "color": Color(0.92, 0.92, 0.9)},
	{"id": "black", "name": "Black", "color": Color(0.11, 0.11, 0.12)},
	{"id": "yellow", "name": "Yellow", "color": Color(0.95, 0.76, 0.12)},
	{"id": "orange", "name": "Orange", "color": Color(0.93, 0.43, 0.1)},
	{"id": "red", "name": "Red", "color": Color(0.8, 0.1, 0.08)},
	{"id": "pink", "name": "Pink", "color": Color(0.92, 0.36, 0.62)},
	{"id": "purple", "name": "Purple", "color": Color(0.45, 0.22, 0.72)},
	{"id": "blue", "name": "Blue", "color": Color(0.13, 0.36, 0.85)},
	{"id": "teal", "name": "Teal", "color": Color(0.1, 0.62, 0.62)},
	{"id": "lime", "name": "Lime", "color": Color(0.52, 0.8, 0.15)},
	{"id": "silver", "name": "Silver", "color": Color(0.7, 0.71, 0.73)},
	{"id": "gold", "name": "Gold", "color": Color(0.85, 0.68, 0.3)},
]

## Race numbers: a white roundel on both doors and the bonnet.
const NUMBERS := ["none", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "17", "21",
	"23", "27", "33", "42", "44", "55", "64", "77", "88", "99"]

## Underglow colours (light under the car, Underglow).
const UNDERGLOW := [
	{"id": "off", "name": "Off", "color": Color(0.16, 0.16, 0.17)},
	{"id": "blue", "name": "Blue", "color": Color(0.15, 0.4, 1.0)},
	{"id": "cyan", "name": "Ice", "color": Color(0.2, 0.85, 1.0)},
	{"id": "green", "name": "Green", "color": Color(0.2, 1.0, 0.35)},
	{"id": "purple", "name": "Purple", "color": Color(0.6, 0.25, 1.0)},
	{"id": "pink", "name": "Pink", "color": Color(1.0, 0.3, 0.75)},
	{"id": "red", "name": "Red", "color": Color(1.0, 0.15, 0.1)},
	{"id": "orange", "name": "Orange", "color": Color(1.0, 0.5, 0.1)},
	{"id": "white", "name": "White", "color": Color(0.95, 0.95, 1.0)},
]

## Horns. "stock" is the vehicle's own (its VehicleSoundProfile); the rest
## are assets/audio/horn/<file>.wav (ASSET_MANIFEST.md), looped while held.
const HORNS := [
	{"id": "stock", "name": "Stock"},
	{"id": "car", "name": "Beep Beep", "file": "car", "pitch": 1.0, "db": -7.0},
	{"id": "high", "name": "Little Toot", "file": "car", "pitch": 1.4, "db": -9.0},
	{"id": "air", "name": "Truck", "file": "air", "pitch": 1.0, "db": -9.0},
	{"id": "air_big", "name": "Big Rig", "file": "air_big", "pitch": 1.0, "db": -8.0},
	{"id": "klaxon", "name": "Old-Timer", "file": "klaxon", "pitch": 1.0, "db": -8.0},
	{"id": "tune", "name": "Tune", "file": "tune", "pitch": 1.0, "db": -7.0},
	{"id": "clown", "name": "Clown", "file": "clown", "pitch": 1.0, "db": -7.0},
	{"id": "train", "name": "Train", "file": "train", "pitch": 1.0, "db": -9.0},
]

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
static var _number_options: Array = []


static func slot_name(slot: String) -> String:
	return SLOTS[slot]["name"]


static func kind(slot: String) -> String:
	return SLOTS[slot]["kind"]


## The options of a slot, in garage order: Dictionaries with "id" and "name"
## (swatches also have "color"; paint options also "paint", the Color value).
## With a vehicle id, only the options that fit that vehicle.
static func options(slot: String, vehicle_id := "") -> Array:
	var all := _all_options(slot)
	if vehicle_id.is_empty():
		return all
	var fit := []
	for o: Dictionary in all:
		if fits(o, vehicle_id):
			fit.append(o)
	return fit


## True if option `o` fits vehicle `vehicle_id` (planes take no body parts).
static func fits(o: Dictionary, vehicle_id: String) -> bool:
	if o.has("on"):
		return vehicle_id in (o["on"] as Array)
	return true


static func _all_options(slot: String) -> Array:
	match slot:
		"paint", "tone_color":
			if _paint_options.is_empty():
				for i in PaintPalette.GARAGE.size():
					var c := PaintPalette.GARAGE[i]
					_paint_options.append({"id": str(i), "name": PaintPalette.GARAGE_NAMES[i], "color": c, "paint": c})
			return _paint_options
		"stripes":
			return [{"id": "off", "name": "Off"}, {"id": "on", "name": "On"}]
		"finish":
			return FINISHES
		"two_tone":
			return TWO_TONES
		"decal":
			return DECALS
		"decal_color":
			return DECAL_COLORS
		"number":
			if _number_options.is_empty():
				for n: String in NUMBERS:
					_number_options.append({"id": n, "name": "None" if n == "none" else "#" + n})
			return _number_options
		"underglow":
			return UNDERGLOW
		"horn":
			return HORNS
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
	if BODY_PARTS.has(slot):
		return BODY_PARTS[slot]
	return []


## True if `slot` is a body part (BodyKit fits it).
static func is_body_slot(slot: String) -> bool:
	return BODY_PARTS.has(slot)


## The option with this id ({} if there is none).
static func option(slot: String, id: String) -> Dictionary:
	for o: Dictionary in _all_options(slot):
		if o["id"] == id:
			return o
	return {}


## Index in options(slot, vehicle_id) of a slot value (paint: the closest
## colour). 0 if the value isn't there.
static func index_of(slot: String, value: Variant, vehicle_id := "") -> int:
	match slot:
		"paint":
			return closest_color(PaintPalette.GARAGE, value)
		"stripes":
			return 1 if value else 0
	var opts := options(slot, vehicle_id)
	for i in opts.size():
		if opts[i]["id"] == value:
			return i
	return 0


## The slot value of options(slot, vehicle_id)[index] (wrapped round).
static func value_at(slot: String, index: int, vehicle_id := "") -> Variant:
	var opts := options(slot, vehicle_id)
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


static func kit_scene(vehicle_id: String) -> String:
	return "res://assets/models/kits/%s_kit.glb" % vehicle_id


static func horn_stream(id: String) -> String:
	var o := option("horn", id)
	return "res://assets/audio/horn/%s.wav" % o["file"] if o.has("file") else ""
