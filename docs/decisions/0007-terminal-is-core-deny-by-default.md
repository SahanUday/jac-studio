# 0007 — The integrated terminal is core, behind a deny-by-default shell capability

- **Date**: 2026-08-22
- **Status**: superseded by [0025](0025-terminal-gate-is-jac-toml-flag.md)

## Decision

Ship the integrated terminal in the workbench-shell MVP, not a later extension phase: an xterm.js
UI, a walker that spawns the real OS process, output streamed back over SSE — gated behind the
`@jac/desktop` `shell` capability, deny-by-default and explicitly granted in `jac.toml`.

## Why

VS Code's terminal is core too (no language knowledge, no extension involved), and you should be
able to run something in the earliest usable build. The capability gate is a genuine security
improvement on Electron's always-on OS access from the main process.

## Consequences

Superseded only in *mechanism*: jac-studio ships as `kind = "web-app"`, so the `@jac/desktop`
capability is unreachable and 0025 reproduces the same posture through `jac.toml`'s `[terminal]`
section. The "core, not an extension" and "deny-by-default" halves still stand, and every later
subprocess feature (LSP, DAP, AI tools) reuses this gate rather than inventing its own (0051).
