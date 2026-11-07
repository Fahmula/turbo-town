#!/usr/bin/env bash
# Tests tools/steamdeck/turbotown.sh against a fake GitHub (fake_github.py) and
# fake game packages, in a temp folder (HOME too, so nothing real is touched).
# No Godot needed.
#
#   tools/steamdeck/test_launcher.sh
#
# Covers: install, the old update-before-start (when the game hasn't checked
# for updates lately), starting without downloading when it has, installing
# the game's download at start and on a restart (exit code 42), refusing a bad
# or older download, self-update from a download, the restart cap, exit codes
# and no internet.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
R="$WORK/releases"   # the fake GitHub's releases
G="$WORK/game"       # TURBOTOWN_DIR
mkdir -p "$R" "$G" "$WORK/home"
SERVER=""
trap '[[ -n "$SERVER" ]] && kill "$SERVER" 2>/dev/null; rm -rf "$WORK"' EXIT

fails=0 checks=0
check() {  # condition (bash), description
	checks=$((checks + 1))
	if eval "$1"; then echo "  ok    $2"; else echo "  FAIL  $2"; fails=$((fails + 1)); fi
}

# A fake release: its "game" logs the version, the launcher's env and its
# args, runs $WORK/hook once if there is one, then exits with the next code
# in $WORK/exit_codes (0 when empty).
make_release() {  # version
	local v="$1" d="$R/v$1" p="$WORK/pkg/$1/TurboTown"
	mkdir -p "$d" "$p"
	cat >"$p/TurboTown.x86_64" <<EOF
#!/usr/bin/env bash
echo "run $v launcher=\${TURBOTOWN_LAUNCHER:-} dir=\${TURBOTOWN_DIR:-} cwd=\$PWD args=\$*" >>"$WORK/runs.log"
if [[ -f "$WORK/hook" ]]; then bash "$WORK/hook"; rm -f "$WORK/hook"; fi
code=0
if [[ -s "$WORK/exit_codes" ]]; then code=\$(head -1 "$WORK/exit_codes"); sed -i 1d "$WORK/exit_codes"; fi
exit \$code
EOF
	chmod +x "$p/TurboTown.x86_64"
	echo "$v" >"$p/VERSION"
	tar -C "$WORK/pkg/$1" -czf "$d/TurboTown-v$v-linux-x86_64.tar.gz" TurboTown
	(cd "$d" && sha256sum "TurboTown-v$v-linux-x86_64.tar.gz" >"TurboTown-v$v-linux-x86_64.tar.gz.sha256")
	cp "$HERE/turbotown.sh" "$d/turbotown.sh"
}

