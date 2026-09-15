# 0023 — Read-side deduplication, not write-side locking, guards against duplicate nodes

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

`list_commands()`/`list_children_by_path()` de-duplicate by natural key before returning. Every
"get node if exists, else create" pattern owes read-side idempotency, not an app-level lock.

## Why

A Python `threading.Lock()` around the check-then-create sequence was tried first and verified
insufficient live, on a freshly-dropped database. A `def:pub` function's Postgres commit happens
in server middleware *after* the function returns, so any in-function lock releases before the
write is durable. jaseci's documented protection does not fire: `WriteConflict` is never raised
anywhere in the runtime, and `Session.commit`'s own recovery blindly re-flushes already-decided
writes instead of re-running the caller's check
(`2026-08-25-write-conflict-never-raised-session-commit-blind-retries`).

## Consequences

Correct regardless of what the graph holds underneath. The gap is still open upstream, so a future
session must not "replace the redundant dedup with a proper transaction" — there isn't one.
