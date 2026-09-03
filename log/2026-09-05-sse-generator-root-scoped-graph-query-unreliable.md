---
id: 2026-09-05-sse-generator-root-scoped-graph-query-unreliable
date: 2026-09-05
category: doc-gap
severity: major
status: workaround-found
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [sse-streaming, root-scoped-query, graph-query, ai-tool-integration, dap]
---

Found via real user testing of the shipped Claude Code integration (`ai_chat.jac`), not a spike --
the first live, end-to-end use of `claude_code_client.jac`'s `start_chat_turn` against a real open
workspace and a multi-turn conversation.

## What happened

Two distinct-looking failures in the same real session:

1. Asked "What files are in this project?" with `testing-workspace/` genuinely open (confirmed via
   the server log: `open_workspace` had just returned 200 for that exact root moments earlier, in
   the same browser session). Claude Code answered based on `/home/sahan/dev/vs/jac-studio` (this
   project's own repo root -- the server process's own launch directory) instead of the actually
   open workspace.
2. A follow-up message in the *same* conversation failed outright with a real, uncaught exception:
   `jaclang.data.pgwire.PgWireError: {'C': '08006', 'M': 'connection lost mid-transaction; retry'}`,
   raised from inside `store.impl.jac`'s `_run`, reached via `workspace_service.jac`'s
   `get_current_workspace` -> `[root-->[?:Workspace]]` -> `runtime.jac`'s query resolution ->
   `query_planner.impl.jac`'s `_sql_pairs` -> `store.rows`.

## Root cause -- confirmed, not assumed

Both trace to the exact same call site: `claude_code_client.jac`'s `start_chat_turn` (an
`async def:pub ... -> Generator`, consumed as a raw SSE stream) called
`get_current_workspace()` -- a real `root`-scoped graph query -- from *inside* its own inner
`async def stream` generator function, on the assumption that a `Generator`-returning endpoint
still sees the same `root`/DB-connection context as an ordinary call.

This module's own docstring already flagged the *general* risk before this was found (quoting the
still-open question in `2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`)
but explicitly reasoned it didn't apply, since `start_chat_turn` has no mid-session cancel feature
that would need to *write* shared state back and forth the way `dap_client.jac`'s command channel
does. **That reasoning missed that `get_current_workspace()` itself, called once at the very top of
the generator, has the identical exposure** -- it doesn't need another endpoint to have written
anything; it's the read from inside the generator that's unreliable on its own, either returning a
stale/empty result (bug 1) or hitting a genuinely broken DB connection/transaction (bug 2).

This extends, not just re-confirms, the two existing tracker entries on this topic:
`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state` and
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run` both tested only
plain in-memory `glob` state (a dict). This is the first confirmation the same class of isolation
problem reaches a real `root`-scoped **graph query with its own database connection/transaction**,
not just an in-memory Python object -- a materially worse failure mode, since it doesn't just read
stale data, it can throw a real, user-visible, uncaught error mid-conversation.

## The fix

The exact pattern `2026-09-01-...`'s own Plan section already prescribes for "state needed only at
spawn time": resolve it via an ordinary, non-generator call *before* the generator starts, and pass
the result in as a plain function argument, rather than querying it from inside the generator at
all. Concretely:

- `start_chat_turn(prompt, session_id)` became `start_chat_turn(prompt, session_id, cwd)`.
  `stream()` no longer imports or calls `get_current_workspace()` at all.
- `ai_chat.jac`/`inline_chat_widget.jac` (the two callers) now call `get_current_workspace()`
  themselves, as a plain `await`ed RPC call, immediately before `fetch`ing `/function/start_chat_turn`
  -- the exact same call shape `file_tree.jac`'s own session restore already makes successfully
  (`restored = await get_current_workspace();`), confirming the function itself is fine; only
  calling it from inside a `Generator`-returning endpoint's own body is the unreliable part.

Verified after the fix: `cwd` is resolved once, correctly, by the caller, and the generator itself
now does zero graph queries -- there's nothing left inside `stream()` that could reproduce either
failure mode.

## Plan

Any *future* SSE-streamed endpoint in this codebase that needs `root`-scoped state -- not just
`glob` state -- should default to the same rule the two prior entries already established for
`glob`, now confirmed to cover graph queries too: **resolve anything root/session-scoped outside
the generator and pass it in as an argument; never read it from inside a `Generator`-returning
function's own body.** If a future feature genuinely needs to read *fresh* root-scoped state partway
through a long-lived stream (not just at spawn time), that's the harder, still-unsolved case neither
this fix nor `dap_client.jac`'s file-based command channel actually addresses (that channel solves
writing *into* a running generator, not the generator reading graph state reliably) -- worth its own
investigation if/when a real feature needs it, not solved speculatively here.

A permanent, upstream answer would still be worth having (do `Generator`-returning endpoints get
their own DB connection/session, and if so, is `root` binding threaded into it correctly?) but this
project's own workaround doesn't depend on that answer arriving.
