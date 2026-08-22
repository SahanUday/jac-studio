# Challenge tracker — design

Every blocker, compiler quirk, missing feature, and workaround hit while building jac-studio gets
logged as structured data and rendered into a public-ish dashboard the team (and, eventually, the
jac-lang maintainers) can browse. This is a first-class deliverable of the project, not a side
log — the stated goal is improving jac-lang itself, and an unstructured pile of Slack messages or
commit-message asides can't do that.

## Where it lives

A dedicated orphan branch, `tracking`, in the `jac-studio` repo (`SahanUday/jac-studio`), separate
from `main`. Rationale: the tracking data and its site are not part of the product being built —
mixing them into `main`'s history would pollute the product repo's diff/blame with dashboard
churn, and a dedicated branch is exactly the shape GitHub Pages' "deploy from a branch via Actions"
flow expects. `main` stays the jac-studio product source; `tracking` holds the log + the site that
renders it.

## Data format

One markdown file per entry, under `tracking/log/`, filename `YYYY-MM-DD-slug.md`. Frontmatter +
freeform body:

```yaml
---
id: 2026-08-22-example-entry
date: 2026-08-22
category: compiler-bug | missing-feature | doc-gap | ergonomics | translator-blocker | workaround-found | resolved
severity: blocker | major | minor | note
status: open | workaround | resolved | upstream-tracked
phase: 0 | 1 | 2 | ...        # roadmap phase this came up in
subsystem: editor-core | workbench-shell | extensions | persistence | desktop | tooling | translator
jac_version: "x.y.z"
related_vscode_ref: "src/vs/editor/common/model/pieceTreeTextBuffer/..."   # optional
upstream_issue: "jaseci/jaseci#1234"                                       # optional
tags: [piece-tree, wasm, jac2js]
---

Free-text body: what we tried, what happened, the minimal repro if there is one, the workaround
(if any), and what unblocking this would look like.
```

Markdown + YAML frontmatter, not a database, so entries are: easy to write mid-task without
context-switching to a UI, diffable/reviewable like any other commit, and greppable/portable if we
ever want to hand the whole log to the jaseci team directly (a plain folder of files, not locked
into a dashboard's schema).

## Site

A small static-site generator (a plain Python build script — deliberately *not* built in Jac
itself; the tracker's entire purpose is reporting on Jac's own rough edges, so it shouldn't depend
on the thing it's tracking) reads every file under `tracking/log/`, parses frontmatter, and emits
`data.json`. A dependency-free static `index.html` (vanilla HTML/CSS/JS, no build step for the
page itself) fetches `data.json` and renders:

- A stats header (open blockers, resolved count, entries by category/severity)
- A timeline, newest first
- Filters by category / severity / status / subsystem / phase / tag, and free-text search
- Each entry expands to its full body, with the VS Code source ref and upstream issue link
  rendered as actual links where present

Kept intentionally simple and dependency-free (no framework, no CDN) so it stays maintainable by
whoever's around, and loads instantly on GitHub Pages with no build tooling beyond the one Python
script.

## Deploy pipeline

`.github/workflows/deploy-tracker.yml`, triggered on push to `tracking`: runs the build script,
uploads the generated static site via `actions/upload-pages-artifact`, deploys via
`actions/deploy-pages` (GitHub's Actions-based Pages flow, not a legacy `gh-pages`-branch commit
dance). Requires the repo's Pages source to be set to "GitHub Actions" — a one-time repo-settings
change, done deliberately with confirmation before enabling, since it's a shared/visible change to
the repo (not something to flip silently).

## Workflow in practice

Whenever work in the main jac-studio repo (or the translator, per
[`translator-strategy.md`](translator-strategy.md)) hits a blocker worth recording: write one
markdown file under `tracking/log/` on the `tracking` branch, in the same sitting the blocker was
hit — not batched up later from memory, since the repro details and exact error text degrade fast.
Push updates the live dashboard automatically. Entries are never deleted, only re-statused
(`open` → `workaround`/`resolved`/`upstream-tracked`) — the dashboard is a historical record of
what building a huge project in a young language actually required, which is the whole point.
