class_name FuelPump
extends Interactable
## One hose at a pump, or one cable at a charger (`plug`): the nozzle (or
## plug) the player grabs, carries to a vehicle's filler flap and leaves in
## to fill up. A FuelSite owns its hoses and draws the resting ones as one
## mesh; a hose in use draws itself (the handle and a sagging hose, rebuilt
## only while it moves).
##
## Kid-friendly rules: the hose is `lead` metres long and holds the player
## back there like a lead (PlayerCharacter.leash); nothing ever breaks:
## getting in or driving off with the nozzle in pops it out, and a hose let
## go of (hung up, or the player teleports, gets in a vehicle or opens the
## garage) reels back to the pump by itself.
##
## States: RESTING in the holster -> HELD in the player's right hand ->
## IN_VEHICLE in a filler flap (filling) -> HELD again or REELING back.

enum State { RESTING, HELD, IN_VEHICLE, REELING }

## Meta on a character holding a hose: the FuelPump.
const HOLD_META := &"fuel_hose"
const REEL_TIME := 0.6
## A vehicle that moves this far (m) with the nozzle in pops it out.
const POP_DISTANCE := 0.35
## Litres the pump's readout counts for a full tank (just for show).
const TANK_LITRES := 50.0
const CLICK := preload("res://assets/audio/fuel/nozzle_click.wav")
const DING := preload("res://assets/audio/fuel/fill_ding.wav")
const FLOW := preload("res://assets/audio/fuel/fuel_flow.wav")
const HUM := preload("res://assets/audio/fuel/charger_hum.wav")

var site: FuelSite
## A charging cable and plug (for batteries) rather than a fuel hose.
var plug := false
## Where the hose leaves the pump (world) and the handle's place in its
## holster (world).
var outlet := Vector3.ZERO
var rest := Transform3D.IDENTITY
## Hose length (m): how far from the outlet the player can carry it.
var lead := 5.0
## The ground around the pump (the hose never sags through it).
var floor_y := 0.0
## Where the pump shows the fill ticking up (world; facing its +Z), or none.
var readout_xf := Transform3D()
var has_readout := false

var state := State.RESTING
## The character holding it (HELD).
var holder: PlayerCharacter
## The vehicle it's in (IN_VEHICLE).
var vehicle: Vehicle
## The last character to use it (for the "FULL!" popup).
var user: PlayerCharacter

var _handle: MeshInstance3D
var _hose: MeshInstance3D
var _hose_mesh: ArrayMesh
var _handle_xf := Transform3D.IDENTITY
var _last_ends := [Vector3.INF, Vector3.INF]
var _reel_from := Transform3D.IDENTITY
var _reel_t := 0.0
var _insert_at := Vector3.ZERO
var _insert_driver: Object = null
var _readout: Label3D
var _litres := 0.0
var _loop: AudioStreamPlayer3D
var _shot: AudioStreamPlayer3D


func _init() -> void:
	name = "Hose"
	reach = 1.3
	priority = 1


func _ready() -> void:
	# After characters and vehicles move (the handle follows them).
	process_physics_priority = 20
	_handle = MeshInstance3D.new()
	_handle.name = "Handle"
	_handle.mesh = FuelKit.handle_mesh(plug)
	_set_look(_handle)
	_handle.top_level = true
	_handle.visible = false
	add_child(_handle)
	_hose = MeshInstance3D.new()
	_hose.name = "HoseMesh"
	_hose_mesh = ArrayMesh.new()
	_hose.mesh = _hose_mesh
	_set_look(_hose)
	_hose.top_level = true
	_hose.visible = false
	add_child(_hose)
	if has_readout:
		_readout = Label3D.new()
		_readout.name = "Readout"
		_readout.font_size = 40
		_readout.pixel_size = 0.0035
		_readout.outline_size = 0
		_readout.modulate = Color(0.55, 1.0, 0.6)
		_readout.double_sided = false
		_readout.top_level = true
		_readout.global_transform = readout_xf
		_readout.visible = false
		_readout.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_readout)
	_loop = _player(-6.0)
	_shot = _player(-4.0)


