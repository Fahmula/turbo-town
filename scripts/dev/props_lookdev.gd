extends Node
## Close-ups of the street furniture, stunt park and landmarks (ART_BIBLE.md §30):
##   godot --path . --resolution 1280x800 --audio-driver Dummy res://scenes/dev/props_lookdev.tscn -- --props=/tmp/shots
##     --views=a,b      view names (default: all; see _views below)
##     --times=day,sunset,night   (default: day)
##     --quality=0|1|2  graphics quality (default 2 = High)
## A gallery of the physics props and kit meshes is spawned on the stunt park
## pad (z = 316), the landmark views fly the camera to the harbour, airfield,
## lighthouse, tunnel, gas station and the stunt park structures. Prints draw
## calls, primitives and GPU time per view.

const GALLERY_Z := 316.0

# name -> [camera position, look-at, fov]
var _views := {
	"gal_small": [Vector3(-1.0, 1.5, 325.5), Vector3(-1.0, 0.55, 316.0), 55.0],
	"gal_small_l": [Vector3(-9.0, 0.9, 322.0), Vector3(-9.0, 0.55, 316.0), 50.0],
	"gal_small_r": [Vector3(7.0, 0.9, 322.0), Vector3(7.0, 0.55, 316.0), 50.0],
	"gal_tall": [Vector3(26.0, 3.0, 334.0), Vector3(26.0, 3.2, 316.0), 60.0],
	"lamp_head": [Vector3(20.0, 5.6, 322.0), Vector3(22.0, 6.3, 314.6), 45.0],
	"signal_head": [Vector3(33.0, 4.6, 322.0), Vector3(35.4, 4.7, 316.0), 45.0],
	"signal_base": [Vector3(41.5, 1.8, 321.0), Vector3(39.0, 1.4, 316.0), 55.0],
	"kickers": [Vector3(4.0, 2.2, 322.0), Vector3(0.0, 1.5, 345.0), 70.0],
	"ramp_deck": [Vector3(3.0, 1.2, 331.0), Vector3(0.5, 0.9, 337.5), 60.0],
	"ramp_side": [Vector3(-6.0, 1.1, 341.0), Vector3(-3.5, 0.8, 337.0), 60.0],
	"mega_ramp":[Vector3(100.0, 5.0, 330.0), Vector3(125.0, 7.0, 362.0), 70.0],
	"loop_side": [Vector3(138.0, 4.5, 362.0), Vector3(160.0, 5.0, 372.0), 70.0],
	"loop_front": [Vector3(158.0, 3.0, 340.0), Vector3(162.0, 4.0, 372.0), 70.0],
	"bowl": [Vector3(165.0, 3.5, 452.0), Vector3(165.0, 4.5, 487.0), 70.0],
	"pins_crates": [Vector3(-30.0, 2.6, 462.0), Vector3(40.0, 1.0, 470.0), 70.0],
	"gate": [Vector3(0.0, 3.0, 328.0), Vector3(0.0, 6.0, 307.0), 75.0],
	"harbour_a": [Vector3(-398.0, 3.0, -198.0), Vector3(-385.0, 3.0, -228.0), 70.0],
	"harbour_b": [Vector3(-436.0, 2.5, -238.0), Vector3(-405.0, 8.0, -250.0), 70.0],
	"boat": [Vector3(-433.0, 2.2, -202.0), Vector3(-442.0, 0.3, -208.5), 55.0],
	"boat_b": [Vector3(-452.0, 2.0, -218.0), Vector3(-442.0, 0.3, -208.5), 55.0],
	"harbour_pier":[Vector3(-415.0, 2.2, -240.0), Vector3(-450.0, 0.5, -243.0), 70.0],
	"airfield_a": [Vector3(330.0, 2.5, 284.0), Vector3(335.0, 7.0, 240.0), 75.0],
	"airfield_plane": [Vector3(316.0, 2.4, 276.0), Vector3(308.0, 2.2, 260.0), 60.0],
	"airfield_tower": [Vector3(366.0, 3.0, 262.0), Vector3(379.0, 14.0, 234.0), 70.0],
	"lighthouse": [Vector3(-508.0, 4.0, 14.0), Vector3(-528.0, 10.0, 0.0), 70.0],
	"cottage": [Vector3(-520.0, 4.0, 20.0), Vector3(-518.0, 3.0, 7.0), 65.0],
	"cottage_gable": [Vector3(-508.0, 3.8, 13.0), Vector3(-518.0, 3.0, 7.0), 60.0],
	"lighthouse_top": [Vector3(-515.0, 17.0, 12.0), Vector3(-528.0, 19.0, 0.0), 60.0],
	"bridge":[Vector3(-400.0, 4.0, 3.0), Vector3(-470.0, 3.0, 0.0), 65.0],
	"tunnel": [Vector3(0.0, 2.0, 160.0), Vector3(0.0, 4.0, 180.0), 70.0],
	"gas_station": [Vector3(172.0, 3.0, -16.0), Vector3(198.0, 3.0, -32.0), 70.0],
}

