# 0006 — Cross-boundary calls are `root spawn`, not a hand-written RPC protocol

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Client→server calls are `root spawn SomeWalker(...)` / ordinary `def:pub` calls, letting the
compiler infer the codespace boundary. No protocol file, no `IChannel`/`IServerChannel`
transport abstraction, no counterpart to `extHost.protocol.ts`.

## Why

Jac's inferred codespaces already solve the problem VS Code's RPC layer exists for. This
collapses an entire upstream architectural layer into "just call the walker."

## Consequences

Rules out hand-maintaining a protocol file. It explicitly does **not** solve the
workbench↔extension-host boundary (0008): that is a *trust* boundary, not a codespace boundary,
and RPC inference implies no sandboxing. Later work found real limits on what crosses these
boundaries safely — see 0049 and 0064 for SSE-generator isolation.
