@tool
class_name FuelBuilder
extends RefCounted
## Where to fill up and charge (FuelSite), built after the landmarks:
## * TURBO FUEL (LandmarksBuilder draws its pumps): eight hoses, both sides
##   of both pumps on each island, and two EV chargers on green bays on the
##   east side of the forecourt.
## * Two city car parks (MapLayout.EV_PARKING): two chargers each, between
##   green bays at the west end of the first row.
## * The airfield: a fuel cabinet with a hose reel on the apron.
## * Each helipad: a small fuel cabinet on its south side, clear of the rotor.
## * The marina: a fuel cabinet on the pontoon's north end, for boats only.
## The props are new geometry here (FuelKit); the hoses and their handles
## are the sites' own (FuelPump), only made when the game runs.

## Hose leads (m): station hoses, charger cables, the reels at the airfield.
const STATION_LEAD := 5.0
const CHARGER_LEAD := 5.5
const AIR_LEAD := 9.0
const HELIPAD_LEAD := 9.5
const MARINA_LEAD := 8.0

var _make_sites := not Engine.is_editor_hint()


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Fuel"
	parent.add_child(root)
	_gas_station(root)
	_station_chargers(root)
	var k := 0
	for block in MapLayout.EV_PARKING:
		_parking_chargers(root, block, k)
		k += 1
	_airfield(root)
	for pad: Vector3 in [MapLayout.HELIPAD_A, MapLayout.HELIPAD_B]:
		_helipad(root, pad)
	_marina(root)


func _site(root: Node3D, site_name: String, kind: VehicleFuel.Kind, title: String) -> FuelSite:
	if not _make_sites:
		return null
	var s := FuelSite.new()
	s.name = site_name
	s.kind = kind
	s.title = title
	root.add_child(s)
	return s


func _props(root: Node3D, body_name: String, mb: MeshBuilder, body: StaticBody3D) -> void:
	body.name = body_name
	var mi := MeshInstance3D.new()
	mi.name = "Props"
	mi.mesh = MeshBuilder.with_lods(mb.build_mesh(StreetKit.material()))
	mi.visibility_range_end = 250.0
	mi.visibility_range_end_margin = 10.0
	body.add_child(mi)
	root.add_child(body)


## A green painted bay (`size` x, z) centred at `center` (on the ground),
## turned by `basis`: a thin painted slab on the props material (on the
## paving material green reads as lawn).
static func _bay(mb: MeshBuilder, basis: Basis, center: Vector3, size: Vector2) -> void:
	mb.add_bevel_box(Transform3D(basis, center + Vector3.UP * 0.006), Vector3(size.x, 0.008, size.y), 0.002,
		Color(ArtPalette.EV_GREEN, StreetKit.PAINTED))


# ----------------------------------------------------------- TURBO FUEL --

func _gas_station(root: Node3D) -> void:
	var s := _site(root, "GasStation", VehicleFuel.Kind.FUEL, "TURBO FUEL")
	if s == null:
		return
	var c := MapLayout.GAS_STATION
	for px: float in [-5.0, 5.0]:
		for pz: float in [-2.0, 2.0]:
			for side: float in [-1.0, 1.0]:
				# The hose leaves the pump's side high up; the nozzle hangs in
				# the holster on the pump's end, spout down.
				var outlet := c + Vector3(px + side * 0.44, 1.2, pz - 0.18)
				var rest := Transform3D(Basis(Vector3.UP, -side * PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5),
					c + Vector3(px + side * 0.53, 0.98, pz + 0.04))
				var readout := Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI), c + Vector3(px, 1.3, pz + side * 0.345))
				s.add_pump(outlet, rest, STATION_LEAD, c.y + 0.02, readout)


## Two chargers on the forecourt's east side, facing west over green bays.
func _station_chargers(root: Node3D) -> void:
	var c := MapLayout.GAS_STATION
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	var s := _site(root, "StationChargers", VehicleFuel.Kind.BATTERY, "Chargers")
	for dz: float in [-9.5, -3.5]:
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), c + Vector3(23.0, 0.02, dz))
		var parts := FuelKit.add_charger(mb, body, xf)
		_bay(mb, xf.basis, xf.origin + xf.basis * Vector3(0.0, 0.0, -2.95), Vector2(2.7, 5.0))
		if s:
			s.add_pump(parts[0], parts[1], CHARGER_LEAD, c.y + 0.02, _screen(xf))
	_props(root, "StationChargerProps", mb, body)


## Where a charger's screen shows the charge (its front, just proud of it).
static func _screen(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis * Basis(Vector3.UP, PI), xf.origin + xf.basis * Vector3(0, 1.29, -0.152))


