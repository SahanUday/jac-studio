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

## Full audit, 2026-09-03: every one of the 84 top-level files/dirs in `chat/browser/`, categorized

Prompted directly by "get all possible capabilities, not everything" — the sections above came from
following one screenshot's lead, not a systematic pass. This is the systematic pass: every entry in
`src/vs/workbench/contrib/chat/browser/` (`ls` count: 84), read or at minimum opened, not inferred
from filenames alone for anything listed as a real finding below.

### New real findings (not covered above)

**Tool approval/confirmation is a whole real subsystem, and jac-studio currently has none of it.**
`tools/languageModelToolsConfirmationService.ts` (read directly) implements a genuine "approve this
tool call" flow: per-tool confirmation prompts, an `IAutoConfirmEntry` store so a user's "always
allow" choice persists, `RUN_WITHOUT_APPROVAL`/`CONTINUE_WITHOUT_REVIEWING_RESULTS` as distinct,
separately-grantable permissions. `chatToolRiskAssessmentService.ts` (sibling file, not read in
full, name/import-graph confirms role) assesses risk before a tool runs. jac-studio's Claude Code
integration today has **zero UI for this** — `claude_code_launcher.py` runs with whatever
`ClaudeAgentOptions.permission_mode` default the SDK applies, entirely invisible to the user in
jac-studio's own chrome. This is the single most concrete, real gap found in this whole audit.

**`chatEditing/` (20 files, `chatEditing.ts` + `chatEditingSession.ts` +
`chatEditingCheckpointTimeline.ts`/`chatEditingCheckpointTimelineImpl.ts` +
`chatEditingModifiedFileEntry.ts`/`chatEditingModifiedDocumentEntry.ts`/
`chatEditingModifiedNotebookEntry.ts` + `chatEditingExplanationWidget.ts` + more) is a real,
sizable feature, bigger than first estimated.** Not a simple "show a diff, click accept" — a
**checkpoint/timeline mechanism** (rollback points across an editing session, not just per-file
undo), separate tracking for text vs. notebook documents, and an "explanation" widget surfacing why
an edit was made. `ai_chat.jac` today has no equivalent at any scale: Claude Code's own file edits
(via its Edit/Write tools) land on disk directly, with no review, diff, or rollback surface inside
jac-studio at all.

**The single strongest finding of this whole investigation: VS Code natively parses a portable,
non-Copilot-specific AI-plugin format that already includes Claude Code's own format.** Read
`src/vs/platform/agentPlugins/common/pluginParsers.ts` directly. `PluginFormat` is an enum with four
values: `Copilot`, `Claude`, `OpenPlugin`, `AgentPlugin`. The `Claude` format config
(`CLAUDE_FORMAT`, line 172) expects `.claude-plugin/plugin.json` as its manifest and
`hooks/hooks.json` for hooks — **the exact directory convention Anthropic's own Claude Code CLI uses
for its plugin system**, not a Copilot invention. A plugin bundle (`IAgentPlugin`,
`agentPluginService.ts`) can carry `hooks`, `commands`, `skills`, `agents`, `instructions`, and
`mcpServerDefinitions` — precisely the same customization surface `.claude/` directories already
use (this very Claude Code session's own skills/hooks are that exact shape). There is also a
distinct `OpenPlugin` format (`.plugin/plugin.json`) that reads as a deliberate attempt at a
vendor-neutral standard, independent of both Copilot and Claude specifically. `agentPluginEditor/`
+ `pluginInstallService.ts`/`pluginMarketplaceService.ts`/`claudePluginRecommendations.ts` (the
files originally flagged as "uncertain") are the UI/install/marketplace layer built on top of this
parser — installable, enablable/disablable, sourced from git repos or a marketplace.

Concrete implication: jac-studio's Claude Code provider already talks to real Claude Code, which
already understands `.claude-plugin/` bundles natively (skills/hooks/agents/commands/MCP servers).
A jac-studio feature that discovers and surfaces `.claude-plugin/`-formatted bundles a user has
installed (or lets them install one from a git URL) would need **no new format design at all** —
it's parsing an already-open, already-documented format that the underlying tool already consumes,
not inventing a jac-studio-specific plugin system from scratch.

**Reusable prompt/skill files (`promptSyntax/`)** confirmed as a real, generic pattern, not
Copilot-specific: `skillActions.ts`, `hookActions.ts`, `chatModeActions.ts` (custom modes),
`newPromptFileActions.ts`/`promptFileActions.ts` (user-authored `.prompt.md`-style files),
`runPromptAction.ts`. This is the UI-side counterpart to the plugin-format finding above — the same
skills/hooks/agents concepts, but authored loosely in a workspace rather than packaged as an
installable plugin bundle.

### Correction to an earlier claim: `chatStatus/` is not a clean generic pattern

The previous version of this doc listed "cost/usage in the status bar" as cheap and reusable,
inferring purely from the directory name. Reading `chatStatusEntry.ts` directly shows this file is
almost entirely **Copilot's own quota/entitlement UI** — `ChatQuotas`, `premiumChat.percentRemaining`,
`isQuotaBlocked`, a `computeQuotaResumeState` state machine tied specifically to Copilot's
subscription-plan quota resets. Little to none of this implementation is generic. The *underlying
idea* (surface per-turn cost/usage in the status bar) is still valid and still cheap for jac-studio —
`ResultMessage.total_cost_usd`/`usage` are already received by `claude_code_client.jac` and
currently discarded — but there is no VS Code implementation worth mirroring for it; it would be a
small, from-scratch addition, not a port.

### Confirmed correctly excluded, no changes from the first pass

`chatPetAchievements*` (4 files), `chatQuotaNotification.ts`, `chatPromoNotification.ts`,
`chatSetup/`, `chatRepoInfo.ts`, `githubRepoFetcher.ts`, `telemetry/`, `feedbackSurvey/`,
`copilotCliEventsUri.ts` — GitHub-account/billing/telemetry/gamification specific, no backend or
audience for any of it outside Copilot's own product. `voiceClient/`, `voiceInputMode/`,
`speechToText/`, `pcmCaptureWorklet.ts` — a real, working feature (voice input), not excluded on
principle, just clearly lower priority than anything above and not investigated further here.
