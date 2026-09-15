# 0014 — Every service module exports a test-only cache reset hook

- **Date**: 2026-08-23
- **Status**: accepted

## Decision

Each service module exports `_reset_<x>_cache_for_tests()`, clearing the whole keyed dict, and
every test exercising that accessor calls it.

## Why

`jac test` reuses a worker process across tests, and `jid(root)` is the *same* identity across
different tests in one worker even though each test's graph content is isolated — verified
directly, keying by root alone still leaked a value from one test into the next
(`2026-08-23-service-cache-test-isolation.md`).

## Consequences

Two different problems (cross-user leakage, cross-test leakage), two different fixes; neither
substitutes for the other. A future session that "simplifies away" the reset hook because the
cache is already keyed will reintroduce cross-test leakage, and the failure will look like a
flaky test rather than a cache bug.
