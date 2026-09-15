# 0025 — The terminal's capability gate is `[terminal] enabled` in `jac.toml`

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

Gate process spawning behind jac-studio's own `[terminal] enabled` flag, read via
`JacConfig.get_section` — reproducing 0007's deny-by-default posture with a mechanism this
project's runtime can actually reach.

## Why

jac-studio ships as `kind = "web-app"`, not `desktop`, so the `@jac/desktop` `shell` capability
0007 originally specified is unreachable.

## Consequences

Deny-by-default is jac-studio's own convention, not the platform's — nothing enforces it for us,
so every new subprocess-spawning feature must opt into this gate explicitly (0051 did, for LSP
and DAP; the Claude Code client did too). If desktop packaging (0009) ever lands, revisit whether
the real `shell` capability should back this flag.
