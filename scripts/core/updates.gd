extends Node
## In-game updates (autoload "Updates"). Only active when the Steam Deck
## launcher (tools/steamdeck/turbotown.sh) started the game: it sets
## TURBOTOWN_LAUNCHER (2 or more) and TURBOTOWN_DIR (where it installs).
## Editor and dev builds, and the CI smoke test, never touch the network.
##
## A few seconds after start this asks GitHub for the latest stable release.
## If it's newer than this build, its package downloads in the background into
## <TURBOTOWN_DIR>/pending.part/. Then the SHA-256 is checked, VERSION is
## written and the folder is renamed to pending/. The title screen offers
## RESTART TO UPDATE: quitting with EXIT_RESTART makes the launcher install it
## and start the game again (otherwise it's installed at the next launch).
## Each successful check touches <TURBOTOWN_DIR>/last-check. When that's a
## week old, the launcher updates before starting the game instead, so a
## broken updater can't leave the Deck on an old version.

signal changed

enum State { OFF, WAITING, CHECKING, UP_TO_DATE, DOWNLOADING, VERIFYING, READY, FAILED }

## The exit code that tells the launcher "install the download and start me again".
const EXIT_RESTART := 42
const LAUNCHER_PROTOCOL := 2
const API_URL := "https://api.github.com/repos/Fahmula/turbo-town/releases/latest"
## Seconds until the first check (Wi-Fi may still be connecting), after a
## failure (growing), and between checks while up to date.
const FIRST_CHECK := 4.0
const RETRY: Array[float] = [20.0, 60.0, 300.0, 900.0]
const RECHECK := 1800.0
## A download that gets no data for this long is cancelled (and retried later).
const STALL_MS := 60000

var state := State.OFF
## This build's version ("0.11.0").
var version := ""
## The newer release found ("0.12.0"), "" until there is one.
var latest := ""
## Its release notes as BBCode for a RichTextLabel ("" if it has none).
var notes := ""
## 0..1 while the package downloads.
var progress := 0.0
## Why the last try failed (shown on the title screen, printed to the log).
var problem := ""

var _dir := ""
var _api := API_URL
var _timer: Timer
var _http: HTTPRequest
var _failures := 0
## Downloads still to do: [file name, url, size, required].
var _queue: Array = []
var _current: Array = []
var _package := ""
var _hash_task := -1
var _hash := ""
var _last_emit := 0
var _stall_bytes := -1
var _stall_since := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(check_now)
	add_child(_timer)
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_chunk_size = 1 << 18
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	var launcher := OS.get_environment("TURBOTOWN_LAUNCHER").to_int()
	var dir := OS.get_environment("TURBOTOWN_DIR")
	var ver: String = ProjectSettings.get_setting("application/config/version", "")
	var api := OS.get_environment("TURBOTOWN_API_URL")   # tests: a fake GitHub
	if launcher >= LAUNCHER_PROTOCOL and dir != "" and DirAccess.dir_exists_absolute(dir) and ver != "":
		setup(dir, ver, api if api != "" else API_URL)


## Turns updates on: `dir` is the launcher's folder, `ver` this build's version.
func setup(dir: String, ver: String, api := API_URL) -> void:
	_dir = dir
	version = ver
	_api = api
	_set_state(State.WAITING)
	_timer.start(FIRST_CHECK)


## Whether there's anything for the player to see (a newer version).
func has_news() -> bool:
	return latest != "" and state in [State.DOWNLOADING, State.VERIFYING, State.READY, State.FAILED]


## Asks GitHub now (also what the timer calls). Does nothing while a download
## is running or one is ready.
func check_now() -> void:
	if state in [State.OFF, State.CHECKING, State.DOWNLOADING, State.VERIFYING, State.READY]:
		return
	_timer.stop()
	_http.download_file = ""
	_http.timeout = 20.0
	var err := _http.request(_api, _headers(["Accept: application/vnd.github+json"]))
	if err != OK:
		_fail("couldn't ask GitHub (error %d)" % err)
		return
	_set_state(State.CHECKING)


## Quits so the launcher installs the download and starts the game again.
func restart_to_update() -> void:
	if state == State.READY:
		VehicleAudio.quit_quietly(get_tree(), EXIT_RESTART)


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING and not _current.is_empty():
		var now := Time.get_ticks_msec()
		var got := _http.get_downloaded_bytes()
		if got != _stall_bytes:
			_stall_bytes = got
			_stall_since = now
		elif now - _stall_since > STALL_MS:
			_http.cancel_request()
			_fail("the download stalled")
			return
		if _current[0] == _package:
			var size: int = _current[2] if _current[2] > 0 else _http.get_body_size()
			if size > 0:
				progress = clampf(float(got) / size, 0.0, 1.0)
				if now - _last_emit > 200:
					_last_emit = now
					changed.emit()
	elif state == State.VERIFYING and _hash_task >= 0 and WorkerThreadPool.is_task_completed(_hash_task):
		WorkerThreadPool.wait_for_task_completion(_hash_task)
		_hash_task = -1
		_finish_verify()


func _headers(extra: Array) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: TurboTown/%s" % version])
	h.append_array(extra)
	return h


