# 0042 — Stage the `Diagnostic` node type before any producer exists

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Ship a `Diagnostic` node type attached to `File` as data-model-only, deliberately first and
alone, with no code writing to it yet.

## Why

Phase 4's task-runner/problem-matcher work and the later language-intelligence work both need
somewhere to write from day one; the bullet was explicitly scoped as "just the data model", not
as an unfinished feature.

## Consequences

A schema landing ahead of its producers is deliberate here, not dead code to prune. It also made
a latent bug visible for the first time: diagnostics were the first feature to attach durable
per-file state via a custom edge type, which is how
`2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open` (still open) was found.
