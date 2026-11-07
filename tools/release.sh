#!/usr/bin/env bash
# Turbo Town release pipeline. See RELEASING.md.
#
# Releases are made by release-please: merging its release PR tags vX.Y.Z and
# creates a draft GitHub Release, and GitHub Actions then runs --publish.
#
#   tools/release.sh 0.12.0 --dry-run            build + package + smoke test HEAD; publishes nothing
#   tools/release.sh 0.12.0 <commit> --dry-run   the same for another commit
#   tools/release.sh 0.12.0 --publish            build the tag v0.12.0, upload it to its draft
#                                                release and publish it (what CI runs)
#   tools/release.sh 0.12.0 --publish --yes      the same without asking first
#
# The build is made from a clean `git archive` of the commit, never from the
# working tree, so uncommitted or experimental work can't leak into a release.
set -euo pipefail

GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2"                       # must match the installed export templates (CI reads this too)
PRESET="Linux x86_64 (Steam Deck)"          # name in export_presets.cfg
GAME="TurboTown"
BRANCH="main"

die() { echo "release: error: $*" >&2; exit 1; }
warn() { echo "release: warning: $*" >&2; }
step() { echo; echo "==> $*"; }

VERSION="" COMMIT="" DRY_RUN=0 PUBLISH=0 YES=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--publish) PUBLISH=1 ;;
		--yes|-y) YES=1 ;;
		-h|--help) sed -n '2,14p' "$0"; exit 0 ;;
		-*) die "unknown option $arg" ;;
		*) if [[ -z "$VERSION" ]]; then VERSION="$arg"; else COMMIT="$arg"; fi ;;
	esac
done
[[ -n "$VERSION" ]] || die "usage: tools/release.sh X.Y.Z [commit] --dry-run | --publish [--yes]"
[[ $DRY_RUN == 1 || $PUBLISH == 1 ]] \
	|| die "pick --dry-run (test build) or --publish (CI). Releases are made by merging the release-please PR, see RELEASING.md"
