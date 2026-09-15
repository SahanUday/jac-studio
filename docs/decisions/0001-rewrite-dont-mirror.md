# 0001 — Rewrite, don't mirror

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Do not transliterate VS Code's TypeScript into Jac. Where upstream's solution shape exists only
because TypeScript/Electron lacked a primitive Jac already has, redesign it in Jac's grain.

## Why

VS Code's constructor-injected DI, hand-written RPC protocol, always-on OS access from the main
process, and `.code-workspace` file format are all workarounds for missing language primitives.
Jac has a persistent graph, inferred codespace placement/RPC, and a capability system already.

## Consequences

Commits us to the service registry (0003), `root spawn` cross-boundary calls (0006), the
capability-gated terminal (0007), multi-root workspaces falling out of the graph (0004), and
excluding upstream's chat subsystem (0010). It does *not* license reinventing solved algorithms:
the TS→Jac translator still applies where the problem, not the source language, dictates the
shape (0002). A future session should not "restore fidelity to upstream" by rebuilding a DI
container or an RPC protocol file — those absences are deliberate.
