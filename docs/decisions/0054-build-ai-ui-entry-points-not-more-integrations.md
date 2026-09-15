# 0054 — Build AI UI entry points against one provider interface, not more integrations

- **Date**: 2026-09-03
- **Status**: accepted

## Decision

Reframe the AI phase: richer AI UX means new *UI entry points* (code actions, inline chat, session
visualization) against the already-shipped `start_chat_turn` interface, not three more subprocess
integrations.

## Why

A real `microsoft/vscode` checkout's Copilot Chat source (now merged in-tree) shows its
"Fix"/"Explain"/"Review" quick-fix menu, inline chat and inline completions are all built on
generic, backend-agnostic APIs — `CodeActionProvider`, a `ZoneWidget`,
`InlineCompletionItemProvider` — none of them Copilot-specific. jac-studio embeds real Monaco, so
those APIs are already reachable, and each ultimately just constructs a prompt and hands it to a
generic "start a chat turn" entry point.

## Consequences

Backend reuse is total: AI code actions route through the existing sidebar via an `onAskAI`
callback threaded down the same chain `onOpenLocation` already uses, with no new endpoint. The
code-action provider registers for `"*"` (every language) — explaining code is useful outside
`.jac` files, unlike the LSP-backed providers. Auto-send for self-contained "Fix"/"Explain",
prefill-only for "Modify", matching upstream's own `autoSend` distinction.
