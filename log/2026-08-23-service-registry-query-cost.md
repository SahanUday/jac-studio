---
id: 2026-08-23-service-registry-query-cost
date: 2026-08-23
category: resolved
severity: major
status: resolved
phase: 0
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main @ 86b0c25da)"
related_vscode_ref: "src/vs/platform (IInstantiationService/createDecorator DI container, 580k lines)"
upstream_issue: ""
tags: [service-registry, performance, testing, architecture-validation, phase-0]
---

Phase 0 spike (`service-registry-spike/`) to validate the root-graph-as-service-registry proposal
in `docs/architecture.md`: a real `ConfigService` + `CommandRegistry` + `FileTreeService` slice,
each reached from `root` via a graph query instead of constructor injection, interacting with each
other the way real jac-studio services will (`FileTreeService` reads its default root name from
`ConfigService` at creation time, through the graph, not a passed reference).

**What happened**: the pattern itself works — get-or-create idempotency and cross-service
interaction held up under real code and 13 passing tests. (**Correction below**: "multi-root
safety" in the original version of this sentence was wrong — the fix as first shipped was not
multi-root-safe. See the correction section at the bottom before relying on anything in this
entry's original body.) But a fresh
`[root-->[?:ConfigService]]` query measured **~600–630us/call** under `jac run` on this machine,
against a plain `dict` lookup baseline of ~0.05us/call — over 10,000x slower. A keystroke has
roughly a 16ms (60fps) frame budget; one such lookup alone burns ~4% of it, and a real command
dispatch would chain several (config, file tree, more). This is exactly the risk
`architecture.md` flagged as the reason for running this spike, now measured instead of assumed.

**Minimal repro**: `service-registry-spike/tests/integration_tests.jac`, the two tests named
"an uncached graph lookup alone is far too slow..." and "the cached accessor is what actually
makes repeated lookups hot-path-safe" — both assert on the measured numbers directly.

**The fix (superseded — see correction below)**: resolve each service's node once per process and
cache the reference in a module-level `glob`, inside the `get_<x>_service()` accessor itself (not
at call sites). After caching, field access measured ~0.06us/call — indistinguishable from a plain
attribute read. This is the same "construct once" discipline constructor-injected DI gets for
free; Jac's version needs it written explicitly since the graph query isn't free to repeat. This
description of "the fix" is incomplete in a way that matters — see below.

**Plan**: folded into `docs/architecture.md`'s service-registry section as a concrete
implementation rule for every service module built on this pattern from Phase 1 onward: a
`get_<x>_service()` accessor that resolves once and caches — never a bare `[root-->[?:Type]]` at
the call site. Nothing further to do for this specific finding — closing as resolved. Full
measured numbers and the tests that pin them: `service-registry-spike/README.md`.

**Root-cause note (added after landing, no change to the fix above)**: a follow-up dig into
`jaseci`'s own source (`jaclang/runtimelib/store.jac`'s `PgStore`, `jaclang/jac0core/osp_graph_sv.jac`)
found the in-memory traversal logic itself is cheap (plain dict/list lookups); the cost tracks with
a consistency/freshness mechanism around it (`Session.read_barrier`, `TxnIsolation`), and persisted
even inside a single already-open served request (tested via `JacTestClient`) — so this is not a
"missing session reuse" bug, more likely a deliberate correctness-over-speed tradeoff in the
Postgres-backed graph. See `2026-08-23-service-registry-snapshot-read-primitive` for the open
question this raises for jaseci.

**CORRECTION (same day, before this ever left the spike)**: the fix described above — a single
`glob X | None = None` cache per service — is wrong and was caught late. `root` is bound to
whoever is calling a served app, not a process-wide constant, so a single cached value silently
serves one user's node to a different user's request the moment the same server process handles
more than one person. Reproduced directly: two users logged in via `JacTestClient` against the
same process, second user's request returned the first user's cached data. This was caught by
the person reviewing this work asking a direct, skeptical question about scope ("is this only a
test-running problem?") rather than by anything in the original test suite — the 13 passing tests
at the time never exercised more than one `root` in the same process, so a real cross-user leak
sailed through green. **The corrected fix**: key the cache by `jid(root)` —
`dict[str, ServiceType]`, not a single value — verified with a permanent regression test
(`service-registry-spike/tests/multiuser_tests.jac`) simulating two logged-in users. Full detail:
`service-registry-spike/README.md`'s "A second finding" section (renumbered after this
correction). Lesson for every future entry in this tracker, not just this one: a fix "verified" by
tests that only ever exercise a single `root` has not verified multi-user correctness, and this
project's services are multi-user by design (`architecture.md`'s data model) — any future
performance fix touching a `root`-scoped accessor needs a multi-root/multi-user test, not just a
single-session one, before it's called resolved.
