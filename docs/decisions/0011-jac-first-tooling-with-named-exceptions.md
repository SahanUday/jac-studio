# 0011 — Jac-first tooling, with narrow, confirmed exceptions

- **Date**: 2026-08-23
- **Status**: superseded by [0067](0067-reuse-proven-libraries-for-solved-problems.md)

## Decision

Project tooling is written in Jac. Three deliberate exceptions: the translator's structural
extraction runs as a small Node subprocess, the challenge tracker's build script is Python, and
`internal/translator/land-blocker.sh` is plain bash.

## Why

The Node subprocess was confirmed necessary by a real spike, not assumed — Jac's npm interop
cannot reach the TypeScript compiler API (`npm-interop-server-only-blocked`, blocker→resolved).
The tracker's build script and the blocker-landing script touch the observability backstop
itself, so they must not depend on the thing they exist to record failures about.

## Consequences

Every future non-Jac component owes the same standard: a real spike proving the block, plus a
tracker entry — not "it was faster in Python." The same reasoning later justified
`claude_code_launcher.py` (0053) and `dap_launcher.py`.
