extends "res://scripts/dev/split_tests.gd"
## The in-game update dev test (run from DevTools):
##   --updater=<dir>  Updates against a fake GitHub (tools/steamdeck/fake_github.py):
##                    off in a dev build, the first check, up to date, GitHub
##                    refusing, a download with a bad checksum, the background
##                    download (progress on the title screen), the toast while
##                    driving, pending/ for the launcher, the pause note, the
##                    title box and its gamepad focus, WHAT'S NEW, and finally
##                    RESTART TO UPDATE, which quits with exit code 42 (checks
##                    and shots).
## Run it with tools/steamdeck/test_updates.sh, which starts the fake GitHub,
## sets TURBOTOWN_TEST_GITHUB / TURBOTOWN_DIR / TURBOTOWN_LAUNCHER and checks
## the exit code and the summary line.

## The fake GitHub's releases folder, and the launcher's folder.
var _gh := ""
var _dir := ""


func run() -> void:
	var g := game
	var menu := g.menu
	var u := Updates
	_gh = OS.get_environment("TURBOTOWN_TEST_GITHUB")
	_dir = OS.get_environment("TURBOTOWN_DIR")
	if _gh == "" or _dir == "":
		check(false, "run this with tools/steamdeck/test_updates.sh (TURBOTOWN_TEST_GITHUB, TURBOTOWN_DIR)")
		return
	var port := FileAccess.get_file_as_string(_gh.path_join("port")).strip_edges()
	var api := "http://127.0.0.1:%s/repos/Fahmula/turbo-town/releases/latest" % port
	g.traffic.set_enabled(false)

	# --- A dev build under the launcher: no version, so updates stay off -------
	check(OS.get_environment("TURBOTOWN_LAUNCHER") == "2", "started as if by the launcher")
	check(u.state == u.State.OFF, "dev build (no version): updates are off")
	g._enter_title()
	await wait_s(0.3)
	check(not menu._update_box.visible, "title: no update box")
	check(not _requested("/repos/"), "nothing was asked of GitHub")

	# --- Up to date ----------------------------------------------------------------
	_write("latest", "v0.11.0")
	u.setup(_dir, "0.11.0", api)
	check(u.state == u.State.WAITING, "turned on (as 0.11.0): waiting for the first check")
	await _until(func() -> bool: return u.state == u.State.UP_TO_DATE, u.FIRST_CHECK + 6.0)
	check(u.state == u.State.UP_TO_DATE, "first check after %.0f s: up to date" % u.FIRST_CHECK)
	check(FileAccess.file_exists(_dir.path_join("last-check")), "last-check written for the launcher")
	check(not menu._update_box.visible, "title: still no update box")
	check(u._timer.time_left > 600.0, "next check in %.0f min" % (u._timer.time_left / 60.0))

	# --- GitHub refusing (rate limited): a quiet failure, retried later ------------------
	_write("api_status", "403")
	DirAccess.remove_absolute(_dir.path_join("last-check"))
	u.check_now()
	await _until(func() -> bool: return u.state == u.State.FAILED, 10.0)
	check(u.state == u.State.FAILED and u.problem.contains("403"), "GitHub answers 403: failed (%s)" % u.problem)
	check(not menu._update_box.visible, "title: nothing shown for that")
	check(not FileAccess.file_exists(_dir.path_join("last-check")), "no last-check (the launcher's fallback stays armed)")
	check(u._timer.time_left > 0.0 and u._timer.time_left <= 60.0, "retry in %.0f s" % u._timer.time_left)
	_write("api_status", "200")

	# --- A newer release whose package doesn't match its checksum ---------------------
	_write("latest", "v0.12.1")
	u.check_now()
	await _until(func() -> bool: return u.state == u.State.FAILED, 30.0)
	check(u.state == u.State.FAILED and u.problem.contains("damaged"), "bad checksum: refused (%s)" % u.problem)
	check(not DirAccess.dir_exists_absolute(_dir.path_join("pending")), "nothing in pending/")
	check(not DirAccess.dir_exists_absolute(_dir.path_join("pending.part")), "pending.part/ cleaned up")
	await wait(2)
	check(menu._update_box.visible and menu._update_status.text.begins_with("Couldn't download"),
		"title: \"%s\"" % menu._update_status.text)
	check(not menu._update_restart.visible and not menu._update_bar.visible, "no RESTART button or bar")
	await shot("update_failed")

	# --- The good release, downloading in the background (throttled) -------------------
	_write("latest", "v0.12.0")
	u.check_now()
	await _until(func() -> bool: return u.state == u.State.DOWNLOADING and u.progress > 0.25, 20.0)
	check(u.state == u.State.DOWNLOADING and u.latest == "0.12.0", "v0.12.0 found, downloading")
	check(u.problem == "", "the old problem is cleared")
	await wait(3)
	check(menu._update_box.visible and menu._update_bar.visible and menu._update_status.text.begins_with("Downloading..."),
		"title: \"%s\", bar %.0f%%" % [menu._update_status.text, menu._update_bar.value * 100.0])
	check(menu._update_title.text == "NEW VERSION 0.12.0", "box title: %s" % menu._update_title.text)
	check(not menu._update_restart.visible and menu._update_notes.visible, "WHAT'S NEW? already, no RESTART yet")
	await shot("update_downloading")
	var fps_low := 1000.0
	g._enter_driving()
	# Finishing while driving: a toast says where to find it.
	while u.state in [u.State.DOWNLOADING, u.State.VERIFYING]:
		await tools.get_tree().process_frame
		fps_low = minf(fps_low, Engine.get_frames_per_second())
	check(u.state == u.State.READY, "downloaded and checked (%s)" % u.problem)
	print("  (lowest fps reading while downloading: %.0f)" % fps_low)
	await wait(3)
	check(g.p1.hud._toast.text == "New version ready! Find it in the MAIN MENU.", "toast while driving: %s" % g.p1.hud._toast.text)
	var pending := _dir.path_join("pending")
	var pkg := pending.path_join("TurboTown-v0.12.0-linux-x86_64.tar.gz")
	check(FileAccess.get_file_as_string(pending.path_join("VERSION")).strip_edges() == "0.12.0", "pending/VERSION is 0.12.0")
	check(FileAccess.file_exists(pkg) and FileAccess.get_sha256(pkg) == FileAccess.get_file_as_string(pkg + ".sha256").split(" ")[0],
		"pending/ has the package, and it matches its .sha256")
	check(FileAccess.get_file_as_string(pending.path_join("turbotown.sh")).begins_with("#!/usr/bin/env bash"), "and the release's launcher script")
	check(not DirAccess.dir_exists_absolute(_dir.path_join("pending.part")), "pending.part/ was renamed to pending/")
	var asked := _count("/repos/")
	u.check_now()
	check(u.state == u.State.READY and _count("/repos/") == asked, "no more checks once one is ready")

	# --- Pause, then the title screen -------------------------------------------------
	g._enter_pause()
	await wait(2)
	check(menu._note.visible and menu._note.text == "Update ready: see MAIN MENU", "pause note: %s" % menu._note.text)
	await shot("update_pause")
	g._on_menu_action("title")
	await wait_s(0.5)
	check(menu.page == "title" and menu._update_box.visible, "MAIN MENU: the update box is there")
	check(menu._update_status.text == "Ready! Restart the game to play it." and menu._update_restart.visible and not menu._update_bar.visible,
		"title: \"%s\", RESTART TO UPDATE, no bar" % menu._update_status.text)
	check(tools.get_viewport().gui_get_focus_owner() != menu._update_restart, "PLAY! keeps the first focus (no accidental restart)")
	var vp := tools.get_viewport().get_visible_rect().size
	var box := menu._update_box.get_global_rect()
	check(box.end.x <= vp.x - 23.0 and box.end.y <= vp.y - 23.0 and box.position.x > 420.0,
		"box inside the safe margin, clear of the menu column (%s in %s)" % [box, vp])
	await shot("update_ready")

	# --- Gamepad: QUIT, down, into the box ---------------------------------------------
	menu._title_quit.grab_focus()
	await wait(2)
	await pad(0, JOY_BUTTON_DPAD_DOWN)
	check(tools.get_viewport().gui_get_focus_owner() == menu._update_restart, "D-pad down from QUIT: RESTART TO UPDATE")
	await pad(0, JOY_BUTTON_DPAD_DOWN)
	check(tools.get_viewport().gui_get_focus_owner() == menu._update_notes, "down again: WHAT'S NEW?")
	await pad(0, JOY_BUTTON_DPAD_LEFT)
	check(tools.get_viewport().gui_get_focus_owner() == menu._title_quit, "left: back to QUIT")
	menu._update_notes.grab_focus()
	await wait(2)
	await pad(0, JOY_BUTTON_A)
	await wait(3)
	check(menu.page == "whats_new", "A on WHAT'S NEW?: the page opens")
	var t := menu._news_text.get_parsed_text()
	check(menu._news_title.text == "WHAT'S NEW IN 0.12.0", "page title: %s" % menu._news_title.text)
	check(t.contains("New stuff") and t.contains("Garage: New BODY tab") and t.contains("Fixes"), "the notes: new stuff, fixes")
	check(not t.contains("**") and not t.contains("](") and not t.contains("abc1234"), "no Markdown, links or commit hashes")
	check(not t.contains("Steam Deck") and not t.contains("Commits since") and not t.contains("SHA-256"), "no install steps, commit list or checksum")
	check(menu._news_restart.visible, "RESTART TO UPDATE on the page too")
	await shot("whats_new")
	var bar := menu._news_text.get_v_scroll_bar()
	await pad(0, JOY_BUTTON_DPAD_DOWN)
	check(bar.max_value <= bar.page or bar.value > 0.0, "down scrolls the notes (%.0f of %.0f)" % [bar.value, bar.max_value - bar.page])
	await pad(0, JOY_BUTTON_B)
	await wait(2)
	check(menu.page == "title", "B: back to the title screen")

	# --- RESTART TO UPDATE (last: it quits; the wrapper checks exit code 42) -----------
	print("UPDATER: %d checks, %d failed" % [checks, fails])
	print("  RESTART TO UPDATE: expecting exit code %d" % u.EXIT_RESTART)
	menu._update_restart.grab_focus()
	await wait(2)
	await pad(0, JOY_BUTTON_A)
	await wait_s(3.0)
	print("UPDATER: RESTART TO UPDATE didn't quit")


func _until(cond: Callable, timeout: float) -> void:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await tools.get_tree().process_frame


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(_gh.path_join(file), FileAccess.WRITE)
	f.store_string(text + "\n")


func _count(path_part: String) -> int:
	var log := FileAccess.get_file_as_string(_gh.path_join("requests.log"))
	return log.count(path_part)


func _requested(path_part: String) -> bool:
	return _count(path_part) > 0
