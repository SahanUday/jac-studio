---
id: 2026-08-22-file-move-schema-migration
date: 2026-08-22
category: ergonomics
severity: major
status: open
phase: 3
subsystem: persistence
jac_version: "unspecified — see jac-sv-persistence.md"
related_vscode_ref: ""
upstream_issue: ""
tags: [persistence, graph, refactoring, node, edge]
---

Jac's graph-is-the-database persistence model is graceful for field additions/removals (new fields
default, removed fields move to an "attic"), but a **file move or rename for any module declaring
`node`/`edge` types is effectively a breaking schema migration**, because archetype identity
includes the module path — unless `@archetype_alias`/`schema_alias` is declared explicitly ahead
of the move.

**Impact on jac-studio**: our whole data model (workspace/files/tabs/extensions/settings, per
`architecture.md`) is built out of `node`/`edge` types. This project will do a lot of iterative
refactoring of that model as the design settles (Phases 1–5) — every file move or rename in that
area risks silently orphaning persisted data unless we remember the alias step every time.

**Plan**: write a short internal checklist/lint reminder before Phase 2 (workspace-as-graph work
begins) — "moving or renaming a node/edge module? declare the alias first." Consider whether a
`jac` CLI lint rule could catch this automatically; if not, that's worth raising upstream as a
DX suggestion once we've hit it for real in our own history (not yet — this entry is pre-emptive,
based on the docs, not on an incident yet).
