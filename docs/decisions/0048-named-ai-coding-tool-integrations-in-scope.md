# 0048 — A small, named set of AI coding-tool integrations is in scope

- **Date**: 2026-08-31
- **Status**: accepted

## Decision

Per explicit project-sponsor direction, integrate a short named list — GitHub Copilot, OpenCode,
Claude Code — as its own deliverable, each driven as a capability-gated subprocess speaking
JSON-RPC or its own SDK, streamed back via the SSE/`Generator` pattern. `by llm()`/`sem` stay a
first-class native option, not superseded.

## Why

Real-world precedent for the mechanism: even inside VS Code, Copilot's inline-completion path runs
a bundled `copilot-language-server` subprocess speaking an LSP-like protocol, not primarily the
chat-extension APIs. So the realistic shape is the same subprocess pattern `jac lsp` and the
terminal already use — no `vscode`-chat-API shim.

## Consequences

This is a short list of integrations, not a platform: a generic mechanism for *arbitrary*
third-party chat/agent extensions needs the Phase B/C trust work and stays deferred. Porting
upstream's chat subsystem (0010) stays excluded. Each tool needs its own scoping pass
(auth/licensing, subprocess surface, UI surface) before implementation — only Claude Code ever
got one (0053, 0062).