func _set_look(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	mi.layers = Vehicle.VISUAL_LAYER
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _player(db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"Environment"
	p.unit_size = 3.0
	p.max_distance = 35.0
	p.volume_db = db
	p.top_level = true
	add_child(p)
	return p


## The hose a character is holding, or null.
static func held_by(actor: Node) -> FuelPump:
	if actor == null or not is_instance_valid(actor) or not actor.has_meta(HOLD_META):
		return null
	var p: Variant = actor.get_meta(HOLD_META)
	if p is FuelPump and is_instance_valid(p) and (p as FuelPump).holder == actor:
		return p
	actor.remove_meta(HOLD_META)
	return null


## Can this hose fill `v`? (Fuel nozzles for tanks, plugs for batteries.)
func fits(v: Vehicle) -> bool:
	return v != null and v.electric == plug


func noun() -> String:
	return "plug" if plug else "nozzle"


# --- Interactable -----------------------------------------------------------

func reach_distance(point: Vector3) -> float:
	match state:
		State.RESTING:
			var p := rest.origin
			if absf(point.y - floor_y) > 1.0:
				return INF
			var d := Vector2(point.x - p.x, point.z - p.z).length()
			return d if d <= reach else INF
		State.HELD:
			# Anywhere: the fallback "hang it back up" for whoever holds it
			# (a filler flap close by wins).
			return 30.0
	return INF


func prompt(actor: Node3D) -> String:
	var pc := actor as PlayerCharacter
	if pc == null:
		return ""
	match state:
		State.RESTING:
			if pc.can_act() and held_by(pc) == null:
				return "Grab the %s" % noun()
		State.HELD:
			if holder == pc and pc.can_act():
				return "Hang up the %s" % noun()
	return ""


func interact(actor: Node3D) -> bool:
	var pc := actor as PlayerCharacter
	if pc == null or prompt(actor) == "":
		return false
	if state == State.RESTING:
		grab(pc)
	else:
		hang_up()
	return true


# --- Using it ------------------------------------------------------------------

## `pc` takes the handle out of the holster.
func grab(pc: PlayerCharacter) -> void:
	_take(pc)
	_handle_xf = rest
	_click(1.0)
	if site:
		site.rebuild_rest()


## `pc` holds it now (from the holster or out of a filler).
func _take(pc: PlayerCharacter) -> void:
	state = State.HELD
	holder = pc
	user = pc
	pc.set_meta(HOLD_META, self)
	pc.leash_point = outlet
	pc.leash_length = lead
	pc.set_holding(true)
	_handle.visible = true
	_hose.visible = true
	_last_ends = [Vector3.INF, Vector3.INF]


## The holder lets go: the hose reels back into the pump.
func hang_up() -> void:
	_release_holder()
	_reel(_handle_xf)


func _release_holder() -> void:
	if holder and is_instance_valid(holder):
		holder.leash_length = 0.0
		holder.set_holding(false)
		if holder.get_meta(HOLD_META, null) == self:
			holder.remove_meta(HOLD_META)
	holder = null


func _reel(from: Transform3D) -> void:
	_stop_filling()
	state = State.REELING
	_reel_from = from
	_reel_t = 0.0
	_handle.visible = true
	_hose.visible = true


## The holder puts it into `v`'s filler (`flap`): it fills by itself now.
func insert(v: Vehicle, flap: FillerFlap) -> void:
	_release_holder()
	state = State.IN_VEHICLE
	vehicle = v
	_insert_at = v.global_position
	var c := Controllable.of(v)
	_insert_driver = c.controller if c and not c.is_free() else null
	var fuel := VehicleFuel.of(v)
	if fuel:
		fuel.nozzle = self
	_handle_xf = flap.nozzle_transform()
	_litres = 0.0
	_click(0.9)
	if fuel and not fuel.is_full():
		_loop.stream = HUM if plug else FLOW
		_loop.global_position = _handle_xf.origin
		_loop.play()
		if _readout:
			_readout.visible = true
	elif fuel:
		_full(fuel)


## Out of the filler into `pc`'s hand.
func take_out(pc: PlayerCharacter) -> void:
	_stop_filling()
	_detach()
	_take(pc)
	_click(1.1)


## Out of the filler by itself (the vehicle drove off or someone got in):
## it reels back to the pump.
func pop_out() -> void:
	_detach()
	_click(1.2)
	_reel(_handle_xf)


func _detach() -> void:
	if vehicle and is_instance_valid(vehicle):
		var fuel := VehicleFuel.of(vehicle)
		if fuel and fuel.nozzle == self:
			fuel.nozzle = null
	vehicle = null
	_insert_driver = null


func _stop_filling() -> void:
	if _loop.playing:
		_loop.stop()
	if _readout:
		_readout.visible = false


func _click(pitch: float) -> void:
	_shot.stream = CLICK
	_shot.pitch_scale = pitch
	_shot.global_position = _handle_xf.origin if state != State.RESTING else rest.origin
	_shot.play()


## The tank's full: "FULL!" for whoever filled it, and a ding.
func _full(fuel: VehicleFuel) -> void:
	_stop_filling()
	_shot.stream = DING
	_shot.pitch_scale = 1.0
	_shot.global_position = _handle_xf.origin
	_shot.play()
	var hud := _hud_of(user)
	if hud:
		hud.show_popup("FULL!" if not fuel.is_battery() else "CHARGED!", 1.6, Color(0.3, 1.0, 0.45))


static func _hud_of(pc: PlayerCharacter) -> Hud:
	if pc == null or not is_instance_valid(pc) or not pc.is_inside_tree():
		return null
	var g := pc.get_tree().current_scene as Game
	if g == null:
		return null
	var i: int = pc.get_meta(Controllable.OWNER_META, 0)
	return g.players[i].hud if i < g.players.size() else null


# --- Every tick ----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	match state:
		State.HELD:
			# The player went somewhere the hose can't follow (a vehicle, the
			# garage, a teleport): it goes home by itself.
			if holder == null or not is_instance_valid(holder) or not holder.is_inside_tree() \
					or holder.state == PlayerCharacter.State.HIDDEN \
					or Vector2(holder.global_position.x - outlet.x, holder.global_position.z - outlet.z).length() > lead + 2.5:
				hang_up()
		State.IN_VEHICLE:
			_fill(dt)
		State.REELING:
			_reel_t += dt / REEL_TIME
			if _reel_t >= 1.0:
				state = State.RESTING
				_handle.visible = false
				_hose.visible = false
				if site:
					site.rebuild_rest()


func _fill(dt: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		vehicle = null
		_reel(_handle_xf)
		return
	var c := Controllable.of(vehicle)
	var driver: Object = c.controller if c and not c.is_free() else null
	if vehicle.global_position.distance_to(_insert_at) > POP_DISTANCE or driver != _insert_driver:
		pop_out()
		return
	var fuel := VehicleFuel.of(vehicle)
	if fuel == null or fuel.is_full() or not _loop.playing:
		return
	var before := fuel.level
	var done := fuel.fill(dt)
	_litres += (fuel.level - before) * TANK_LITRES
	if _readout:
		_readout.text = ("%d %%" % roundi(fuel.level * 100.0)) if plug else ("%.1f L" % _litres)
	if done:
		_full(fuel)


func _process(_dt: float) -> void:
	match state:
		State.HELD:
			if holder and is_instance_valid(holder):
				_handle_xf = holder.hold_transform()
		State.IN_VEHICLE:
			if vehicle and is_instance_valid(vehicle):
				var flap := vehicle.get_node_or_null("FillerFlap") as FillerFlap
				if flap:
					_handle_xf = flap.nozzle_transform(true)
		State.REELING:
			var k := smoothstep(0.0, 1.0, _reel_t)
			_handle_xf = Transform3D(_reel_from.basis.slerp(rest.basis, k).orthonormalized(), _reel_from.origin.lerp(rest.origin, k))
		_:
			return
	_handle.global_transform = _handle_xf
	if _loop.playing:
		_loop.global_position = _handle_xf.origin
	var tail := _handle_xf * FuelKit.NOZZLE_TAIL
	# (Rebuilt only once the end has moved a centimetre: ~0.2 ms a time.)
	if tail.distance_to(_last_ends[1]) < 0.01 and state != State.REELING:
		return
	_last_ends = [outlet, tail]
	var d := outlet.distance_to(tail)
	var slack := lerpf(1.1, 0.12, clampf(d / lead, 0.0, 1.0))
	if state == State.REELING:
		slack = lerpf(slack, 0.9, _reel_t)
	var mb := MeshBuilder.new()
	FuelKit.add_hose(mb, FuelKit.hose_points(outlet, tail, slack, floor_y), plug)
	_hose_mesh.clear_surfaces()
	mb.build_mesh(StreetKit.material(), _hose_mesh)


## The resting hose and handle, for the site's merged mesh.
func add_rest_to(mb: MeshBuilder) -> void:
	FuelKit.add_hose(mb, FuelKit.hose_points(outlet, rest * FuelKit.NOZZLE_TAIL, 0.9, floor_y), plug)
	FuelKit.add_handle(mb, rest, plug)
