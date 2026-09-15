# 0013 — Cache each service node once per `root`, keyed by `jid(root)`

- **Date**: 2026-08-23
- **Status**: superseded by [0029](0029-cache-the-jid-not-the-node.md)

## Decision

Never issue a bare `[root-->[?:Type]]` at a call site. Every service accessor resolves its node
once and caches it in a module-level `glob _cache: dict[str, ServiceType] = {}` keyed by
`jid(root)` — never a single bare `X | None = None`.

## Why

A fresh graph query measured **~600us/call** under `jac run` — one lookup eats ~4% of a 16ms
frame budget, and a command dispatch chains several (`2026-08-23-service-registry-query-cost.md`).
Cached reads are ~0.06us/call. The keying is load-bearing: `root` is bound to the calling user,
and a non-keyed cache verifiably leaked one user's node into another user's request, reproduced
with two logged-in users via `JacTestClient`.

## Consequences

Superseded because "cache the reference" is wrong for anything the accessor will **mutate** (0029).
The measured cost, the mandatory per-root keying, and the ban on call-site queries all still stand.
Unbounded growth of the keyed dict (one entry per distinct root ever seen) is a known, unaddressed
gap — fine for a local single-user tool.
