class_name VehicleCatalog
extends RefCounted
## The vehicles the player can pick in the garage, with the text and 1-5 star
## ratings shown there. Ratings follow the physics tests (time to 80 km/h,
## speed after 15 s, cornering), so they match how each vehicle really drives.
## To add a drivable vehicle: make its scene, then add an entry here.

const ENTRIES := [
	{
		"id": "sports_car", "scene": "res://scenes/vehicles/sports_car.tscn",
		"name": "Sports Car", "blurb": "Fast and nimble. Great for jumps and drifts!",
		"speed": 5, "accel": 5, "handling": 5, "smash": 1,
	},
	{
		"id": "sedan", "scene": "res://scenes/vehicles/sedan.tscn",
		"name": "Sedan", "blurb": "A comfy family car. Easy to drive.",
		"speed": 4, "accel": 3, "handling": 4, "smash": 2,
	},
	{
		"id": "van", "scene": "res://scenes/vehicles/van.tscn",
		"name": "Van", "blurb": "Tall and bouncy. Watch it lean in the corners!",
		"speed": 3, "accel": 3, "handling": 3, "smash": 3,
	},
	{
		"id": "box_truck", "scene": "res://scenes/vehicles/box_truck.tscn",
		"name": "Delivery Truck", "blurb": "Big, heavy and strong. Turbo deliveries!",
		"speed": 2, "accel": 2, "handling": 2, "smash": 4,
	},
	{
		"id": "bus", "scene": "res://scenes/vehicles/bus.tscn",
		"name": "Bus", "blurb": "Huge and heavy. Pushes everything out of the way!",
		"speed": 2, "accel": 1, "handling": 1, "smash": 5,
	},
	{
		"id": "pickup", "scene": "res://scenes/vehicles/pickup.tscn",
		"name": "Pickup", "blurb": "Tough and handy. Good on the road and on the dirt.",
		"speed": 4, "accel": 3, "handling": 3, "smash": 3,
	},
	{
		"id": "buggy", "scene": "res://scenes/vehicles/buggy.tscn",
		"name": "Buggy", "blurb": "Light, bouncy and quick. Made for jumps and dirt!",
		"speed": 4, "accel": 5, "handling": 4, "smash": 1,
	},
	{
		"id": "monster_truck", "scene": "res://scenes/vehicles/monster_truck.tscn",
		"name": "Monster Truck", "blurb": "GIANT wheels! Drive right over the cars!",
		"speed": 3, "accel": 3, "handling": 2, "smash": 5,
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
