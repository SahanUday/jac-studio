# 0017 — Translate a module's real dependencies when that data *is* the module's job

- **Date**: 2026-08-23
- **Status**: accepted

## Decision

`interval-tree`'s "leave `Range`/`ModelDecorationOptions` as untyped placeholders, the tests never
touch them" move applies only when the tests genuinely never touch them. For the piece-tree
buffer, `Position`, `Range`, `WordCharacterClassifier` and a subset of `textModelSearch.ts` were
translated for real.

## Why

The buffer's entire job is line/offset math and its ported tests construct and check
`Position`/`Range` values field-by-field. Building a placeholder for a class whose shape nothing
verifies means guessing — `interval-tree`'s `set_options()` was deliberately left unported for
exactly that reason.

## Consequences

A target's real dependency surface is not visible until the target is read in full; the
translator's target list will keep under-counting work. Deferred placeholders are a debt with a
named trigger (port it once the real class exists), not a permanent shape.
