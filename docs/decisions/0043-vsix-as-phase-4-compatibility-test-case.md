# 0043 — Use the published `jaseci-labs.jaclang-extension` `.vsix` as the compatibility test case

- **Date**: 2026-08-28
- **Status**: superseded by [0046](0046-defer-vsix-compatibility-research.md)

## Decision

Treat "can jac-studio load the real published `jaseci-labs.jaclang-extension` `.vsix`
unmodified?" as a Phase 4 planning item — the concrete test case for how much of VS Code's
`vscode` API to target.

## Why

It is a real, published extension shipping both a 4,937-line `jac.tmLanguage.json` TextMate
grammar (far richer than the Monarch stopgap in 0035) and a real language server — a better
compatibility yardstick than an abstract API-surface debate.

## Consequences

Downgraded three days later (0046) once it became clear the *language-server* half of its value
was reachable directly via `jac lsp` (0045), without loading anything. The grammar half remains a
legitimate reason to eventually answer the question — just not on the critical path.
