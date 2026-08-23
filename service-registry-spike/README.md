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

Run the demo: `jac run main.jac`. Run the suite: `jac test` (14 tests, `jac check .` is clean
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

**The fix, corrected once**: resolve the node once per *root* and cache the reference in a
module-level `glob` (`get_config_service`, `get_file_tree_service`, `get_command_registry` all do
this now — see the "uncached vs cached" tests in `tests/integration_tests.jac`). The first version
of this fix cached a single bare value (`glob X | None = None`) and shipped as "resolved" — that
was wrong. `root` is bound to whoever is calling, not a process-wide constant (a served app
resolves a different `root` per authenticated user, same as `is_mine`-style per-caller logic
anywhere else in a Jac server). A single bare cached value verifiably leaks one user's node into
another user's request in a long-lived server process — reproduced with two logged-in users via
`JacTestClient` (`tests/multiuser_tests.jac`), fixed by keying the cache
`dict[jid(root), ServiceType]` instead of caching one value. After caching (correctly keyed),
field access is indistinguishable from a plain object attribute read. This is the same discipline
constructor-injected DI gets for free by only constructing a service once *per request/user* —
Jac's version needs it written explicitly, keyed by whose `root` it is.

**Verdict for the roadmap**: keep the root-graph-as-registry pattern, but every service module built
on it from Phase 1 onward should follow this exact shape: a `get_<x>_service()` accessor backed by
`dict[jid(root), ServiceType]`, never a bare `[root-->[?:Type]]` query inline at every call site,
and never a single non-keyed cached value. This is written into `architecture.md`'s
service-registry section as a concrete implementation rule, not left as a footnote.

## A second finding: the keyed cache does NOT by itself fix test isolation

`jac test` runs test blocks in parallel across isolated workers, but a worker handles **multiple
tests sequentially**, not one test per process. The persisted graph *content* is isolated per test
(confirmed empirically — one test's `config_set` never leaks into another's `config_get` when no
caching is involved), but **`jid(root)` itself is the same across different tests in one worker**
(the test harness resets graph content between tests but reuses the same root identity — unlike
real users, who each genuinely get a distinct root node). So keying by `jid(root)` fixes the real
multi-user leak above, but does *not*, by itself, fix cross-test leakage — verified directly: a
cache keyed by `jid(root)` still leaked a value from one test into the next when tried without the
reset hooks. Both fixes are needed, for different reasons; neither substitutes for the other.

**The test-isolation fix**: every service module additionally exports a
`_reset_<x>_cache_for_tests()` function (now clearing the whole keyed dict, not a single value),
and every test that exercises one of these accessors calls it first (see any test file in
`tests/`). Verified by running the full suite 5x back to back both with and without `jac clean`
between runs — 14/14 pass every time; removing the reset calls reproduces the original failure.

**Both are real, generalizable rules for every future service built on this pattern, not just
these three** — worth carrying forward into `jac-studio-implementation`'s guidance once Phase 1
starts writing real service modules: (1) key any service cache by `jid(root)`, never a bare value;
(2) give it a test-reset hook, and call it from any test that touches the accessor.

## What's NOT covered by this spike

- `root.shared` (deployment-wide singletons genuinely meant to be shared across all users) — none
  of these three services are that; if a future service legitimately wants one shared instance
  across everyone, the per-root-keyed shape here doesn't apply to it.
- Cache eviction: `dict[jid(root), ServiceType]` grows one entry per distinct root ever seen in
  the process's lifetime and nothing here ever removes an entry. Fine for this spike; a long-lived
  production server with many users would want bounded eviction (e.g. an LRU) — not implemented or
  measured here, flagged for whoever builds the first real service on this pattern.
- Cache invalidation for a service that could legitimately need to be re-created mid-process for
  the *same* root (none of the three services here ever are — revisit if a future service needs
  that).
