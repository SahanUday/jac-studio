"""AI Chat sidebar view: streams `start_chat_turn`'s SSE frames and renders the turn log.
`cwd` must be resolved here and passed in -- a `root`-scoped graph query from inside the SSE
generator is unreliable (tracker 2026-09-05-sse-generator-root-scoped-graph-query-unreliable).
Conversation continuity is the round-tripped `session_id`, not client-side history replay;
approval decisions are never echoed locally, the launcher's own `tool_result` carries the outcome.
Model/permission-mode/effort pickers and the `@`-file-attachment picker (ADR 0076) are the client's
own per-turn state, sent fresh on every call. Resizable and maximizable (a CSS overlay on this same
mounted instance, never a remount -- ADR 0066); "AI Chat" is the primary identity, "via Claude Code"
a caption, since more providers are planned (ADR 0063)."""

import from "react" { useState, useEffect }
import from src.workbench.ai.claude_code_client { start_chat_turn, approve_tool_call }
import from src.workbench.ai.ai_tool_diff_preview { app as AiToolDiffPreview }
import from src.workbench.ai.markdown_message { app as MarkdownMessage }
import from src.workbench.ai.thinking_indicator { app as ThinkingIndicator }
import from src.workbench.workspace.workspace_service { get_current_workspace, list_all_files }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem
}
import from src.workbench.file_icons.file_icons { file_icon_class }

glob MODEL_OPTIONS: list[dict[str, str]] = [
    {"value": "haiku", "label": "Haiku"},
    {"value": "sonnet", "label": "Sonnet"},
    {"value": "opus", "label": "Opus"}
];

"""**History on this list's "Auto" entry, in order, none of it silently dropped:**
1. Originally sent `"auto"`, on the wrong assumption it was "the SDK's own broadest bypass."
2. Corrected (same day) to `"bypassPermissions"` on that same wrong assumption, one field
   (`PermissionMode.ts`'s `external: 'default'`) read in isolation.
3. **Reverted back to `"auto"`** after a real user, testing this app, contradicted that from their
   own experience with the real extension -- `permissions.ts`'s actual enforcement code confirmed
   `"auto"` is a genuine, distinct, classifier-backed mode, nothing like Manual.
4. **Confirmed live (isolated `claude_agent_sdk.query()` probe, three-way A/B/C, not more source
   guessing) that `"auto"`'s classifier fast-path is simply inert in the currently-bundled CLI
   build** -- `"auto"` behaves identically to `"default"` here, for reasons outside this project's
   control (see `claude_code_launcher.py`'s docstring and tracker entry
   `2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation` for the full,
   conclusive finding).
5. **`"bypassPermissions"`, deliberately, again -- this time not a mistake, a considered choice
   given step 4's finding (2026-09-04, later the same day).** A user, told plainly that "Auto" does
   nothing useful here right now, asked for what they actually wanted instead: give the agent a
   complete instruction and let it run end to end, only interrupting the user for a genuine
   clarifying question (ordinary chat text, not a tool-approval gate) rather than a permission
   check on every tool call. `"bypassPermissions"` is the real mode that delivers exactly that --
   confirmed live in step 4's own probe to skip `can_use_tool` unconditionally. This is a materially
   bigger trust step than `"acceptEdits"`: it also skips Bash and every MCP tool call, not just file
   writes, with no per-call check at all -- flagged explicitly to the user (and confirmed) before
   wiring it in, not assumed to be wanted just because "Auto" was the closest existing label."""
glob PERMISSION_MODE_OPTIONS: list[dict[str, str]] = [
    {"value": "default", "label": "Manual"},
    {"value": "acceptEdits", "label": "Edit automatically"},
    {"value": "plan", "label": "Plan"},
    {"value": "bypassPermissions", "label": "Auto"}
];

