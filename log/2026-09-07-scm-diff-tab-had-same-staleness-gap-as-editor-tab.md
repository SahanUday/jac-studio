---
id: 2026-09-07-scm-diff-tab-had-same-staleness-gap-as-editor-tab
date: 2026-09-07
category: resolved
severity: minor
status: resolved
phase: 5
subsystem: workbench-shell
jac_version: "0.37.3 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [scm, gitdiff, monaco, editor-tabs, real-user-qa]
---

## What happened

Real-user QA, same day as (and directly following) the auto-reload feature that closed
`2026-09-04-...-editor-tab-...` (the plain-editor-tab case): asked the AI Chat to rewrite a file
that was already open in an SCM diff ("gitdiff") tab, twice in a row. The diff view kept showing
the *first* edit's diff, not the second -- the auto-reload feature explicitly did not cover this
tab kind at the time ("diff or gitdiff tab kinds... don't have a single live buffer this reload
mechanism targets," from that fix's own docstring).

## Root cause

`scm_diff_editor.jac`'s `ScmDiffEditorApp` fetches its diff (`git_service.get_diff_content`)
exactly once, in `can with entry` at mount, and never refetches -- the identical staleness class
just fixed for `monaco_editor.jac`, in a sibling component deliberately left out of that fix's
scope.

## Fix

Extended the same mechanism: `workbench.jac`'s `handle_files_changed_externally` now also matches
a `"gitdiff"`-kind tab (keyed by its own `t["filePath"]`, the same real on-disk path the watcher
reports) into the shared `files_pending_reload` nonce a plain tab already used, threaded through
`editor_tabs.jac` to a new `reloadNonce` prop on `ScmDiffEditorApp`, which refetches
`get_diff_content` and reassigns `original_content`/`modified_content` state on change.

**Deliberately dropped the `dirty_paths` filter at the `workbench.jac` layer entirely** for this
extension -- a `"gitdiff"` tab is read-only end to end (no dirty state of its own) and should
always refresh; a plain tab sharing the same path stays safe regardless, since
`monaco_editor.jac`'s own `reload_from_disk` already re-checks `dirty` itself immediately before
touching anything (the real safety guarantee always lived there, not in the parent's filter).

`scm_diff_editor.jac`'s own client-side fix is simpler than `monaco_editor.jac`'s: its
`<DiffEditor>` is a *controlled* component (`original`/`modified` are real props sourced from
state, unlike `monaco_editor.jac`'s deliberate uncontrolled `defaultValue`), so reassigning state
on a fresh fetch just re-renders both sides correctly -- no imperative `setValue` call, no cursor
to preserve, no dirty-tracking `onChange` handler to suppress, since this view has none of those in
the first place.

## A verification-methodology note worth keeping

An initial live check for this fix, using `document.body.innerText.includes(marker)`, falsely read
as "not reloaded." Root cause of the false negative: Monaco virtualizes line rendering (only
visible lines exist in the DOM at any time), and the test's marker text was appended past the end
of a longer file, off the default scroll position -- unrelated to whether the actual content update
worked. Corrected by checking Monaco's own live model content directly
(`window.monaco.editor.getModels()`), which reflects the true model state regardless of scroll
position or what's currently rendered to the DOM -- confirmed correct that way: the diff's
"modified" side model picked up the fresh content, "original" (the git `HEAD` blob) correctly did
not change at all.

## Plan

No further action needed -- this closes the gap the sibling entry's own fix deliberately left open,
using the identical, already-proven-correct mechanism. Worth remembering for verifying *any* future
Monaco-based live-content check in this project: prefer `window.monaco.editor.getModels()` over DOM
text assertions, since Monaco's virtualized rendering makes DOM text an unreliable signal for
content that isn't currently scrolled into view.
