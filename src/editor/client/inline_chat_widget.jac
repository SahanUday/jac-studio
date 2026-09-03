"""InlineChatWidgetApp: the second, "medium lift" item from `docs/architecture.md`'s "Reframed
2026-09-03" AI section -- a Ctrl+I popover for targeted edits without leaving the editor. Confirmed
in `docs/research/vscode-copilot-architecture.md` that real inline chat is built on Monaco's own
`ZoneWidget`, a floating widget anchored at the cursor/selection -- editor-level UI, not workbench
chrome. **Total backend reuse, as that same research doc's finding requires**: this widget makes
its own direct `start_chat_turn` call (the identical SSE endpoint `ai_chat.jac`'s sidebar panel
already streams from), not a new backend concept -- "different presentation" of the same stream.

**A real Monaco content widget (`editor.addContentWidget`), not upstream's internal `ZoneWidget`
class, and that's a deliberate, documented scope cut, not an oversight.** `ZoneWidget`
(`vs/editor/contrib/zoneWidget/...`) is real VS Code's own internal contrib class -- it is **not**
part of the public `monaco-editor` npm package's exported API surface this project actually embeds
(`docs/architecture.md`'s Editor Core decision), only `IContentWidget`/`addContentWidget`,
`IViewZone`/`addViewZone`, and `IOverlayWidget`/`addOverlayWidget` are. A hand-built approximation
of `ZoneWidget`'s "push surrounding lines apart" behavior (an empty `addViewZone` reserving space,
overlaid with a positioned content widget) is possible but real additional scope; this v1 is a
floating content widget that can overlap nearby lines, the same tradeoff the AI code-actions
Quick-Fix menu (a native Monaco widget) already makes. Worth revisiting if the overlap proves
disruptive in real use -- not assumed necessary preemptively.

**React content reaches a Monaco-owned DOM node via `ReactDOM.createPortal`, a genuinely new
integration pattern in this project, verified live before this file's design was finalized.**
Every other Monaco-facing provider in this directory goes the *other* direction (Jac/React code
calling into Monaco's imperative API); this is the first case of the reverse -- Monaco's content
widget owns and positions a raw DOM node it manages itself
(`getDomNode`/`getPosition`/`addContentWidget`), and this component's actual JSX needs to render
*into* that externally-owned node, which only `createPortal` (not a normal JSX return value) can
do. `widget_node_ref` (a `Ref[any]`, not `has` state) holds that raw node, lazily created on first
render if absent -- **created directly in the render body, not inside `useEffect`**, since a `Ref`
write doesn't trigger a re-render the way `has`-state does; creating it only inside the effect
would leave the very first render with nothing to portal into.

**The content widget itself is registered/unregistered in a `useEffect([open])`, keyed on `open`
alone, not on the anchor position.** Its position is captured once, at the moment it opens (the
current selection's start if there is one, else the plain cursor position) -- real VS Code's own
inline chat doesn't re-anchor mid-conversation either; a widget that visibly jumps every time the
(possibly-multi-turn) conversation causes a re-render would be worse UX than a fixed anchor.

**A fully independent chat session from the sidebar `AIChatApp`, not a shared one -- deliberate,
matching real VS Code's own inline chat being a distinct, transient interaction from the main chat
view.** Its own `session_id`/`messages`-equivalent state lives entirely in this component; closing
the popover ends that context (no resume across a reopen in this first slice).

**Tool approval is handled here too, not silently dropped, and reuses the exact same components
`ai_chat.jac` does (`AiToolDiffPreview`, `approve_tool_call`) rather than inventing a second,
different approval UI.** This widget's own `tool_approval_request` events arrive on *this* stream,
a completely separate SSE connection from the sidebar's -- so the sidebar's own pending-approvals
list would never show a matching card for a tool call this popover's own turn triggers. Omitting
approval handling here would leave any Edit/Write/Bash call an inline-chat turn makes silently
stuck until the launcher's own 5-minute timeout auto-denies it, with no visible way to approve it
faster. `pending_approvals` here is the same per-call-id list shape `ai_chat.jac` established, just
rendered smaller to fit this popover's own compact footprint."""

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

    async def handle_submit -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    async def handle_approval_decision(tool_use_id: str, name: str, decision: str) -> None;
    def handle_close(e: any) -> None;

    if not widget_node_ref.current {
        widget_node_ref.current = document.createElement("div");
    }

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
                        <div style={{"maxHeight": "10rem", "overflow": "auto", "padding": "0.3rem", "background": "#1E1E1E", "borderRadius": "3px"}}>
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
