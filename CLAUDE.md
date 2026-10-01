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
- **The art migration (ART_BIBLE.md §31) happens on the `dev` branch.** Commit
  and push art work there (`origin dev`). Merge `dev` into `main` only when the
  owner says so. Small fixes for the released game still go on `main`; merge
  `main` into `dev` afterwards so `dev` keeps them.

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

## Choosing a model (Sonnet 5.5 vs Opus 5.5)

The owner wants to save session limits: **Sonnet 5.5 is the default model.**
Opus 5.5 costs about twice as much per token, so use it only where it pays off.

- **Sonnet is fine** for jobs that are clear and easy to check: small UI or
  text tweaks, adding content (props, colours, vehicles from the existing
  kit), obvious bugs, running tests, docs, releases.
- **Opus is worth it** for open-ended or tricky work: new features or systems,
  bugs whose cause isn't known (or a fix that didn't work), traffic AI, car
  physics, performance, and planning big batches of work.
- **Before starting a task, say which model it suits** in one line. If you're
  Sonnet and the task is in the Opus list, suggest switching (the owner picks
  the model in the app's model menu) before diving in. If you're Opus and the
  hard part is done and the rest is routine, say so, so the owner can switch
  back to Sonnet.
