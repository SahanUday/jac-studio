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
blocks the tool call until a decision arrives. Keeping approval cards in their own list (rather
than widening `messages`' `dict[str, str]` shape to carry a mix of types) keeps both pieces simple:
`messages` stays a plain rendering log, and a resolved approval collapses into one short log line
there (`"[Approved Write]"`/`"[Denied Bash]"`) once decided. `tool_use_id` is the join key between
a card and the `approve_tool_call` RPC call it fires -- concurrent approval requests (the SDK can
ask for several tool calls in one turn) are handled correctly since each card tracks its own id
independently."""

import from "react" { useState }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }

def:pub app(active: bool) -> JsxElement {
    has messages: list[dict[str, str]] = [];
    has input_text: str = "";
    has is_streaming: bool = False;
    has session_id: str | None = None;
    has pending_approvals: list[dict[str, any]] = [];

    async def handle_send -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    async def handle_approval_decision(tool_use_id: str, name: str, decision: str) -> None;

    can_send = input_text.strip() != "" and not is_streaming;

    <div style={{"display": "block" if active else "none", "height": "100%", "flexDirection": "column", "fontFamily": "system-ui, sans-serif", "fontSize": "12px", "color": "#CCCCCC"}}>
        <div style={{"height": "100%", "display": "flex", "flexDirection": "column"}}>
            <div style={{"padding": "0.3rem 0.6rem", "color": "#8C8C8C", "fontSize": "11px", "textTransform": "uppercase", "borderBottom": "1px solid #2A2B2C", "flexShrink": "0"}}>
                Claude Code
            </div>
            <div style={{"flex": "1", "overflow": "auto", "padding": "0.5rem 0.6rem", "display": "flex", "flexDirection": "column", "gap": "0.6rem"}}>
                {[
                    <div key={str(i)} style={{"display": "flex", "flexDirection": "column", "gap": "0.15rem"}}>
                        <span style={{
                            "fontSize": "10px",
                            "textTransform": "uppercase",
                            "color": "#f48771" if m["role"] == "error" else ("#569CD6" if m["role"] == "tool" else ("#9CDCFE" if m["role"] == "user" else "#8C8C8C"))
                        }}>
                            {m["role"]}
                        </span>
                        <span style={{"whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{m["text"]}</span>
                    </div>
                    for (i, m) in enumerate(messages)
                ]}
            </div>
            {[
                <div key={a["tool_use_id"]} style={{"margin": "0 0.6rem 0.5rem", "border": "1px solid #f0883e", "borderRadius": "3px", "background": "#2A1F14", "padding": "0.4rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.3rem", "flexShrink": "0"}}>
                    <span style={{"fontSize": "11px", "color": "#f0883e"}}>{"Claude Code wants to use " + a["name"]}</span>
                    <pre style={{"margin": "0", "fontSize": "11px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "6rem", "overflow": "auto", "color": "#CCCCCC", "fontFamily": "monospace"}}>{a["input_text"]}</pre>
                    <div style={{"display": "flex", "gap": "0.4rem"}}>
                        <button
                            onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], a["name"], "allow"); }}
                            style={{"background": "#238636", "color": "#FFFFFF", "border": "none", "borderRadius": "3px", "padding": "0.2rem 0.6rem", "cursor": "pointer", "fontSize": "11px"}}
                        >
                            Allow
                        </button>
                        <button
                            onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], a["name"], "deny"); }}
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
