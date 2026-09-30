# Releasing Turbo Town

Stable builds for the Steam Deck are published as GitHub Releases on the
public repo [Fahmula/turbo-town](https://github.com/Fahmula/turbo-town).
Each release has one complete Linux x86_64 build: `TurboTown-vX.Y.Z-linux-x86_64.tar.gz`.

## Rules

- **Development happens on `main`.** Commit and push as often as you like. Nothing
  reaches the Steam Deck until someone runs the release script.
- **A release is always an explicit decision by the owner.** Never run
  `tools/release.sh` (without `--dry-run`) unless asked to.
- Releases are built from a clean `git archive` of a commit, not the working
  tree. Uncommitted or experimental files can't end up in a release.
- Tags `vX.Y.Z` are permanent. Never move, delete or force-push them. If a release
  is bad, ship a new patch version.

## Versioning

`MAJOR.MINOR.PATCH`, tagged `vX.Y.Z`. The git tag is the source of truth. The
script stamps the version into the exported build (`application/config/version`)
and into `VERSION` in the package. `project.godot` in the repo is not changed.

- **MINOR** (0.2.0 → 0.3.0): new features or content (a milestone in PROGRESS.md).
- **PATCH** (0.3.0 → 0.3.1): bug fixes only.
- **MAJOR**: stays 0 until the game is "finished".

## Making a release

```bash
# 1. Commit the work you want to ship, then check it builds and runs:
tools/release.sh 0.3.0 --dry-run

# 2. Write player-facing notes: in CHANGELOG.md rename [Unreleased] to
#    "## [0.3.0] - YYYY-MM-DD". Commit and push:
git commit -am "Release notes for 0.3.0" && git push

# 3. Release. It asks for confirmation before tagging/publishing:
tools/release.sh 0.3.0
```

The script:

1. Checks Godot 4.7.2 and its export templates, and that the tag is new and
   newer than the last one.
2. Checks the commit is pushed to `origin/main` and CHANGELOG.md has a `## [X.Y.Z]` section.
3. Extracts the commit to `build/release/vX.Y.Z/src`, imports the assets, and
   exports the preset "Linux x86_64 (Steam Deck)".
4. Smoke-tests the exported binary headless for 600 frames. It fails on any
   script or engine error.
5. Packages to `dist/TurboTown-vX.Y.Z-linux-x86_64.tar.gz` (+ `.sha256`).
6. Creates an annotated tag `vX.Y.Z`, pushes it, and creates the GitHub Release
   with the CHANGELOG section, Steam Deck install steps, commit list and checksum.

Options: `tools/release.sh X.Y.Z <commit>` releases an older pushed commit,
`--yes` skips the confirmation prompt, and `GODOT=/path/to/godot` picks another
Godot binary.

`build/` and `dist/` are gitignored. Logs for each run are in
`build/release/vX.Y.Z/{import,export,smoke}.log`.

## One-time setup on a new PC

- `godot` 4.7.2 on PATH, plus `gh` logged in (`gh auth login`).
- Linux export templates in `~/.local/share/godot/export_templates/4.7.2.stable/`
  (`linux_release.x86_64`, `linux_debug.x86_64`, `version.txt`), from
  `Godot_v4.7.2-stable_export_templates.tpz` on the Godot releases page, or
  Editor > Manage Export Templates.
- When upgrading Godot, update `GODOT_VERSION` in `tools/release.sh` and install
  the matching templates.

## Steam Deck: install and auto-update

`tools/steamdeck/turbotown.sh` is uploaded with every release. It installs the
game, adds it to Steam, and updates it on every launch.

**First-time install** (Desktop Mode, open Konsole):

```bash
curl -fLo /tmp/turbotown.sh https://github.com/Fahmula/turbo-town/releases/latest/download/turbotown.sh && bash /tmp/turbotown.sh install
```

This installs to `~/Games/TurboTown/` (`turbotown.sh` + `current/`), adds a
menu entry, and adds a "Turbo Town" shortcut to Steam (via `steamos-add-to-steam`).
If Steam doesn't show it, add it yourself: Add a Non-Steam Game > Turbo Town.

**After that, nothing:** every time the game is started from Steam, the launcher:

- checks `github.com/Fahmula/turbo-town/releases/latest`, which only ever
  points to the newest stable release (drafts and pre-releases are ignored);
- if it's newer, downloads it, verifies the SHA-256, and swaps it in. A failed
  download never touches the installed game;
- updates itself to the launcher script from that release;
- starts the game. With no internet it just starts the installed version.

Other commands: `~/Games/TurboTown/turbotown.sh status | update`. Log:
`~/Games/TurboTown/update.log`. Save data is in `~/.local/share/godot/app_userdata/`
and is never touched by updates. To uninstall, delete `~/Games/TurboTown`,
`~/.local/share/applications/turbotown.desktop` and the Steam shortcut.

To test the launcher locally, point it at a fake server with
`TURBOTOWN_REPO_URL=...` and `TURBOTOWN_DIR=...`.
