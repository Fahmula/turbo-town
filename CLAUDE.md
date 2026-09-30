# Turbo Town: notes for Claude

Godot 4.7.2 driving sandbox. Game docs: README.md. Plan/backlog: PROGRESS.md.

## Git and releases

- The repo is **public** at github.com/Fahmula/turbo-town (never commit secrets). Develop on `main`.
  Commit working, tested states with clear messages and push them. Don't commit
  half-broken work to `main` (use a branch if needed).
- The owner's son plays **stable releases** on a Steam Deck. Releases are made
  only when the owner explicitly asks: `tools/release.sh X.Y.Z`. Full workflow
  and versioning rules are in RELEASING.md.
  `tools/release.sh X.Y.Z --dry-run` (export + smoke test, no publishing) is
  always safe to run.
- The Steam Deck auto-updates on launch (tools/steamdeck/turbotown.sh) to
  whatever release GitHub marks as latest. Publishing a release = shipping it
  to the Deck, so never publish drafts or tests as normal releases.
- Never move, delete or force-push release tags (`v*`), and never rewrite
  pushed history.
- For user-facing changes, add a line under `## [Unreleased]` in CHANGELOG.md.
  Those lines become the release notes.
- `.godot/`, `build/`, `dist/` and `reference images/` are gitignored. Don't
  commit caches, builds or secrets.
