"""AIChat: the UI half of Phase 5's native Claude Code integration (`docs/roadmap.md`'s "native AI
coding-tool integrations" phase). A new left-sidebar view (`activity_bar.jac`'s `VIEWS`), not the
auxiliary/secondary side bar real VS Code uses for Chat -- that panel doesn't exist in jac-studio
yet (`vscode-complete-triage.md`'s `auxiliarybar` row, explicitly Phase 6 scope, per
`docs/roadmap.md`'s 2026-08-31 re-prioritization). Reusing the existing `VIEWS` sidebar mechanism
(one entry + one branch in `workbench.jac`, the same "no new plumbing" pattern Search/SCM/Outline
already proved in Phase 4) is the deliberate, scoped choice here -- the narrower width is a real v1
tradeoff, not an oversight, and moving this component into a real auxiliary bar later needs no
rework of the component itself, only where it's mounted.

**The SSE stream is consumed with a raw `fetch`, not the generated RPC stub -- same reasoning, and
the identical two-`JSON.parse` unwrap + trailing-`event: end`-frame guard, as
`debug_console.impl.jac`.** `claude_code_client.jac`'s `start_chat_turn` is declared `-> Generator`
specifically so it stays a real server-push stream.

**No mid-turn cancel in this first slice** -- matches `claude_code_client.jac`'s own documented v1
scope cut (see that module's docstring for why). The Send control simply disables while a turn is
in flight.

**Conversation continuity is `session_id` round-tripped through `done` events, not client-side
history replay** -- each turn sends only the new prompt plus the previous turn's `session_id`; the
SDK's own `resume` mechanism (via `claude_code_launcher.py`) reconstructs context server-side. The
displayed `messages` list is purely a rendering log, not what gets sent back on the next turn.

**Tool-approval requests are a separate `pending_approvals` list, not folded into `messages`.**
`claude_code_launcher.py`'s `can_use_tool` callback (see that module's own docstring for the
real trust-boundary gap this closes) emits a `tool_approval_request` event mid-stream and then
blocks the tool call until a decision arrives. Keeping approval cards in their own list keeps both
pieces simple: `messages` stays a plain rendering log of turn content (text and tool steps), while
`pending_approvals` is purely "what's blocked on the user right now" -- once decided, the card is
just removed, and the corresponding `tool_step` entry in `messages` (see below) picks up the real
outcome on its own via the launcher's own `tool_result` event, not a note written here. `tool_use_id`
is the join key between a card and the `approve_tool_call` RPC call it fires -- concurrent approval
requests (the SDK can ask for several tool calls in one turn) are handled correctly since each card
tracks its own id independently.

**`Edit`/`Write` cards render a real diff (`ai_tool_diff_preview.jac`), not the generic JSON dump.**
`claude_code_launcher.py` includes `original_text`/`modified_text` on the event only for those two
tool names (see that module's own docstring for how they're computed) -- every other tool (`Bash`,
the `jac mcp` tools, ...) has neither key, and `a["has_diff"]` (set in `handle_event`) is `False`,
so the card falls back to the same plain input-JSON `<pre>` block PR #72 already shipped.

**`pendingPrompt`/`pendingAutoSend`/`pendingNonce` are the receiving half of
`ai_code_action_provider.jac`'s "Fix"/"Explain"/"Modify" lightbulb menu (`docs/architecture.md`'s
"Reframed 2026-09-03" AI section, item 1) -- `workbench.jac`'s own docstring covers the sending
half.** `useEffect([pendingNonce])`, not `useEffect([pendingPrompt])` -- keying off the text itself
would silently no-op a second identical request (React's own dependency-array equality check sees
no change), where the nonce increments on every call regardless of the text. Sets `input_text` to
the constructed prompt always; calls `handle_send()` immediately only when `pendingAutoSend` is
`True` ("Fix"/"Explain", self-contained requests) -- "Modify..." leaves it in the box unsent so the
user can finish describing the change before submitting.

**`messages` holds two kinds of entries, distinguished by `m["kind"]`, interleaved in stream
order -- item 6 of the "Reframed 2026-09-03" AI section (richer agent-session visualization).**
`"text"` (the pre-existing `role`+`text` shape) and `"tool_step"` (`tool_use_id`, `name`, `input`,
`status`: `"running"|"done"|"error"`, `result_text`) -- a structured card per tool call instead of
the old plain `"[Using X...]"` marker spliced into the surrounding text, driven by
`claude_code_launcher.py`'s three-event tool lifecycle (`tool_use_start`/`tool_use_input`/
`tool_result`, see that module's own docstring). A `tool_step` is a genuinely separate list entry,
not folded into the running assistant text bubble the way the old marker was -- `text_delta`
appends into `messages[-1]` only when it's still an open `"text"` entry; once a `tool_step` lands
as the last entry, the next `text_delta` starts a fresh `"text"` entry rather than corrupting the
step card, matching how a real turn actually alternates between talking and acting.

**Tool approval no longer writes a local "[Allowed X]"/"[Denied X]" note.** Found live, confirmed
via a direct `can_use_tool`-denial probe: a decision -- allow or deny -- always produces a real
`tool_result` event from the launcher shortly after (the SDK sends a synthetic
`ToolResultBlock(is_error=True, content=<the deny message>)` for a denial, indistinguishable in
shape from a real execution's result), which updates the matching `tool_step` card with the
authentic outcome. A separate optimistic local note was redundant with, and could race, that
authoritative update -- `handle_approval_decision` now only forwards the decision and clears the
pending-approval card; the step card itself carries the result.

**First real-user QA pass (2026-09-05, post-Phase-5-closure), a real fix + polish round, not new
scope** -- see `docs/phases/phase-5-ai-integrations.md`'s own addendum for the full record:

- **`cwd` is now resolved by the caller and passed into `start_chat_turn` as a plain argument,
  never queried from inside its generator.** A real user hit two failures from the same root cause:
  a turn silently answered based on the *server process's own* cwd instead of the real open
  workspace, and a follow-up turn in the same conversation hit a genuine, uncaught
  `PgWireError: connection lost mid-transaction`. Both trace to `get_current_workspace()` (a real
  `root`-scoped graph query) having been called from inside `start_chat_turn`'s own SSE generator --
  see `claude_code_client.jac`'s docstring and tracker entry
  `2026-09-05-sse-generator-root-scoped-graph-query-unreliable` for the full root-cause writeup.
  This component now calls `get_current_workspace()` itself, as a plain `await`ed RPC call, right
  before `fetch`ing `/function/start_chat_turn`.
- **Tool-step cards are collapsed by default** (`m["expanded"]`, set `False` at `tool_use_start`,
  toggled by clicking the card's header row) -- a one-line summary (`_tool_step_summary`, the most
  relevant single input value: `command`/`file_path`/`pattern`/`path`, whichever the tool actually
  has) plus a status icon and a chevron, matching how VS Code's own Copilot Chat renders a
  collapsed tool call rather than always showing full JSON input/result inline.
- **The primary identity is "AI Chat," with a small "via Claude Code" caption, not "Claude Code" as
  the headline.** A real user flagged that hardcoding the specific provider's name everywhere reads
  oddly given `roadmap.md`'s own stated intent to eventually support more than one (Copilot,
  OpenCode, a native `by llm()` "Jac Agent" -- see `jac-agent.md`). **Deliberately not a full
  provider-selector UI** -- with only one working provider today, a dropdown with nothing real to
  switch to would be premature, not helpful; this is a light naming fix, not new provider-selection
  infrastructure. The pending-approval card's "Claude Code wants to use X" and the input
  placeholder also dropped the specific provider name for the same reason, as did the "Fix"/
  "Explain"/"Modify" Quick Fix menu items (`ai_code_action_provider.jac`) and inline chat's own
  header/placeholder (`inline_chat_widget.jac`).
- **The sidebar is now resizable** (wrapped in a `ResizablePanel`/`ResizableHandle`, the same
  primitive editor-group splitting already uses) -- applies to every sidebar view (Explorer/Search/
  SCM/Outline/AI Chat), not just this one, since they all share the same column.
- **A "maximize" toggle gives this panel the whole workbench area on demand** (the
  `codicon-screen-full`/`codicon-screen-normal` button next to the header, `maximized`/
  `onToggleMaximize` props owned by `workbench.jac`) -- real VS Code's own "maximize panel"
  (double-click a panel tab) is the precedent, not upstream's separate auxiliary-bar Chat panel
  (still Phase 6 scope, unbuilt). **Deliberately a pure CSS/style toggle on this same mounted
  instance** (`position: fixed; inset: 0 0 0 48px` when maximized, covering everything right of the
  activity bar), **not a second mount point (a real tab, a portal, ...)** -- the point is more room
  for the exact same live conversation a user might already be mid-turn in; anything that
  unmounts/remounts this component to get there would lose `messages`/`session_id`/
  `pending_approvals` in the process. `zIndex: 30` -- above ordinary in-flow content (the sidebar's
  own `zIndex: 20`) but below dialogs/menus/toasts (Radix's own `z-50` convention throughout this
  project), so the command palette and other overlays still correctly sit on top even while this
  panel is maximized.

**Second QA pass on the same branch (2026-09-05), after manually testing the first round above --
two more real, live-found gaps:**

- **Assistant text now renders as real markdown** (`markdown_message.jac`, shared with
  `inline_chat_widget.jac`) instead of raw pre-wrap text. Found live: a response's own literal
  ```` ``` ````/`**` markdown syntax was showing up unrendered in the panel, not interpreted --
  confirmed via a real screenshot, not assumed. User's own messages stay plain text (matching real
  chat UIs -- markdown rendering is for the *assistant's* formatted output, not literal
  interpretation of what a user typed).
- **A `ThinkingIndicator` (spinner + a rotating status word + elapsed seconds, e.g.
  "Pondering… (7s)") now shows for the whole duration `is_streaming` is true**, docked at the
  bottom of the message list -- found live: nothing in the UI indicated the agent was actively
  working between hitting Send and the first token/tool call arriving. **Refined twice on the same
  day, both from live feedback**: a first version was a single static "Thinking…" label; shown a
  real screenshot of Claude Code's own extension UI (a rotating whimsical verb next to its own
  spinner, not a fixed word), `thinking_indicator.jac` now cycles through a similarly-spirited word
  list every 2.5s and counts elapsed seconds, shared with `inline_chat_widget.jac`'s own popover
  rather than duplicated. Not a byte-for-byte reproduction of Anthropic's own exact internal word
  list (unverifiable from here) -- see that module's own docstring.

**Third QA pass (2026-09-05), two more small but real UI bugs found live, both fixed here:**

- **Tool-step cards (and, defensively, plain text entries too) now carry an explicit
  `flexShrink: "0"`.** Found live via two screenshots of the same conversation before/after a
  follow-up message: tool-step cards visibly collapsed to razor-thin bars once the message list
  grew past the visible area, while plain text bubbles didn't. Root cause: each tool-step card's
  outer wrapper has `overflow: "hidden"` (needed for its own collapse/expand animation-adjacent
  clipping) -- per the CSS flexbox spec, a flex item's *automatic* minimum size in the main axis is
  0 when it has `overflow` other than `visible`, instead of its content size. In a `flexDirection:
  column` list under real content pressure, that makes exactly the entries with `overflow: hidden`
  (the tool-step cards, not the plain-text ones) the first to get squeezed toward zero height. Not
  a guess -- confirmed against the exact styles below and the spec's own "automatic minimum size"
  rule. `pending_approvals`' own cards already had `flexShrink: "0"` from PR #72; this extends the
  same guard to every entry in the main `messages` list, which never had it.
- **The message list no longer shows a visible scrollbar** (`className="no-scrollbar"`, an
  existing Tailwind `@utility` in `styles/global.css` that was defined but never actually applied
  anywhere in this project until now) -- `overflow: "auto"` still scrolls via wheel/touch/keyboard,
  it just doesn't reserve a visible OS-chrome scrollbar gutter in a column this narrow. Same
  treatment applied to `inline_chat_widget.jac`'s own scrollable response area for consistency."""

