# 0074 — Null-check `editor.getPosition()` everywhere, matching upstream

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

Every call site that reads `editor.getPosition()` checks for `null` before use.

## Why

A live-reported crash — `Cannot read properties of null (reading 'lineNumber')` — fired right after
a freshly-opened tab mounted. Monaco's own type signature is `getPosition(): Position | null`, a
documented possible return, and a freshly-mounted editor before layout/model attachment settles is
exactly when it fires. Real VS Code's own closest equivalent (`documentSymbolsOutline.ts`)
null-checks this at every call site; this project didn't, in `handle_mount` and
`update_breadcrumb`.

## Consequences

A `null` position skips that tick's cursor-position report or clears the breadcrumb, rather than
crashing — matching upstream's own handling exactly. Any new code reading `getPosition()` must
check for `null`, not assume the editor is always fully settled.