# ------------------------------------------------------------ car parks --

func _parking_chargers(root: Node3D, block: Vector2i, k: int) -> void:
	var corner := MapLayout.ev_parking_corner(block)
	var y := MapLayout.CURB_HEIGHT
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	var s := _site(root, "ParkingChargers%d" % (k + 1), VehicleFuel.Kind.BATTERY, "Chargers")
	for pair in 2:
		# On the line between bays 2k and 2k+1, in the strip between the
		# pavement and the stalls' noses, facing the bays (south).
		var x := corner.x + MapLayout.STALL_X_INSET + MapLayout.STALL_WIDTH * (1 + 2 * pair)
		var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, corner.y + MapLayout.STALL_ROW_INSET * 0.45))
		var parts := FuelKit.add_charger(mb, body, xf)
		if s:
			s.add_pump(parts[0], parts[1], CHARGER_LEAD, y, _screen(xf))
	# The green bays: the first stalls of the row (CityBuilder keeps them free),
	# inside their white lines.
	for bay in MapLayout.EV_BAYS:
		var x0 := corner.x + MapLayout.STALL_X_INSET + MapLayout.STALL_WIDTH * bay
		var z0 := corner.y + MapLayout.STALL_ROW_INSET
		_bay(mb, Basis.IDENTITY, Vector3(x0 + MapLayout.STALL_WIDTH * 0.5, y + 0.004, z0 + MapLayout.STALL_DEPTH * 0.5),
			Vector2(MapLayout.STALL_WIDTH - 0.24, MapLayout.STALL_DEPTH - 0.2))
	_props(root, "ParkingChargerProps%d" % (k + 1), mb, body)


# ------------------------------------------------------------- aircraft --

## The airfield's fuel cabinet on the apron, between the parked planes and
## west of the taxiway, facing south (planes pull up in front of it).
func _airfield(root: Node3D) -> void:
	var ac := MapLayout.APRON_CENTER
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	var xf := Transform3D(Basis(Vector3.UP, PI), ac + Vector3(-13.0, 0.02, 4.0))
	var parts := FuelKit.add_air_pump(mb, body, xf)
	var s := _site(root, "AirfieldFuel", VehicleFuel.Kind.FUEL, "Airfield fuel")
	if s:
		s.for_cars = true
		s.for_planes = true
		s.add_pump(parts[0], parts[1], AIR_LEAD, ac.y + 0.02, _cabinet_screen(xf))
	_props(root, "AirfieldFuelProps", mb, body)


## A helipad's fuel cabinet on its south side, inside the pad but clear of
## the rotor (5 m) of a helicopter on the H, facing the H.
func _helipad(root: Node3D, pad: Vector3) -> void:
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	# South of the H (a helicopter on the pad faces south, its tail boom
	# reaching over the north side), facing north.
	var xf := Transform3D(Basis.IDENTITY, pad + Vector3(0.0, 0.03, 6.1))
	var parts := FuelKit.add_air_pump(mb, body, xf)
	var s := _site(root, "HelipadFuel%s" % ("A" if pad == MapLayout.HELIPAD_A else "B"), VehicleFuel.Kind.FUEL, "Helipad fuel")
	if s:
		s.for_cars = true
		s.for_planes = true
		s.add_pump(parts[0], parts[1], HELIPAD_LEAD, pad.y + 0.03, _cabinet_screen(xf))
	_props(root, "HelipadFuelProps%s" % ("A" if pad == MapLayout.HELIPAD_A else "B"), mb, body)


# ----------------------------------------------------------------- boats --

## The marina's fuel cabinet on the pontoon's north end, its hose reel
## toward the berths (boats pull up alongside the first finger or the
## pontoon's west side).
func _marina(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	# Facing west (its front, with the screen and the holster, toward the water).
	var at := Vector3(MapLayout.MARINA_X + 0.35, MapLayout.MARINA_DECK, MapLayout.MARINA_Z0 + 1.3)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), at)
	var parts := FuelKit.add_air_pump(mb, body, xf)
	var s := _site(root, "MarinaFuel", VehicleFuel.Kind.FUEL, "Marina fuel")
	if s:
		s.for_cars = false
		s.for_boats = true
		s.add_pump(parts[0], parts[1], MARINA_LEAD, MapLayout.MARINA_DECK, _cabinet_screen(xf))
	_props(root, "MarinaFuelProps", mb, body)


static func _cabinet_screen(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis * Basis(Vector3.UP, PI), xf.origin + xf.basis * Vector3(-0.15, 1.08, -0.32))
