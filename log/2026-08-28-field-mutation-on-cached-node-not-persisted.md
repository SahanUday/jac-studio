---
id: 2026-08-28-field-mutation-on-cached-node-not-persisted
date: 2026-08-28
category: compiler-bug
severity: blocker
status: workaround
phase: 3
subsystem: persistence
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [persistence, service-registry, caching, jobj, restart]
---

## What happened

Phase 3's workspace-state-persistence work (`docs/roadmap.md`) needs data to survive a genuine app
restart, not just a browser page reload within the same live server process — that distinction is
the whole point of the exit criterion ("closing and reopening the app restores the previous session
exactly"). Verifying it properly (`jac browse` driving a real `jac run --serve --dev` process,
killed and restarted — not just `location.reload()`) surfaced a real, previously-undiscovered gap
in this project's own project-wide caching rule from `docs/architecture.md`'s service-registry
section: **"every service accessor resolves its node once per `root` and caches the reference in a
module-level `glob` keyed by `jid(root)`."**

That rule is validated for *reads* (the Phase 0 spike proved get-or-create idempotency and
cross-service interaction). It is silently wrong for *writes*: a `has`-field mutation made through
a node object that was cached from an *earlier, separate request* is never durably committed to the
database, even though jaseci's own persistence docs say "writes persist automatically — no save/
commit call needed inside endpoints." Every module in `src/workbench/` built so far on this pattern
was affected: `settings_service.jac` (`set_setting`), the new `session_service.jac`
(`save_session`), `workspace_service.jac` (`get_or_create_workspace`'s `root_path`/`scanned` reset,
`_ensure_scanned`'s `scanned = True`), and `command_registry.jac`'s `KeybindingOverrides`
(`set_keybinding_override`). This had already shipped, unnoticed, in PR #35 (settings & keybinding
overrides) — that PR's own live verification tested a page reload, which the bug is invisible to,
not a real restart.

## Repro (clean, minimal, reproduced multiple times)

1. `jac run --serve --dev main.jac`, `jac browse open` the app.
2. Call a `def:pub` that resolves a node via the project's own `glob _cache: dict[str, Node]`
   pattern and mutates a `has` field on it (e.g. `settings_service.jac`'s `set_setting`).
3. Read it back immediately — correct, because the read hits the same live Python object.
4. Kill the server process (`kill -TERM`, a graceful shutdown — ruled out "the kill wasn't clean"
   as an explanation) and start a fresh `jac run --serve --dev main.jac`.
5. Call the read function again: the mutation is gone. Direct inspection of the underlying Postgres
   row (`jac run` a throwaway script importing `jaclang.runtimelib.pgembed.PgRuntime` /
   `jaclang.runtimelib.store.PgStore` directly, connecting to the exact database `jac db list`
   reports as this project's live one) confirmed the row's `version` column stayed `0` — it was
   never written past its initial creation, regardless of how many times the cached object's field
   was reassigned.

Confirmed narrow, not a general "nothing persists" problem (three false leads chased and ruled out
first, worth recording so a future session doesn't re-chase them):

- **Not an anonymous-identity-instability issue.** A `debug_whoami` probe returning `jid(root)`
  gave the *same* id across multiple real restarts, and every affected node was attached to that
  same, stable root. (A red herring surfaced along the way: `jac db sql`/`jac db inspect` connect
  to the *wrong*, empty database — `jac_main_<hash>` instead of `jac_<project>_<hash>` — whenever
  the project root has more than one top-level `.jac` file, because `_project_database()`'s
  `Path.cwd().glob("*.jac")` target-detection silently gives up and falls back the moment there's
  more than one match. This project has had two top-level files, `main.jac` and `main.impl.jac`,
  since PR #35 — a separate, real CLI-tooling defect, but not the persistence bug itself, once a
  direct-connection script bypassing that inference confirmed the real database's actual row
  counts.)
- **Not a `pkill -9` (unclean shutdown) artifact.** Repeated with a graceful `SIGTERM` and a
  multi-second wait for the drain-complete log line before restarting; the mutation was still gone.
- **Not a general "field mutation never persists" problem.** A node created *and* mutated within
  a single fresh `jobj()`-per-call resolution (no cross-request cache at all) survived a real
  restart cleanly on the first try. Edge creation (`parent +>:Contains():+> child`) and edge
  traversal reads (`[parent->:Contains:->]`) through a cross-request *cached* object were also
  separately verified to survive a restart — the gap is specific to `has`-field mutation on an
  object that a `glob` dict handed back from an earlier request, not the caching pattern itself,
  and not graph writes/reads in general.

## Plan

Adopted as the corrected, permanent version of the project-wide caching rule (see
`docs/architecture.md`'s "Correction (2026-08-28)" in the service-registry section): cache the
**jid** (`glob _cache: dict[str, str]`), not the node object, and resolve via `jobj(cached_jid)`
immediately before any mutation — the `jac-sv-persistence` guide's own canonical "UPDATE" pattern
(`target = jobj(post_id); target.published = True;`), which this project had been reading past
without registering that its `jobj()` call was load-bearing for more than cross-user grants.
`jobj()` is documented O(1), so this keeps the original rule's entire performance rationale (never
re-paying the ~600us/call `[root-->[?:Type]]` traversal) while being correct. Applied to
`settings_service.jac`, the new `session_service.jac`, `workspace_service.jac`, and
`command_registry.jac`'s `KeybindingOverrides` in the same PR that found this
(`phase3/workspace-state-persistence`); `get_command_registry`'s own cached `CommandRegistry` node
and `register_command`'s `existing_command` did **not** need the fix (read-only traversal use and a
fresh-per-call traversal result, respectively — both already outside the affected shape).

Marked `status: workaround` rather than `resolved`: the *practice* (cache the jid, `jobj()` before
writing) is the correct, permanent one going forward, not a stopgap — but the underlying jaseci
behavior (a `def:pub`'s request-scoped persistence tracking apparently not recognizing a node
object reused from a different request's resolution, even though its fields are freely readable
and writable in-process) is still unexplained at the runtime-mechanism level and worth raising
upstream; this entry doesn't attempt that root-cause, only the empirical repro and the fix that
works. Revisit if a future jaseci version's changelog mentions request-scoped persistence/session
tracking changes.
