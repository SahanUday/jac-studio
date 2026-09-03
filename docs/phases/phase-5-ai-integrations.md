# Phase 5 — Native AI coding-tool integrations

Status: **complete** — 2026-09-04, closed by explicit project-sponsor direction. Exit criteria in
[`../roadmap.md`](../roadmap.md) are met: Claude Code is usable end to end inside jac-studio for a
real coding task, with its own auth flow and output surfaced through Phase 4's Output/notification
infra. This doc stays as the record of how Phase 5 actually went; Phase 6 (extension system, Phase
B) is next per the roadmap's own ordering, though nothing in it depends on this phase's closure.
Read this before touching the Claude Code integration again — it's the fastest way to get oriented
without re-reading eight PRs and two research docs from scratch.

## Goal (from roadmap.md)

A small, explicitly-named set of external AI coding tools work natively inside jac-studio, without
building a generic mechanism for arbitrary third-party chat/agent extensions to plug in (that stays
deferred to the extension-system Phase B/C track). Exit criteria: at least one of the three named
tools (GitHub Copilot, OpenCode, Claude Code) usable end to end for a real coding task, not a
mock/demo, with its own auth flow and output surfaced through the Output/notification infra.

## What was actually built (PRs #69–#76)

- **#69 — Native Claude Code chat integration.** The foundation: `claude_code_client.jac`
  (subprocess-only, gated behind `[terminal] enabled`) + `claude_code_launcher.py` (plain Python,
  not `.jac` — see "Key decisions" below) + `ai_chat.jac`'s sidebar panel. Real SSE streaming, real
  multi-turn continuity via the SDK's own `resume` mechanism. Met this phase's exit criteria on its
  own.
- **#70 — Reframe AI-integration plan (docs-only).** Two research passes (a live `microsoft/vscode`
  checkout's actual Copilot Chat source; jaseci's own native agentic capabilities) found Copilot's
  own "Fix"/"Explain" quick-fix menu, inline chat, and inline completions are all built on generic,
  backend-agnostic Monaco/editor APIs, not Copilot-specific mechanisms — reframing the rest of this
  phase from "build three more subprocess integrations" to "build new UI entry points against the
  one provider interface already shipped." See `architecture.md`'s "Reframed 2026-09-03" subsection
  and both linked research docs for the full reasoning.
- **#71 — MCP wiring.** `jac mcp` (a real, working first-party MCP server — confirmed via
  `jac mcp --inspect`: 140 resources/19 tools/9 prompts) pointed at from `claude_code_launcher.py`'s
  `ClaudeAgentOptions.mcp_servers`, giving Claude Code structured Jac-specific tools instead of
  shelling out through Bash for the same work.
- **#72 — Tool approval/confirmation.** The single most-flagged trust/safety gap from the reframe's
  own audit: without it, every Edit/Write/Bash/MCP call ran with the SDK's silent non-interactive
  default (confirmed live: a plain `Write` call was outright denied, invisibly). Wired
  `ClaudeAgentOptions.can_use_tool` to emit an approval-request event and block on a real
  approve/deny card in `ai_chat.jac`.
- **#73 — Multi-file edit review.** A real Monaco diff (`ai_tool_diff_preview.jac`) inside each
  `Edit`/`Write` approval card, computed server-side before the tool call ever runs — closes the
  second trust/safety gap the same audit surfaced (a silent overwrite with no preview).
- **#74 — AI code actions.** The "Fix"/"Explain"/"Modify" lightbulb menu
  (`ai_code_action_provider.jac`, a Monaco `CodeActionProvider` registered for every language),
  routing through the already-shipped sidebar via a new `onAskAI` callback — no new backend call.
- **#75 — Inline chat.** A `Ctrl+I` popover (`inline_chat_widget.jac`), a real Monaco content
  widget with React content mounted via `ReactDOM.createPortal` — the first case in this project of
  React rendering into a Monaco-owned DOM node rather than the other direction. Found and fixed a
  real, previously-undiscovered bug along the way: Monaco's standalone `addCommand` doesn't scope
  keybindings per editor instance, which also silently affected the pre-existing `Ctrl+S`.
- **#76 — Richer agent-session visualization.** Replaced the plain `"[Using X...]"` text marker
  with a structured step card per tool call (name, input, running/done/error status, real result
  text), driven by widening the launcher's single bare `tool_use` event into a three-event
  lifecycle (`tool_use_start`/`tool_use_input`/`tool_result`).

Every PR above was live-verified end to end (`jac browse` against a real `jac run --serve --dev`
session, real credentials, screenshots), not just `jac check`/`jac test` — see each PR's own
description and `architecture.md`'s corresponding numbered item for the full verification record.

## Key decisions made

- **`claude_code_launcher.py` is plain Python, never imported into `.jac`-compiled code.**
  `import claude_agent_sdk` pulls in a dependency closure (mcp, pydantic, httpx2, truststore,
  click) that explodes jaclang's own compiler/type-checker with hundreds of errors — confirmed live
  before this design was settled, not assumed. Mirrors `dap_launcher.py`'s identical role for
  debugpy.
- **The tool-approval decision crosses OS processes via a hardcoded `/tmp` file**
  (`_TOOL_APPROVAL_FILE`), reusing `dap_client.jac`'s `_DAP_COMMAND_FILE` pattern verbatim — the
  launcher, and the separate RPC call carrying the user's decision, are different processes with no
  shared `glob` state reaching between them.
