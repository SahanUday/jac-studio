# 0004 — The workspace is the graph

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Files, folders, editor groups, tabs and cursor state are nodes and edges
(`Workspace --Contains--> Folder --Contains--> File`, `EditorGroup --Shows--> Tab`), not
in-memory arrays owned by a workbench model object.

## Why

Persistence-by-reachability comes free (no settings serialization to write), and the pattern is
already proven in littleX/day_planner. Validated structurally at scale by
`internal/workspace-graph-spike/`: 2,974 real nodes scanned, every node reached exactly once, no
duplicates.

## Consequences

Multi-root workspaces fall out for free (several `Folder` nodes under one `Workspace`) — no
`.code-workspace` format to design; collaborative groundwork inherits `grant`/`revoke`/
`root.shared`. The same spike measured the cost forcing lazy loading (0019), and later phases
found real durability gaps in mutating and detaching graph state (0029, 0030).
