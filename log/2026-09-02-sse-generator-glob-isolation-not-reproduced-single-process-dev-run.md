---
id: 2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run
date: 2026-09-02
category: doc-gap
severity: major
status: open
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [sse-streaming, glob-state, process-isolation, ai-tool-integration]
---

Found running the same Phase 5 isolation spike as
`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure` (see that entry
for the module setup). Directly contradicts, under this entry's own test conditions, the earlier
`2026-08-31-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state` finding from
`dap_client.jac` -- flagging as a real discrepancy to reconcile, not asserting the earlier entry
was wrong.

## What the earlier entry found

`dap_client.jac`'s own docstring: "A `glob` written by one RPC call was still empty when read
moments later from inside `start_debug_session`'s own body ... confirmed by comparing `id()` on
both sides (different objects) and by one side's `print()` never appearing in the server's stdout
log at all." Conclusion there: a `Generator`-returning SSE endpoint runs in a genuinely separate
OS process from every other `def:pub`/`async def:pub` in the same module, with no shared `glob`
state at all -- the reason `dap_client.jac` uses a file-based command channel instead.

## What this entry found -- the identical test, different result

A throwaway probe module (`_isolation_probe.jac`, since deleted) defined the same shape: a plain
`def:pub write_probe(value)` writing to a module `glob _probe_state: dict[str, str]`, and a
`Generator`-returning `async def:pub read_probe_stream` that reads the same glob and reports
`os.getpid()` + `id(_probe_state)` as its very first yielded event, before doing anything else.

Sequence, against a real `jac run --no-client` server:

1. `POST /function/write_probe {"value": "hello-final"}` -> `{"pid": 579708, "obj_id":
   127642624822272, "stored": "hello-final"}`
2. `POST /function/read_probe_stream {}` (SSE) -> first event: `{"pid": 579708, "obj_id":
   127642624822272, "seen_value": "hello-final"}`

**Identical pid, identical `id()`, and the write was visible.** No isolation observed -- the
opposite of the DAP finding, under what looks like the same mechanism (a plain RPC call followed
by a `Generator`-returning SSE call in the same module, same server process).

## What's NOT yet ruled out

This is one data point under one specific configuration, not a controlled comparison against the
exact conditions of the original finding:

- **jaclang version/build**: this ran under `jac 0.37.1` (dev mode, local `jaseci/jac` source
  checkout) -- unknown whether the original DAP finding was made against the same build, an
  installed package version, or a different commit. `jac.toml` pins `jac-version = "==0.36.1"`,
  one minor version behind what's actually running dev-mode.
- **Server invocation**: this entry ran `jac run --no-client` (single process, no hot-reload
  watcher actively rebuilding). Whether `--dev`/hot-reload mode, or a genuinely concurrent
  multi-request scenario, changes the isolation behavior is untested.
- **Whether the DAP-specific isolation was really about `Generator`-returning functions in
  general, or something narrower to `start_debug_session`'s own shape** (e.g. a long-lived
  connection interacting with `asyncio` event-loop-per-worker behavior under real concurrent load,
  which a single sequential curl test here would not surface).

## Plan

Do not treat either finding as the settled default for Phase 5's real `ChatProvider` work without
reconciling this first. Concretely:

1. Re-run this entry's exact probe shape against whatever exact jaclang build/version the original
   `dap_client.jac` finding was made under, if that's recoverable (check the PR #52-#60 timeframe's
   `jac --version` output, or the jaseci commit at that time).
2. Test under real concurrency (two overlapping SSE requests, or an SSE request racing a plain RPC
   call mid-stream) rather than only sequential requests -- the original finding's own framing
   ("read moments later from inside `start_debug_session`'s own body") suggests it may have
   involved a background task or a longer-lived connection, not a simple two-request sequence.
3. Until reconciled, **default to the safer assumption (DAP's: no shared glob state)** for any new
   SSE-streamed client that needs cross-request state (e.g. a future `ChatProvider`'s mid-session
   "send another message"/"cancel" controls) -- reuse `dap_client.jac`'s file-based command channel
   pattern rather than relying on this entry's single, unconfirmed observation of shared state.