# What the game does after downloading and checking a release: the files in
# pending.part/, a VERSION file, then the folder renamed to pending/.
game_downloads_script() {  # version
	cat <<EOF
rm -rf "$G/pending" "$G/pending.part" && mkdir -p "$G/pending.part" && cp "$R/v$1"/* "$G/pending.part/" \
	&& echo "$1" >"$G/pending.part/VERSION" && mv "$G/pending.part" "$G/pending"
EOF
}
game_downloads() { bash -c "$(game_downloads_script "$1")"; }

launcher() {  # args...; sets $code
	TURBOTOWN_REPO_URL="${REPO_URL:-http://127.0.0.1:$PORT}" TURBOTOWN_DIR="$G" HOME="$WORK/home" \
		bash "$G/turbotown.sh" "$@" >>"$WORK/launcher.out" 2>&1
	code=$?
}
installed() { cat "$G/current/VERSION" 2>/dev/null; }
last_run() { tail -1 "$WORK/runs.log" 2>/dev/null; }
downloads_of() { grep -c "GET /releases/download/v$1/" "$R/requests.log" 2>/dev/null; }

for v in 0.11.0 0.12.0 0.13.0 0.14.0 0.15.0 0.16.0; do make_release "$v"; done
echo "v0.11.0" >"$R/latest"
python3 -I "$HERE/fake_github.py" "$R" >"$WORK/server.out" 2>&1 &
SERVER=$!
for _ in $(seq 50); do [[ -s "$R/port" ]] && break; sleep 0.1; done
PORT="$(cat "$R/port")"
echo "fake GitHub on port $PORT"

echo "== install"
TURBOTOWN_REPO_URL="http://127.0.0.1:$PORT" TURBOTOWN_DIR="$G" HOME="$WORK/home" \
	bash "$HERE/turbotown.sh" install >>"$WORK/launcher.out" 2>&1
check '[[ "$(installed)" == 0.11.0 ]]' "install: 0.11.0 is installed"
check '[[ -x "$G/turbotown.sh" ]]' "install: the launcher is copied into the game folder"
check '[[ -f "$WORK/home/.local/share/applications/turbotown.desktop" ]]' "install: menu entry added"

echo "== the game hasn't checked for updates: update before starting (the old way)"
echo "v0.12.0" >"$R/latest"
launcher
check '[[ "$(installed)" == 0.12.0 ]]' "updated to 0.12.0 before starting"
check '[[ "$(last_run)" == "run 0.12.0 launcher=2 dir=$G cwd=$G/current args=" ]]' "started 0.12.0 with TURBOTOWN_LAUNCHER=2 and TURBOTOWN_DIR (got: $(last_run))"
check '[[ $code == 0 ]]' "exit code 0"

echo "== the game checked recently: start straight away, no download"
touch "$G/last-check"
echo "v0.13.0" >"$R/latest"
launcher
check '[[ "$(installed)" == 0.12.0 && "$(downloads_of 0.13.0)" == 0 ]]' "0.13.0 not downloaded by the launcher"
check '[[ "$(last_run)" == "run 0.12.0 "* ]]' "started 0.12.0"

echo "== the game's download is installed at the next start"
game_downloads 0.13.0
launcher
check '[[ "$(installed)" == 0.13.0 && ! -e "$G/pending" ]]' "0.13.0 installed from pending/, pending/ removed"
check '[[ "$(last_run)" == "run 0.13.0 "* ]]' "started 0.13.0"

echo "== RESTART TO UPDATE: the game downloads 0.14.0 and exits with 42"
game_downloads_script 0.14.0 >"$WORK/hook"
printf '42\n0\n' >"$WORK/exit_codes"
: >"$WORK/runs.log"
launcher play --some-arg
check '[[ "$(installed)" == 0.14.0 ]]' "0.14.0 installed after the restart"
check '[[ "$(sed -n 1p "$WORK/runs.log")" == "run 0.13.0 "*"args=--some-arg" && "$(sed -n 2p "$WORK/runs.log")" == "run 0.14.0 "*"args=--some-arg" ]]' "ran 0.13.0, then 0.14.0, same args both times"
check '[[ $code == 0 && $(wc -l <"$WORK/runs.log") == 2 ]]' "then the launcher exits 0"

echo "== a download that doesn't match its checksum is refused"
game_downloads 0.15.0
printf 'junk' >>"$G/pending/TurboTown-v0.15.0-linux-x86_64.tar.gz"
launcher
check '[[ "$(installed)" == 0.14.0 && ! -e "$G/pending" ]]' "still 0.14.0, the bad download is removed"
check 'grep -q "0.15.0 didn.t check out" "$G/update.log"' "update.log says why"

echo "== an older download is ignored, a half-finished one is cleaned up"
game_downloads 0.12.0
mkdir -p "$G/pending.part" && touch "$G/pending.part/partial"
launcher
check '[[ "$(installed)" == 0.14.0 && ! -e "$G/pending" && ! -e "$G/pending.part" ]]' "still 0.14.0; pending/ and pending.part/ removed"

echo "== the launcher updates itself from the game's download"
echo "# marker: launcher from 0.16.0" >>"$R/v0.16.0/turbotown.sh"
game_downloads 0.16.0
launcher
check '[[ "$(installed)" == 0.16.0 ]] && grep -q "marker: launcher from 0.16.0" "$G/turbotown.sh"' "0.16.0 installed and the launcher replaced"
check 'bash -n "$G/turbotown.sh"' "the new launcher is valid bash"

echo "== exit codes and the restart cap"
printf '3\n' >"$WORK/exit_codes"
: >"$WORK/runs.log"
launcher
check '[[ $code == 3 && $(wc -l <"$WORK/runs.log") == 1 ]]' "a crash code (3) is passed on, no restart"
printf '42\n42\n42\n42\n42\n' >"$WORK/exit_codes"
: >"$WORK/runs.log"
launcher
check '[[ $(wc -l <"$WORK/runs.log") == 4 && $code == 42 ]]' "42 with nothing to install: 3 restarts at most (ran $(wc -l <"$WORK/runs.log") times)"
: >"$WORK/exit_codes"

echo "== no internet"
rm -f "$G/last-check"
REPO_URL="http://127.0.0.1:9" launcher
check '[[ $code == 0 && "$(last_run)" == "run 0.16.0 "* ]]' "starts the installed game"

echo "== status"
game_downloads 0.15.0 && rm -f "$G/pending/TurboTown-v0.15.0-linux-x86_64.tar.gz.sha256"
touch "$G/last-check"
status_out="$(TURBOTOWN_REPO_URL="http://127.0.0.1:$PORT" TURBOTOWN_DIR="$G" bash "$G/turbotown.sh" status 2>&1)"
check '[[ "$status_out" == *"installed: 0.16.0"* && "$status_out" == *"latest:    v0.13.0"* && "$status_out" == *"downloaded, installs at next start: 0.15.0"* && "$status_out" == *"last checked for updates: 20"* ]]' "status shows installed, latest, the download and the last check"
launcher
check '[[ "$(installed)" == 0.16.0 && ! -e "$G/pending" ]]' "a download without its .sha256 is refused"

echo
echo "LAUNCHER: $checks checks, $fails failed"
[[ $fails == 0 ]] || { echo "--- launcher output"; tail -40 "$WORK/launcher.out"; echo "--- update.log"; tail -20 "$G/update.log"; }
exit $((fails > 0))
