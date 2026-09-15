# 0050 — Use `debugpy` directly as the DAP adapter against jaclang bytecode

- **Date**: 2026-09-02
- **Status**: accepted

## Decision

Drive `debugpy` as the debug adapter for `.jac` source, with no source-translation or mapping
layer in between.

## Why

Confirmed live, end to end, *before* writing a line of the client: jaclang ships no DAP server of
its own, but `debugpy` works directly against jaclang-compiled bytecode —
`co_filename`/line tables map 1:1 to real `.jac` source. Tracker entry
`2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source`.

## Consequences

Breakpoints, stepping, call stack and variable inspection are a real DAP session, not a `pdb`
shim dressed up as one. Answers the last open research question from 0047. A missing `debugpy`
must be reported explicitly — it originally surfaced as a silent 15-second timeout with a generic
failure message and nothing to diagnose from.
