# 0051 — LSP and DAP subprocesses reuse the terminal's capability gate

- **Date**: 2026-09-02
- **Status**: accepted

## Decision

Spawning `jac lsp` and `python -m debugpy` is gated behind the same `[terminal] enabled` flag as
the terminal itself (0025), not a new per-feature capability.

## Why

Both are subprocess execution — the same trust class already gated project-wide. Inventing a
second boundary would give the appearance of finer-grained control without any real difference in
what is being permitted.

## Consequences

Turning the terminal off disables language intelligence and debugging too, which is the honest
consequence of them being the same capability. If per-capability granularity is ever wanted, it
is a deliberate redesign of the gate, not a bug fix — and it should happen at the same time for
every subprocess feature, including the AI integrations.