var _dir := ""
var _only: PackedStringArray = []
var _times := ["day"]
var _quality := 2
var _game: Game


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--props="):
			_dir = arg.split("=")[1]
		elif arg.begins_with("--views="):
			_only = arg.split("=")[1].split(",")
		elif arg.begins_with("--times="):
			_times = Array(arg.split("=")[1].split(","))
		elif arg.begins_with("--quality="):
			_quality = int(arg.split("=")[1])
	if _dir == "":
		push_error("props_lookdev: pass --props=<dir>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	# One close-up per gallery prop: name, x, height (m), camera distance (m).
	for p: Array in [["cone", -14.0, 0.72, 1.9], ["barrel", -11.0, 0.95, 2.4], ["crate", -8.0, 1.2, 3.0], ["pin", -5.0, 1.9, 4.0],
			["hydrant", -2.0, 0.8, 2.0], ["bin", 1.0, 1.0, 2.6], ["bench", 4.0, 0.9, 3.2], ["cabinet", 7.0, 1.7, 3.6],
			["bollard", 10.0, 1.0, 2.2], ["shelter", 16.0, 2.6, 6.5]]:
		var h: float = p[2]
		var d: float = p[3]
		_views["p_" + p[0]] = [Vector3(p[1] + d * 0.4, h * 0.7 + 0.3, GALLERY_Z + d), Vector3(p[1], h * 0.45, GALLERY_Z), 50.0]
	_game =(load("res://scenes/main.tscn") as PackedScene).instantiate() as Game
	add_child(_game)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	await _wait(30)
	var game := _game
	game.traffic.set_enabled(false)
	game.hud.visible = false
	Settings.set_value("graphics", _quality)
	_spawn_gallery(game)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cam := game.camera
	var names: Array = _views.keys()
	for t in _times:
		Settings.set_value("time_of_day", ["day", "sunset", "night"].find(t))
		await _wait(10)
		for n: String in names:
			if not _only.is_empty() and not _only.has(n):
				continue
			var v: Array = _views[n]
			var pos: Vector3 = v[0]
			cam.set_process(false)
			# Park the car out of the shot and let the area stream in.
			var back: Vector3 = pos - Vector3((v[1] as Vector3).x - pos.x, 0.0, (v[1] as Vector3).z - pos.z).normalized() * 14.0
			game.vehicle.teleport(Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(back.x, 0.6 + maxf(pos.y - 3.0, 0.0), back.z)))
			cam.global_position = pos
			cam.fov = v[2]
			cam.look_at(v[1], Vector3.UP)
			await _wait(14)
			cam.global_position = pos
			cam.look_at(v[1], Vector3.UP)
			await _wait(6)
			var calls := 0
			var prims := 0
			var gpu := 0.0
			for k in 20:
				await RenderingServer.frame_post_draw
				calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			print("LOOK %-14s %-6s %4d calls %8d prims  gpu %.2f ms" % [n, t, calls / 20, prims / 20, gpu / 20.0])
			var img := get_viewport().get_texture().get_image()
			img.save_png(_dir.path_join("%s_%s.png" % [n, t]))
	cam.set_process(true)
	get_tree().quit(0)


## Every physics prop and the kit-only meshes in two rows on the stunt park pad.
func _spawn_gallery(game: Game) -> void:
	var small := ["traffic_cone", "barrel", "crate", "bowling_pin", "hydrant", "street_bin", "bench", "signal_cabinet"]
	var x := -14.0
	for s: String in small:
		var n := (load("res://scenes/props/%s.tscn" % s) as PackedScene).instantiate() as Node3D
		n.position = Vector3(x, 0.05, GALLERY_Z)
		game.world.add_child(n)
		x += 3.0
	for kind in ["bollard", "shelter"]:
		var mi := MeshInstance3D.new()
		mi.mesh = StreetKit.mesh(kind)
		mi.position = Vector3(x + (3.0 if kind == "shelter" else 0.0), 0.03, GALLERY_Z)
		game.world.add_child(mi)
		x += 3.0
	x = 22.0
	for s: String in ["street_lamp", "traffic_signal"]:
		var n := (load("res://scenes/props/%s.tscn" % s) as PackedScene).instantiate() as Node3D
		n.position = Vector3(x, 0.05, GALLERY_Z)
		game.world.add_child(n)
		if s == "traffic_signal":
			(n as TrafficLightProp).set_state(TrafficNetwork.SignalState.GREEN)
			n.position = Vector3(x + 10.0, 0.05, GALLERY_Z)
		x += 7.0
