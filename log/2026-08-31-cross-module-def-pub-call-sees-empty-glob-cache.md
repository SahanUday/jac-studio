---
id: 2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache
date: 2026-08-31
category: compiler-bug
severity: blocker
status: workaround
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [glob, module-state, jid, root, cross-module-import, search, workspace-service]
---

## What happened

Building Phase 4's search-in-files feature (`docs/roadmap.md`), `src/workbench/search/search_service.jac`
did exactly what `docs/architecture.md`'s "reuse existing infrastructure" principle asks for: reused
`workspace_service.jac`'s already-shipped, already-proven `list_all_files()` (a plain `os.walk` over
the current workspace, the same data source Quick Open already uses) as its candidate file set,
rather than duplicating that logic.

Live in a real browser (`jac browse` against `jac run --serve --dev`), search consistently returned
zero results for queries that definitely matched real file content -- confirmed via a fixture
workspace with known text. `jac test` (35 tests covering the exact same matching logic against a
tempfile fixture, via `open_workspace` + direct in-process calls) passed 100% the whole time; this
only reproduced through a real HTTP round trip.

## Repro (isolated with temporary debug instrumentation, since removed)

Sequence, all against one already-open workspace, same browser/curl session throughout:

1. `POST /function/get_current_workspace` -> succeeds, and (temporarily instrumented) reports
   `jid(root) = fc26d10eff74436aa82b3f474d763a73`.
2. `POST /function/list_all_files` (workspace_service.jac's own directly-registered endpoint) ->
   returns the real file list, and (temporarily instrumented) reports the *same*
   `jid(root) = fc26d10eff74436aa82b3f474d763a73`, with its internal `_cached_workspace_jid` dict
   correctly containing that key.
3. `POST /function/search_in_files` (search_service.jac's endpoint, which internally calls the
   *identical* `list_all_files()` via `import from src.workbench.workspace.workspace_service
   { list_all_files }`) -> (temporarily instrumented) reports the exact same
   `jid(root) = fc26d10eff74436aa82b3f474d763a73` -- but `_cached_workspace_jid`'s own keys, read
   from *inside that same function body*, come back **empty** (`cache_keys=[]`).

`root`'s identity is confirmed byte-for-byte identical across all three calls. The module-level
`glob _cached_workspace_jid: dict[str, str] = {}` dict itself is not shared between
`workspace_service.jac`'s own directly-registered `def:pub` endpoints and a `def:pub` in a
*different* module (`search_service.jac`) calling one of those functions via a plain cross-module
import. Everything points at two independent copies of `workspace_service`'s module-level state
existing simultaneously in the same running server process -- one backing its own registered
routes, a second (empty) one backing calls reached through `search_service.jac`'s import -- but the
exact mechanism (duplicate module instantiation at route-registration time vs. something else) is
not fully isolated; this entry reports the confirmed symptom, not a confirmed root cause.

## Why this was easy to miss until now

Every module in this project reused so far (`get_or_create_workspace`, `get_current_workspace`)
has a graph-query fallback on a cache miss (`existing = [root-->[?:Workspace]]`), so a duplicated,
independently-empty cache copy only costs an extra ~600us query for those functions -- invisible
unless you're specifically measuring latency. `list_all_files` was written assuming its own
module's cache was *always* populated correctly by that point (a hard `if key not in
_cached_workspace_jid { return []; }`, no fallback), because until this feature, it was only ever
called from within its own module's already-warm-cache context. `search_service.jac` is the first
module in this project to call another module's `def:pub` function that depends on that function's
*own* module-level cache -- exposing a gap that a graph-query-fallback function would have quietly
absorbed.

## Fix (shipped)

Gave `list_all_files` the same resilience `get_or_create_workspace` already has: fall back to a
real graph query (`[root-->[?:Workspace]]`) on a cache miss instead of an unconditional
`return []`, and repopulate the cache from that query's result. See
`src/workbench/workspace/workspace_service.jac`'s `list_all_files` docstring for the in-code
record. This fixes the *symptom* for every current and future caller of `list_all_files`
specifically, cross-module or not -- it does not fix the underlying cache-duplication mechanism
itself, which is still unconfirmed and may affect any other `glob`-cached, no-fallback accessor a
future module reuses cross-module.

## Plan

`workaround-found`, not `resolved` -- unlike the `open()`/`with`-block finding logged alongside
this one, the actual root cause (why a cross-module `def:pub`-to-`def:pub` call sees a *different*
copy of the callee module's `glob` state than the callee's own directly-registered routes do) is
not understood, only worked around for this one accessor. Concretely still open:

1. Is this specific to `def:pub`-decorated modules with their own registered routes (i.e., does
   jaseci's server dispatch instantiate a separate module object per registered-route module,
   duplicating any module reached that way vs. reached by plain import), or does it affect *any*
   cross-module `glob` regardless of whether the importing/imported module has `pub` endpoints?
2. Does this affect `node`-backed caches the same way (this project's `jid(root)`-keyed *node*
   caches, e.g. `command_registry.jac`'s `_cached_command_registries`) or only plain-`obj`/
   dict-keyed ones like `_cached_workspace_jid`?
3. A general audit: every other `glob _cached_..._jid`-style accessor in this project
   (`settings_service.jac`, `session_service.jac`, `command_registry.jac`, `output_service.jac`)
   should be checked for the same "no graph/fallback path on cache miss" shape `list_all_files` had
   -- any of them could carry the identical latent gap the moment a future feature reuses them
   cross-module the way `search_service.jac` just did for `list_all_files`. Not audited yet as part
   of this entry; worth a dedicated pass before the next cross-module reuse (the SCM/task-runner
   work later in this same Phase 4 is the next likely candidate to hit this).

Until the root cause is confirmed: any new module that calls another module's cached, `root`-keyed
accessor cross-module should verify live (real HTTP round trip, not just `jac test`) that the
callee's cache-miss path degrades gracefully, the same discipline this finding itself was caught by.
