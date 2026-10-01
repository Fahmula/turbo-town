# Turbo Town: notes for Claude

Godot 4.7.2 driving sandbox. Game docs: README.md. Plan/backlog: PROGRESS.md.
Art direction: ART_BIBLE.md.

## Art direction

- **Read ART_BIBLE.md before any visual, UI, environment, vehicle, material,
  lighting, shader or asset change.** At minimum read §0 (quick rules) and the
  sections for what you're touching. The direction is stylized realism, and
  Steam Deck 60 fps budgets are part of it (§27).
- Most of today's look is legacy toy style (ART_BIBLE.md §3). Don't copy it into
  new work, and don't restyle existing assets unless the task asks.
- If you change a rule or a value (palette, budgets, contracts), update
  ART_BIBLE.md in the same commit.
- The style reference images are in `reference images/stylized-realism/`
  (local only). They're other games' art, so never commit them.

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
