#!/usr/bin/env bash
# Turbo Town installer / updater / launcher for the Steam Deck (any x86_64 Linux).
#
#   bash turbotown.sh install   first-time setup: installs to ~/Games/TurboTown,
#                               adds a menu entry and a Steam shortcut
#   turbotown.sh                (what the Steam shortcut runs) update if a newer
#                               stable release exists, then start the game
#   turbotown.sh update         update only
#   turbotown.sh status         show installed and latest versions
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

set -uo pipefail

log() {
	mkdir -p "$DIR"
	echo "[$(date '+%F %T')] $*" >>"$LOG"
	echo "$*" >&2
}

installed_version() { cat "$DIR/current/VERSION" 2>/dev/null || echo "none"; }

# /releases/latest redirects to /releases/tag/vX.Y.Z (the newest stable release).
latest_tag() {
	curl -fsSL --connect-timeout 5 --max-time 15 -o /dev/null -w '%{url_effective}' \
		"$REPO_URL/releases/latest" | sed -n 's#.*/releases/tag/\(v[0-9][0-9.]*\)$#\1#p'
}

fetch() {  # url, output file
	curl -fsSL --connect-timeout 10 --max-time 900 --retry 2 -o "$2" "$1"
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
	# Download, verify and unpack into a temp folder first; the installed game is
	# only replaced once everything checked out.
	if fetch "$REPO_URL/releases/download/$tag/$pkg" "$tmp/$pkg" \
		&& fetch "$REPO_URL/releases/download/$tag/$pkg.sha256" "$tmp/$pkg.sha256" \
		&& (cd "$tmp" && sha256sum --check --status "$pkg.sha256") \
		&& mkdir "$tmp/x" && tar -xzf "$tmp/$pkg" -C "$tmp/x" \
		&& [[ -x "$tmp/x/$GAME/$GAME.x86_64" && "$(cat "$tmp/x/$GAME/VERSION")" == "$ver" ]]; then
		rm -rf "$DIR/old"
		[[ -d "$DIR/current" ]] && mv "$DIR/current" "$DIR/old"
		mv "$tmp/x/$GAME" "$DIR/current"
		rm -rf "$DIR/old"
		self_update "$tag" "$tmp"
		rm -rf "$tmp"
		log "Installed Turbo Town $ver."
		return 0
	fi
	rm -rf "$tmp"
	log "Update to $ver failed (download or checksum); keeping version $(installed_version)."
	return 1
}

# Replace this script with the copy published alongside the release. The new
# file is renamed into place, so the running copy is not disturbed.
self_update() {  # tag, temp dir
	local new="$2/turbotown.sh"
	fetch "$REPO_URL/releases/download/$1/turbotown.sh" "$new" || return 0
	bash -n "$new" 2>/dev/null || return 0
	cmp -s "$new" "$DIR/turbotown.sh" && return 0
	chmod +x "$new" && mv -f "$new" "$DIR/turbotown.sh" && log "Updated the launcher script."
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
	do_update || true
	if [[ ! -x "$DIR/current/$GAME.x86_64" ]]; then
		log "Turbo Town is not installed and could not be downloaded."
		command -v zenity >/dev/null && zenity --error --text="Turbo Town could not be downloaded.\nCheck the internet connection and try again." 2>/dev/null
		exit 1
	fi
	cd "$DIR/current" && exec "./$GAME.x86_64" "$@"
}

main() {
	case "${1:-play}" in
		install) do_install ;;
		update) do_update ;;
		status) echo "installed: $(installed_version)"; echo "latest:    $(latest_tag || true)" ;;
		play) shift || true; do_play "$@" ;;
		*) do_play "$@" ;;   # any other args are passed to the game
	esac
}
main "$@"
exit
