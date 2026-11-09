class_name FrameProbe
extends Node
## Splits every frame into its phases from the engine's own signals, so no
## game code needs timing calls (dev only, see DevTools --framebench):
##   phys_scripts  every node's _physics_process, all ticks of the frame
##   phys_step     the physics engine's step (plus its sync), all ticks
##   process       every node's _process
##   render        RenderingServer draw (CPU side)
##   other         the rest: input, audio, vsync / swap waits, the OS
## Add it to the tree, then start() and stop(); frames holds one Dictionary
## per frame.
## Code can also be timed by hand with FrameProbe.add(name, usec): sums per
## physics tick (names starting "p:" per _process pass instead), reported by
## section_report() as the mean and the worst pass.

var frames: Array[Dictionary] = []
var _on := false
var _frame_start := 0
var _tick_start := 0
var _cur := _blank_static()
## name -> [total usec, worst pass usec], and how many passes were seen.
static var sections := {}
static var _pass := {}
static var _sections_on := false
static var _phys_passes := 0
static var _proc_passes := 0


static func add(section: String, usec: int) -> void:
	if _sections_on:
		_pass[section] = int(_pass.get(section, 0)) + usec


static func _flush(process: bool) -> void:
	if not _sections_on:
		return
	if process:
		_proc_passes += 1
	else:
		_phys_passes += 1
	for k: String in _pass.keys():
		if k.begins_with("p:") != process:
			continue
		var v := int(_pass[k])
		var rec: Array = sections.get_or_add(k, [0, 0])
		rec[0] += v
		rec[1] = maxi(rec[1], v)
		_pass.erase(k)


func _ready() -> void:
	# Last in every physics and process pass: its callbacks mark where the
	# scripts end.
	process_physics_priority = 1 << 30
	process_priority = 1 << 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().physics_frame.connect(_on_tick_start)
	get_tree().process_frame.connect(_on_process_start)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func start() -> void:
	frames.clear()
	_on = true
	_frame_start = 0
	sections.clear()
	_pass.clear()
	_phys_passes = 0
	_proc_passes = 0
	_sections_on = true


func stop() -> void:
	_on = false
	_sections_on = false


## The hand-timed sections, most expensive first.
static func section_report() -> String:
	var keys := sections.keys()
	keys.sort_custom(func(a, b): return sections[a][0] > sections[b][0])
	var lines := PackedStringArray()
	for k: String in keys:
		var passes := _proc_passes if k.begins_with("p:") else _phys_passes
		lines.append("  %-24s mean %.3f ms per %s, worst %.2f ms" % [k, sections[k][0] / 1000.0 / maxi(passes, 1),
			"frame" if k.begins_with("p:") else "tick", sections[k][1] / 1000.0])
	return "\n".join(lines)


func _blank() -> Dictionary:
	return _blank_static()


static func _blank_static() -> Dictionary:
	return {"phys_scripts": 0, "phys_step": 0, "process": 0, "render": 0, "ticks": 0, "total": 0}


func _on_tick_start() -> void:
	var now := Time.get_ticks_usec()
	if _frame_start == 0:
		_frame_start = now
		_cur = _blank()
	elif _tick_start > 0 and _cur.has("_scripts_end"):
		_cur["phys_step"] += now - int(_cur["_scripts_end"])
		_cur.erase("_scripts_end")
	_tick_start = now


func _physics_process(_dt: float) -> void:
	if _frame_start == 0 or _tick_start == 0:
		return
	var now := Time.get_ticks_usec()
	_cur["phys_scripts"] += now - _tick_start
	_cur["ticks"] += 1
	_cur["_scripts_end"] = now
	_flush(false)


func _on_process_start() -> void:
	var now := Time.get_ticks_usec()
	if _frame_start == 0:
		_frame_start = now
		_cur = _blank()
	if _cur.has("_scripts_end"):
		_cur["phys_step"] += now - int(_cur["_scripts_end"])
		_cur.erase("_scripts_end")
	_tick_start = 0
	_cur["_process_start"] = now


func _process(_dt: float) -> void:
	if _cur.has("_process_start"):
		_cur["process"] += Time.get_ticks_usec() - int(_cur["_process_start"])
		_cur.erase("_process_start")
	_flush(true)


func _on_pre_draw() -> void:
	_cur["_draw_start"] = Time.get_ticks_usec()


func _on_post_draw() -> void:
	var now := Time.get_ticks_usec()
	if _cur.has("_draw_start"):
		_cur["render"] += now - int(_cur["_draw_start"])
		_cur.erase("_draw_start")
	if _frame_start == 0:
		return
	# The frame ends here; the next one starts with whatever comes next.
	_cur["_end"] = now
	if _on and frames.size() < 100000:
		frames.append(_cur)
	_frame_start = now
	_cur = _blank()


## Frame N's total runs from frame N-1's draw end to its own: fills "total"
## and "other" (everything not in a named phase) in milliseconds, and turns
## the phases into milliseconds too.
func finished() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prev_end := 0
	for f in frames:
		var end := int(f.get("_end", 0))
		if prev_end > 0:
			var d := {}
			for k in ["phys_scripts", "phys_step", "process", "render"]:
				d[k] = int(f[k]) / 1000.0
			d["ticks"] = int(f["ticks"])
			d["total"] = (end - prev_end) / 1000.0
			d["other"] = d["total"] - d["phys_scripts"] - d["phys_step"] - d["process"] - d["render"]
			out.append(d)
		prev_end = end
	return out


## One line of averages, percentiles and the slow frames' share, plus the
## slowest frames broken down.
static func report(label: String, fs: Array[Dictionary], slow_ms := 20.0, show := 6) -> String:
	if fs.is_empty():
		return "%s: no frames" % label
	var totals: Array[float] = []
	var sums := {"phys_scripts": 0.0, "phys_step": 0.0, "process": 0.0, "render": 0.0, "other": 0.0, "ticks": 0.0}
	var slow: Array[Dictionary] = []
	for f in fs:
		totals.append(f["total"])
		for k in sums:
			sums[k] += float(f[k])
		if f["total"] > slow_ms:
			slow.append(f)
	totals.sort()
	var n := fs.size()
	var lines := PackedStringArray()
	lines.append("%s: %d frames, mean %.1f ms, p50 %.1f, p95 %.1f, p99 %.1f, max %.1f, %d > %.0f ms" % [label, n,
		totals.reduce(func(a, b): return a + b, 0.0) / n, totals[n / 2], totals[int(n * 0.95)],
		totals[int(n * 0.99)], totals[n - 1], slow.size(), slow_ms])
	lines.append("  mean per frame: phys scripts %.2f, phys step %.2f, process %.2f, render %.2f, other %.2f ms, %.2f ticks" % [
		sums["phys_scripts"] / n, sums["phys_step"] / n, sums["process"] / n, sums["render"] / n, sums["other"] / n, sums["ticks"] / n])
	slow.sort_custom(func(a, b): return a["total"] > b["total"])
	for i in mini(show, slow.size()):
		var f := slow[i]
		lines.append("  slow %.1f ms: phys scripts %.1f, phys step %.1f (%d ticks), process %.1f, render %.1f, other %.1f" % [
			f["total"], f["phys_scripts"], f["phys_step"], f["ticks"], f["process"], f["render"], f["other"]])
	return "\n".join(lines)
