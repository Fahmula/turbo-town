extends Node
## Best stunt results, saved to user://records.cfg (autoload "Records").
## Like Settings, dev/test runs (command-line user args) never touch the file.

signal record_broken(what: String)

const PATH := "user://records.cfg"
const TOP_COMBOS := 5

var persist := OS.get_cmdline_user_args().is_empty()
var path := PATH

## [{"points": int, "vehicle": String, "tricks": String}], best first.
var best_combos: Array = []
var best_air := 0.0
var best_drift := 0.0
var most_flips := 0
var near_misses := 0
var total_score := 0


func _enter_tree() -> void:
	if persist:
		load_file()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	best_combos = cfg.get_value("records", "best_combos", [])
	best_air = cfg.get_value("records", "best_air", 0.0)
	best_drift = cfg.get_value("records", "best_drift", 0.0)
	most_flips = cfg.get_value("records", "most_flips", 0)
	near_misses = cfg.get_value("records", "near_misses", 0)
	total_score = cfg.get_value("records", "total_score", 0)


func save_file() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_combos", best_combos)
	cfg.set_value("records", "best_air", best_air)
	cfg.set_value("records", "best_drift", best_drift)
	cfg.set_value("records", "most_flips", most_flips)
	cfg.set_value("records", "near_misses", near_misses)
	cfg.set_value("records", "total_score", total_score)
	cfg.save(path)


## Adds a finished combo. Returns its place in the top list (1 = best), or 0.
func add_combo(points: int, vehicle_name: String, tricks: String) -> int:
	total_score += points
	var place := 0
	for i in best_combos.size():
		if points > int(best_combos[i]["points"]):
			place = i + 1
			break
	if place == 0 and best_combos.size() < TOP_COMBOS:
		place = best_combos.size() + 1
	if place > 0:
		best_combos.insert(place - 1, {"points": points, "vehicle": vehicle_name, "tricks": tricks})
		best_combos.resize(mini(best_combos.size(), TOP_COMBOS))
		if place == 1 and best_combos.size() > 1:
			record_broken.emit("BEST COMBO")
	save_file()
	return place


## The report_* functions keep the best value and announce it (only when an
## earlier record was beaten, so the very first jump isn't a "record").
func report_air(seconds: float) -> bool:
	if seconds <= best_air:
		return false
	var had := best_air > 0.0
	best_air = seconds
	save_file()
	if had:
		record_broken.emit("BIGGEST AIR")
	return true


func report_drift(seconds: float) -> bool:
	if seconds <= best_drift:
		return false
	var had := best_drift > 0.0
	best_drift = seconds
	save_file()
	if had:
		record_broken.emit("LONGEST DRIFT")
	return true


func report_flips(count: int) -> bool:
	if count <= most_flips:
		return false
	var had := most_flips > 0
	most_flips = count
	save_file()
	if had:
		record_broken.emit("MOST FLIPS")
	return true


func add_near_miss() -> void:
	near_misses += 1