glob EFFORT_OPTIONS: list[dict[str, str]] = [
    {"value": "low", "label": "Low"},
    {"value": "medium", "label": "Medium"},
    {"value": "high", "label": "High"},
    {"value": "xhigh", "label": "X-High"},
    {"value": "max", "label": "Max"}
];

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
    has model: str = "haiku";
    has permission_mode: str = "default";
    has effort: str = "high";
    has attach_open: bool = False;
    has attach_files: list[dict[str, str]] = [];
    has attached_paths: list[str] = [];

    async def handle_send -> None;
    def handle_input_change(e: any) -> None;
    def handle_key_down(e: any) -> None;
    def handle_event(event: dict[str, any]) -> None;
    def update_tool_step(tool_use_id: str, updates: dict[str, any]) -> bool;
    def toggle_tool_step_expanded(tool_use_id: str) -> None;
    async def handle_approval_decision(tool_use_id: str, decision: str) -> None;
    async def refresh_attach_files -> None;
    def handle_attach_select(path: str) -> None;
    def remove_attached_file(path: str) -> None;

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

    useEffect(lambda {
        if attach_open {
            refresh_attach_files();
        }
    }, [attach_open]);

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
            <div style={{"borderTop": "1px solid #2A2B2C", "padding": "0.5rem 0.6rem", "flexShrink": "0", "display": "flex", "flexDirection": "column", "gap": "0.35rem"}}>
                {(
                    <div style={{"display": "flex", "flexWrap": "wrap", "gap": "0.3rem"}}>
                        {[
                            <span
                                key={p}
                                title={p}
                                style={{"display": "flex", "alignItems": "center", "gap": "0.25rem", "background": "#2A2B2C", "borderRadius": "3px", "padding": "0.1rem 0.4rem", "fontSize": "10px", "color": "#CCCCCC"}}
                            >
                                <span className={"codicon " + file_icon_class(p.split("/").pop(), False, False)} style={{"fontSize": "11px"}} />
                                {p.split("/").pop()}
                                <span
                                    role="button"
                                    onClick={lambda (e: any) { remove_attached_file(p); }}
                                    className="codicon codicon-close"
                                    style={{"fontSize": "10px", "cursor": "pointer", "opacity": "0.7"}}
                                />
                            </span>
                            for p in attached_paths
                        ]}
                    </div>
                ) if len(attached_paths) > 0 else None}
                <div style={{"display": "flex", "gap": "0.4rem", "alignItems": "flex-end"}}>
                    <textarea
                        value={input_text}
                        onChange={handle_input_change}
                        onKeyDown={handle_key_down}
                        placeholder="Ask AI... (type @ to attach a file)"
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
                <div style={{"display": "flex", "gap": "0.3rem"}}>
                    <select
                        value={permission_mode}
                        onChange={lambda (e: any) { permission_mode = e.target.value; }}
                        title="Permission mode"
                        style={{"flex": "1", "background": "#1E1E1E", "color": "#CCCCCC", "border": "1px solid #2A2B2C", "borderRadius": "3px", "fontSize": "10px", "padding": "0.15rem"}}
                    >
                        {[<option key={o["value"]} value={o["value"]}>{o["label"]}</option> for o in PERMISSION_MODE_OPTIONS]}
                    </select>
                    <select
                        value={effort}
                        onChange={lambda (e: any) { effort = e.target.value; }}
                        title="Effort"
                        style={{"flex": "1", "background": "#1E1E1E", "color": "#CCCCCC", "border": "1px solid #2A2B2C", "borderRadius": "3px", "fontSize": "10px", "padding": "0.15rem"}}
                    >
                        {[<option key={o["value"]} value={o["value"]}>{o["label"]}</option> for o in EFFORT_OPTIONS]}
                    </select>
                    <select
                        value={model}
                        onChange={lambda (e: any) { model = e.target.value; }}
                        title="Model"
                        style={{"flex": "1", "background": "#1E1E1E", "color": "#CCCCCC", "border": "1px solid #2A2B2C", "borderRadius": "3px", "fontSize": "10px", "padding": "0.15rem"}}
                    >
                        {[<option key={o["value"]} value={o["value"]}>{o["label"]}</option> for o in MODEL_OPTIONS]}
                    </select>
                </div>
            </div>
        </div>
        <CommandDialog open={attach_open} onOpenChange={lambda (v: any) { attach_open = v; }}>
            <CommandInput placeholder="Attach a file by name..." />
            <CommandList>
                <CommandEmpty>No matching files.</CommandEmpty>
                <CommandGroup heading="files">
                    {[
                        <CommandItem key={f["path"]} value={f["path"]} onSelect={handle_attach_select}>
                            <span className={"codicon " + file_icon_class(f["name"], False, False)} style={{"fontSize": "14px", "opacity": "0.85", "flexShrink": "0"}} />
                            <span>{f["name"]}</span>
                            <span style={{"marginLeft": "0.5rem", "fontSize": "11px", "color": "#8C8C8C", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>
                                {f["path"]}
                            </span>
                        </CommandItem>
                        for f in attach_files
                    ]}
                </CommandGroup>
            </CommandList>
        </CommandDialog>
    </div>
}
