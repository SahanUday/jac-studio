---
id: 2026-09-07-save-session-hits-readonly-transaction-race-upstream
date: 2026-09-07
category: missing-feature
severity: major
status: open
phase: 5
subsystem: persistence
jac_version: "0.37.3 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [session-service, postgres, transactions, real-user-qa, upstream-jaclang]
---

## What happened

Real-user QA, live server: `save_session` (`src/workbench/session/session_service.jac`) failed
outright, repeatedly, with a raw Postgres error surfaced straight to the client:

```
{'S': 'ERROR', 'V': 'ERROR', 'C': '25006', 'M': 'cannot execute INSERT in a read-only transaction',
 'F': 'utility.c', 'L': '411', 'R': 'PreventCommandIfReadOnly'}
```

Not a one-off -- the same error recurred multiple times across one session, at various points
(tab open, tab switch, gitdiff tab open), each time on a `save_session` call specifically.

## Root cause

Traced into jaclang's own source (`/home/sahan/dev/jaseci/jac`, a separate project, run here in dev
mode) -- not a bug in `session_service.jac` itself, which is a straightforward `def:pub` function
that plainly mutates node fields (confirmed by direct read: no ambiguity about whether it writes).

`jaclang/server/impl/session.impl.jac` implements an *optimistic* transaction strategy for
performance: a session's underlying Postgres transaction starts in a lightweight
`SNAPSHOT READ ONLY` isolation level whenever every currently-active "unit" (an in-flight function
call sharing this session) is itself classified as read-only (`_txn_isolation`'s
`self._ro_units == self._active_units` check). The moment any unit is detected to actually write
(`self._dirty` set), `_ensure_txn` is meant to transparently commit the read-only transaction and
restart it as `SERIALIZABLE` (writable) *before* the real write reaches the database -- with a
`_raise_ro_retry`/`ReadOnlyRetry` path specifically built to catch and retry a write that was
optimistically started under a read-only assumption.

The raw, uncaught Postgres error reaching the client means this upgrade-and-retry path did not fire
in time for these specific `save_session` calls. Root cause of *why* the upgrade missed was not
pinned down to the exact line -- this is a live concurrency mechanism (unit stacks, active-unit
counts, per-key write-history tracking) that would need controlled concurrent-request reproduction
to fully isolate, well beyond what a single live session's logs can prove. The most plausible
trigger, given this app's own real traffic shape: `save_session` fires on nearly every UI action
(tab open/close/select, cursor-move debounce), constantly overlapping with the workspace watcher's
own 1-second poll (`check_workspace_changes`/`list_children_by_path`, both genuinely read-only) --
exactly the kind of frequent, overlapping read/write call mix that would stress a "which of these
concurrent units actually needs to write" tracking mechanism.

## Scope

Confirmed this lives entirely in jaseci's own server/session runtime
(`jaclang/server/impl/session.impl.jac`'s `_txn_isolation`/`_ensure_txn`/`unit_enter`/
`_raise_ro_retry`), not anywhere in this project's own `.jac` source. `session_service.jac`'s
`save_session` was read directly and is unambiguously a writer (`session.groups = groups;` and
three other direct field mutations, plus a conditional `root ++> WorkspaceSession()` inside its own
`get_session_node()` helper) -- there is no jac-studio-side classification or usage error to fix.

## Practical impact

Low, not silent permanent data loss: `save_session` persists the open-tabs/cursor-position session
snapshot, and is called again on essentially every subsequent user action -- a single failed save
just means that one snapshot didn't land, and the very next action retries the whole thing. The
realistic risk window is narrow: only the very last session state immediately before a hard crash
or server restart is genuinely at risk of not having been the most recently attempted save that
actually succeeded.

## Plan

No fix possible from this project's own code -- the actual defect is in jaclang's own
optimistic-transaction upgrade path, a separate upstream project. Two real paths forward if this
becomes a bigger problem later, neither attempted here:

1. **Upstream**: the real fix belongs in `session.impl.jac`'s own read-only-to-serializable upgrade
   logic -- needs controlled, concurrent-request reproduction (not achievable via `jac test`'s
   synchronous execution, the same limitation this project's own `_workspace_lock` docstring
   already documents for a different race) to isolate the exact missed-upgrade window.
2. **Mitigation, not a fix, available from this project's side if the frequency becomes a real
   problem**: reduce how often `save_session` is called (it already debounces cursor-movement
   saves; tab open/close/select still save immediately, per that module's own docstring's stated
   design). Explicitly **not** applied here -- asked the user directly, given the low measured
   impact and that a mitigation wouldn't close the underlying race anyway, the call was to log this
   finding and move on rather than add speculative throttling.
