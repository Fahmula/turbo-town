class_name Loadout
extends RefCounted
## One vehicle's garage setup: a value for every PartsCatalog slot (paint is
## a Color, stripes a bool, the rest option ids). Each vehicle keeps its own:
## they're saved in the settings ("loadouts": vehicle id -> only the values
## that differ from stock), so a slot or option added later simply starts at
## its stock value.
##
## Only the player's vehicle gets one; traffic and parked cars keep the looks
## their scenes give them.

## Slots that change the wheels (WheelKit rebuilds them).
const WHEEL_SLOTS := ["rims", "rim_color", "tyres", "tyre_stripe", "calipers"]
## Slots the custom paint shader shows (VehicleBodyVisual.set_paint_style).
const PAINT_STYLE_SLOTS := ["finish", "two_tone", "tone_color", "decal", "decal_color", "number"]

var vehicle_id := ""
## Slot id -> value, for every slot.
var values := {}
var _stock := {}


## The vehicle as it comes (its scene's paint, its own wheels).
static func stock(id: String) -> Loadout:
	var l := Loadout.new()
	l.vehicle_id = id
	l._stock = _stock_values(id)
	l.values = l._stock.duplicate()
	return l


## The setup saved for this vehicle (stock where nothing was saved).
static func saved(id: String) -> Loadout:
	var l := stock(id)
	var all: Dictionary = Settings.get_value("loadouts")
	var mine: Variant = all.get(id)
	if mine is Dictionary:
		for slot: Variant in mine:
			l.set_value(str(slot), mine[slot])
	return l


func copy() -> Loadout:
	var l := Loadout.new()
	l.vehicle_id = vehicle_id
	l._stock = _stock
	l.values = values.duplicate()
	return l


func get_value(slot: String) -> Variant:
	return values.get(slot, _stock.get(slot))


## Sets a slot, if the value suits it (wrong types and unknown ids, e.g. from
## an older or newer save, are ignored).
func set_value(slot: String, value: Variant) -> void:
	if not PartsCatalog.SLOTS.has(slot):
		return
	match slot:
		"paint":
			if value is Color:
				values[slot] = PaintPalette.GARAGE[PartsCatalog.closest_color(PaintPalette.GARAGE, value)]
		"stripes":
			if value is bool:
				values[slot] = value
		_:
			if not (value is String or value is StringName):
				return
			var o := PartsCatalog.option(slot, str(value))
			# Unknown ids and parts that don't fit this vehicle are ignored.
			if not o.is_empty() and (vehicle_id.is_empty() or PartsCatalog.fits(o, vehicle_id)):
				values[slot] = str(value)


func is_stock(slot: String) -> bool:
	return get_value(slot) == _stock.get(slot)


func stock_value(slot: String) -> Variant:
	return _stock.get(slot)


## The values that differ from stock (what gets saved).
func overrides() -> Dictionary:
	var d := {}
	for slot: String in values:
		if not is_stock(slot):
			d[slot] = values[slot]
	return d


func wheels_stock() -> bool:
	return _all_stock(WHEEL_SLOTS)


func body_stock() -> bool:
	return _all_stock(PartsCatalog.BODY_PARTS.keys())


## True if the paint needs nothing but the plain car paint (no finish,
## two-tone, decals or number).
func paint_style_stock() -> bool:
	return get_value("finish") == "stock" and get_value("two_tone") == "off" \
		and get_value("decal") == "none" and get_value("number") == "none"


func _all_stock(slots: Array) -> bool:
	for slot: String in slots:
		if not is_stock(slot):
			return false
	return true


## Writes this setup into the settings (saved to disk with them).
func save() -> void:
	var all: Dictionary = (Settings.get_value("loadouts") as Dictionary).duplicate(true)
	var diff := overrides()
	if diff.is_empty():
		all.erase(vehicle_id)
	else:
		all[vehicle_id] = diff
	Settings.set_value("loadouts", all)


## Puts this setup on `v`. Works on a vehicle in the tree; one that isn't
## ready yet gets it as soon as it is.
func apply(v: Vehicle) -> void:
	if not v.is_node_ready():
		v.ready.connect(apply.bind(v), CONNECT_ONE_SHOT)
		return
	var body := v.get_node_or_null("Body") as VehicleBodyVisual
	if body:
		body.set_paint_color(get_value("paint"))
		body.set_stripes(get_value("stripes") and body.has_stripes())
	WheelKit.fit(v, self)
	BodyKit.fit(v, self)
	if body:
		body.set_paint_style(paint_style())
	Underglow.fit(v, PartsCatalog.option("underglow", get_value("underglow")))
	var audio := v.get_node_or_null("Audio") as VehicleAudio
	if audio:
		audio.set_horn_override(get_value("horn"))


## What VehicleBodyVisual.set_paint_style needs ({} = plain paint).
func paint_style() -> Dictionary:
	if paint_style_stock():
		return {}
	var tone := PartsCatalog.option("tone_color", get_value("tone_color"))
	var decal := PartsCatalog.option("decal", get_value("decal"))
	var number: String = get_value("number")
	return {
		"finish": PartsCatalog.option("finish", get_value("finish")),
		"tone_mode": PartsCatalog.option("two_tone", get_value("two_tone"))["mode"],
		"tone_color": tone.get("color", Color.BLACK),
		"decal_row": decal["row"],
		"decal_color": PartsCatalog.option("decal_color", get_value("decal_color"))["color"],
		"number": -1 if number == "none" else int(number),
	}


static func _stock_values(id: String) -> Dictionary:
	var index := VehicleCatalog.index_of_id(id)
	var e := VehicleCatalog.entry(id)
	var paint := Color(0.784, 0.137, 0.106)
	var caliper := Color(0.16, 0.16, 0.17)
	if index >= 0:
		paint = VehicleCatalog.scene_value(index, "Body", "paint_color", paint)
		caliper = VehicleCatalog.scene_value(index, ".", "caliper_color", caliper)
	var caliper_colors: Array = PartsCatalog.CALIPER_COLORS.map(func(o: Dictionary) -> Color: return o["color"])
	return {
		"paint": PaintPalette.GARAGE[PartsCatalog.closest_color(PaintPalette.GARAGE, paint)],
		"stripes": e.get("stripes", false),
		"rims": e.get("rims", "sport5"),
		"rim_color": "stock",
		"tyres": e.get("tyres", "sport"),
		"tyre_stripe": "none",
		"calipers": PartsCatalog.CALIPER_COLORS[PartsCatalog.closest_color(caliper_colors, caliper)]["id"],
		"finish": "stock",
		"two_tone": "off",
		"tone_color": str(PaintPalette.GARAGE.size() - 1),  # graphite
		"decal": "none",
		"decal_color": "white",
		"number": "none",
		"front": "stock",
		"rear": "stock",
		"skirts": "stock",
		"flares": "stock",
		"spoiler": "stock",
		"bonnet": "stock",
		"roof": "stock",
		"underglow": "off",
		"horn": "stock",
	}
