# jac-studio — `tracking` branch

This branch holds the **challenge tracker**: the log of blockers, compiler quirks, missing
features, and workarounds hit while rebuilding VS Code in Jac. It is deliberately separate from
`main` (the product source) — design rationale in `docs/challenge-tracking.md` on `main`.

## Layout

- `log/*.md` — one markdown file per entry, YAML frontmatter + freeform body. See `main`'s
  `docs/challenge-tracking.md` for the field reference.
- `site/index.html` — the dashboard (dependency-free static HTML/CSS/JS).
- `site/build.py` — reads `log/*.md`, emits `dist/{index.html,data.json}`. Stdlib-only Python by
  design — this tool reports on Jac's rough edges, so it doesn't depend on Jac itself.
- `.github/workflows/deploy-tracker.yml` — builds and deploys `dist/` to GitHub Pages on every
  push to this branch.
- `dist/` — build output, gitignored, not committed.

## Adding an entry

Add a new file under `log/`, named `YYYY-MM-DD-short-slug.md`, in the same sitting the blocker was
hit — not batched up later from memory. Push. The dashboard updates automatically.

## Local preview

```
python3 site/build.py
python3 -m http.server -d dist 8000
# open http://localhost:8000
```
