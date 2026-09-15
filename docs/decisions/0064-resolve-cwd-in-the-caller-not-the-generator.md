# 0064 — Resolve the workspace path in the caller, never inside the SSE generator

- **Date**: 2026-09-05
- **Status**: accepted

## Decision

`ai_chat.jac`/`inline_chat_widget.jac` resolve `cwd` with an ordinary `await`ed call and pass it
into `start_chat_turn` as a plain argument. No `root`-scoped graph query runs inside the SSE
generator.

## Why

`get_current_workspace()` called from inside `start_chat_turn`'s own generator made a chat turn
silently answer about the server process's launch directory instead of the real open workspace,
and a follow-up turn hit an uncaught `PgWireError`. This is the first confirmation that the known
SSE-generator isolation risk (0049, previously only tested against plain `glob` state) extends to
a real graph query with its own DB connection and transaction. Tracker entry
`2026-09-05-sse-generator-root-scoped-graph-query-unreliable`.

## Consequences

Generalizes 0049's rule: an SSE generator gets everything it needs at spawn time — the "state
needed only at spawn time" pattern `dap_client.jac`'s own tracker entry already prescribed. Any
future generator endpoint that reaches for graph state inside itself will reproduce this, and the
first symptom is a wrong answer, not an error.
