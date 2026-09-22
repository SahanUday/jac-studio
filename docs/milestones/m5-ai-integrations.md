# M5 — AI integration

**Status**: complete, 2026-09-04, closed by explicit project-sponsor direction

Claude Code usable end to end inside jac-studio for a real coding task, with its own auth flow and
output surfaced through M4's Output/notification infra.

## Shipped
| PR | What |
|---|---|
| #69 | Native Claude Code chat integration: `claude_code_client.jac` (subprocess, gated behind `[terminal] enabled`) + `claude_code_launcher.py` (plain Python) + `ai_chat.jac` sidebar panel. Real SSE streaming, multi-turn continuity via SDK `resume`. |
| #70 | Reframe (docs-only): Copilot's own Fix/Explain, inline chat, and inline completions are generic Monaco/editor APIs, not Copilot-specific — reframed remaining scope to new UI entry points against the one provider already shipped. |
| #71 | MCP wiring: `jac mcp` pointed at from `claude_code_launcher.py`'s `ClaudeAgentOptions.mcp_servers` (140 resources/19 tools/9 prompts). |
| #72 | Tool approval: `can_use_tool` emits an approval-request event, blocks on a real approve/deny card. |
| #73 | Multi-file edit review: server-side Monaco diff (`ai_tool_diff_preview.jac`) inside each approval card. |
| #74 | AI code actions: Fix/Explain/Modify lightbulb menu (`ai_code_action_provider.jac`), routes through the existing sidebar. |
| #75 | Inline chat: `Ctrl+I` popover (`inline_chat_widget.jac`), a Monaco content widget with React mounted via `ReactDOM.createPortal`. |
| #76 | Richer agent-session visualization: structured step card per tool call, driven by a three-event lifecycle (`tool_use_start`/`tool_use_input`/`tool_result`). |

Every PR was live-verified end to end against a real `jac run --serve --dev` session with real
credentials.

## Decisions
- [ADR 0048](../decisions/0048-named-ai-coding-tool-integrations-in-scope.md), [0049](../decisions/0049-file-based-command-channel-for-sse-generators.md), [0053](../decisions/0053-claude-code-launcher-is-plain-python.md), [0054](../decisions/0054-build-ai-ui-entry-points-not-more-integrations.md), [0055](../decisions/0055-point-claude-code-at-the-jac-mcp-server.md), [0056](../decisions/0056-explicit-approval-for-every-agent-tool-call.md), [0057](../decisions/0057-multi-file-edit-review-is-a-diff-preview.md), [0058](../decisions/0058-inline-chat-uses-a-content-widget.md), [0059](../decisions/0059-global-keybinding-registry-for-monaco-chords.md), [0060](../decisions/0060-tool-lifecycle-is-three-events.md), [0061](../decisions/0061-pin-claude-model-to-haiku.md), [0062](../decisions/0062-close-phase-5-and-defer-remaining-tools.md), [0063](../decisions/0063-do-not-split-chatprovider-yet.md), [0064](../decisions/0064-resolve-cwd-in-the-caller-not-the-generator.md), [0065](../decisions/0065-panel-identity-is-ai-chat.md), [0066](../decisions/0066-maximize-is-a-css-overlay-not-a-remount.md).

