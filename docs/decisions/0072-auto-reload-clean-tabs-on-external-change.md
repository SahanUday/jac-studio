# 0072 — Auto-reload open tabs on a clean external change, never a dirty one

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

When the workspace watcher ([ADR 0071](0071-workspace-watched-via-os-level-events.md)) reports a
modified file that is open in a tab, `workbench.jac` signals a reload only if that tab is not
dirty. A clean tab reloads its content from disk automatically; a dirty one is never touched. The
same mechanism covers plain editor tabs and SCM `"gitdiff"` tabs.

## Why

An already-open, undirtied tab kept showing stale content after an external edit (e.g. the AI chat
editing a file already open in the editor). Modeled directly on real VS Code
(`TextFileEditorModelManager.onDidFilesChange`): reload a clean model automatically, never touch a
dirty one.

## Consequences

- `monaco_editor.jac`'s `reload_from_disk` re-checks `dirty` itself immediately before touching the
  buffer — a narrow race exists between the parent's decision and this effect running, and trusting
  only the parent's filter risks clobbering a keystroke that landed in that window.
- Calling `editor.setValue(...)` fires the identical `onDidChangeModelContent` event a real
  keystroke does. A `suppress_dirty_ref` guard (`True` immediately before `setValue`, `False`
  immediately after) stops a reload from re-marking a just-cleaned tab dirty.
- Cursor position is preserved across the reload (`getPosition`/`setPosition` around `setValue`),
  deliberately, since `setValue` replaces the whole model.
- The reload resyncs the LSP server via `notify_document_save`, not `notify_document_open` — the
  document already has a higher version than `notify_document_open`'s hardcoded `version: 1`.
- `scm_diff_editor.jac`'s `"gitdiff"` tabs reuse the same reload-nonce mechanism but need no
  suppress/cursor/dirty handling at all: its `DiffEditor` is a controlled component, so reassigning
  state on a fresh fetch re-renders correctly on its own, and a `"gitdiff"` tab is read-only with no
  dirty state to protect.
