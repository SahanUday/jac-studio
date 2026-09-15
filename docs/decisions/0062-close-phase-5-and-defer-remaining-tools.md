# 0062 — Close the AI phase with two of its three named tools never started

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

Close Phase 5 and move GitHub Copilot, OpenCode, a native `by llm()` provider, and
`.claude-plugin/` bundle discovery to "Explicitly out of scope for now" — real deferred work, not
decided against, each needing its own scoping pass before it is picked up.

## Why

Decided by explicit project-sponsor direction: the phase's exit criteria were fully met by Claude
Code alone (tool approval, edit review, MCP wiring, and all three reframed UI entry points, each
live-verified). Holding the phase open around unstarted work and proposal-stage ideas was adding
status noise, not progress.

## Consequences

Picking any of these up is its own scoped effort, not a Phase 5 reopening. `by llm(tools=[...])`
is a real ReAct tool-calling loop needing no subprocess and no external CLI — but it is explicitly
**not** assumed to be a drop-in replacement for an agentic CLI (permission prompting, context
management, a curated tool set and safety guardrails all start from zero). The "Jac Agent" idea
stays tracked separately, outside the phase structure, at idea stage only.
