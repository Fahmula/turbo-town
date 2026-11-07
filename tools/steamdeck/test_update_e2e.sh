#!/usr/bin/env bash
# End-to-end check of in-game updates with real exported builds (slow: two
# exports of the current commit, so commit first).
#
#   tools/steamdeck/test_update_e2e.sh
#
# Exports HEAD twice with tools/release.sh --dry-run, stamped 0.12.0 and
# 0.13.0. Installs 0.12.0 the way the Deck has it (launcher + current/, the
# game checked recently), serves 0.13.0 from a fake GitHub, and starts the
# real launcher with the game in --headless --updatecycle mode:
#   0.12.0 finds 0.13.0, downloads and checks it, and quits with exit code 42;
#   the launcher installs 0.13.0 and starts it again;
#   0.13.0 finds it's up to date and quits; the launcher exits 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
R="$WORK/releases"
G="$WORK/game"
SERVER=""
trap '[[ -n "$SERVER" ]] && kill "$SERVER" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$R/v0.13.0" "$G" "$WORK/home" "$WORK/x"
fails=0 checks=0
check() {
	checks=$((checks + 1))
	if eval "$1"; then echo "  ok    $2"; else echo "  FAIL  $2"; fails=$((fails + 1)); fi
}

SHORT="$(git -C "$ROOT" rev-parse --short=8 HEAD)"
[[ -z "$(git -C "$ROOT" status --porcelain -- scripts tools project.godot)" ]] \
	|| echo "warning: uncommitted changes in scripts/, tools/ or project.godot are NOT in this build (it exports HEAD $SHORT)"
for v in 0.12.0 0.13.0; do
	echo "==> Exporting $SHORT as $v"
	"$ROOT/tools/release.sh" "$v" HEAD --dry-run >"$WORK/build-$v.log" 2>&1 \
		|| { tail -20 "$WORK/build-$v.log"; echo "export $v failed"; exit 1; }
done
pkg() { echo "$ROOT/dist/TurboTown-v$1-DRYRUN-$SHORT-linux-x86_64.tar.gz"; }

# The Deck: 0.12.0 installed by the launcher, and the game checked recently
# (so the launcher starts it without downloading anything itself).
tar -xzf "$(pkg 0.12.0)" -C "$WORK/x" && mv "$WORK/x/TurboTown" "$G/current"
cp "$HERE/turbotown.sh" "$G/turbotown.sh"
touch "$G/last-check"

# GitHub: 0.13.0 is the latest release.
P="TurboTown-v0.13.0-linux-x86_64.tar.gz"
cp "$(pkg 0.13.0)" "$R/v0.13.0/$P"
(cd "$R/v0.13.0" && sha256sum "$P" >"$P.sha256")
cp "$HERE/turbotown.sh" "$R/v0.13.0/turbotown.sh"
printf '### New stuff\n\n* **test:** end to end\n' >"$R/v0.13.0/notes.md"
echo "v0.13.0" >"$R/latest"
python3 -I "$HERE/fake_github.py" "$R" >"$WORK/server.out" 2>&1 &
SERVER=$!
for _ in $(seq 50); do [[ -s "$R/port" ]] && break; sleep 0.1; done
PORT="$(cat "$R/port")"

echo "==> Starting the launcher (game: --headless --updatecycle)"
TURBOTOWN_REPO_URL="http://127.0.0.1:$PORT" \
TURBOTOWN_API_URL="http://127.0.0.1:$PORT/repos/Fahmula/turbo-town/releases/latest" \
TURBOTOWN_DIR="$G" HOME="$WORK/home" \
	timeout 600 bash "$G/turbotown.sh" play --headless -- --updatecycle >"$WORK/run.log" 2>&1
code=$?
grep -E "^updatecycle:|^updates:|Restarting|Installed" "$WORK/run.log"

check '[[ $code == 0 ]]' "the launcher exits 0 (got $code)"
check 'grep -q "^updatecycle: version 0.12.0, state READY, latest 0.13.0" "$WORK/run.log"' "0.12.0 found 0.13.0 and downloaded it"
check 'grep -q "Restarting Turbo Town to install the update." "$G/update.log"' "it quit with code 42; the launcher restarted it"
check '[[ "$(cat "$G/current/VERSION")" == 0.13.0 ]] && grep -q "Installed Turbo Town 0.13.0." "$G/update.log"' "the launcher installed 0.13.0"
check 'grep -q "^updatecycle: version 0.13.0, state UP_TO_DATE" "$WORK/run.log"' "0.13.0 started and found it's up to date"
check '[[ ! -e "$G/pending" && ! -e "$G/pending.part" ]]' "pending/ is gone"
check '[[ "$(grep -c "^GET /releases/download/v0.13.0/$P$" "$R/requests.log")" == 1 ]]' "the package was downloaded once, by the game"
check '! grep -E "SCRIPT ERROR|Parse Error" "$WORK/run.log" >/dev/null' "no script errors"
check '[[ -f "$WORK/home/.local/share/godot/app_userdata/Turbo Town/settings.cfg" || -d "$WORK/home/.local/share/godot" ]]' "save data stayed in the test HOME"

echo
echo "E2E: $checks checks, $fails failed"
[[ $fails == 0 ]] || { echo "--- run.log"; tail -40 "$WORK/run.log"; echo "--- update.log"; cat "$G/update.log"; }
exit $((fails > 0))
