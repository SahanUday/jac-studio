# 0061 — Pin `ClaudeAgentOptions.model` to `"haiku"`, permanently

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

`claude_code_launcher.py` pins the model to `"haiku"` — a standing choice for all AI-integration
work, not a temporary setting for the PR it first appeared in.

## Why

Every feature in the AI phase is exercised for real (real server, real API calls) per this
project's "verify empirically" discipline; pinning to the cheapest model keeps that affordable
across the whole run of the work. Decided explicitly by the project sponsor mid-Phase-5.

## Consequences

Do not "upgrade" this pin as an incidental improvement, and do not remove it when refactoring the
launcher — it is a deliberate cost decision with an owner. If a feature genuinely needs a larger
model, that is a decision to raise, not a default to change.
