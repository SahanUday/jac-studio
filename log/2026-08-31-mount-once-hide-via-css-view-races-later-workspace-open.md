---
id: 2026-08-31-mount-once-hide-via-css-view-races-later-workspace-open
date: 2026-08-31
category: ergonomics
severity: major
status: resolved
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [react, useEffect, mount-once-hide-via-css, workspace, scm, output, stale-data]
---

## What happened

Verifying Phase 4's new SCM sidebar view (`src/workbench/scm/scm.jac`) live against a real git
fixture: opened a real repo with staged/unstaged/untracked changes through the Explorer, switched
to the Source Control tab, and it permanently showed "No repository" -- even though a direct
`fetch('/function/get_scm_status', ...)` from the same browser session, at the same moment, returned
fully correct data (`is_repo: true`, real branch, all three status buckets populated). The backend
was never wrong; the view just never asked again.

## Root cause

`ScmApp` follows this project's established "mount once, hide via CSS" convention for stateful
sidebar views (the same one `FileTreeApp`/`SearchApp` already use, per `search.jac`'s own
docstring) -- it's mounted by `workbench.jac` at page load, alongside every other sidebar view,
regardless of which one is actually visible. Its first version fetched status the same way
`search.jac`/`monaco_diff_editor.jac` fetch their own data: once, in `can with entry`. But `can with
entry` fires at *that* mount -- page load, before the user has opened any folder at all -- and never
again. Every later action that would make its data stale or newly-correct (opening a workspace for
the first time, switching folders) happens with `ScmApp` already mounted and silently not listening
for any of it.

This is a different failure mode from the "no live file-watcher" limitation the view's docstring
already, deliberately scopes out (an external `git` command run outside the app not being picked up
without a manual refresh) -- this bug meant the view never showed correct data even from the app's
*own* first-ever folder-open action, not just missing a later external change.

`output.jac` had already solved the identical shape of problem for a different reason (it only
wants to poll while its tab is actually the visible one, not always) via an `active: bool` prop
driving `useEffect(lambda { ... }, [active])` -- refetch once whenever the view transitions to
visible, not just at first mount. The fix here is the exact same mechanism, just for correctness
(get fresh data whenever shown) rather than output's original motivation (don't poll a hidden
panel).

## Plan

Fixed: `scm.jac` now takes an `active: bool` prop (`workbench.jac` passes `active_view_id ==
"scm"`) and refreshes via `useEffect([active])` instead of a mount-time `can with entry`. Verified
live against the same repro: opening the fixture folder, then switching to Source Control for the
first time, now shows the real staged/unstaged/untracked status immediately, no manual refresh
needed.

Worth checking as a class, not just this one instance: **any future mount-once-hide-via-CSS sidebar
view whose data depends on workspace state that can change *after* that view's own first mount**
(the task runner's Problems-adjacent views and the LSP client's outline/symbols view, both later in
this same Phase 4, are the next likely candidates) should default to the `active`-prop-driven
`useEffect` shape from the start, not a bare `can with entry` -- `search.jac`'s own `can with entry`
happens to be safe only because its data (an empty query/result set) has nothing *to* go stale at
mount time, not because the mount-once convention itself is safe by default.
