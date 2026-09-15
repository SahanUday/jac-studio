# 0038 — Minimap on in the editor; the diff panes have none by design

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`monaco_editor.jac` sets `"minimap": {"enabled": True}`, matching VS Code's own default. The diff
editor deliberately does not get the same flip.

## Why

Decided on rather than inherited from an unrevisited Phase 2 default. For the diff editor, read
`monaco-editor`'s own source (`diffEditor/components/diffEditorEditors.js`'s
`_adjustOptionsForSubEditor`): it hardcodes `minimap.enabled = false` for both panes
unconditionally, regardless of the options passed in — and real VS Code's diff view has no
per-pane minimap either.

## Consequences

The missing diff minimap is deliberate upstream design, not a gap to work around. Passing the
option there would be dead configuration, and "fixing" it would require patching Monaco.
