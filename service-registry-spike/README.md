# Service-registry spike (Phase 0)

Validates (or replaces) the "root-graph-as-service-registry" proposal in
[`../docs/architecture.md`](../docs/architecture.md) before the workbench shell gets built on top
of it, per the Phase 0 exit criteria in [`../docs/roadmap.md`](../docs/roadmap.md).

## What this is

A real three-service slice — `ConfigService`, `CommandRegistry`, `FileTreeService` — each
implemented as a `node` reached from `root` via a graph query (`[root-->[?:Type]]`) instead of a
constructor-injected reference, interacting with each other the same way real jac-studio services
will:

- `FileTreeService` reads its default root folder name from `ConfigService` **at creation time**,
  through the graph, not a passed-in reference (`src/file_tree_service.jac`).
- `CommandRegistry` stores contributed command *metadata* (id, title) as graph nodes — real,
  query-able, listable state, the way a command palette would read it — while the *handler* a
  command id dispatches to lives in a plain in-memory table, deliberately not graph-stored (see
  the module docstring in `src/command_registry.jac` for why).
- `main.jac` wires a `files.listRoot` command end to end: registry → file-tree service →
  config service, zero DI.

Run the demo: `jac run main.jac`. Run the suite: `jac test` (13 tests, `jac check .` is clean
except intentional `any`-typed fields on `ConfigService.values` and command handlers, which are
genuinely heterogeneous).

## Result: validated, with a real caveat that changes how the pattern must be used

**The pattern works** — get-or-create idempotency, cross-service interaction through the graph,
and multi-root-safety all hold up under real code and real tests (see `tests/`).

**But a fresh `[root-->[?:Type]]` query is far too slow to call on every access.** Measured on
this machine, under `jac run`:

| Access pattern | Cost |
|---|---|
| Fresh graph query per call (`[root-->[?:ConfigService]]`) | **~600–630us/call** |
| Plain module-level `dict` lookup (baseline) | ~0.05us/call |
| Cached node reference, direct field read | ~0.06us/call |

A ~600us graph query is roughly 4% of a single 16ms (60fps) keystroke frame budget **by itself**
— and a real command dispatch would chain several such lookups (config, file tree, maybe more),
which would eat the whole frame. This is exactly the risk `architecture.md` flagged as the
reason for this spike, now with a real number instead of a guess.

**The fix is cheap and already applied to all three services here**: resolve the node once per
process and cache the reference in a module-level `glob` (`get_config_service`,
`get_file_tree_service`, `get_command_registry` all do this now — see the "uncached vs cached"
tests in `tests/integration_tests.jac`, which measure both regimes explicitly so a regression in
either direction fails loudly). After caching, field access is indistinguishable from a plain
object attribute read. This is the same discipline constructor-injected DI gets for free by only
constructing a service once — Jac's version just needs to do it explicitly via a cache, since the
graph query itself isn't free to repeat.

**Verdict for the roadmap**: keep the root-graph-as-registry pattern, but every service module built
on it from Phase 1 onward should follow this shape: a `get_<x>_service()` accessor that resolves
once and caches, never a bare `[root-->[?:Type]]` query inline at every call site. This should be
written into `architecture.md`'s service-registry section as a concrete implementation rule, not
left as a footnote (done — see the updated section).

## A second, unplanned finding: the cache breaks test isolation across a shared worker

`jac test` runs test blocks in parallel across isolated workers, but a worker handles **multiple
tests sequentially**, not one test per process. The persisted graph root *is* isolated per test
(confirmed empirically — one test's `config_set` never leaks into another's `config_get`), but a
plain module-level `glob` cache is a Python-level binding that survives across tests sharing a
worker, so a cached node reference from an earlier test can silently leak into a later one and
return stale data (not a crash — a wrong-but-plausible-looking result, which is worse).

**The fix applied here**: every service module exports a `_reset_<x>_cache_for_tests()` function,
and every test that exercises one of these accessors calls it first (see any test file in
`tests/`). Verified by running the full suite 5x back to back both with and without `jac clean`
between runs — 13/13 pass every time; removing the reset calls reproduces the original failure
(a test asserting a freshly-created service's config-derived field got a stale cached instance's
value instead).

**This is a real, generalizable testing rule for every future service built on this pattern, not
just these three** — worth carrying forward into `jac-studio-implementation`'s testing guidance
once Phase 1 starts writing real service modules.

## What's NOT covered by this spike

- Concurrent/multi-user access to a cached service reference (no `root.shared` slice tested here
  — this spike is single-user, single-process, matching Phase 0's scope).
- Cache invalidation for a service that could legitimately need to be re-created mid-process
  (none of the three services here ever are — revisit if a future service needs that).
