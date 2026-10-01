class_name MapLayout
extends RefCounted
## Every number that defines the map lives here, so the world can be reshaped
## without digging through the builders.
##
## Coordinates: X = east, Z = south, Y = up (Godot's -Z is "north").
## Rough layout:
##   city grid in the middle, a ring highway around it (elevated where it
##   crosses the north/south avenues), a mountain with a loop road to the
##   north, the stunt park to the south, dirt fields east, beach west,
##   all on an island.

# --- City ---
const CITY_GRID: Array[float] = [-150.0, -75.0, 0.0, 75.0, 150.0]
const CITY_ROAD_WIDTH := 12.0
const SIDEWALK_WIDTH := 4.0
const CURB_HEIGHT := 0.15
## Block type per [row z][column x], north to south, west to east.
const BLOCK_TYPES := [
	["buildings", "buildings", "park", "buildings"],
	["buildings", "plaza", "buildings", "parking"],
	["parking", "buildings", "buildings", "buildings"],
	["buildings", "park", "parking", "buildings"],
]

# --- Highway ring ---
const HIGHWAY_HALF_EXTENT := 250.0
const HIGHWAY_CORNER_RADIUS := 100.0
const HIGHWAY_LANES := 3
const HIGHWAY_LANE_WIDTH := 3.6
const HIGHWAY_MEDIAN := 2.4
const HIGHWAY_SHOULDER := 1.4
const HIGHWAY_BRIDGE_HEIGHT := 9.0
## Path distance from each overpass centre that stays at full height.
const HIGHWAY_BRIDGE_FLAT := 55.0
const HIGHWAY_BRIDGE_RAMP := 170.0

static func highway_width() -> float:
	return HIGHWAY_MEDIAN + 2.0 * (HIGHWAY_LANES * HIGHWAY_LANE_WIDTH + HIGHWAY_SHOULDER)

# --- Avenues leaving the city ---
const AVENUE_NORTH_END := -295.5
const AVENUE_SOUTH_END := 305.0
const AVENUE_EAST_END := 335.0
const AVENUE_WEST_END := -330.0

# --- Mountain (north) ---
const MOUNTAIN_CENTER := Vector2(0.0, -490.0)
const MOUNTAIN_HEIGHT := 48.0
const MOUNTAIN_RADIUS := 100.0
const HILL_ROAD_WIDTH := 9.0
const HILL_LOOP := [
	Vector2(0, -300), Vector2(-60, -310), Vector2(-120, -345), Vector2(-150, -410),
	Vector2(-140, -480), Vector2(-90, -540), Vector2(-20, -565), Vector2(50, -555),
	Vector2(115, -510), Vector2(150, -440), Vector2(140, -370), Vector2(100, -322),
	Vector2(50, -305),
]
## Dirt trail zig-zagging up the mountain's south face (gentle grades) from
## near the hill loop junction to the summit.
const MOUNTAIN_TRAIL := [
	Vector2(0, -318), Vector2(55, -345), Vector2(-45, -372), Vector2(45, -400),
	Vector2(-35, -425), Vector2(25, -450), Vector2(0, -468),
]
const TRAIL_WIDTH := 6.0
const SUMMIT_ROAD := [
	Vector2(-147, -440), Vector2(-110, -462), Vector2(-60, -485), Vector2(-22, -490),
]
const SUMMIT_RADIUS := 26.0

# --- Stunt park (south) ---
const PARK_MIN := Vector2(-190.0, 305.0)
const PARK_MAX := Vector2(190.0, 520.0)

# --- Dirt fields (east) ---
const FIELDS_CENTER := Vector2(420.0, 0.0)
const DIRT_MOUNDS := [
	# x, z, radius, height
	Vector4(370, -40, 9, 2.5), Vector4(400, -40, 9, 3.0), Vector4(430, -40, 10, 3.5),
	Vector4(380, 50, 14, 5.0), Vector4(450, 60, 18, 7.0), Vector4(480, -90, 12, 4.0),
	Vector4(360, 110, 8, 2.0), Vector4(375, 110, 8, 2.0), Vector4(390, 110, 8, 2.0),
	Vector4(405, 110, 8, 2.0), Vector4(420, 110, 8, 2.0),
]

# --- Beach (west) ---
const BEACH_LOT := Vector2(-352.0, 0.0)

# --- Island / terrain ---
const TERRAIN_HALF_SIZE := 640.0
const TERRAIN_CELL := 4.0
const SEA_LEVEL := -1.2
const SHORE_DISTANCE := 575.0
const SHORE_DISTANCE_WEST := 430.0
const CORE_FLAT_HEIGHT := -0.05
