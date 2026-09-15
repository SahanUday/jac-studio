# 0028 — Persist settings, keybindings and workspace state by graph reachability

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Settings, keybinding overrides and workspace state (open groups, active group, cursor positions,
terminal visibility) are graph-attached `obj`s restored on mount — no explicit save/load code, no
settings-file serialization.

## Why

Direct application of 0004: anything reachable from `root` persists for free, which is the whole
reason to model the workspace as a graph rather than as workbench-owned arrays.

## Consequences

Committed us to a real restart test as the exit criterion, which is the only reason the
field-mutation durability bug (0029) was ever found — every prior phase had verified against a
continuously-running server. Restore ordering is load-bearing, not incidental: `cursor_positions`
must be assigned before `groups`, because `groups` becoming non-empty is what first mounts each
tab's editor and `initialCursor` is read exactly once, at mount. Dirty state is deliberately
excluded from the persisted session (it describes in-memory Monaco content a reload cannot
recover).
