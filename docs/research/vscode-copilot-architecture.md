# Research notes: how VS Code's own AI features are actually built

Source: `/home/sahan/dev/vs/vscode` (a real, current `microsoft/vscode` checkout, `origin` =
`github.com/microsoft/vscode.git`, `main` @ `00cc2df8` as of 2026-08-21) — the actual open-source
editor, including `extensions/copilot/` (the real GitHub Copilot Chat extension source, merged
in-tree; the standalone `microsoft/vscode-copilot-chat` repo is now archived and redirects here).
Investigated 2026-09-03, prompted by a real screenshot of Copilot's Quick Fix menu (Fix/Explain/
Rewrite) during a debate about jac-studio's own AI-provider architecture. Grounding reference for
[`../architecture.md`](../architecture.md)'s "AI coding tool integrations" section — read that
document for the actual jac-studio decisions; this file only records what was found, not what was
decided.

## The one finding that matters most: two decoupled layers, not one

VS Code's chat system is explicitly split into two independent extension APIs
(`src/vscode-dts/vscode.d.ts`):

- **`chat.createChatParticipant(id, handler)`** (`vscode.d.ts:20121`) — registers *behavior*: what
  happens when a user's message is routed to this participant. A participant's `requestHandler`
  gets a `ChatRequest` (prompt, references, the currently-selected model) and a `ChatResponseStream`
  to push content back into. It can call whatever backend it wants.
- **`lm.registerLanguageModelChatProvider(vendor, provider)`** (`vscode.d.ts:20847`) — registers a
  *model backend*: `LanguageModelChatProvider` (`vscode.d.ts:20683`) is a three-method interface —
  `provideLanguageModelChatInformation` (list what models this backend offers),
  `provideLanguageModelChatResponse` (stream a response given messages, tools, and a progress
  callback), `provideTokenCount`. An example given directly in the interface's own doc comment:
  "An example of this would be an OpenAI provider that provides models like gpt-5, o3, etc."

**Why this split matters**: any registered participant can use any registered model
(`lm.selectChatModels()`), and the chat UI itself is generic over both axes. A participant is "what
agent behavior," a provider is "which model answers it" — completely orthogonal. This is a more
mature version of the same instinct behind jac-studio's own `ChatProvider` design (one interface,
swap the implementation per external tool) — VS Code's version additionally separates the *UI-facing
agent identity* from the *backend* as two different extension points, which jac-studio's current
single-provider-does-everything shape doesn't yet.

## AI code actions (the "Fix"/"Explain"/"Review" lightbulb menu) are not a special API at all

Read directly: `extensions/copilot/src/extension/inlineChat/vscode-node/inlineChatCodeActions.ts`.
`QuickFixesProvider` and `RefactorsProvider` are both ordinary `vscode.CodeActionProvider`
implementations — the exact same generic API any linter or language server uses to contribute a
quick-fix. Every action they offer ("Fix", "Explain", "Review", "Generate"/"Modify") does the same
thing under the hood: build a prompt string and either call `vscode.editorChat.start({ message,
autoSend, ... })` (opens inline chat, pre-filled) or a plain custom command. "Fix" is quite literally
`` `/fix ${diagnosticsAsText}` `` handed to the same inline-chat entry point "Explain" and "Modify"
also use. There is no Copilot-specific extension API involved in this mechanism at all — a generic
`CodeActionProvider` plus a "start a chat turn with this prompt" call is the entire pattern.

Concrete implication: jac-studio's editor is real Monaco (`@monaco-editor/react`), and Monaco itself
exposes `languages.registerCodeActionProvider` — the identical mechanism, already reachable, no
workbench-shell dependency. An "AI code actions" feature in jac-studio would be a new Monaco
provider (same category as the LSP client's existing completion/hover/definition providers) that
constructs a prompt and calls the *already-built* `start_chat_turn` SSE endpoint — no new backend
concept needed.

## Inline chat (Ctrl+I) is a Monaco editor widget, not workbench chrome

`src/vs/workbench/contrib/inlineChat/browser/` (~3,900 lines total: `inlineChatWidget.ts` 519,
`inlineChatZoneWidget.ts` 499, `inlineChatController.ts`, session services, accessibility). Built on
`ZoneWidget` — a real Monaco/editor-core concept: a floating widget anchored at a cursor/selection
position that pushes surrounding lines apart to make room (the same underlying mechanism the actual
diff/peek views use). This is editor-level UI, not workbench-shell-level — most of the line count in
upstream is Copilot-specific polish (accessibility, notebook support, edit-review sessions), not
irreducible complexity in the core mechanism itself.

## Inline completions (ghost text) are a separate, independent API

`InlineCompletionItemProvider` (`vscode.d.ts:5233`) — `provideInlineCompletionItems(document,
position, context, token)` returning items with `insertText`. Completely independent of the
chat/participant system above; this is what powers both Copilot's basic ghost-text suggestions and
"next edit suggestions." Also a real Monaco API (`languages.registerInlineCompletionsProvider`),
already reachable from jac-studio without any workbench dependency.

## What's genuinely NOT reusable

- **The actual completion/chat model backend** — GitHub's own service. Not in this repo at all;
  `extensions/copilot/`'s code is a *client* of it, same as any `LanguageModelChatProvider`
  implementation is a client of whatever backend it wraps.
- **Entitlement/subscription/billing** (`copilot_internal/*` endpoints in `product.json`) — real
  GitHub account/billing plumbing, irrelevant to any other backend.
- Confirmed via the extension's own README: even with the source open and buildable, "an active
  GitHub Copilot subscription is required" — open source here does not mean a free or local backend.

## Agent-mode session UI (multi-step, tool-call visibility)

`src/vs/workbench/contrib/chat/browser/chatSessions/` (~2,260 lines) — the richer session view for
autonomous agent runs (multiple tool calls, file changes, step tracking). Comparable in scope and
purpose to what jac-studio's existing `ai_chat.jac` sidebar panel already does at a smaller scale
(it streams `tool_use` events today) — this is an enhancement of an existing surface, not a new
mechanism, and lowest priority of the patterns found here.
