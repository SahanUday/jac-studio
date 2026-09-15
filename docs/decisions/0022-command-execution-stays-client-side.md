# 0022 — Command execution stays client-side; only metadata lives server-side

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

`CommandRegistry`/`Command` nodes hold `command_id`/`title`/`keybindings` for discovery and
display; `workbench.jac`'s `handle_command` is the single place mapping an id onto a client-side
ability. Add a server-side `run_command` only when a command genuinely needs one.

## Why

Reasoned through before building the palette: every Phase 2 command is a workbench UI-state
mutation (split a group, close a tab, toggle the terminal) with no server-side effect to invoke.

## Consequences

The command registry is the first real consumer of the contribution-registry pattern, but only
for metadata — a future extension system cannot assume a server-side dispatch path already
exists. Adding one is a deliberate extension of this decision, not a bug fix.
