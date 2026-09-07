---
id: 2026-09-07-monaco-getposition-null-not-checked
date: 2026-09-07
category: resolved
severity: minor
status: resolved
phase: 5
subsystem: editor-core
jac_version: "0.37.3 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: "src/vs/workbench/contrib/codeEditor/browser/outline/documentSymbolsOutline.ts"
upstream_issue: ""
tags: [monaco, editor-core, real-user-qa, vscode-comparison]
---

## What happened

Real-user QA: right after a freshly-opened tab mounted (an AI-Chat-driven `open_document`/tab
reopen), the client crashed with `Cannot read properties of null (reading 'lineNumber')`, thrown
from `monaco_editor.jac`'s `handle_mount`.

## Root cause

`handle_mount` calls `position = editor.getPosition(); onCursorChange(path, position.lineNumber,
...)` unconditionally. Monaco's own public type signature is `getPosition(): Position | null` --
a real, documented possible return, not an implementation detail -- and a freshly-mounted editor,
before layout/model attachment fully settles, is exactly the situation where it returns `null`.
`update_breadcrumb` had the identical gap one line later (guarded against `editor_ref.current`
being unset, but not against a set editor's own `getPosition()` returning `null`).

## Fix

Asked to check how real VS Code handles this specific case before fixing it. Checked
`documentSymbolsOutline.ts` (its own breadcrumb/outline cursor-position mapping, the closest real
equivalent to this project's `update_breadcrumb`) in a real `microsoft/vscode` checkout: every
single call site there null-checks `getPosition()`'s result before using it (`if (!position || ...)
{ return; }` / `{ return undefined; }`), never assumes a value. `handle_mount` and
`update_breadcrumb` now do the same -- a `null` position skips the cursor-position report /
clears the breadcrumb for that tick instead of crashing, matching VS Code's own handling exactly
rather than a guessed workaround.

## Plan

No further action needed -- correct, permanent fix, matching a real upstream reference
implementation's own established pattern. Worth remembering generally for this codebase's own
Monaco integration: any Monaco API documented as returning `T | null` should be treated as
genuinely nullable at every call site, not just the ones that have already been caught live.
