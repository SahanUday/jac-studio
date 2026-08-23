---
id: 2026-08-23-service-registry-query-cost
date: 2026-08-23
category: workaround-found
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

**What happened**: the pattern itself works — get-or-create idempotency, cross-service
interaction, multi-root-safety all held up under real code and 13 passing tests. But a fresh
`[root-->[?:ConfigService]]` query measured **~600–630us/call** under `jac run` on this machine,
against a plain `dict` lookup baseline of ~0.05us/call — over 10,000x slower. A keystroke has
roughly a 16ms (60fps) frame budget; one such lookup alone burns ~4% of it, and a real command
dispatch would chain several (config, file tree, more). This is exactly the risk
`architecture.md` flagged as the reason for running this spike, now measured instead of assumed.

**Minimal repro**: `service-registry-spike/tests/integration_tests.jac`, the two tests named
"an uncached graph lookup alone is far too slow..." and "the cached accessor is what actually
makes repeated lookups hot-path-safe" — both assert on the measured numbers directly.

**The fix**: resolve each service's node once per process and cache the reference in a
module-level `glob`, inside the `get_<x>_service()` accessor itself (not at call sites). After
caching, field access measured ~0.06us/call — indistinguishable from a plain attribute read. All
three services in the spike now do this. This is the same "construct once" discipline
constructor-injected DI gets for free by only running its constructor once; Jac's version needs it
written explicitly since the graph query isn't free to repeat.

**A second, unplanned finding surfaced while fixing the first**: that cache is a plain Python
module global. `jac test` isolates the persisted graph root per test (verified empirically — one
test's `config_set` never leaks into another's `config_get`), but a worker process handles
multiple tests sequentially, and the module-level cache is NOT reset between them — so a cached
node reference from an earlier test silently leaked into a later one, returning stale
(wrong-but-plausible, not a crash) data. Repro: `git log` the spike branch for the commit before
the `_reset_*_for_tests` hooks were added — running the full suite (not a single file) reproduces
one specific assertion failure in `file_tree_service_tests.jac` about 100% of the time; running
each test file individually never reproduces it, which is what makes this the kind of bug that's
easy to ship undetected if tests are only ever run per-file during development.

**Plan**: both findings are now folded into `docs/architecture.md`'s service-registry section as
concrete implementation rules for every service module built on this pattern from Phase 1 onward:
(1) a `get_<x>_service()` accessor that resolves once and caches — never a bare
`[root-->[?:Type]]` at the call site; (2) a paired `_reset_<x>_service_cache_for_tests()` hook,
called at the top of any test that exercises the accessor. Nothing further to do for this specific
finding — closing as resolved. Worth carrying the testing rule (2) into `jac-studio-implementation`
or `jac-studio-architecture`'s skill guidance once Phase 1 starts writing real service modules, so
it's not rediscovered the hard way per-module. Full measured numbers and the tests that pin them:
`service-registry-spike/README.md`.
