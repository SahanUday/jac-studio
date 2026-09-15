# 0002 — Redesign / translate / build-fresh decision procedure

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Classify each upstream feature with two questions, lazily, at the start of the phase that needs
it: (1) is its complexity caused by a TS/Electron limitation? → **redesign**. If inherent to the
problem: (2) is it small, self-contained, and covered by upstream tests? → **translate**;
otherwise → **build fresh**.

## Why

A one-time upfront judgment across all 158 triaged feature areas would be designing years ahead
of the work, against a moving-target language. "Build fresh" needs naming as its own bucket:
Monaco's rendering/interaction layer is neither TS-shaped nor a clean translatable unit.

## Consequences

Each phase owes this classification explicitly, not by assumption — Phase 3 confirmed after the
fact that no PR used the translator and that this was correct, by classifying every PR against
the procedure. Mechanically translating a large, DOM-coupled, untested module is ruled out: it
just produces a Jac-flavored mess.