import from "react" { useState, useEffect }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }
import from src.workbench.ai.ai_tool_diff_preview { app as AiToolDiffPreview }
import from src.workbench.ai.markdown_message { app as MarkdownMessage }
import from src.workbench.ai.thinking_indicator { app as ThinkingIndicator }
import from src.workbench.workspace.workspace_service { get_current_workspace }

"""One-line summary for a collapsed tool-step card's header -- the single input value most useful
to see at a glance without expanding, matching how VS Code's own Copilot Chat renders a collapsed
tool call (`Read file.ts`, not the full JSON args). Falls back to nothing (just the icon+name) for
a tool shape this hasn't special-cased -- no attempt to guess a summary from an arbitrary shape."""
def _tool_step_summary(name: str, input: dict[str, any]) -> str {
    if "command" in input {
        return str(input["command"]);
    }
    if "file_path" in input {
        return str(input["file_path"]);
    }
    if "pattern" in input {
        return str(input["pattern"]);
    }
    if "path" in input {
        return str(input["path"]);
    }
    return "";
}

def:pub app(active: bool, pendingPrompt: str, pendingAutoSend: bool, pendingNonce: int, maximized: bool, onToggleMaximize: any) -> JsxElement {
    has messages: list[dict[str, any]] = [];
    has input_text: str = "";
    has is_streaming: bool = False;
    has session_id: str | None = None;
    has pending_approvals: list[dict[str, any]] = [];

    async def handle_send -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    def update_tool_step(tool_use_id: str, updates: dict[str, any]) -> bool;
    def toggle_tool_step_expanded(tool_use_id: str) -> None;
    async def handle_approval_decision(tool_use_id: str, decision: str) -> None;

    useEffect(lambda {
        if pendingNonce > 0 {
            input_text = pendingPrompt;
            if pendingAutoSend {
                handle_send();
            }
        }
    }, [pendingNonce]);

    can_send = input_text.strip() != "" and not is_streaming;

    <div style={{
        "display": "block" if active else "none",
        "height": "100%" if not maximized else "auto",
        "flexDirection": "column",
        "fontFamily": "system-ui, sans-serif",
        "fontSize": "12px",
        "color": "#CCCCCC",
        "position": "fixed" if maximized else "static",
        "top": "0" if maximized else "auto",
        "right": "0" if maximized else "auto",
        "bottom": "0" if maximized else "auto",
        "left": "48px" if maximized else "auto",
        "zIndex": "30" if maximized else "auto",
        "background": "#181818"
    }}>
        <div style={{"height": "100%", "display": "flex", "flexDirection": "column"}}>
            <div style={{"padding": "0.3rem 0.6rem", "borderBottom": "1px solid #2A2B2C", "flexShrink": "0", "display": "flex", "alignItems": "center", "gap": "0.4rem"}}>
                <span style={{"color": "#8C8C8C", "fontSize": "11px", "textTransform": "uppercase"}}>AI Chat</span>
                <span style={{"color": "#5A5A5A", "fontSize": "10px", "flex": "1"}}>via Claude Code</span>
                <span
                    role="button"
                    title={"Restore to sidebar" if maximized else "Maximize"}
                    onClick={onToggleMaximize}
                    className={"codicon " + ("codicon-screen-normal" if maximized else "codicon-screen-full")}
                    style={{"fontSize": "13px", "color": "#8C8C8C", "cursor": "pointer", "opacity": "0.8"}}
                />
            </div>
            <div className="no-scrollbar" style={{"flex": "1", "overflow": "auto", "padding": "0.5rem 0.6rem", "display": "flex", "flexDirection": "column", "gap": "0.6rem"}}>
                {[
                    (
                        <div key={str(i)} style={{"border": "1px solid #2A2B2C", "borderRadius": "4px", "background": "#1E1E1E", "overflow": "hidden", "flexShrink": "0"}}>
                            <div
                                role="button"
                                onClick={lambda (e: any) { toggle_tool_step_expanded(m["tool_use_id"]); }}
                                style={{"display": "flex", "alignItems": "center", "gap": "0.4rem", "padding": "0.3rem 0.45rem", "cursor": "pointer"}}
                            >
                                <span
                                    className={"codicon " + ("codicon-loading codicon-modifier-spin" if m["status"] == "running" else ("codicon-error" if m["status"] == "error" else "codicon-pass"))}
                                    style={{"fontSize": "12px", "flexShrink": "0", "color": "#8C8C8C" if m["status"] == "running" else ("#f48771" if m["status"] == "error" else "#89D185")}}
                                />
                                <span style={{"fontSize": "11px", "color": "#569CD6", "flexShrink": "0"}}>{m["name"]}</span>
                                <span style={{"fontSize": "11px", "color": "#8C8C8C", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap", "flex": "1"}}>
                                    {_tool_step_summary(m["name"], m["input"])}
                                </span>
                                <span
                                    className={"codicon " + ("codicon-chevron-down" if m.get("expanded") else "codicon-chevron-right")}
                                    style={{"fontSize": "12px", "flexShrink": "0", "color": "#5A5A5A"}}
                                />
                            </div>
                            {(
                                <div style={{"padding": "0 0.45rem 0.4rem", "display": "flex", "flexDirection": "column", "gap": "0.3rem", "borderTop": "1px solid #2A2B2C"}}>
                                    {(
                                        <pre style={{"margin": "0.3rem 0 0", "fontSize": "10px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "6rem", "overflow": "auto", "color": "#8C8C8C", "fontFamily": "monospace"}}>{JSON.stringify(m["input"])}</pre>
                                    ) if m["input"] else None}
                                    {(
                                        <pre style={{"margin": "0", "fontSize": "10px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "8rem", "overflow": "auto", "color": "#f48771" if m["status"] == "error" else "#CCCCCC", "fontFamily": "monospace"}}>{m["result_text"]}</pre>
                                    ) if m["result_text"] != "" else None}
                                </div>
                            ) if m.get("expanded") else None}
                        </div>
                    ) if m.get("kind") == "tool_step" else (
                        <div key={str(i)} style={{"display": "flex", "flexDirection": "column", "gap": "0.15rem", "flexShrink": "0"}}>
                            <span style={{
                                "fontSize": "10px",
                                "textTransform": "uppercase",
                                "color": "#f48771" if m["role"] == "error" else ("#9CDCFE" if m["role"] == "user" else "#8C8C8C")
                            }}>
                                {m["role"]}
                            </span>
                            {(
                                <MarkdownMessage text={m["text"]} />
                            ) if m["role"] == "assistant" else (
                                <span style={{"whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{m["text"]}</span>
                            )}
                        </div>
                    )
                    for (i, m) in enumerate(messages)
                ]}
                <ThinkingIndicator active={is_streaming} />
            </div>
            {[
                <div key={a["tool_use_id"]} style={{"margin": "0 0.6rem 0.5rem", "border": "1px solid #f0883e", "borderRadius": "3px", "background": "#2A1F14", "padding": "0.4rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.3rem", "flexShrink": "0"}}>
                    <span style={{"fontSize": "11px", "color": "#f0883e"}}>{"Wants to use " + a["name"]}</span>
                    {(
                        <AiToolDiffPreview toolUseId={a["tool_use_id"]} filePath={a["file_path"]} originalText={a["original_text"]} modifiedText={a["modified_text"]} />
                    ) if a["has_diff"] else (
                        <pre style={{"margin": "0", "fontSize": "11px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "6rem", "overflow": "auto", "color": "#CCCCCC", "fontFamily": "monospace"}}>{a["input_text"]}</pre>
                    )}
                    <div style={{"display": "flex", "gap": "0.4rem"}}>
                        <button
                            onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], "allow"); }}
                            style={{"background": "#238636", "color": "#FFFFFF", "border": "none", "borderRadius": "3px", "padding": "0.2rem 0.6rem", "cursor": "pointer", "fontSize": "11px"}}
                        >
                            Allow
                        </button>
                        <button
                            onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], "deny"); }}
                            style={{"background": "#3A3A3A", "color": "#CCCCCC", "border": "none", "borderRadius": "3px", "padding": "0.2rem 0.6rem", "cursor": "pointer", "fontSize": "11px"}}
                        >
                            Deny
                        </button>
                    </div>
                </div>
                for a in pending_approvals
            ]}
            <div style={{"borderTop": "1px solid #2A2B2C", "padding": "0.5rem 0.6rem", "flexShrink": "0", "display": "flex", "gap": "0.4rem", "alignItems": "flex-end"}}>
                <textarea
                    value={input_text}
                    onChange={handle_input_change}
                    onKeyDown={handle_key_down}
                    placeholder="Ask AI..."
                    rows={2}
                    style={{
                        "flex": "1",
                        "background": "#1E1E1E",
                        "color": "#CCCCCC",
                        "border": "1px solid #2A2B2C",
                        "borderRadius": "3px",
                        "padding": "0.3rem 0.4rem",
                        "fontFamily": "inherit",
                        "fontSize": "12px",
                        "resize": "none"
                    }}
                />
                <button
                    onClick={handle_send}
                    disabled={not can_send}
                    title="Send"
                    style={{
                        "background": "transparent",
                        "border": "none",
                        "color": "#CCCCCC" if can_send else "#5A5A5A",
                        "cursor": "pointer" if can_send else "default",
                        "padding": "0.3rem"
                    }}
                >
                    <span className="codicon codicon-send" style={{"fontSize": "16px"}} />
                </button>
            </div>
        </div>
    </div>
}
