---
id: 2026-08-31-background-task-graph-writes-never-auto-committed
date: 2026-08-31
category: missing-feature
severity: blocker
status: workaround-found
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jaseci, persistence, asyncio, background-task, commit, lsp]
---

## What happened

Verifying the new native Jac LSP client live: `jac lsp`'s own `publishDiagnostics` notification
correctly arrived at the client (confirmed via raw debug logging of every incoming JSON-RPC
message), was correctly routed to the handler, and `add_diagnostic` genuinely returned `True` for
each diagnostic (its own in-process graph mutation succeeded, confirmed via debug logging of the
return value). But a **separate, later** `list_all_diagnostics()` call -- a completely ordinary
RPC, no different from any other -- kept coming back empty every time, across many clean
restarts and several different real compiler errors used as test content.

## Root cause

The diagnostics-writing code (`lsp_client.jac`'s `_handle_publish_diagnostics`) runs inside
`_read_loop`, a background task started once via `asyncio.create_task` (see
`2026-08-31-await-inside-test-block-fails-bytecode-compilation`'s sibling finding for why this
needed to be a genuinely persistent task in the first place) that reacts to unsolicited
notifications pushed by the `jac lsp` subprocess. **There is no HTTP request/response cycle
wrapping any of this** -- unlike every other graph write in this project so far (`add_diagnostic`
called from `task_service.jac`'s problem matchers, every `workspace_service.jac` mutation, ...),
all of which run as the direct synchronous body of a function a real client HTTP call is waiting
on. jaseci's dispatcher performs the actual durable commit in `_finalize_call_response`
(`jaclang/runtimelib/impl/server.impl.jac`), *after* a `def:pub` function returns, as part of
finishing that specific request's response -- a step that simply never happens for code with no
request to finish.

This is a **different** persistence gap from the two already documented in this project
(`2026-08-28-field-mutation-on-cached-node-not-persisted`: a mutation on a cached node not reaching
the database even *within* a normal request/response cycle; `2026-08-28-edge-deletion-not-
committed-across-real-http-requests`: an edge deletion that doesn't reliably survive *across*
separate requests). Both of those describe commits that *should* happen (there's a real request
driving them) but don't, reliably. This one is structurally different: there is no request at all
for a commit to attach to in the first place, so the gap isn't reliability -- it's that the
mechanism has no hook to fire from for this shape of code at all.

## Workaround

An explicit `await Jac.acommit()` (`import from jaclang { JacRuntime as Jac }`,
`jaclang.runtime.runtime.JacRuntime` -- **not** ambient in this project's own module context
despite a standalone scratch-file repro resolving `Jac` with no import at all; needs the explicit
import here or it fails at runtime with `name 'Jac' is not defined`) at the end of the background
handler, calling the exact same commit primitive `_finalize_call_response` calls internally.
Verified against the same live repro: diagnostics now correctly persist and are visible to a
separate, later request.

`Jac` is checker-typed as `Unknown` (the standard untyped-Python-interop boundary `jac-python-
interop`'s guide already describes), so the call site needs `(Jac as any).acommit()` to satisfy
`jac check` -- not a real type error, just the checker not resolving a runtime object it was never
going to fully type.

## Plan

Any future feature that reacts to a server-pushed, unsolicited event from a background task or
subprocess (the DAP client, later in this same phase, is the next near-certain candidate --
breakpoint-hit/stopped events from a debug adapter are exactly this shape) needs to remember this
explicit commit, every time, for every graph write made from that code path. Worth checking whether
jaseci could offer this more discoverably (a clearer error than a silently-empty-looking write when
`root`/graph mutations happen outside a request context, or documentation calling out that
`asyncio.create_task`-originated code needs an explicit commit) -- right now this is exactly the
kind of gap that's cheap to hit and expensive to diagnose (this session's own repro took extensive
live debugging: confirming the notification arrived, confirming it routed correctly, confirming
`add_diagnostic`'s own return value, before finally isolating that the write simply never reached
the database at all).
