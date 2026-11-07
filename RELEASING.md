# Releasing Turbo Town

Stable builds for the Steam Deck are published as GitHub Releases on the
public repo [Fahmula/turbo-town](https://github.com/Fahmula/turbo-town).
Each release has one complete Linux x86_64 build: `TurboTown-vX.Y.Z-linux-x86_64.tar.gz`.

Releases are made by [release-please](https://github.com/googleapis/release-please)
and GitHub Actions ([.github/workflows/release.yml](.github/workflows/release.yml)):
merging the **release PR** is the release.

## Rules

- **Work happens on feature branches** with a PR into `main`. Nothing reaches
  the Steam Deck until the release PR is merged.
- **A release is always an explicit decision by the owner**: only the owner
  merges the release PR. Claude never merges it (or any PR).
- Releases are built by GitHub Actions from a clean `git archive` of the tagged
  commit, not a working tree, and smoke-tested before they're published.
- Tags `vX.Y.Z` are permanent. Never move, delete or force-push them. If a release
  is bad, ship a new patch version.
- **Squash-merge PRs** into `main` (the repo only allows squash merging), so each
  PR is one commit and its title and description drive the release notes.

## How it works

1. Every push to `main` runs release-please. It reads the merged PRs since the
   last release and keeps one PR open called `chore(main): release X.Y.Z`. That
   PR bumps `version.txt` and `.release-please-manifest.json` and adds the new
   `## [X.Y.Z]` section to CHANGELOG.md.
2. Merging that PR makes release-please tag `vX.Y.Z` and create a **draft**
   GitHub Release. Drafts are invisible to the Steam Deck.
3. The `publish` job then runs `tools/release.sh X.Y.Z --publish`:
   - checks the tag, that the release is still a draft, and that nothing newer
     is already published (that would downgrade the Deck);
   - installs Godot and its export templates (cached), imports and exports the
     preset "Linux x86_64 (Steam Deck)", and runs the exported game headless
     for 600 frames. Any script or engine error stops it;
   - packages `TurboTown-vX.Y.Z-linux-x86_64.tar.gz` (+ `.sha256`), uploads it
     with `turbotown.sh` to the draft, adds the Steam Deck install steps, commit
     list and checksum to the notes, then **publishes** it as the latest release.
4. The Deck picks it up the next time the game is launched.

Pull requests into `main` get a test build (export + smoke test, nothing
published), so a broken export shows up on the PR, before it's merged.

## Versioning

`MAJOR.MINOR.PATCH`, tagged `vX.Y.Z`. release-please picks the number from the
merged PRs since the last release:

- `feat:` → **MINOR** (0.11.0 → 0.12.0): new features or content.
- `fix:` or `perf:` → **PATCH** (0.12.0 → 0.12.1).
- **MAJOR** stays 0 until the game is "finished". Even a breaking change
  (`feat!:`) only bumps MINOR while the version is 0.x.
- To pick a version yourself, add a blank line and then `Release-As: 1.0.0`
  under one of the lines in a PR's override block (see below).

The tag is the source of truth. The build stamps the version into the exported
game (`application/config/version`, shown on the title screen) and into
`VERSION` in the package. `project.godot` in the repo is not changed.

## Release notes: every PR

The changelog and the GitHub Release notes are written from the merged PRs, so
each PR says what changed **for the player**:

- **PR title** in [Conventional Commits](https://www.conventionalcommits.org/)
  form: `feat(garage): body kits and spoilers`, `fix: horn stuck on`,
  `perf: faster world build`. Changes a player doesn't see use `docs:`,
  `chore:`, `refactor:`, `test:`, `build:` or `ci:`. Those don't appear in the
  notes and don't trigger a release on their own.
- **PR description**: the player-facing lines go in an override block, one
  line each, with a **blank line between them**:

  ```
  BEGIN_COMMIT_OVERRIDE
  feat(garage): New BODY tab: spoilers on every vehicle, bonnet scoops and roof racks.

  feat(garage): Underglow neon in eight colours, brightest at night.

  fix: The garage camera no longer clips into the car.
  END_COMMIT_OVERRIDE
  ```

  Each line becomes one bullet under "New stuff" (`feat`), "Fixes" (`fix`) or
  "Runs smoother" (`perf`), with the `(scope)` in bold. Keep each line on one
  line; anything on the next line without a blank line is dropped. Without the
  block, the PR title is the only line.
- **Fixing notes**: edit the merged PR's description, then run the workflow by
  hand on `main` (Actions > Release > Run workflow). The release PR is
  rewritten. You can also edit CHANGELOG.md in the release PR's branch, but the
  next push to `main` overwrites that.

Don't edit CHANGELOG.md on `main` by hand (except to fix a typo in an old
entry), and don't add an "Unreleased" heading: release-please inserts each new
version above the first version heading.

## Making a release

1. Merge the feature PRs you want to ship. Each one got a test build on its PR.
2. Open the release PR (`chore(main): release X.Y.Z`) and check the version and
   the notes. Want to try the exact build first? `tools/release.sh X.Y.Z --dry-run`
   on a checkout of `main` builds and smoke-tests it locally.
3. Merge the release PR. Watch Actions > Release: the `publish` job takes a few
   minutes. When it's green, the release is live.

**If the publish job fails**, the release stays a draft and the Deck keeps the
old version. The job's `release-logs` artifact has the import, export and smoke
test logs.

- A hiccup (network, GitHub): Actions > Release > Run workflow on `main` with
  the tag (`v0.12.0`). This builds and publishes the draft again.
- The game itself is broken: fix it in a PR and merge it. release-please then
  proposes the next patch version. Leave the failed draft or delete it on
  GitHub; its tag stays (tags are permanent).
- GitHub Actions is down: on a PC with the one-time setup below, after the
  release PR is merged, run `tools/release.sh X.Y.Z --publish`. It does the same
  as CI and asks before publishing.

`tools/release.sh` options: `--dry-run` (build + package + smoke test only; the
package name says DRYRUN so it's never mistaken for a release), an optional
commit (`tools/release.sh 0.12.0 <commit> --dry-run`), `--yes` (don't ask), and
`GODOT=/path/to/godot`. `build/` and `dist/` are gitignored. Logs for each run
are in `build/release/vX.Y.Z/{import,export,smoke}.log`.

## One-time setup

**GitHub repo settings** (once per repo):

- Settings > Actions > General > Workflow permissions: tick **Allow GitHub
  Actions to create and approve pull requests** (release-please opens the
  release PR with the workflow's token).
- Settings > General > Pull Requests: allow **squash merging** only, with
  default commit message **Pull request title**.

**A PC for dry runs (or publishing when Actions is down):**

- `godot` 4.7.2 on PATH, plus `gh` logged in (`gh auth login`).
- Linux export templates in `~/.local/share/godot/export_templates/4.7.2.stable/`
  (`linux_release.x86_64`, `linux_debug.x86_64`, `version.txt`), from
  `Godot_v4.7.2-stable_export_templates.tpz` on the Godot releases page, or
  Editor > Manage Export Templates.

**Upgrading Godot:** change `GODOT_VERSION` in `tools/release.sh`. CI reads it
from there, downloads that version and checks it against Godot's SHA-512 sums.
Install the matching templates on your PC too.

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
