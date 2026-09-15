# 0047 — The DAP client is native infrastructure, alongside the LSP client

- **Date**: 2026-08-31
- **Status**: accepted

## Decision

Move the Debug Adapter Protocol client out of the extension-dependent future and into the same
native-infrastructure phase as the LSP client, built as its own scoped workbench-core subsystem.

## Why

Same category of problem for the same reason: a debug adapter is just another subprocess speaking
a JSON wire protocol, needing nothing beyond the process-spawn mechanism the terminal already
established. It does not fall out of the general extension-contribution model — it won't — so it
gets its own design effort.

## Consequences

Extensions can later plug into it the way they do upstream, but nothing waits on that. The
remaining open question at the time was only whether a Python DAP client library was reachable
via interop — answered by 0050. Real debugging (breakpoints, stepping, call stack, variable
inspection) is core, unlike "run without debugging", which is nearly free once the terminal
exists.