func _on_request_completed(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	if state == State.CHECKING:
		_on_checked(result, code, body)
	elif state == State.DOWNLOADING:
		_on_downloaded(result, code)


func _on_checked(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("no connection to GitHub (result %d)" % result)
		return
	if code != 200:
		_fail("GitHub answered %d" % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not str(data.get("tag_name", "")).begins_with("v"):
		_fail("GitHub's answer didn't make sense")
		return
	_touch_last_check()
	_failures = 0
	var ver := str(data["tag_name"]).substr(1)
	if not newer(ver, version):
		latest = ""
		problem = ""
		_set_state(State.UP_TO_DATE)
		_timer.start(RECHECK)
		return
	_package = "TurboTown-v%s-linux-x86_64.tar.gz" % ver
	var assets := {}
	for a: Variant in data.get("assets", []):
		if a is Dictionary:
			assets[str(a.get("name", ""))] = a
	if not assets.has(_package) or not assets.has(_package + ".sha256"):
		_fail("v%s has no Steam Deck package yet" % ver)
		return
	latest = ver
	notes = notes_bbcode(str(data.get("body", "")))
	problem = ""
	progress = 0.0
	_queue.clear()
	for f: String in [_package + ".sha256", _package, "turbotown.sh"]:
		if assets.has(f):
			var a: Dictionary = assets[f]
			_queue.append([f, str(a.get("browser_download_url", "")), int(a.get("size", 0)), f != "turbotown.sh"])
	_remove_tree(_part_dir())
	DirAccess.make_dir_recursive_absolute(_part_dir())
	_set_state(State.DOWNLOADING)
	_next_download()


func _next_download() -> void:
	if _queue.is_empty():
		_current = []
		_start_verify()
		return
	_current = _queue.pop_front()
	_stall_bytes = -1
	_stall_since = Time.get_ticks_msec()
	_http.download_file = _part_dir().path_join(_current[0])
	_http.timeout = 0.0   # a big download may take a while; a dropped connection still fails
	var err := _http.request(_current[1], _headers([]))
	if err != OK:
		_fail("couldn't start the download (error %d)" % err)


func _on_downloaded(result: int, code: int) -> void:
	var required: bool = _current[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if required:
			_fail("the download stopped (result %d, HTTP %d)" % [result, code])
			return
		DirAccess.remove_absolute(_part_dir().path_join(_current[0]))   # optional (the launcher script)
	_next_download()


func _start_verify() -> void:
	progress = 1.0
	_set_state(State.VERIFYING)
	_hash = ""
	_hash_task = WorkerThreadPool.add_task(_hash_file.bind(_part_dir().path_join(_package)), false, "Checking the update")


## (Worker thread.) SHA-256 of a file, read 1 MB at a time.
func _hash_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var size := f.get_length()
	while f.get_position() < size:
		ctx.update(f.get_buffer(1 << 20))
	_hash = ctx.finish().hex_encode()


func _finish_verify() -> void:
	var sums := FileAccess.get_file_as_string(_part_dir().path_join(_package + ".sha256"))
	var expected := sums.strip_edges().split(" ", false)[0].to_lower() if sums.strip_edges() != "" else ""
	if expected.length() != 64 or _hash != expected:
		_fail("the download was damaged (checksum didn't match)")
		return
	var f := FileAccess.open(_part_dir().path_join("VERSION"), FileAccess.WRITE)
	if f == null:
		_fail("couldn't save the update")
		return
	f.store_string(latest + "\n")
	f.close()
	var pending := _dir.path_join("pending")
	_remove_tree(pending)
	if DirAccess.rename_absolute(_part_dir(), pending) != OK:
		_fail("couldn't save the update")
		return
	print("updates: v%s is downloaded and ready to install" % latest)
	_set_state(State.READY)


func _fail(why: String) -> void:
	problem = why
	print("updates: ", why)
	_queue.clear()
	_current = []
	if _dir != "":
		_remove_tree(_part_dir())
	_set_state(State.FAILED)
	_timer.start(RETRY[mini(_failures, RETRY.size() - 1)])
	_failures += 1


func _set_state(s: State) -> void:
	state = s
	changed.emit()


func _part_dir() -> String:
	return _dir.path_join("pending.part")


func _touch_last_check() -> void:
	var f := FileAccess.open(_dir.path_join("last-check"), FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system() + "\n")


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Is version `a` ("0.12.0") newer than `b`?
static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false


## A GitHub Release's notes (Markdown from release-please and
## tools/release.sh) as short BBCode: headings in bold, one line per bullet,
## without links, commit hashes, the install steps or the commit list.
static func notes_bbcode(body: String) -> String:
	var text := body.replace("\r", "")
	var cut := text.find("## Steam Deck")
	if cut >= 0:
		text = text.substr(0, cut)
	var refs := RegEx.create_from_string("\\s*\\(\\[[^\\]]*\\]\\([^)]*\\)\\)")   # " ([#2](url))", " ([abc1234](url))"
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\([^)]+\\)")           # [text](url) -> text
	var out: Array[String] = []
	var items: Array[String] = []   # the bullet list being read
	for raw in text.split("\n"):
		var s := link.sub(refs.sub(raw, "", true), "$1", true).replace("**", "").replace("`", "").strip_edges()
		var skip := s == "" or s == "---" or s.begins_with("## [")
		if s.begins_with("* ") or s.begins_with("- "):
			var item := s.substr(2).strip_edges()
			items.append(_bb_escape(item.left(1).to_upper() + item.substr(1)))
			continue
		if not items.is_empty() and not skip and not s.begins_with("#"):
			items[-1] += " " + _bb_escape(s)   # a bullet wrapped onto the next line
			continue
		if not items.is_empty():
			out.append("[ul]%s[/ul]" % "\n".join(items))
			items.clear()
		if skip:
			continue
		if s.begins_with("#"):
			if not out.is_empty():
				out.append("")
			out.append("[b]%s[/b]" % _bb_escape(s.lstrip("# ")))
		else:
			out.append(_bb_escape(s))
	if not items.is_empty():
		out.append("[ul]%s[/ul]" % "\n".join(items))
	return "\n".join(out)


static func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")
