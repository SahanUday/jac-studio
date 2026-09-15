# 0060 — A tool call is three events joined by `tool_use_id`

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

The launcher's single bare `{"type": "tool_use", "name": ...}` event becomes
`tool_use_start` (at `content_block_start`, id+name only), `tool_use_input` (from the completed
`AssistantMessage`'s `ToolUseBlock`) and `tool_result` (from the `UserMessage`/`ToolResultBlock`),
all sharing `tool_use_id` — the same pairing shape `tool_approval_request`/`approve_tool_call`
already established. `ai_chat.jac` renders a structured step card per call.

## Why

The full `input` dict does not exist yet at `content_block_start` — confirmed live that the
completed message is the first point it does. Also confirmed live: a `can_use_tool` denial reaches
the client through the *identical* `tool_result` event as a real execution, arriving as
`is_error=True` content rather than through any separate mechanism.

## Consequences

That last finding let `handle_approval_decision` drop its optimistic local "[Allowed X]" note
entirely — the authoritative `tool_result` updates the card shortly after either decision, so the
note was redundant and could race it. Do not reintroduce an optimistic local note. Step cards are
collapsed by default (a later QA round), matching Copilot Chat's own precedent.