[[ $DRY_RUN == 1 && $PUBLISH == 1 ]] && die "--dry-run and --publish can't be combined"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 0.3.0 (got '$VERSION')"
TAG="v$VERSION"
[[ -n "$COMMIT" ]] || { [[ $PUBLISH == 1 ]] && COMMIT="$TAG" || COMMIT="HEAD"; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ---------------------------------------------------------------- checks
step "Checking prerequisites"
command -v "$GODOT" >/dev/null || die "godot not found (set GODOT=/path/to/godot)"
"$GODOT" --headless --version | grep -q "^$GODOT_VERSION\." || die "expected Godot $GODOT_VERSION, got $("$GODOT" --headless --version)"
TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION.stable"
[[ -f "$TEMPLATES/linux_release.x86_64" ]] || die "missing export template $TEMPLATES/linux_release.x86_64 (see RELEASING.md)"

if [[ $PUBLISH == 1 ]]; then
	# In CI gh uses GH_TOKEN; on a PC it needs `gh auth login`.
	[[ -n "${GH_TOKEN:-}" ]] || gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
	git fetch -q origin "$BRANCH" --tags
	git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
		|| die "tag $TAG doesn't exist; release-please makes it when the release PR is merged"
fi

SHA="$(git rev-parse --verify "$COMMIT^{commit}")" || die "unknown commit $COMMIT"
SHORT="${SHA:0:8}"

if [[ $PUBLISH == 1 ]]; then
	[[ "$(git rev-parse "$TAG^{commit}")" == "$SHA" ]] || die "tag $TAG is not on commit $SHORT"
	git merge-base --is-ancestor "$SHA" "origin/$BRANCH" || die "commit $SHORT is not on origin/$BRANCH"
	# Only a draft is (re)built. A published release is on the Deck already and
	# its files must never change: ship a new version instead.
	IS_DRAFT="$(gh release view "$TAG" --json isDraft --jq .isDraft 2>/dev/null)" \
		|| die "there is no GitHub Release for $TAG (release-please creates it as a draft)"
	[[ "$IS_DRAFT" == "true" ]] || die "$TAG is already published; releases are permanent, ship a new version instead"
	# Publishing marks the release "latest", and the Deck installs whatever is
	# latest, so an old draft published late would downgrade it.
	LATEST="$(gh release view --json tagName --jq .tagName 2>/dev/null || true)"
	if [[ -n "$LATEST" && "$(printf '%s\n%s\n' "${LATEST#v}" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]]; then
		die "$LATEST is already published and newer than $TAG; publishing $TAG would downgrade the Deck"
	fi
	REPO_WEB="$(gh repo view --json url --jq .url)"
elif git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	warn "tag $TAG already exists (fine for a test build)"
fi

PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude "$TAG" "$SHA" 2>/dev/null || true)"
if [[ -n "$PREV_TAG" ]]; then
	# sort -V: the new version must be strictly newer than the previous release
	if ! [[ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" == "$VERSION" && "${PREV_TAG#v}" != "$VERSION" ]]; then
		[[ $PUBLISH == 1 ]] && die "$TAG is not newer than previous release $PREV_TAG"
		warn "$TAG is not newer than previous release $PREV_TAG (fine for a test build)"
	fi
fi

# release-please writes "## [X.Y.Z](compare link) (date)"; older entries are "## [X.Y.Z] - date".
NOTES="$(git show "$SHA:CHANGELOG.md" 2>/dev/null | awk -v v="$VERSION" '
	index($0, "## [" v "]") == 1 { on = 1; next }
	on && /^## \[/ { exit }
	on { print }' | sed -e '/./,$!d' || true)"   # drop leading blank lines
if [[ -z "${NOTES//[[:space:]]/}" ]]; then
	[[ $PUBLISH == 1 ]] && die "CHANGELOG.md at $SHORT has no '## [$VERSION]' section (release-please writes it in the release PR)"
	warn "no CHANGELOG.md section for $VERSION (fine for a test build)"
fi

# ---------------------------------------------------------------- build
OUT="$ROOT/build/release/$TAG"
SRC="$OUT/src"
BIN_DIR="$OUT/linux"
PKG_NAME="$GAME-$TAG-linux-x86_64"
[[ $DRY_RUN == 1 ]] && PKG_NAME="$GAME-$TAG-DRYRUN-$SHORT-linux-x86_64"   # never mistaken for a release
PKG_DIR="$OUT/package/$GAME"
DIST="$ROOT/dist"
TARBALL="$DIST/$PKG_NAME.tar.gz"
rm -rf "$OUT"
mkdir -p "$SRC" "$BIN_DIR" "$PKG_DIR" "$DIST"

step "Extracting clean source of $SHORT"
git archive "$SHA" | tar -x -C "$SRC"
# Stamp the version into the build copy only (ProjectSettings application/config/version).
sed -i '/^config\/version=/d; /^\[application\]$/a config/version="'"$VERSION"'"' "$SRC/project.godot"

# Godot prints script/import errors but still exits 0, so scan the logs.
check_log() {  # file, label
	if grep -E "SCRIPT ERROR|^ERROR:|Parse Error|Failed to load" "$1" >/dev/null; then
		grep -E -A2 "SCRIPT ERROR|^ERROR:|Parse Error|Failed to load" "$1" | head -40 >&2
		die "$2 reported errors (full log: $1)"
	fi
}

step "Importing assets"
"$GODOT" --headless --path "$SRC" --import >"$OUT/import.log" 2>&1 || { tail -30 "$OUT/import.log" >&2; die "import failed"; }
check_log "$OUT/import.log" "import"

step "Exporting '$PRESET'"
"$GODOT" --headless --path "$SRC" --export-release "$PRESET" "$BIN_DIR/$GAME.x86_64" >"$OUT/export.log" 2>&1 \
	|| { tail -30 "$OUT/export.log" >&2; die "export failed"; }
check_log "$OUT/export.log" "export"
[[ -x "$BIN_DIR/$GAME.x86_64" ]] || die "export produced no binary"

step "Smoke test: running the exported game headless for 600 frames"
timeout 180 "$BIN_DIR/$GAME.x86_64" --headless --quit-after 600 >"$OUT/smoke.log" 2>&1 \
	|| { tail -30 "$OUT/smoke.log" >&2; die "exported game crashed or hung"; }
check_log "$OUT/smoke.log" "smoke test"
echo "ok"

# ---------------------------------------------------------------- package
step "Packaging $PKG_NAME.tar.gz"
cp "$BIN_DIR/$GAME.x86_64" "$PKG_DIR/"
printf '%s\n' "$VERSION" >"$PKG_DIR/VERSION"
cp "$SRC/icon.svg" "$PKG_DIR/icon.svg"
cat >"$PKG_DIR/README.txt" <<EOF
Turbo Town $TAG (Linux x86_64 / Steam Deck)
Built from commit $SHORT with Godot $GODOT_VERSION.

Run: ./$GAME.x86_64
Steam Deck: use the turbotown.sh installer from the GitHub Release page instead;
it installs, adds a Steam shortcut, and keeps the game updated.
EOF
tar -C "$OUT/package" -czf "$TARBALL" "$GAME"
(cd "$DIST" && sha256sum "$PKG_NAME.tar.gz" >"$PKG_NAME.tar.gz.sha256")
CHECKSUM="$(cut -d' ' -f1 "$TARBALL.sha256")"
ls -lh "$TARBALL"

if [[ $DRY_RUN == 1 ]]; then
	echo
	echo "Dry run complete. Game: $BIN_DIR/$GAME.x86_64   Package: $TARBALL"
	exit 0
fi

# ---------------------------------------------------------------- publish
NOTES_FILE="$OUT/release-notes.md"
{
	printf '%s\n\n' "$NOTES"
	cat <<EOF
## Steam Deck
Already installed with \`turbotown.sh\`? Nothing to do: the game updates itself the next time it's launched.

First-time install (Desktop Mode, open Konsole):
\`\`\`
curl -fLo /tmp/turbotown.sh $REPO_WEB/releases/latest/download/turbotown.sh && bash /tmp/turbotown.sh install
\`\`\`
Manual alternative: extract \`$PKG_NAME.tar.gz\` and run \`$GAME/$GAME.x86_64\`.

EOF
	if [[ -n "$PREV_TAG" ]]; then
		echo "## Commits since $PREV_TAG"
		git log --no-merges --format='- %s (%h)' "$PREV_TAG..$SHA"
		echo
	fi
	echo "---"
	echo "Built from $SHORT with Godot $GODOT_VERSION. SHA-256 of \`$PKG_NAME.tar.gz\`: \`$CHECKSUM\`"
} >"$NOTES_FILE"

step "Ready to publish"
echo "  version: $TAG   commit: $SHORT $(git log -1 --format=%s "$SHA")"
echo "  previous release: ${PREV_TAG:-none}"
echo "  asset: $TARBALL"
echo "  notes: $NOTES_FILE"
if [[ $YES == 0 ]]; then
	read -r -p "Publish $TAG as the new stable release (the Steam Deck installs it on its next launch)? [y/N] " answer
	[[ "$answer" == [yY]* ]] || die "cancelled; the draft release was not changed"
fi

# Files first, then publish: until the last command the release is still a
# draft, which the Deck never sees. --clobber replaces files from a failed run.
step "Uploading to the draft release $TAG"
cp "$SRC/tools/steamdeck/turbotown.sh" "$OUT/turbotown.sh"
gh release upload "$TAG" "$TARBALL" "$TARBALL.sha256" "$OUT/turbotown.sh" --clobber

step "Publishing $TAG"
gh release edit "$TAG" --title "Turbo Town $TAG" --notes-file "$NOTES_FILE" --draft=false --latest
echo
echo "Released $TAG: $(gh release view "$TAG" --json url --jq .url)"
