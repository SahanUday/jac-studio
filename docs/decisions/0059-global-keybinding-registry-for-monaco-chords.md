# 0059 — Register editor chords once globally and dispatch by real focus

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

Stop trusting Monaco's per-instance keybinding routing. A module-level registry
(`_focused_editor_handlers`, keyed by file path) holds every mounted instance's save/toggle
callbacks; `Ctrl+S` and `Ctrl+I` are registered exactly once, globally, and the shared handler
resolves the truly focused editor via `monaco.editor.getEditors().find(hasTextFocus)` before
dispatching.

## Why

With more than one tab open — the normal case, since `keepCurrentModel` (0021) keeps every tab's
editor mounted — each instance's `editor.addCommand(chord, handler)` does **not** scope the
binding to that instance: only the *last-registered* handler for a chord ever fires, confirmed
live with an isolated minimal test independent of this project's code. Passing `"editorTextFocus"`
as the context argument (the correct fix in a real VS Code workbench) was tried and confirmed not
to fix it in a standalone embedding. Before the fix, editing `broken.jac` and pressing Ctrl+S
could silently save `README.md`. Tracker:
`2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance`.

## Consequences

Any new editor chord must go through this registry. Adding one via `addCommand` per instance will
silently break every other instance's binding — with data loss as the failure mode, not an error.
