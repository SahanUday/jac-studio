# 0012 — Translator supervision scales with risk tier

- **Date**: 2026-08-23
- **Status**: accepted

## Decision

Small, pure modules run the translate→verify loop with light supervision. A `foundational`
risk-tier target (the piece-tree buffer — everything else depended on it) gets a single-module
session with real review plus differential testing beyond ported-test parity.

## Why

Hybrid automation by risk tier was chosen instead of one uniform level of rigour: uniform-light
would have shipped the highest-stakes translation unreviewed, uniform-heavy would have made the
small targets uneconomic.

## Consequences

`risk_tier` in `internal/translator/manifest.toml` is load-bearing metadata, not documentation.
Differential testing against a naive oracle (used for `interval-tree`: 18 generated regressions
asserting tree invariants after every mutation) is the expected standard for a tree/graph
algorithm, not an optional extra.
