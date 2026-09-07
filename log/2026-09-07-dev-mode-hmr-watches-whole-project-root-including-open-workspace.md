---
id: 2026-09-07-dev-mode-hmr-watches-whole-project-root-including-open-workspace
date: 2026-09-07
category: missing-feature
severity: major
status: open
phase: 5
subsystem: tooling
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-run-dev, hmr, watchdog, real-user-qa, upstream-jaclang, ai-chat]
---

## What happened

Real-user QA: asked the AI Chat to edit `testing-workspace/hello.jac` (a file inside the fixture
workspace jac-studio itself has open). The edit genuinely landed on disk (confirmed by opening the
same file in a separate editor), but jac-studio's own Explorer/editor tab kept showing the old
content, and the very next `list_children_by_path` call failed with the identical
`'Workspace' object has no attribute 'path'` crash `2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target`
documents. That entry's own root cause was left explicitly open at the time -- this is a strong,
source-confirmed candidate for what that trigger actually is (see that entry's own 2026-09-07
correction for the full crash-side writeup; this entry documents the general watcher-scope finding
on its own, since it's bigger than just this one crash).

## Root cause

The real terminal log showed `[HMR] Reloaded: .../testing-workspace/hello.jac` immediately followed
by this server's own full startup banner -- a genuine process restart, not a cosmetic log line.
Traced into jaclang's own source (`/home/sahan/dev/jaseci/jac`, a separate project, run in dev mode
here): `jac run --dev` constructs its hot-reload watcher as
`JacFileWatcher(watch_paths=[base])`, where `base` is simply the directory containing the
entry-point file (`main.jac`'s own directory -- the whole project root), watched *recursively* for
`*.jac`/`*.tsx`/`*.js`/`*.css`/`*.png`/`*.jpg`/`*.jpeg` files. The only exclusions
(`jaclang/server/impl/watcher.impl.jac`'s `_on_change`) are the `.jac/` build-cache directory,
`node_modules`, and `__pycache__` -- nothing scopes the watch to the app's own actual source tree,
and nothing excludes a project's own data/fixture directories.

`testing-workspace/` -- jac-studio's own gitignored fixture, deliberately kept at the repo root per
`jac-studio-implementation`'s documented convention, specifically so real `jac browse` sessions and
the maintainer's own manual testing have a realistic project to open -- sits directly under that
watched root. Any write to a `.jac` file inside it (an AI Chat tool call being the concrete,
reported case, but equally true of any external tool, or even hand-editing the fixture in another
editor) is indistinguishable, to this watcher, from a real change to jac-studio's own application
source, and triggers the identical hot-reload/restart path.

**Scope, confirmed from the same source reading**: this is a *dev/testing-environment* issue
specific to this project's own setup (a fixture workspace nested inside the served app's own repo),
not a production concern. A real end user running an installed jac-studio pointed at their own,
separate project elsewhere on disk would never trigger this -- their project directory has no
overlap with jac-studio's own served root at all.

## Why this matters beyond the one crash

A hot-reload restart mid-session silently resets every piece of this app's own in-process state
that isn't durably persisted: `workspace_service.jac`'s `_path_index`/`_cached_workspace_jid`
caches, and (as of this same day's earlier work) `workspace_watcher.jac`'s own `_watched_root`/
`_observer`/`_dirty_dirs`/`_modified_files`. Nothing currently tells the *client* this happened, so
after any AI-driven `.jac` edit inside the open workspace: the server-side file watcher silently
stops watching (explaining "the AI says it edited the file, but jac-studio still shows the old
one" independent of, and in addition to, the crash), and the graph-cache state most likely
underlies the original, still-not-fully-closed crash this entry's sibling documents.

## Plan

No fix attempted in this repo -- the actual defect (no exclude-patterns option, no scoping to the
entry-point's own package rather than the whole project directory) lives in
`jaclang/server/watcher.jac`/`jaclang/cli/commands/impl/execution.impl.jac`, a separate upstream
project, not jac-studio's own `.jac` source. Two real paths forward, neither taken yet:

1. **Upstream**: add an exclude-patterns/exclude-paths option to `JacFileWatcher` (or a `jac.toml`
   setting jac-studio could then set to exclude `testing-workspace/`), or default the watched root
   to the entry-point's own containing package rather than the whole project directory. Requires
   work in the jaclang repo, not this one.
2. **Immediate, low-cost mitigation for continued QA in this repo**: run the dev server *without*
   `--dev` while doing AI Chat / workspace-editing testing -- `JacFileWatcher` setup is entirely
   gated behind `if dev { ... }`, so omitting the flag removes this whole trigger class outright, at
   the cost of losing Vite's client-bundle hot-reload for jac-studio's own source changes during
   that session (server-side `.jac` changes already needed a manual restart regardless, per an
   earlier same-day finding).

Not closing this as resolved -- the crash-side symptom has a defensive guard already
(`2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target`), but the underlying
"AI edits reset the server mid-session" behavior itself is still real and still happens.
