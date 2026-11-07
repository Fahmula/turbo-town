#!/usr/bin/env bash
# Turbo Town installer / updater / launcher for the Steam Deck (any x86_64 Linux).
#
#   bash turbotown.sh install   first-time setup: installs to ~/Games/TurboTown,
#                               adds a menu entry and a Steam shortcut
#   turbotown.sh                (what the Steam shortcut runs) start the game
#   turbotown.sh update         update now (download the latest release)
#   turbotown.sh status         show installed and latest versions
#
# Updates: the game checks GitHub itself and downloads a newer release in the
# background into pending/ (it's started with TURBOTOWN_LAUNCHER and
# TURBOTOWN_DIR so it knows where). This script installs that download: when
# the player picks RESTART TO UPDATE (the game exits with code 42 and is
# started again), or at the next launch. If the game hasn't managed to check
# for 7 days (an old version, no updater, or something broken), the launcher
# updates before starting, like it always did.
#
# Only the latest *stable* GitHub Release is ever installed (drafts and
# pre-releases are ignored). With no internet it just starts the installed game.
# Save data lives in ~/.local/share/godot/app_userdata/, not here, so updates
# never touch it.

REPO_URL="${TURBOTOWN_REPO_URL:-https://github.com/Fahmula/turbo-town}"
DIR="${TURBOTOWN_DIR:-$HOME/Games/TurboTown}"
GAME="TurboTown"
LOG="$DIR/update.log"
DESKTOP_FILE="$HOME/.local/share/applications/turbotown.desktop"
PENDING="$DIR/pending"            # a release the game downloaded and checked
CHECK_STAMP="$DIR/last-check"     # the game touches this after each successful check
STALE_DAYS=7
LAUNCHER_PROTOCOL=2               # what the game reads from TURBOTOWN_LAUNCHER
EXIT_RESTART=42                   # the game's exit code for "install the update and restart me"

set -uo pipefail

log() {
	mkdir -p "$DIR"
	echo "[$(date '+%F %T')] $*" >>"$LOG"
	echo "$*" >&2
}

installed_version() { cat "$DIR/current/VERSION" 2>/dev/null || echo "none"; }

