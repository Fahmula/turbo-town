#!/usr/bin/env bash
# Tests in-game updates end to end on this PC (needs Godot and a display):
#  1. tools/steamdeck/test_launcher.sh (the launcher, with fake packages)
#  2. the game's updater (scripts/dev/updater_tests.gd, --updater) against a
#     fake GitHub (fake_github.py), throttled so the download takes a few
#     seconds; it must end with exit code 42 (RESTART TO UPDATE).
#
#   tools/steamdeck/test_updates.sh [shots dir]     (GODOT=/path/to/godot to pick one)
#
# Screenshots of the title screen's update box and WHAT'S NEW go to the shots
# dir (default: build/updater_shots).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-godot}"
SHOTS="${1:-$ROOT/build/updater_shots}"
WORK="$(mktemp -d)"
R="$WORK/releases"
SERVER=""
trap '[[ -n "$SERVER" ]] && kill "$SERVER" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$R" "$WORK/game" "$SHOTS"
failed=0

echo "==> Launcher"
"$HERE/test_launcher.sh" || failed=1

echo
echo "==> Game updater (fake GitHub, $GODOT)"
release() {  # tag, package size in KB, [bad]
	local d="$R/$1" pkg="TurboTown-$1-linux-x86_64.tar.gz"
	mkdir -p "$d"
	head -c "$(($2 * 1024))" /dev/urandom >"$d/$pkg"
	(cd "$d" && sha256sum "$pkg" >"$pkg.sha256")
	[[ "${3:-}" == bad ]] && printf 'damaged' >>"$d/$pkg"
	cp "$HERE/turbotown.sh" "$d/turbotown.sh"
}
release v0.11.0 64
release v0.12.1 256 bad
release v0.12.0 3072
cat >"$R/v0.12.0/notes.md" <<'EOF'
### New stuff

* **garage:** New BODY tab: spoilers on every vehicle (lip, ducktail, GT wing and a huge Mega Wing), bonnet vents, scoops and a supercharger sticking out of the bonnet, roof scoops, racks, light bars (they light up at night) and roof boxes. ([#2](https://github.com/Fahmula/turbo-town/issues/2)) ([abc1234](https://github.com/Fahmula/turbo-town/commit/abc1234))
* **garage:** PAINT: finishes (gloss, metallic, pearl, matte, chrome) and two-tone paint (roof, bonnet, both, or the lower half in a second colour). ([#2](https://github.com/Fahmula/turbo-town/issues/2)) ([abc1234](https://github.com/Fahmula/turbo-town/commit/abc1234))
* **garage:** New EXTRAS tab: underglow neon in eight colours (brightest at night) and eight horns to pick from, including an old-timer "ah-oo-gah", a little tune, a clown honk and a train horn. ([#2](https://github.com/Fahmula/turbo-town/issues/2)) ([abc1234](https://github.com/Fahmula/turbo-town/commit/abc1234))
* **garage:** The garage camera turns to show the part you're changing. ([#2](https://github.com/Fahmula/turbo-town/issues/2)) ([abc1234](https://github.com/Fahmula/turbo-town/commit/abc1234))

### Fixes

* The horn [no longer] gets stuck on. ([#5](https://github.com/Fahmula/turbo-town/issues/5)) ([def5678](https://github.com/Fahmula/turbo-town/commit/def5678))

## Steam Deck
Already installed with `turbotown.sh`? Nothing to do: the game updates itself.

First-time install (Desktop Mode, open Konsole):
```
curl -fLo /tmp/turbotown.sh https://github.com/Fahmula/turbo-town/releases/latest/download/turbotown.sh && bash /tmp/turbotown.sh install
```

## Commits since v0.11.0
- feat(garage): body kits, spoilers, paint finishes, decals, underglow, horns (abc1234)

---
Built from abc1234 with Godot 4.7.2. SHA-256 of `TurboTown-v0.12.0-linux-x86_64.tar.gz`: `0000`
EOF
echo "v0.11.0" >"$R/latest"
python3 -I "$HERE/fake_github.py" "$R" --throttle-kbps 700 >"$WORK/server.out" 2>&1 &
SERVER=$!
for _ in $(seq 50); do [[ -s "$R/port" ]] && break; sleep 0.1; done

TURBOTOWN_LAUNCHER=2 TURBOTOWN_DIR="$WORK/game" TURBOTOWN_TEST_GITHUB="$R" \
	timeout 300 "$GODOT" --path "$ROOT" --resolution 1280x800 -- --updater="$SHOTS" >"$WORK/godot.log" 2>&1
code=$?
cp "$WORK/godot.log" "$SHOTS/godot.log"
grep -E "^  (ok  |FAIL)|^UPDATER|^  RESTART|lowest fps|^updates:" "$WORK/godot.log"
summary="$(grep -E '^UPDATER: [0-9]+ checks' "$WORK/godot.log")"
if [[ "$summary" != *", 0 failed" ]]; then
	echo "FAIL  updater checks failed (or didn't finish)"; failed=1
fi
if [[ $code == 42 ]]; then
	echo "  ok    the game quit with exit code 42 (the launcher's restart code)"
else
	echo "  FAIL  exit code $code, expected 42"; failed=1
fi
if grep -E "SCRIPT ERROR|Parse Error" "$WORK/godot.log" >/dev/null; then
	echo "  FAIL  script errors:"; grep -E -A3 "SCRIPT ERROR|Parse Error" "$WORK/godot.log" | head -20; failed=1
fi
echo "Shots: $SHOTS"
echo
[[ $failed == 0 ]] && echo "ALL UPDATE TESTS PASSED" || echo "SOME UPDATE TESTS FAILED (game log: $SHOTS/godot.log)"
exit $failed
