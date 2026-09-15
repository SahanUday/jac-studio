# Challenge tracker — design

Every blocker, compiler quirk, missing feature, and workaround hit while building jac-studio is
logged as structured data and rendered into a public dashboard for the team and, eventually, the
jac-lang maintainers. A first-class deliverable — the goal is improving jac-lang itself.

**Where it lives**: a dedicated orphan branch, `tracking`, separate from `main` — keeps dashboard
churn out of the product repo's history and matches GitHub Pages' "deploy from a branch" flow.
`main` holds the product; `tracking` holds the log and the site.

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
phase: 0 | 1 | 2 | ...        # roadmap milestone this came up in
subsystem: editor-core | workbench-shell | extensions | persistence | desktop | tooling | translator
jac_version: "x.y.z"
related_vscode_ref: "src/vs/editor/common/model/pieceTreeTextBuffer/..."   # optional
upstream_issue: "jaseci/jaseci#1234"                                       # optional
tags: [piece-tree, wasm, jac2js]
---

Free-text body: what we tried, what happened, the minimal repro if there is one, the workaround
(if any), and what unblocking this would look like.
```

Markdown + YAML, not a database: writable mid-task, diffable like any commit, portable if the log
ever needs to go to the jaseci team directly.

## Site and deploy

A plain Python build script (not Jac, deliberately — the tracker reports on Jac's own rough edges)
reads `tracking/log/`, emits `data.json`; a dependency-free static `index.html` renders a stats
header, a timeline, filters, and each entry's full body with source/issue links.
`.github/workflows/deploy-tracker.yml` builds and deploys on every push to `tracking`.

## Workflow in practice

Whenever work (main repo or the [translator](translator-strategy.md)) hits a blocker worth
recording: write one markdown file under `tracking/log/` on the `tracking` branch, in the same
sitting — not batched from memory, since repro details degrade fast. Entries are never deleted,
only re-statused (`open` → `workaround`/`resolved`/`upstream-tracked`).
