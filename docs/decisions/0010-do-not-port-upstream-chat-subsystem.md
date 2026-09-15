# 0010 — Do not port upstream's chat/agent subsystem

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Exclude `workbench/contrib/chat` as a port target. Start from `by llm()` and `sem` for anything
jac-studio wants to build itself.

## Why

The subsystem is 442,661 lines — now larger than VS Code's entire editor core — and is bolted on
precisely because TypeScript has no native LLM syntax (Tier 2.5 in the gap analysis, tracked as
`2026-08-22-chat-subsystem-scale.md`).

## Consequences

This exclusion has never been reversed, including when native AI integrations came into scope
(0048) and when the plan was reframed toward richer UI (0054) — both build against our own
provider interface, not upstream's subsystem. A generic mechanism for arbitrary third-party
chat/agent extensions stays out of scope until the Phase B/C trust work exists.
