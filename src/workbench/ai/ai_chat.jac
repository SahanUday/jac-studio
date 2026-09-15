"""AI Chat sidebar view: streams `start_chat_turn`'s SSE frames and renders the turn log.
`cwd` must be resolved here and passed in -- a `root`-scoped graph query from inside the SSE
generator is unreliable (tracker 2026-09-05-sse-generator-root-scoped-graph-query-unreliable).
Conversation continuity is the round-tripped `session_id`, not client-side history replay;
approval decisions are never echoed locally, the launcher's own `tool_result` carries the outcome."""

import from "react" { useState, useEffect }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }
import from src.workbench.ai.ai_tool_diff_preview { app as AiToolDiffPreview }
import from src.workbench.ai.markdown_message { app as MarkdownMessage }
import from src.workbench.ai.thinking_indicator { app as ThinkingIndicator }
import from src.workbench.workspace.workspace_service { get_current_workspace }

"""Header line for a collapsed tool-step card; `""` for a tool with no known summary field."""
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
    has messages_list_ref: Ref[any] = Ref();

    async def handle_send -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    def update_tool_step(tool_use_id: str, updates: dict[str, any]) -> bool;
    def toggle_tool_step_expanded(tool_use_id: str) -> None;
    async def handle_approval_decision(tool_use_id: str, decision: str) -> None;

    # Keyed on the nonce, not the text: a repeated identical prompt must still fire.
    useEffect(lambda {
        if pendingNonce > 0 {
            input_text = pendingPrompt;
            if pendingAutoSend {
                handle_send();
            }
        }
    }, [pendingNonce]);

    useEffect(lambda {
        if messages_list_ref.current {
            messages_list_ref.current.scrollTop = messages_list_ref.current.scrollHeight;
        }
    }, [messages, is_streaming, pending_approvals]);

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
            <div ref={messages_list_ref} className="no-scrollbar" style={{"flex": "1", "overflow": "auto", "padding": "0.5rem 0.6rem", "display": "flex", "flexDirection": "column", "gap": "0.6rem"}}>
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
                            {(
                                <div style={{"background": "#2A2B2C", "borderRadius": "6px", "padding": "0.4rem 0.55rem"}}>
                                    <span style={{"whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{m["text"]}</span>
                                </div>
                            ) if m["role"] == "user" else (
                                <>
                                    <span style={{"fontSize": "10px", "textTransform": "uppercase", "color": "#f48771" if m["role"] == "error" else "#8C8C8C"}}>
                                        {m["role"]}
                                    </span>
                                    {(
                                        <MarkdownMessage text={m["text"]} />
                                    ) if m["role"] == "assistant" else (
                                        <span style={{"whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{m["text"]}</span>
                                    )}
                                </>
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
