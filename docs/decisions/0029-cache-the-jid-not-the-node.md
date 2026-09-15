# 0029 — Cache the jid, not the node, and resolve via `jobj()` before any mutation

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Correcting 0013: service accessors cache a `dict[str, str]` of jids and resolve via
`jobj(cached_jid)` — the `jac-sv-persistence` guide's own canonical UPDATE pattern — immediately
before any mutation. Applied in `settings_service.jac`, `session_service.jac`,
`workspace_service.jac`, and `command_registry.jac`'s `KeybindingOverrides`.

## Why

A `has`-field mutation made through a node object cached from an *earlier, separate* request is
never durably committed. The bug hides in plain sight: the mutation stays visible to every read
for the rest of the process's life — it even survives a page reload — but the row's `version`
never advances and a real restart reverts it. Found only by a genuine `jac run --serve --dev`
kill-and-restart test, which no Phase 0–2 test ever did. Tracker entry
`2026-08-28-field-mutation-on-cached-node-not-persisted`.

## Consequences

`jobj()` is documented O(1), so this keeps 0013's whole point (avoiding the ~600us traversal)
while being correct. Confirmed narrow: edge *creation* and traversal reads through a cached
object are unaffected, verified separately across a real restart. Passing tests are not evidence
here — they never cross a real request/commit boundary. Edge *deletion* has its own distinct gap
(0030).
