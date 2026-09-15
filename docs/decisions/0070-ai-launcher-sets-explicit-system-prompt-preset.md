# 0070 — The AI launcher sets an explicit system prompt preset

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

`claude_code_launcher.py` passes the `"claude_code"` system prompt preset explicitly, rather than
leaving `system_prompt` at the SDK's `None` default.

## Why

A report that looked like a file-tree bug wasn't one: the model wrote a scratch file to `/tmp`
instead of the open workspace. `None` sends the CLI an explicit empty custom prompt, which skips
the CLI's entire default system prompt — including the `<env>Working directory: ...</env>` block
that tells the model where it actually is. With no such context, it fell back to `/tmp` for a
scratch-sounding filename. Traced through the installed SDK's source and cross-checked against a
real Claude Code CLI checkout. This is an independent flag from [ADR 0069](0069-ai-chat-fully-isolates-from-host-claude-md.md)'s
`setting_sources` — fixing one does not fix the other.

## Consequences

Any future `ClaudeAgentOptions` change must keep an explicit `system_prompt` preset — leaving it at
the SDK default silently drops the model's own knowledge of the working directory, with no error.
