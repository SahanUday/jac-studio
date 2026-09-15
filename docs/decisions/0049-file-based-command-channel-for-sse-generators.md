# 0049 — Cross into an SSE generator through a file-based command channel

- **Date**: 2026-09-01
- **Status**: accepted

## Decision

Where a running SSE stream must receive a command from an ordinary RPC call, pass it through a
fixed file (`dap_client.jac`'s `_DAP_COMMAND_FILE`), polled by the generator side.

## Why

A `Generator`-returning SSE endpoint runs in a genuinely separate execution context from every
other function in the same module — no shared `glob` state reaches it. Tracker entry
`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`.

## Consequences

Established the pattern the Claude Code tool-approval flow later reused verbatim (0056), for the
identical reason. The isolation turned out to be broader than `glob` state alone — a real
root-scoped graph query inside a generator is unreliable too (0064). Treat an SSE generator as a
separate process: give it everything it needs at spawn time.
