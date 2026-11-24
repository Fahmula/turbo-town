@tool
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

## City car parks with EV chargers ([column, row] in BLOCK_TYPES): two
## chargers at the west end of the first row of stalls, each between two
## green bays (kept free of parked cars).
const EV_PARKING: Array[Vector2i] = [Vector2i(3, 1), Vector2i(2, 3)]
const EV_BAYS := 4
## Car park stalls (CityBuilder._add_parking): width, depth, first row's
## inset from the block's inner edge, first stall's inset.
const STALL_WIDTH := 2.9
const STALL_DEPTH := 5.5
const STALL_ROW_INSET := 1.0
const STALL_X_INSET := 3.0
## The TURBO FUEL station (LandmarksBuilder) by the east avenue.
const GAS_STATION := Vector3(198, 0, -32)


## The inner north-west corner (x, z) of an EV car park block.
static func ev_parking_corner(block: Vector2i) -> Vector2:
	var hw := CITY_ROAD_WIDTH * 0.5
	return Vector2(CITY_GRID[block.x] + hw + SIDEWALK_WIDTH, CITY_GRID[block.y] + hw + SIDEWALK_WIDTH)


## Is the car park whose inner corner is (x0, z0) one with chargers?
static func is_ev_parking(x0: float, z0: float) -> bool:
	for b in EV_PARKING:
		if ev_parking_corner(b).distance_to(Vector2(x0, z0)) < 0.5:
			return true
	return false


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

# --- Airport (south-east): runway with an apron of hangars to its north ---
const RUNWAY_A := Vector3(285, 1.0, 300)
const RUNWAY_B := Vector3(525, 1.0, 300)
const RUNWAY_WIDTH := 28.0
const APRON_CENTER := Vector3(335, 1.0, 258)
const APRON_SIZE := Vector2(100, 36)
## Two helipads east of the apron (centre, on the ground). The garage's
## helicopter starts on the first (in split-screen the players 14 m apart);
## a parked one stands on the second.
const HELIPAD_A := Vector3(402, 1.0, 254)
const HELIPAD_B := Vector3(430, 1.0, 254)
const HELIPAD_SIZE := 24.0

# --- Tunnel through a hill on the south avenue ---
const TUNNEL_Z0 := 180.0
const TUNNEL_Z1 := 228.0
const TUNNEL_HALF_WIDTH := 7.5
const TUNNEL_HILL_HALF_WIDTH := 32.0

# --- Harbour on the north-west coast: a quay with piers into the sea ---
const HARBOR_QUAY_A := Vector3(-392, 1.2, -200)
const HARBOR_QUAY_B := Vector3(-392, 1.2, -280)

# --- Marina: boats (LandmarksBuilder._build_marina) ---
## A floating pontoon off the quay between the first two piers (its centre
## line x, ends z, width, deck height just above the water), reached by a
## gangway down from the quay. Finger berths run west from it (their centre
## lines z), so moored boats lie bow-out toward the open sea. The sea floor is
## dredged round it (MARINA_BASIN: x0, z0, x1, z1; TerrainBuilder).
const MARINA_X := -423.0
const MARINA_Z0 := -236.0
const MARINA_Z1 := -219.0
const MARINA_WIDTH := 2.8
const MARINA_DECK := -0.75   # SEA_LEVEL + 0.45
const MARINA_FINGERS: Array[float] = [-235.4, -227.5, -219.6]
const MARINA_FINGER_LENGTH := 7.0
const MARINA_FINGER_WIDTH := 1.2
const MARINA_GANGWAY_Z := -229.5
const MARINA_BASIN := Vector4(-447.0, -239.0, -419.0, -216.0)
## Where the two parked speedboats lie (their origin, on the water line),
## bow to the west, one along each outer finger.
const MARINA_BERTHS: Array[Vector2] = [Vector2(-428.6, -233.12), Vector2(-428.6, -221.88)]
## Open water where a boat is put (the garage, teleports, the help button
## off a beach): x, z and the way it faces (x, z). The marina's channel
## first.
const BOAT_SPOTS: Array[Vector4] = [
	Vector4(-441.0, -227.5, -1.0, 0.0),     # Harbour: the marina's channel, heading out
	Vector4(-460.0, 26.0, 0.0, 1.0),        # off the west beach, south of the islet bridge
	Vector4(-530.0, 58.0, -1.0, 0.0),       # south of Lighthouse Island
	Vector4(0.0, 612.0, 1.0, 0.0),          # off the stunt park, south coast
	Vector4(612.0, 0.0, 0.0, 1.0),          # off the dirt fields, east coast
	Vector4(560.0, 470.0, -0.7, 0.7),       # south-east, past the airfield
	Vector4(0.0, -632.0, -1.0, 0.0),        # under the mountain, north coast
	Vector4(-420.0, 520.0, 0.6, 0.8),       # south-west
]

## Floating jump ramps for boats (their low lip just under the water, rising
## the way they face): x, z and the way they face (x, z).
const BOAT_RAMPS: Array[Vector4] = [
	Vector4(-500.0, -244.0, -1.0, 0.0),     # off the marina's mouth
	Vector4(-460.0, 72.0, 0.0, 1.0),        # ahead of the west beach spot
	Vector4(70.0, 612.0, 1.0, 0.0),         # ahead of the south coast spot
]

# --- Lighthouse islet off the west beach, joined by a bridge ---
const ISLET_CENTER := Vector2(-528, 0)
const ISLET_RADIUS := 30.0
const ISLET_HEIGHT := 3.0
const BRIDGE_EAST_X := -405.0
const BRIDGE_WEST_X := -506.0
const BRIDGE_WIDTH := 9.0

# --- Island / terrain ---
const TERRAIN_HALF_SIZE := 640.0
const TERRAIN_CELL := 4.0
const SEA_LEVEL := -1.2
const SHORE_DISTANCE := 575.0
const SHORE_DISTANCE_WEST := 430.0
const CORE_FLAT_HEIGHT := -0.05