- **A tool call's full lifecycle is three events sharing `tool_use_id` as the join key**
  (`tool_use_start`/`tool_use_input`/`tool_result`), the same pairing shape
  `tool_approval_request`/`approve_tool_call` already established — confirmed live (a direct
  `query()` probe against the SDK) that a `can_use_tool` denial reaches the client through the
  identical `tool_result` event as a real execution, which let `handle_approval_decision` drop a
  redundant local note it no longer needed.
- **`ClaudeAgentOptions.model` is pinned to `"haiku"`, permanently, not just for one PR's live
  testing.** Every feature in this phase was exercised for real (real server, real API calls) per
  jac-studio's own "verify empirically" discipline — pinning to the cheapest model keeps that
  affordable across the whole run of AI-integration work, decided explicitly by the project sponsor
  mid-Phase-5 (2026-09-04) to apply going forward, not only to the PR it was first added for.
- **Synthetic Monaco model URIs are keyed by `tool_use_id`, not just file path**
  (`ai_tool_diff_preview.jac`), extending `scm_diff_editor.jac`'s established pattern one step
  further — this card, unlike a single git diff view, can have multiple concurrent pending requests
  against the same file.
- **A module-level keybinding registry (`_focused_editor_handlers`) replaces Monaco's own
  per-instance `addCommand` routing**, found necessary while wiring `Ctrl+I`: with more than one
  editor tab mounted (the normal case), only the last-registered handler for a chord ever fires,
  regardless of which editor has real focus. `Ctrl+S`/`Ctrl+I` are now registered exactly once,
  globally, dispatching dynamically to whichever editor `hasTextFocus()` at invocation time.

## Deviations from the original plan (found by actually building, not assumed upfront)

- **Only one of the three originally-named tools (Claude Code) was actually built.** GitHub Copilot
  and OpenCode were both named in the original Phase 5 scope but never started — see "What's left"
  below for where they live now.
- **The reframe (PR #70, 2026-09-03) changed the shape of "the rest of this phase" mid-flight**,
  from "three more subprocess integrations" to "new UI entry points against the one provider
  already shipped" — a real finding from reading VS Code's actual Copilot Chat source, not a
  planning guess.
- **MCP wiring landed in `claude_code_launcher.py`, not `claude_code_client.jac`** as the original
  roadmap bullet said — that module never touches `ClaudeAgentOptions` at all, for the same
  import-explosion reason the launcher exists as its own plain-Python process.
- **A systematic follow-up audit (all 84 top-level entries in upstream's `chat/browser/`, not just
  the one screenshot that prompted the reframe) surfaced two trust/safety gaps** — tool approval
  and multi-file edit review — that weren't in the original plan at all, and were built ahead of
  the reframed UI items once found, since they're data-loss/trust risks, not polish.
- **Building `Ctrl+I` surfaced a real, previously-unknown bug in the pre-existing `Ctrl+S`** — not
  something this phase set out to fix, but sharing the exact same root cause and fix shape as the
  new feature's own requirement, so it was fixed in the same PR rather than deferred.
- **The phase was closed with two of its three named tools never started**, by explicit
  project-sponsor direction (2026-09-04) once it became clear the exit criteria were already met
  and continuing to hold the phase open around unscoped future work (Copilot, OpenCode) or
  proposal-stage ideas (the native provider, `.claude-plugin/` discovery) was adding status noise
  rather than real progress. Not a scope cut — those items are real, deferred work, not decided
  against.

## Blockers logged during this phase

- `2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure` (blocker,
  workaround-found) — the finding that forced `claude_code_launcher.py`'s plain-Python,
  subprocess-only shape; see "Key decisions" above.
- `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance` (major,
  workaround-found) — found building inline chat (PR #75), also affected the pre-existing `Ctrl+S`.
  Full investigation and the registry-based fix in the entry itself.
- `2026-09-03-jac-run-kill-leaves-vite-child-process-serving-stale-state` — not caused by this
  phase's own code (a general dev-loop issue), but hit repeatedly during this phase's many live
  `jac browse` verification sessions; logged from a different phase's work, cross-referenced here
  since anyone doing more live AI-integration testing will hit it too.

## What's left / suggested next steps

1. **GitHub Copilot, OpenCode, a native `by llm()` provider, and `.claude-plugin/` bundle
   discovery** are all real, legitimate future work, moved to `roadmap.md`'s "Explicitly out of
   scope for now" section on this phase's closure — not decided against, just no longer implicitly
   part of an already-complete phase. Each needs its own scoping pass (auth/licensing model for
   Copilot/OpenCode; nothing beyond implementation for the native provider and plugin discovery,
   which were only ever proposed) before work starts. Pick these up as their own scoped effort
   whenever prioritized, not as a Phase 5 reopening.
2. **The `ChatProvider`-split question in `architecture.md`** (whether agent-behavior identity and
   model backend should eventually decouple, the way VS Code's `chat.createChatParticipant` /
   `lm.registerLanguageModelChatProvider` do) stays genuinely open — worth revisiting once a
   *second* external-tool provider actually exists and there's a real second data point, whenever
   that happens.
3. **Phase 6's own auth-provider broker** (extension system, Phase B) is a natural fit for
   Copilot/OpenCode's eventual auth needs once either is picked up — worth checking whether they
   can reuse that broker rather than each rolling its own credential storage, per Phase 6's own
   roadmap bullet.
4. **No mid-turn cancel** stays a deliberate v1 scope cut across the whole Claude Code integration
   (`claude_code_client.jac`'s own docstring) — still true, not blocking, but worth remembering
   before any of the deferred items above reuse this provider's shape wholesale.
5. Per `roadmap.md`'s own ordering, **Phase 6 (extension system, Phase B: dynamic loading, a
   manifest format, the Extensions view) is next** — nothing in it depends on any of this phase's
   deferred items shipping first.