## Deviations from plan
- Only Claude Code, of the three originally-named tools (Copilot, OpenCode, Claude Code), was built.
- The reframe (#70) changed "the rest of the milestone" mid-flight based on reading VS Code's actual Copilot Chat source, not a planning guess.
- MCP wiring landed in `claude_code_launcher.py`, not `claude_code_client.jac`, since that module never touches `ClaudeAgentOptions`.
- A systematic audit of upstream's `chat/browser/` surfaced two unplanned trust/safety gaps (tool approval, multi-file edit review), built ahead of the reframed UI items since they were data-loss risks.
- Building `Ctrl+I` surfaced a real pre-existing bug in `Ctrl+S` (Monaco's `addCommand` doesn't scope per editor instance), fixed in the same PR.
- The milestone was closed with Copilot and OpenCode never started, by explicit project-sponsor direction, once exit criteria were met.

## Blockers logged
- `2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure` (blocker, workaround-found).
- `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance` (major, workaround-found).
- `2026-09-03-jac-run-kill-leaves-vite-child-process-serving-stale-state` (cross-referenced; not caused by this milestone's own code).
- `2026-09-05-sse-generator-root-scoped-graph-query-unreliable` — a chat turn could answer using the server's launch directory instead of the open workspace, and a follow-up turn could hit an uncaught `PgWireError`; a `root`-scoped graph query called from inside an SSE generator is unreliable, the same isolation risk previously seen only with plain `glob` state. Fixed by resolving `cwd` in the caller and passing it in as an argument.

## Left open
- GitHub Copilot, OpenCode, a native `by llm()` provider, and `.claude-plugin/` bundle discovery: real future work, moved to `roadmap.md`'s "Not planned yet" section.
- The `ChatProvider`-split question in `architecture.md` stays open pending a second provider.
- No mid-turn cancel, a deliberate v1 scope cut, tracked in `roadmap.md`'s M9.
- Post-closure QA (2026-09-05, sponsor's hands-on testing) fixed: collapsed-by-default tool-step cards, "AI Chat" as the primary identity (not "Claude Code"), a resizable sidebar with a maximize toggle, real markdown rendering for assistant messages, a "Thinking…" status row for in-flight turns, a `Math.floor()` cast compile error, a `react-markdown` default-export mismatch, tool-step cards collapsing to thin bars under flex pressure, and a visible OS scrollbar in the message column.
- Still unconfirmed, no tracker entry yet: a genuine compile error in one client file may silently strip exports from unrelated files in the client bundle, based on one incident (`workspace_service.jac` losing `create_file`'s export after an unrelated `thinking_indicator.jac` compile error) — not yet reproduced in isolation.

## Second post-closure QA round (2026-09-04 to 2026-09-07)

Further hands-on testing surfaced a longer list of real bugs and product decisions, closed as its
own PR (#80) after this milestone's own closure. Decisions: [ADR 0068](../decisions/0068-paint-theme-colors-at-the-root-div.md)
(white-gap bugs, paint theme colors at the root), [0069](../decisions/0069-ai-chat-fully-isolates-from-host-claude-md.md)
(full CLAUDE.md isolation), [0070](../decisions/0070-ai-launcher-sets-explicit-system-prompt-preset.md)
(explicit system prompt preset), [0071](../decisions/0071-workspace-watched-via-os-level-events.md)
(OS-level workspace watcher, replacing SSE then polling), [0072](../decisions/0072-auto-reload-clean-tabs-on-external-change.md)
(auto-reload clean tabs, extended to `"gitdiff"` tabs), [0073](../decisions/0073-sidebar-width-override-via-style-not-classname.md)
(sidebar width via `style`), [0074](../decisions/0074-null-check-monaco-getposition-everywhere.md)
(null-check `getPosition()`), [0075](../decisions/0075-auto-mode-sends-bypasspermissions.md) (Auto
mode sends `bypassPermissions`), [0076](../decisions/0076-resolve-chat-attachments-server-side-before-sending.md)
(server-side attachment resolution), [0077](../decisions/0077-inline-chat-uses-fixed-permission-mode.md)
(inline chat's fixed permission mode).

Blockers logged: `2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target` (a
`Contains`-edge target that isn't a `Folder`/`File` crashed the whole Explorer tree; also found
`isinstance` fails identically to the field access it was guarding against — use `hasattr`),
`2026-09-07-save-session-hits-readonly-transaction-race-upstream` (a real jaseci concurrency bug,
not fixable from this project's `.jac` source — logged and left open by the sponsor's own call).

An indefinite SSE stream for the first watcher version broke `list_children_by_path` server-wide —
the same known SSE-generator-isolation risk, but the first time from a stream that never
disconnects on its own; fixed by polling a stateless `def:pub` function instead (ADR 0071).
