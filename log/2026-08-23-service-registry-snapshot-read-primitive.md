---
id: 2026-08-23-service-registry-snapshot-read-primitive
date: 2026-08-23
category: missing-feature
severity: minor
status: open
phase: 0
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main @ 86b0c25da)"
related_vscode_ref: ""
upstream_issue: ""
tags: [service-registry, performance, jac-runtime, upstream-question, phase-0]
---

Follow-on from `2026-08-23-service-registry-query-cost` (the ~600us/call graph-traversal cost,
fixed there with an app-level `glob` cache). This entry tracks a narrower, still-open question
that fix didn't answer: **is the cost avoidable at the runtime level, without app-level caching,
via something jaseci already has the pieces for?**

**What was found**: `jaclang/runtimelib/store.jac` defines a `TxnIsolation` enum including
`SNAPSHOT_READ_ONLY = 'ISOLATION LEVEL REPEATABLE READ READ ONLY'`, and `Session` (same file's
neighbor, `session.jac`) exposes `read_scope_enter`/`read_scope_exit`/`_snapshot_reads` internally.
None of this is exposed as documented, user-facing Jac syntax — `jac guide --search` for "cache",
"read scope", "snapshot read", and "unit of work" turned up nothing a `.jac` program can opt into.
Separately, reading the actual traversal implementation (`jaclang/jac0core/osp_graph_sv.jac`'s
`sv_live_edges`/`_resolve`) shows the in-memory graph-walk itself is cheap (plain dict/list
operations, no visible DB call) — so the ~600us measured in the linked entry likely comes from
something wrapping that call, not the traversal logic itself, and it recurs on every call even
inside one already-open served request (verified via `JacTestClient`), ruling out "just hold a
session open" as a fix.

**Why this matters beyond one spike**: if a stable-snapshot read scope is exposable (or could be
made exposable) at the language level for the "many repeated reads, tolerate a snapshot instead of
per-call freshness" case, it could give jac-studio (and any other Jac app with a hot-path read
pattern) the speed of app-level caching with runtime-guaranteed correctness, instead of every
service module hand-rolling its own cache + reset-for-tests dance. If no such thing exists or is
planned, that's also useful to know — it confirms the app-level caching pattern in the linked entry
is the durable answer, not a stopgap, and jac-studio should stop looking for a cleverer fix here.

**Plan**: not investigated further on our side without input from jaseci itself — this needs
either reading `Session`'s actual implementation more deeply than this pass did (the exact call
site that re-syncs with the store per graph read wasn't traced) or asking the maintainers directly.
No action needed for jac-studio right now: the app-level caching fix in the linked entry already
unblocks Phase 1+, and nothing here changes it. Revisit if/when this gets raised with jaseci
upstream (`upstream_issue` field to be filled in if so) or if a future phase's hot-path needs push
past what caching alone comfortably covers.
