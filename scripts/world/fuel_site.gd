class_name FuelSite
extends Node3D
## A place to fill up or charge: the TURBO FUEL station's pumps, a row of EV
## chargers, the airfield's fuel cabinet, a helipad's. It owns its hoses
## (FuelPump children) and draws the ones resting in their holsters as one
## merged mesh (one draw call per site, rebuilt when a hose is taken or comes
## back). The maps mark it (pump or plug icon) and the low-fuel arrow
## points at the nearest one that serves the player's vehicle.

const GROUP := &"fuel_sites"

## FUEL: petrol nozzles; BATTERY: charging plugs.
var kind := VehicleFuel.Kind.FUEL
## Who it's for: cars and trucks can drive up to it; planes taxi to it
## (the airfield and the helipads); helicopters can land at any fuel site.
var for_cars := true
var for_planes := false
## A marina's pump: only boats can get to it (and only it serves them).
var for_boats := false
var title := "Gas station"
var pumps: Array[FuelPump] = []

var _rest: MeshInstance3D
var _rest_mesh: ArrayMesh


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


func _ready() -> void:
	_rest = MeshInstance3D.new()
	_rest.name = "RestingHoses"
	_rest_mesh = ArrayMesh.new()
	_rest.mesh = _rest_mesh
	_rest.visibility_range_end = 160.0
	_rest.visibility_range_end_margin = 10.0
	_rest.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	# (Thin hoses: their shadow isn't worth a pass per cascade.)
	_rest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rest)
	rebuild_rest()


## A hose (`plug`: a charging cable) leaving the pump at `outlet`, its handle
## resting at `rest` (world), `lead` m long, over ground at `floor_y`.
## `readout`: where the pump shows the fill (optional; Transform3D() = none).
func add_pump(outlet: Vector3, rest: Transform3D, lead: float, floor_y: float, readout := Transform3D()) -> FuelPump:
	var p := FuelPump.new()
	p.site = self
	p.plug = kind == VehicleFuel.Kind.BATTERY
	p.outlet = outlet
	p.rest = rest
	p.lead = lead
	p.floor_y = floor_y
	p.position = rest.origin
	if readout != Transform3D():
		p.readout_xf = readout
		p.has_readout = true
	pumps.append(p)
	add_child(p)
	return p


## Does this site fill `v`? (A battery needs a charger, a tank a pump; a
## plane can't drive to the gas station.)
func serves(v: Vehicle) -> bool:
	if v == null:
		return false
	if (kind == VehicleFuel.Kind.BATTERY) != v.electric:
		return false
	if v is Boat:
		return for_boats
	if for_boats:
		return false
	if v is Helicopter:
		return true
	if v is Aircraft:
		return for_planes
	return for_cars


## The middle of the site (for the maps and the arrow).
func center() -> Vector3:
	if pumps.is_empty():
		return global_position
	var c := Vector3.ZERO
	for p in pumps:
		c += p.rest.origin
	return c / pumps.size()


## Redraws the hoses resting in their holsters.
func rebuild_rest() -> void:
	if _rest_mesh == null:
		return
	var mb := MeshBuilder.new()
	for p in pumps:
		if p.state == FuelPump.State.RESTING:
			p.add_rest_to(mb)
	_rest_mesh.clear_surfaces()
	if not mb.is_empty():
		mb.build_mesh(StreetKit.material(), _rest_mesh)


## The nearest site that serves `v` from `at`, or null.
static func nearest_for(tree: SceneTree, v: Vehicle, at: Vector3) -> FuelSite:
	var best: FuelSite = null
	var best_d := INF
	for node in tree.get_nodes_in_group(GROUP):
		var s := node as FuelSite
		if s == null or not s.serves(v):
			continue
		var d := s.center().distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best


## A hose of a site that serves `v` within reach of its lead from `at`
## (someone sitting in a vehicle by a pump), or null.
static func pump_near(tree: SceneTree, v: Vehicle, at: Vector3) -> FuelPump:
	for node in tree.get_nodes_in_group(GROUP):
		var s := node as FuelSite
		if s == null or not s.serves(v):
			continue
		for p in s.pumps:
			if Vector2(p.outlet.x - at.x, p.outlet.z - at.z).length() < p.lead + 1.0:
				return p
	return null
