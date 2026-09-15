# 0003 — The graph reachable from `root` is the service registry

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Model a service (config, command registry, file-tree, session) as a `node` created once and
attached to `root`, reached by graph query, instead of building a DI container equivalent to
`IInstantiationService`/`createDecorator`.

## Why

Jac already has persistent object identity and a registry; VS Code's 580k-line `platform` layer
exists largely because TypeScript does not. Validated in Phase 0 by a real three-service slice
(`internal/service-registry-spike/`): get-or-create idempotency and cross-service interaction
hold up.

## Consequences

Validation came with two mandatory implementation rules that are not optional decoration — the
per-root cache (0013, corrected by 0029) and the test-reset hook (0014). Being a node is itself a
choice, not the default (0015). Do not re-open "graph registry or `glob` singletons?" — it was
decided with real code, not in the abstract.
