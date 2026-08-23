---
id: 2026-08-23-service-cache-test-isolation
date: 2026-08-23
category: workaround-found
severity: minor
status: resolved
phase: 0
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main @ 86b0c25da)"
related_vscode_ref: ""
upstream_issue: ""
tags: [service-registry, testing, jac-test, phase-0]
---

Follow-on from `2026-08-23-service-registry-query-cost`: fixing that finding meant adding a
module-level `glob` cache to each `get_<x>_service()` accessor in the service-registry spike
(`service-registry-spike/`), so a resolved node reference isn't re-queried from the graph on every
call.

**What happened**: `jac test` isolates the *persisted graph root* per test (verified empirically —
one test's `config_set` never leaked into another's `config_get`), but a worker process handles
multiple tests sequentially, not one test per process, and a plain Python module-level `glob` is
NOT reset between tests sharing a worker. A cached node reference from an earlier test silently
leaked into a later one, returning stale-but-plausible data rather than crashing. Repro: running
the full suite (not a single file) reproduced one specific assertion failure in
`file_tree_service_tests.jac` about 100% of the time; running that test file alone never
reproduced it — the kind of bug that's easy to ship undetected if tests are only ever run
per-file during development.

**The fix**: each service module also exports a `_reset_<x>_service_cache_for_tests()` function,
and every test that exercises a cached accessor calls it first. Verified by running the full suite
5x back to back (with and without `jac clean` between runs) — 13/13 pass every time; removing the
reset calls reproduces the original failure reliably.

**Plan**: this isn't a bug in `jac test` itself — the parallel-worker-reuse behavior is already
documented (`jac-testing`'s "Graph state: parallel workers + a persisted root" section warns
in-memory state isn't test-scoped). It's a real, generalizable consequence of combining that
documented behavior with the caching pattern the previous entry recommends, worth stating
explicitly since it wasn't obvious until it broke a test. Carry the rule forward into whatever
`jac-studio-implementation` or `jac-studio-architecture` skill guidance covers service modules
once Phase 1 starts writing real ones: any `get_<x>_service()`-shaped accessor that caches must
ship a paired test-reset hook, and any test touching it must call that hook first. Nothing further
to do here — closing as resolved. Full details: `service-registry-spike/README.md`.
