# 0046 — Defer `.vsix` compatibility research; it blocks nothing

- **Date**: 2026-08-31
- **Status**: accepted

## Decision

Downgrade 0043 from a Phase 4 planning item to explicitly deferred, non-blocking research,
re-sequenced into the Phase 6 extension-system track.

## Why

The language-server half of that extension's value — the actual reason it mattered — is reachable
directly today via `jac lsp` (0045), without loading the `.vsix` at all. Nothing in the
native-feature-parity milestone (0044) depends on the answer.

## Consequences

The Monarch tokenizer (0035) stays the working baseline for `.jac` highlighting until someone
picks this up. The question is still worth answering eventually — it is the concrete test case
for how much `vscode`-API compatibility a Phase B manifest should target — so it is deferred, not
decided against.
