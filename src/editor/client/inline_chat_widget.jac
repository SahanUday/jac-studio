"""Ctrl+I popover for targeted edits without leaving the editor, anchored with Monaco's
`addContentWidget` (not `ZoneWidget` — see `docs/libraries/monaco.md`). Makes its own
`start_chat_turn` call on a session independent from the sidebar `AIChatApp`; closing ends that
context, no resume on reopen. Tool approval reuses `ai_chat.jac`'s `AiToolDiffPreview`/
`approve_tool_call`, since this widget's approval events arrive on their own SSE stream."""

import from "react" { useEffect }
import from "react-dom" { createPortal }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }
import from src.workbench.ai.ai_tool_diff_preview { app as AiToolDiffPreview }
import from src.workbench.ai.markdown_message { app as MarkdownMessage }
import from src.workbench.ai.thinking_indicator { app as ThinkingIndicator }
import from src.workbench.workspace.workspace_service { get_current_workspace }

def:pub app(open: bool, onClose: any, editorRef: any, monacoRef: any, path: str) -> JsxElement {
    has input_text: str = "";
    has response_text: str = "";
    has is_streaming: bool = False;
    has session_id: str | None = None;
    has pending_approvals: list[dict[str, any]] = [];
    has widget_node_ref: Ref[any] = Ref();
    has content_widget_ref: Ref[any] = Ref();
    has response_area_ref: Ref[any] = Ref();

    async def handle_submit -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    async def handle_approval_decision(tool_use_id: str, name: str, decision: str) -> None;
    def handle_close(e: any) -> None;

    # Created in render body, not useEffect: a Ref write doesn't trigger re-render, so the first
    # render would have nothing to portal into.
    if not widget_node_ref.current {
        widget_node_ref.current = document.createElement("div");
    }

    # Anchor captured once when open flips true, not re-anchored on later re-renders.
    useEffect(lambda {
        editor = editorRef.current;
        monaco = monacoRef.current;
        if open and editor and monaco {
            selection = editor.getSelection();
            anchor_position = selection.getStartPosition() if selection and not selection.isEmpty() else editor.getPosition();
            widget = {
                "getId": lambda { return "jac-studio.inlineChatWidget"; },
                "getDomNode": lambda { return widget_node_ref.current; },
                "getPosition": lambda {
                    return {
                        "position": anchor_position,
                        "preference": [
                            monaco.editor.ContentWidgetPositionPreference.BELOW,
                            monaco.editor.ContentWidgetPositionPreference.ABOVE
                        ]
                    };
                }
            };
            content_widget_ref.current = widget;
            editor.addContentWidget(widget);
            return lambda {
                if editor and content_widget_ref.current {
                    editor.removeContentWidget(content_widget_ref.current);
                    content_widget_ref.current = None;
                }
            };
        }
    }, [open]);

    useEffect(lambda {
        if response_area_ref.current {
            response_area_ref.current.scrollTop = response_area_ref.current.scrollHeight;
        }
    }, [response_text, is_streaming, pending_approvals]);

    <>
        {(
            createPortal(
                <div
                    style={{
                        "width": "22rem",
                        "background": "#252526",
                        "border": "1px solid #454545",
                        "borderRadius": "4px",
                        "boxShadow": "0 4px 16px rgba(0,0,0,0.5)",
                        "padding": "0.5rem",
                        "fontFamily": "system-ui, sans-serif",
                        "fontSize": "12px",
                        "color": "#CCCCCC",
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "0.4rem"
                    }}
                >
                    <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center"}}>
                        <span style={{"color": "#8C8C8C", "fontSize": "10px", "textTransform": "uppercase"}}>Inline Chat</span>
                        <span
                            role="button"
                            onClick={handle_close}
                            className="codicon codicon-close"
                            style={{"cursor": "pointer", "fontSize": "13px", "opacity": "0.7"}}
                        />
                    </div>
                    {(
                        <div ref={response_area_ref} className="no-scrollbar" style={{"maxHeight": "10rem", "overflow": "auto", "padding": "0.3rem", "background": "#1E1E1E", "borderRadius": "3px"}}>
                            <MarkdownMessage text={response_text} />
                        </div>
                    ) if response_text != "" else None}
                    <ThinkingIndicator active={is_streaming} />
                    {[
                        <div key={a["tool_use_id"]} style={{"border": "1px solid #f0883e", "borderRadius": "3px", "background": "#2A1F14", "padding": "0.3rem", "display": "flex", "flexDirection": "column", "gap": "0.25rem"}}>
                            <span style={{"fontSize": "10px", "color": "#f0883e"}}>{"Wants to use " + a["name"]}</span>
                            {(
                                <AiToolDiffPreview toolUseId={a["tool_use_id"]} filePath={a["file_path"]} originalText={a["original_text"]} modifiedText={a["modified_text"]} />
                            ) if a["has_diff"] else (
                                <pre style={{"margin": "0", "fontSize": "10px", "whiteSpace": "pre-wrap", "wordBreak": "break-word", "maxHeight": "4rem", "overflow": "auto"}}>{a["input_text"]}</pre>
                            )}
                            <div style={{"display": "flex", "gap": "0.3rem"}}>
                                <button onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], a["name"], "allow"); }} style={{"background": "#238636", "color": "#FFFFFF", "border": "none", "borderRadius": "3px", "padding": "0.15rem 0.5rem", "cursor": "pointer", "fontSize": "10px"}}>Allow</button>
                                <button onClick={lambda (e: any) { handle_approval_decision(a["tool_use_id"], a["name"], "deny"); }} style={{"background": "#3A3A3A", "color": "#CCCCCC", "border": "none", "borderRadius": "3px", "padding": "0.15rem 0.5rem", "cursor": "pointer", "fontSize": "10px"}}>Deny</button>
                            </div>
                        </div>
                        for a in pending_approvals
                    ]}
                    <div style={{"display": "flex", "gap": "0.3rem", "alignItems": "flex-end"}}>
                        <textarea
                            value={input_text}
                            onChange={handle_input_change}
                            onKeyDown={handle_key_down}
                            placeholder="Ask AI to edit this..."
                            rows={2}
                            autoFocus={True}
                            style={{"flex": "1", "background": "#1E1E1E", "color": "#CCCCCC", "border": "1px solid #2A2B2C", "borderRadius": "3px", "padding": "0.3rem", "fontFamily": "inherit", "fontSize": "12px", "resize": "none"}}
                        />
                        <button
                            onClick={handle_submit}
                            disabled={is_streaming or input_text.strip() == ""}
                            style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if (not is_streaming and input_text.strip() != "") else "#5A5A5A", "cursor": "pointer", "padding": "0.2rem"}}
                        >
                            <span className="codicon codicon-send" style={{"fontSize": "16px"}} />
                        </button>
                    </div>
                </div>,
                widget_node_ref.current
            )
        ) if open else None}
    </>
}
