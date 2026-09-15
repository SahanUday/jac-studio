# 0056 — Gate every agent tool call behind an explicit approval card

- **Date**: 2026-09-03
- **Status**: accepted

## Decision

Wire `ClaudeAgentOptions.can_use_tool` in the launcher: it emits a `tool_approval_request` over
the existing SSE stream and blocks the call by polling a `/tmp` decision file; `ai_chat.jac`
renders an approve/deny card per pending request, tracked by the SDK's own `tool_use_id`. No
"always allow this tool" persistence in this slice.

## Why

The SDK's default `permission_mode` meant a silent, outright **deny** for anything needing a
prompt — confirmed live, a plain `Write` and a plain MCP tool call were both blocked with no way
for the user to say yes, and entirely invisible in jac-studio's UI. The highest-priority gap from
the audit of all 84 entries in upstream's `chat/browser/`: trust/safety, not polish.

## Consequences

Uses 0049's cross-process file channel, for the same reason (launcher and decision-carrying RPC
are different processes). A decision must never be logged as a separate `{"role": "tool"}` chat
entry — that broke the "last message is the live assistant response" invariant `text_delta`
depends on and concatenated Claude's resumed text onto it, reproduced live. A persisted per-tool
trust store (upstream's `IAutoConfirmEntry`) is real follow-up work, deliberately not here.
