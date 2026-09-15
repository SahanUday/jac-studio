# 0039 — Quick Open lists files with a plain `os.walk`, never the workspace graph

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`workspace_service.jac`'s `list_all_files` is a plain `os.walk`. Quick Open (Ctrl+P) is
registered as `workbench.action.quickOpen` in `command_registry.jac`'s `BUILTIN_COMMANDS` and
dispatched through `workbench.jac`'s generic keybinding mechanism, not a second bespoke keydown
listener.

## Why

A whole-workspace file list is exactly the eager traversal 0019 ruled out; going around the
graph avoids paying that ~3s cost. Quick Open itself was a documented-but-undelivered Phase 2
item (scoped in the triage doc as a second `quickaccess` provider, never built, and the phase was
marked complete without it) — delivered in Phase 3 as the slip it always was, not new scope.

## Consequences

Two file-listing paths now exist with different semantics: the lazy graph-backed tree and a flat
filesystem walk. That is intentional. Note also the departure from `command_palette.jac`'s
self-contained `Ctrl+Shift+P` handling, which predates the generic mechanism and was later lifted
to match (0040's sibling fix in the title bar work).
