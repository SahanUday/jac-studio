---
id: 2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state
date: 2026-09-01
category: doc-gap
severity: major
status: workaround
phase: 4
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [sse, generator, glob, multiprocess, dap]
---

Building the DAP client (`src/workbench/dap/dap_client.jac`), a `set_breakpoints`/`get_breakpoints`
pair worked correctly against each other (write in one RPC call, read back correctly in a later
RPC call — the ordinary, expected `glob` behavior every other stateful module in this project
already relies on: `lsp_client.jac`'s `_lsp_processes`, `workspace_service.jac`'s caches, etc.).
But the *same* `glob` dict, read from inside `start_debug_session` — a function declared
`-> Generator` and consumed as a raw SSE stream (the same shape `terminal_service.jac`'s
`run_in_terminal` already uses) — was reliably empty, even moments after a `set_breakpoints` call
in the same browser session had just written to it.

**Confirmed live, not assumed**, with two independent pieces of evidence:
1. `id(_dap_breakpoints)` printed from inside `set_breakpoints` and from inside
   `start_debug_session` were two different Python object ids across the same running server.
2. `set_breakpoints`'s own `print()` call never appeared in the server's stdout log at all — only
   `start_debug_session`'s own prints did. Two `print()` calls writing to genuinely different
   stdout streams only happens across a real OS process boundary, not merely a different Python
   module instance in the same interpreter.

An earlier, narrower theory (that `jid(root)` specifically resolves to a placeholder inside a
`Generator` function, distinct from a real per-request root) was tested and ruled out: a **bare,
unkeyed** `glob` dict (no `jid(root)` involved at all) showed the identical split — still visibly
different `id()`s and still no shared stdout. The isolation is unconditional for any `glob` state,
not specific to `root`-derived data.

`run_in_terminal` never surfaced this because it has zero need for state written by another
endpoint — every call is self-contained (spawn a subprocess, stream its output, done). The DAP
client is the first feature in this project to need a `Generator`-returning endpoint to *also* see
state a separate, later RPC call writes (breakpoints set before starting; continue/step/stop
commands sent to an already-running session) — the first place this constraint could have been hit
at all.

**Plan**: no application-level glob-based fix exists — the isolation is presumably intentional
platform behavior (SSE/streaming responses likely run on a dedicated worker/process, separate from
the request/response dispatch loop, for reasons unrelated to this project). Two workarounds landed
in `dap_client.jac`, chosen per the shape of the actual problem:
- **State needed only at spawn time** (the initial set of breakpoints): passed as an explicit
  function argument (`start_debug_session(path, lines)`) instead of read from a `glob` — the
  client already has this value, so there's nothing to bridge.
- **State needed for the lifetime of a long-running SSE session, written by later, separate RPC
  calls** (continue/step/stop): a small file-based command channel (`_DAP_COMMAND_FILE`, a fixed
  `/tmp` path — real OS-level shared state neither process's own memory needs to agree on).
  `continue_execution`/`step_over`/`step_into`/`step_out`/`stop_session` each write one `{"seq",
  "cmd"}` JSON command to it; a background task spawned *inside* the SSE function's own process
  (`_watch_dap_commands`, holding the live subprocess handle) polls the same file every 200ms and
  dispatches each new command against the connection it actually holds. This generalizes to any
  future SSE-endpoint-needs-external-input case in this project, not just this one.

A permanent, correct answer would either document this constraint explicitly (so the next SSE
feature in this codebase doesn't rediscover it via a live debugging session), or expose a real
cross-process primitive for it (the graph/Postgres persistence layer is one candidate, if the state
in question is serializable — a live subprocess handle, socket, and asyncio `Queue`/`Event` are
not, which is why the command-channel workaround above is file-based rather than graph-based).
