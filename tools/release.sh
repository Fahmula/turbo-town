#!/usr/bin/env bash
# Turbo Town release pipeline. See RELEASING.md.
#
#   tools/release.sh 0.3.0              build HEAD, tag v0.3.0, publish GitHub Release
#   tools/release.sh 0.3.0 <commit>     release a specific (already pushed) commit
#   tools/release.sh 0.3.0 --dry-run    build + package + smoke test only; no tag, no release
#   tools/release.sh 0.3.0 --yes        don't ask for confirmation before publishing
#
# The build is made from a clean `git archive` of the commit, never from the
# working tree, so uncommitted or experimental work can't leak into a release.
set -euo pipefail

GODOT="${GODOT:-godot}"
GODOT_VERSION="4.7.2"                       # must match the installed export templates
PRESET="Linux x86_64 (Steam Deck)"          # name in export_presets.cfg
GAME="TurboTown"
BRANCH="main"

die() { echo "release: error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

VERSION="" COMMIT="HEAD" DRY_RUN=0 YES=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--yes|-y) YES=1 ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		-*) die "unknown option $arg" ;;
		*) if [[ -z "$VERSION" ]]; then VERSION="$arg"; else COMMIT="$arg"; fi ;;
	esac
done
[[ -n "$VERSION" ]] || die "usage: tools/release.sh X.Y.Z [commit] [--dry-run] [--yes]"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 0.3.0 (got '$VERSION')"
TAG="v$VERSION"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ---------------------------------------------------------------- checks
step "Checking prerequisites"
command -v "$GODOT" >/dev/null || die "godot not found (set GODOT=/path/to/godot)"
"$GODOT" --version | grep -q "^$GODOT_VERSION\." || die "expected Godot $GODOT_VERSION, got $("$GODOT" --version)"
TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION.stable"
[[ -f "$TEMPLATES/linux_release.x86_64" ]] || die "missing export template $TEMPLATES/linux_release.x86_64 (see RELEASING.md)"

SHA="$(git rev-parse --verify "$COMMIT^{commit}")" || die "unknown commit $COMMIT"
SHORT="${SHA:0:8}"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"

PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$SHA" 2>/dev/null || true)"
if [[ -n "$PREV_TAG" ]]; then
	# sort -V: the new version must be strictly newer than the previous release
	[[ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" == "$VERSION" && "${PREV_TAG#v}" != "$VERSION" ]] \
		|| die "$TAG is not newer than previous release $PREV_TAG"
fi

NOTES="$(git show "$SHA:CHANGELOG.md" 2>/dev/null | awk -v v="$VERSION" '
	$0 ~ "^## \\[" v "\\]" { on = 1; next }
	on && /^## \[/ { exit }
	on { print }' | sed -e '/./,$!d' || true)"   # drop leading blank lines
if [[ -z "${NOTES//[[:space:]]/}" ]]; then
	[[ $DRY_RUN == 1 ]] || die "CHANGELOG.md at $SHORT has no '## [$VERSION]' section; write the release notes and commit first"
	echo "warning: no CHANGELOG.md section for $VERSION (ok for --dry-run)"
fi

if [[ $DRY_RUN == 0 ]]; then
	gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
	git fetch -q origin "$BRANCH" --tags
	git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists on origin"
	git merge-base --is-ancestor "$SHA" "origin/$BRANCH" \
		|| die "commit $SHORT is not on origin/$BRANCH yet; push first: git push origin $BRANCH"
fi

# ---------------------------------------------------------------- build
OUT="$ROOT/build/release/$TAG"
SRC="$OUT/src"
BIN_DIR="$OUT/linux"
PKG_NAME="$GAME-$TAG-linux-x86_64"
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
cat >"$PKG_DIR/README.txt" <<EOF
Turbo Town $TAG (Linux x86_64 / Steam Deck)
Built from commit $SHORT with Godot $GODOT_VERSION.

Run: ./$GAME.x86_64
Steam Deck: add $GAME.x86_64 to Steam as a Non-Steam Game, then play it from Game Mode.
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
## Install / update on Steam Deck
1. Download \`$PKG_NAME.tar.gz\` below and extract it (it contains a \`$GAME/\` folder).
2. To update, replace the old \`$GAME/\` folder with the new one. Your Steam shortcut keeps working.
3. First install only: in Desktop Mode, Steam > Add a Game > Add a Non-Steam Game > browse to \`$GAME/$GAME.x86_64\`.

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
	read -r -p "Tag and publish $TAG as the new stable release? [y/N] " answer
	[[ "$answer" == [yY]* ]] || die "cancelled; nothing was tagged or published"
fi

step "Tagging $TAG"
git tag -a "$TAG" "$SHA" -m "Turbo Town $TAG"
git push origin "refs/tags/$TAG"

step "Creating GitHub Release"
gh release create "$TAG" "$TARBALL" "$TARBALL.sha256" \
	--verify-tag --latest --title "Turbo Town $TAG" --notes-file "$NOTES_FILE"
echo
echo "Released $TAG: $(gh release view "$TAG" --json url --jq .url)"
