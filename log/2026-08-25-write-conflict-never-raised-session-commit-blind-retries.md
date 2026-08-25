---
id: 2026-08-25-write-conflict-never-raised-session-commit-blind-retries
date: 2026-08-25
category: missing-feature
severity: major
status: workaround-found
phase: 2
subsystem: persistence
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [postgres, transactions, occ, write-conflict, concurrency, persistence, def-pub]
---

Found while chasing a real, reproducible duplicate-node bug in jac-studio's command registry and
workspace-scanner: two genuinely concurrent client calls to the same `def:pub` function, each doing
a "check if X already exists under `root`, else create X" sequence, could both pass the check
before either finished creating — producing two `Command`/`Folder` nodes for what should be one.
Concretely: `workbench.jac` and `command_palette.jac` each independently call `list_commands()`
from their own React mount effect on every page load, guaranteeing two near-simultaneous requests
to the same server function.

**First attempted fix, and why it didn't work.** Wrapped the whole check-then-create body in a
Python `threading.Lock()` (`glob _lock: threading.Lock = threading.Lock(); def:pub foo { with _lock
{ ... } }`), reasoning that a sync `def:pub` is dispatched onto a real OS thread-pool worker via
`asyncio.to_thread` (`jaclang/runtimelib/serving/app.jac`), so a `threading.Lock` should correctly
serialize the function bodies. **Re-tested live on a freshly-dropped database and the duplicate
still appeared on the very first page load** — the lock alone does not close the race.

**Root cause, confirmed by reading the actual dispatch/commit code, not by inspection alone.** For
a `def:pub` function, the durable Postgres commit happens *after* the function body returns, in a
separate step: `ExecutionManager.execute_function_sync` awaits the function via `asyncio.to_thread`,
then only afterward calls `_finalize_call_response`, which is where `await Jac.acommit()` actually
runs (`jaclang/runtimelib/impl/server.impl.jac`, dispatch around line 480-494, commit call around
line 375) → `Jac.acommit` → `ctx.mem.acommit(anchor)` → `Session.commit` →
`self.flush(full=True); self.store.commit();` (`jaclang/jac0core/impl/runtime.impl.jac` ~404-411,
`jaclang/runtimelib/impl/session.impl.jac` ~459-483). A `with _lock { ... }` inside the function
body releases the lock the instant the function *returns* — strictly before that commit runs. So a
second concurrent call can legitimately start executing after the first call's Python code already
finished, and still read a pre-commit view of the graph through its own freshly-created
`ExecutionContext`/`Session` (`_begin_request_context`, `server.impl.jac` ~266-275) — no app-level
lock scoped to the function body can close this, since the actual durability boundary is outside
the function entirely.

**The documented protection for exactly this case doesn't currently fire.** jaseci's own docs
(`jaclang/cli/docs/reference/persistence.md`, ~lines 38-63) describe a `SERIALIZABLE`-isolation
Postgres transaction plus a `WriteConflict`-catching replay loop: a losing concurrent write should
raise `WriteConflict`, and the dispatcher should re-run the walker/function from the top
(`_run_function_with_occ`, `server.impl.jac` ~395-467, catches `WriteConflict` from
`exceptions.jac` ~16-32). **`WriteConflict` is never actually raised anywhere in the current
runtime** — `grep -rn "raise WriteConflict" jaclang/` returns zero hits across the whole compiler
source. Instead, `Session.commit` catches raw Postgres serialization-conflict error codes itself
(`_is_serialization_conflict`, `session.impl.jac` ~199-214) and silently retries via
`_recover_conflict` (`session.impl.jac` ~713-727) — but that retry just re-marks the same dirty
anchors and re-issues the *same* writes that were already decided on, rather than re-running the
caller's check-then-create logic from scratch. Since a newly-created node gets a fresh identity
each time, the blind retry doesn't even collide at the database level — it just successfully lands
a second, duplicate node. The documented replay-from-start path in `_run_function_with_occ` is
consequently unreachable in practice, since nothing upstream of it ever throws the exception it's
waiting to catch.

**Plan**: no fix available at the application/Jac-source level closes this completely — the actual
durability boundary and its conflict-handling both live inside the runtime, outside anything a
`def:pub` body can control. Worked around it in jac-studio by moving the correctness guarantee from
the *write* path to the *read* path instead: `list_commands()`/`list_children_by_path()` now
de-duplicate their returned list by natural key (`command_id`/`path`) before sending it to the
client, so a user never sees a duplicate regardless of how many redundant nodes the graph
underneath ends up holding. This is a real, permanent workaround for jac-studio's own callers, not
a fix to the underlying gap. A real fix belongs upstream: either (a) `Session.commit`'s conflict
recovery should actually raise `WriteConflict` on a genuine serialization conflict instead of
blindly re-flushing, so `_run_function_with_occ`'s already-written replay-from-start logic can do
its job, or (b) jaseci could expose an explicit transaction/advisory-lock primitive at the Jac
language level for the narrower case where an app genuinely needs a check-then-create sequence to
be atomic across concurrent requests without waiting on a full OCC round-trip. Worth raising with
jaseci maintainers directly — same spirit as the still-open
`2026-08-23-service-registry-snapshot-read-primitive` question, but a more serious finding: that
one asked for a nice-to-have, this one is a documented guarantee that silently doesn't hold.
