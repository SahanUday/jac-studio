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
pending-approval card; the step card itself carries the result."""

import from "react" { useState, useEffect }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }
import from src.workbench.ai.ai_tool_diff_preview { app as AiToolDiffPreview }

def:pub app(active: bool, pendingPrompt: str, pendingAutoSend: bool, pendingNonce: int) -> JsxElement {
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

    <div style={{"display": "block" if active else "none", "height": "100%", "flexDirection": "column", "fontFamily": "system-ui, sans-serif", "fontSize": "12px", "color": "#CCCCCC"}}>
        <div style={{"height": "100%", "display": "flex", "flexDirection": "column"}}>
            <div style={{"padding": "0.3rem 0.6rem", "color": "#8C8C8C", "fontSize": "11px", "textTransform": "uppercase", "borderBottom": "1px solid #2A2B2C", "flexShrink": "0"}}>
                Claude Code
            </div>
            <div style={{"flex": "1", "overflow": "auto", "padding": "0.5rem 0.6rem", "display": "flex", "flexDirection": "column", "gap": "0.6rem"}}>
                {[
                    (
                        <div key={str(i)} style={{"border": "1px solid " + ("#3A3A3A" if m["status"] == "running" else ("#f48771" if m["status"] == "error" else "#2A2B2C")), "borderRadius": "3px", "background": "#1E1E1E", "padding": "0.35rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.25rem"}}>
                            <div style={{"display": "flex", "alignItems": "center", "gap": "0.35rem"}}>
                                <span
                                    className={"codicon " + ("codicon-loading codicon-modifier-spin" if m["status"] == "running" else ("codicon-error" if m["status"] == "error" else "codicon-check"))}
                                    style={{"fontSize": "12px", "color": "#8C8C8C" if m["status"] == "running" else ("#f48771" if m["status"] == "error" else "#89D185")}}
                                />
                                <span style={{"fontSize": "11px", "color": "#569CD6"}}>{m["name"]}</span>
                            </div>
                            {(
                                <pre style={{"margin": "0", "fontSize": "10px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "4rem", "overflow": "auto", "color": "#8C8C8C", "fontFamily": "monospace"}}>{JSON.stringify(m["input"])}</pre>
                            ) if m["input"] else None}
                            {(
                                <pre style={{"margin": "0", "fontSize": "10px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "6rem", "overflow": "auto", "color": "#f48771" if m["status"] == "error" else "#CCCCCC", "fontFamily": "monospace"}}>{m["result_text"]}</pre>
                            ) if m["result_text"] != "" else None}
                        </div>
                    ) if m.get("kind") == "tool_step" else (
                        <div key={str(i)} style={{"display": "flex", "flexDirection": "column", "gap": "0.15rem"}}>
                            <span style={{
                                "fontSize": "10px",
                                "textTransform": "uppercase",
                                "color": "#f48771" if m["role"] == "error" else ("#9CDCFE" if m["role"] == "user" else "#8C8C8C")
                            }}>
                                {m["role"]}
                            </span>
                            <span style={{"whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{m["text"]}</span>
                        </div>
                    )
                    for (i, m) in enumerate(messages)
                ]}
            </div>
            {[
                <div key={a["tool_use_id"]} style={{"margin": "0 0.6rem 0.5rem", "border": "1px solid #f0883e", "borderRadius": "3px", "background": "#2A1F14", "padding": "0.4rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.3rem", "flexShrink": "0"}}>
                    <span style={{"fontSize": "11px", "color": "#f0883e"}}>{"Claude Code wants to use " + a["name"]}</span>
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
                    placeholder="Ask Claude Code..."
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
