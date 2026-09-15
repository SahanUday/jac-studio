# 0063 — Do not split `ChatProvider` until a second provider exists

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

Deliberately leave undecided whether the provider shape should split into two layers the way VS
Code's `chat.createChatParticipant` / `lm.registerLanguageModelChatProvider` do (agent-behavior
identity vs. model backend, fully decoupled). Revisit once a *second* external-tool provider is
actually built.

## Why

Splitting now, with one provider shipped, would be exactly the premature generalization this
project's own implementation discipline warns against — there is no second data point to design
against.

## Consequences

This is an open question recorded as a decision to wait, not a rejection of the split. It does not
depend on any phase being open: only on a second provider eventually existing. Anyone building
Copilot or OpenCode (0062) should treat this as the first design question to answer, with real
evidence in hand.
