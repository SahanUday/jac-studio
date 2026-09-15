# 0019 — The file tree loads lazily, expand-on-demand

- **Date**: 2026-08-24
- **Status**: accepted

## Decision

Populate a `Folder`'s children only when the UI expands it. Never eagerly scan-and-traverse the
whole workspace on open.

## Why

`internal/workspace-graph-spike/` measured **~3 seconds combined** to eagerly scan and traverse a
real-sized project (2,974 nodes from the `jaclang` compiler repo) — too slow to feel instant on
open. Tracker entry `2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale`.

## Consequences

This is a measured constraint on the data model (0004), not a UI preference: any feature that
wants a whole-workspace file list must avoid the graph entirely rather than "just walk it once" —
which is why Quick Open uses a plain `os.walk` (0039). A future session adding a workspace-wide
feature should check this before reaching for a full traversal.