newer_than() {  # a, b: is version a newer than b?
	[[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

# /releases/latest redirects to /releases/tag/vX.Y.Z (the newest stable release).
latest_tag() {
	curl -fsSL --connect-timeout 5 --max-time 15 -o /dev/null -w '%{url_effective}' \
		"$REPO_URL/releases/latest" | sed -n 's#.*/releases/tag/\(v[0-9][0-9.]*\)$#\1#p'
}

fetch() {  # url, output file
	curl -fsSL --connect-timeout 10 --max-time 900 --retry 2 -o "$2" "$1"
}

# Installs version $2 from folder $1, which holds the release files
# (TurboTown-vX.Y.Z-linux-x86_64.tar.gz + .sha256, optionally turbotown.sh).
# Checks the SHA-256 and unpacks into a temp folder first; the installed game
# is only replaced once everything checked out.
install_package() {  # folder, version
	local src="$1" ver="$2" pkg="$GAME-v$2-linux-x86_64.tar.gz" x
	x="$(mktemp -d "$DIR/.unpack.XXXXXX")" || return 1
	if [[ -f "$src/$pkg" && -f "$src/$pkg.sha256" ]] \
		&& (cd "$src" && sha256sum --check --status "$pkg.sha256") \
		&& tar -xzf "$src/$pkg" -C "$x" \
		&& [[ -x "$x/$GAME/$GAME.x86_64" && "$(cat "$x/$GAME/VERSION")" == "$ver" ]]; then
		rm -rf "$DIR/old"
		[[ -d "$DIR/current" ]] && mv "$DIR/current" "$DIR/old"
		mv "$x/$GAME" "$DIR/current"
		rm -rf "$DIR/old" "$x"
		[[ -f "$src/turbotown.sh" ]] && self_update "$src/turbotown.sh"
		log "Installed Turbo Town $ver."
		return 0
	fi
	rm -rf "$x"
	return 1
}

do_update() {
	local tag ver pkg tmp
	tag="$(latest_tag)" || { log "Can't reach GitHub; keeping version $(installed_version)."; return 1; }
	[[ -n "$tag" ]] || { log "No stable release has been published yet."; return 1; }
	ver="${tag#v}"
	if [[ "$(installed_version)" == "$ver" && -x "$DIR/current/$GAME.x86_64" ]]; then
		log "Turbo Town $ver is up to date."
		return 0
	fi

	log "Updating Turbo Town $(installed_version) -> $ver ..."
	pkg="$GAME-$tag-linux-x86_64.tar.gz"
	tmp="$(mktemp -d "$DIR/.download.XXXXXX")" || return 1
	if fetch "$REPO_URL/releases/download/$tag/$pkg" "$tmp/$pkg" \
		&& fetch "$REPO_URL/releases/download/$tag/$pkg.sha256" "$tmp/$pkg.sha256"; then
		fetch "$REPO_URL/releases/download/$tag/turbotown.sh" "$tmp/turbotown.sh" || rm -f "$tmp/turbotown.sh"
		if install_package "$tmp" "$ver"; then
			rm -rf "$tmp"
			return 0
		fi
	fi
	rm -rf "$tmp"
	log "Update to $ver failed (download or checksum); keeping version $(installed_version)."
	return 1
}

# Installs what the game downloaded into pending/ (complete once it has a
# VERSION file; the game renames the finished folder into place). Only ever
# moves forward: an older or equal version is thrown away.
install_pending() {
	rm -rf "$DIR/pending.part"   # a download the game didn't finish
	[[ -f "$PENDING/VERSION" ]] || { rm -rf "$PENDING"; return 1; }
	local ver ok=1
	ver="$(cat "$PENDING/VERSION")"
	if [[ -x "$DIR/current/$GAME.x86_64" ]] && ! newer_than "$ver" "$(installed_version)"; then
		log "Ignoring the downloaded update $ver (installed: $(installed_version))."
	elif install_package "$PENDING" "$ver"; then
		ok=0
	else
		log "The downloaded update $ver didn't check out; keeping version $(installed_version)."
	fi
	rm -rf "$PENDING"
	return $ok
}

# Has the game not checked for updates for STALE_DAYS (or never)?
check_is_stale() {
	[[ -z "$(find "$CHECK_STAMP" -maxdepth 0 -mtime "-$STALE_DAYS" 2>/dev/null)" ]]
}

# Replace this script with a newer copy. The new file is renamed into place, so
# the running copy (bash keeps reading the old file) is not disturbed.
self_update() {  # new script
	local new="$DIR/.turbotown.sh.new"
	bash -n "$1" 2>/dev/null || return 0
	cmp -s "$1" "$DIR/turbotown.sh" && return 0
	cp "$1" "$new" && chmod +x "$new" && mv -f "$new" "$DIR/turbotown.sh" && log "Updated the launcher script."
}

do_install() {
	mkdir -p "$DIR"
	local self
	self="$(readlink -f "${BASH_SOURCE[0]}")"
	if [[ "$self" != "$DIR/turbotown.sh" ]]; then
		cp "$self" "$DIR/turbotown.sh" && chmod +x "$DIR/turbotown.sh"
	fi
	do_update || [[ -x "$DIR/current/$GAME.x86_64" ]] || { echo "Install failed, see $LOG"; exit 1; }

	mkdir -p "$(dirname "$DESKTOP_FILE")"
	cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Turbo Town
Comment=Stylized driving sandbox (auto-updates on launch)
Exec="$DIR/turbotown.sh"
Icon=$DIR/current/icon.svg
Terminal=false
Categories=Game;
EOF
	echo "Added 'Turbo Town' to the application menu."

	if [[ -f "$DIR/.added-to-steam" ]]; then
		echo "Steam shortcut was already added earlier."
	elif command -v steamos-add-to-steam >/dev/null; then
		steamos-add-to-steam "$DESKTOP_FILE" && touch "$DIR/.added-to-steam" \
			&& echo "Added 'Turbo Town' to Steam. Find it under Library > Non-Steam."
	else
		echo "Add it to Steam yourself: Steam > Add a Game > Add a Non-Steam Game >"
		echo "tick 'Turbo Town' (or browse to $DIR/turbotown.sh)."
	fi
	echo
	echo "Done. Turbo Town $(installed_version) is installed in $DIR."
	echo "It updates itself to the newest stable release each time it is launched."
}

do_play() {
	install_pending || true
	if [[ ! -x "$DIR/current/$GAME.x86_64" ]] || check_is_stale; then
		do_update || true
	fi
	if [[ ! -x "$DIR/current/$GAME.x86_64" ]]; then
		log "Turbo Town is not installed and could not be downloaded."
		command -v zenity >/dev/null && zenity --error --text="Turbo Town could not be downloaded.\nCheck the internet connection and try again." 2>/dev/null
		exit 1
	fi
	# Stay running while the game plays (Steam sees one session) so it can be
	# restarted into a downloaded update. At most a few restarts per launch.
	local code restarts=0
	while :; do
		(cd "$DIR/current" && TURBOTOWN_LAUNCHER="$LAUNCHER_PROTOCOL" TURBOTOWN_DIR="$DIR" exec "./$GAME.x86_64" "$@")
		code=$?
		[[ $code == "$EXIT_RESTART" && $restarts -lt 3 ]] || return "$code"
		restarts=$((restarts + 1))
		log "Restarting Turbo Town to install the update."
		install_pending || true
	done
}

main() {
	case "${1:-play}" in
		install) do_install ;;
		update) do_update ;;
		status)
			echo "installed: $(installed_version)"
			echo "latest:    $(latest_tag || true)"
			[[ -f "$PENDING/VERSION" ]] && echo "downloaded, installs at next start: $(cat "$PENDING/VERSION")"
			echo "game last checked for updates: $(date -r "$CHECK_STAMP" '+%F %T' 2>/dev/null || echo never)"
			;;
		play) shift || true; do_play "$@" ;;
		*) do_play "$@" ;;   # any other args are passed to the game
	esac
}
main "$@"
exit
