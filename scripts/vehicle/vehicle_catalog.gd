class_name VehicleCatalog
extends RefCounted
## The vehicles the player can pick in the garage, with the text and 1-5 star
## ratings shown there. Ratings follow the physics tests (time to 80 km/h,
## speed after 15 s, cornering), so they match how each vehicle really drives.
## `rims` and `tyres` are the PartsCatalog parts its own wheel model is made
## of (its stock wheels in the garage).
## To add a drivable vehicle: make its scene, then add an entry here.

const ENTRIES := [
	{
		"id": "sports_car", "scene": "res://scenes/vehicles/sports_car.tscn",
		"name": "Sports Car", "blurb": "Fast and nimble. Great for jumps and drifts!",
		"speed": 5, "accel": 5, "handling": 5, "smash": 1,
		"rims": "sport5", "tyres": "sport",
	},
	{
		"id": "sedan", "scene": "res://scenes/vehicles/sedan.tscn",
		"name": "Sedan", "blurb": "A comfy family car. Easy to drive.",
		"speed": 4, "accel": 3, "handling": 4, "smash": 2,
		"rims": "six", "tyres": "road",
	},
	{
		"id": "van", "scene": "res://scenes/vehicles/van.tscn",
		"name": "Van", "blurb": "Tall and bouncy. Watch it lean in the corners!",
		"speed": 3, "accel": 3, "handling": 3, "smash": 3,
		"rims": "steel", "tyres": "heavy",
	},
	{
		"id": "box_truck", "scene": "res://scenes/vehicles/box_truck.tscn",
		"name": "Delivery Truck", "blurb": "Big, heavy and strong. Turbo deliveries!",
		"speed": 2, "accel": 2, "handling": 2, "smash": 4,
		"rims": "steel", "tyres": "heavy",
	},
	{
		"id": "bus", "scene": "res://scenes/vehicles/bus.tscn",
		"name": "Bus", "blurb": "Huge and heavy. Pushes everything out of the way!",
		"speed": 2, "accel": 1, "handling": 1, "smash": 5,
		"rims": "steel", "tyres": "heavy",
	},
	{
		"id": "pickup", "scene": "res://scenes/vehicles/pickup.tscn",
		"name": "Pickup", "blurb": "Tough and handy. Good on the road and on the dirt.",
		"speed": 4, "accel": 3, "handling": 3, "smash": 3,
		"rims": "beadlock", "tyres": "offroad",
	},
	{
		"id": "buggy", "scene": "res://scenes/vehicles/buggy.tscn",
		"name": "Buggy", "blurb": "Light, bouncy and quick. Made for jumps and dirt!",
		"speed": 4, "accel": 5, "handling": 4, "smash": 1,
		"rims": "beadlock", "tyres": "offroad",
	},
	{
		"id": "monster_truck", "scene": "res://scenes/vehicles/monster_truck.tscn",
		"name": "Monster Truck", "blurb": "GIANT wheels! Drive right over the cars!",
		"speed": 3, "accel": 3, "handling": 2, "smash": 5,
		"rims": "beadlock", "tyres": "offroad",
	},
	{
		# "air": a plane (Aircraft). Picking it puts you on the Airfield's
		# runway; it isn't remembered as the vehicle you start with.
		"id": "plane", "scene": "res://scenes/vehicles/plane.tscn",
		"name": "Plane", "blurb": "Fly! Take off from the Airfield runway and loop the loop.",
		"speed": 5, "accel": 3, "handling": 4, "smash": 1,
		"air": true, "stripes": true,
	},
]

## Stat keys and the labels shown for them.
const STATS := [["speed", "SPEED"], ["accel", "ACCELERATION"], ["handling", "HANDLING"], ["smash", "SMASH POWER"]]

## Paint colours the player can choose from (same list for every vehicle;
## finishes and the traffic mix live in PaintPalette).
const COLORS: Array[Color] = PaintPalette.GARAGE


static func count() -> int:
	return ENTRIES.size()


static func scene(index: int) -> PackedScene:
	return load(ENTRIES[index]["scene"]) as PackedScene


## The entry with this id ({} if there is none).
static func entry(id: String) -> Dictionary:
	var i := index_of_id(id)
	return ENTRIES[i] if i >= 0 else {}


## A property a vehicle's scene sets on one of its nodes ("." = the vehicle,
## "Body" = its VehicleBodyVisual), read without instancing the scene;
## `fallback` if the scene leaves it at the default.
static func scene_value(index: int, node_path: String, property: String, fallback: Variant) -> Variant:
	var state := scene(index).get_state()
	var want := NodePath(node_path if node_path == "." else "./" + node_path)
	for n in state.get_node_count():
		if state.get_node_path(n) != want:
			continue
		for p in state.get_node_property_count(n):
			if state.get_node_property_name(n, p) == property:
				return state.get_node_property_value(n, p)
	return fallback


static func index_of_id(id: String) -> int:
	for i in ENTRIES.size():
		if ENTRIES[i]["id"] == id:
			return i
	return -1


## Which entry a vehicle node was instanced from (-1 if none).
static func index_of_vehicle(v: Vehicle) -> int:
	for i in ENTRIES.size():
		if ENTRIES[i]["scene"] == v.scene_file_path:
			return i
	return -1


## The catalog id of a vehicle node ("" if it isn't one of the catalog's).
static func id_of_vehicle(v: Vehicle) -> String:
	var i := index_of_vehicle(v)
	return ENTRIES[i]["id"] if i >= 0 else ""


## Index into COLORS of the colour closest to `c`.
static func closest_color(c: Color) -> int:
	var best := 0
	var best_d := INF
	for i in COLORS.size():
		var o := COLORS[i]
		var d := Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best
