"""MonacoEditorApp: one `@monaco-editor/react` `<Editor>` per open tab, with breadcrumb bar, git
gutter and breakpoint glyph margin. Monaco owns the text after mount (`defaultValue`, never a
controlled `value`). `options.glyphMargin` must stay `True` or glyph decorations silently never
render. Auto-reloads on a clean external change (ADR 0072), never a dirty tab. Monaco's
shared-model, keybinding and null-`getPosition()` gotchas: `docs/libraries/monaco.md`, ADR 0074.
Handler bodies: `monaco_editor.impl.jac`."""

import from "react" { useEffect }
import from "@monaco-editor/react" { Editor }
import from src.editor.document_service { open_document, save_document }
import from src.editor.client.jac_language { register_jac_language }
import from src.editor.client.jac_completion_provider { register_jac_completion_provider }
import from src.editor.client.jac_hover_provider { register_jac_hover_provider }
import from src.editor.client.jac_definition_provider { register_jac_definition_provider }
import from src.editor.client.jac_reference_provider { register_jac_reference_provider }
import from src.editor.client.jac_rename_provider { register_jac_rename_provider }
import from src.editor.client.git_conflict_codelens_provider { register_conflict_codelens_provider }
import from src.editor.client.ai_code_action_provider { register_ai_code_action_provider }
import from src.editor.client.inline_chat_widget { app as InlineChatWidgetApp }
import from src.workbench.scm.git_service { get_line_changes }
import from src.workbench.lsp.lsp_client { notify_document_open, notify_document_save, get_document_symbols }
import from src.workbench.symbol_icons.symbol_icons { symbol_icon_class }
import from src.editor.client.breadcrumb_symbols { symbol_path_at_position }
import from src.workbench.dap.dap_client { get_breakpoints, set_breakpoints }
import from src.editor.client.command_palette_override { register_command_palette_override }

glob _focused_editor_handlers: dict[str, dict[str, any]] = {};
glob _global_keybindings_registered: bool = False;

"""Registered once globally, dispatching by live focus: per-instance `addCommand` does not scope to
its own editor -- `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance`."""
def _register_global_editor_keybindings(editor: any, monaco: any) -> None {
    if _global_keybindings_registered {
        return;
    }
    _global_keybindings_registered = True;

    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, lambda {
        focused = [e for e in monaco.editor.getEditors() if e.hasTextFocus()];
        if len(focused) == 0 {
            return;
        }
        handlers = _focused_editor_handlers.get(focused[0].getModel().uri.path);
        if handlers {
            handlers["save"]();
        }
    });
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyI, lambda {
        focused = [e for e in monaco.editor.getEditors() if e.hasTextFocus()];
        if len(focused) == 0 {
            return;
        }
        handlers = _focused_editor_handlers.get(focused[0].getModel().uri.path);
        if handlers {
            handlers["toggleInlineChat"]();
        }
    });
}

def:pub app(path: str, onCursorChange: any, initialCursor: any, onDirtyChange: any, onOpenLocation: any, onOpenCommandPalette: any, onAskAI: any, reloadNonce: any) -> JsxElement {
    has content: str = "";
    has loaded: bool = False;
    has dirty: bool = False;
    has editor_ref: Ref[any] = Ref();
    has monaco_ref: Ref[any] = Ref();
    has decorations_ref: Ref[any] = Ref();
    has breakpoints_ref: Ref[any] = Ref();
    has suppress_dirty_ref: Ref[any] = Ref();
    has symbols: list[dict[str, any]] = [];
    has breadcrumb_path: list[dict[str, any]] = [];
    has breakpoint_lines: list[int] = [];
    has inline_chat_open: bool = False;

    async can with entry {
        result = await open_document(path);
        loaded_content = result["content"];
        content = loaded_content;
        loaded = True;
        await notify_document_open(path, loaded_content);
        await refresh_symbols(loaded_content);
        if len(symbols) == 0 {
            # documentSymbol answers from `jac lsp`'s hub, empty until the first type-check lands
            setTimeout(lambda { retry_refresh_symbols(loaded_content); }, 4000);
        }
        breakpoint_lines = await get_breakpoints(path);
    }

    async def reload_from_disk -> None;

    # reloadNonce == 0 means "nothing pending" (workbench.jac's default for a path with no entry in
    # filesPendingReload); also skips the mount-time firing every useEffect gets for free, since
    # content is already freshly loaded by can with entry above at that point.
    useEffect(lambda {
        if reloadNonce == 0 or not loaded {
            return;
        }
        reload_from_disk();
    }, [reloadNonce]);

    def handle_before_mount(monaco: any) -> None;
    def handle_mount(editor: any, monaco: any) -> None;
    async def handle_save -> None;
    def handle_cursor_change(e: any) -> None;
    def apply_breakpoint_decorations -> None;
    async def handle_gutter_click(e: any) -> None;
    def handle_content_change(e: any) -> None;
    async def apply_git_decorations -> None;
    async def refresh_symbols(current_content: str) -> None;
    async def retry_refresh_symbols(current_content: str) -> None;
    def update_breadcrumb -> None;
    def handle_breadcrumb_click(target_line: int, target_column: int) -> None;
    def toggle_inline_chat -> None;
    def close_inline_chat -> None;

    <div style={{"height": "100%", "width": "100%", "display": "flex", "flexDirection": "column"}}>
        {(
            <div
                style={{
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "0.3rem",
                    "padding": "0.25rem 0.6rem",
                    "borderBottom": "1px solid #2A2B2C",
                    "background": "#191A1B",
                    "fontSize": "12px",
                    "fontFamily": "system-ui, sans-serif",
                    "color": "#8C8C8C",
                    "flexShrink": "0",
                    "overflow": "auto",
                    "whiteSpace": "nowrap"
                }}
            >
                <span style={{"display": "flex", "alignItems": "center", "gap": "0.25rem"}}>
                    <span className="codicon codicon-file" style={{"fontSize": "13px", "opacity": "0.8"}} />
                    <span>{path.split("/")[-1]}</span>
                </span>
                {[
                    <span key={sym["name"] + ":" + str(sym["line"])} style={{"display": "flex", "alignItems": "center", "gap": "0.25rem"}}>
                        <span className="codicon codicon-chevron-right" style={{"fontSize": "11px", "opacity": "0.5"}} />
                        <span
                            role="button"
                            tabIndex={0}
                            onClick={lambda (e: any) { handle_breadcrumb_click(sym["line"], sym["column"]); }}
                            style={{"display": "flex", "alignItems": "center", "gap": "0.25rem", "cursor": "pointer"}}
                        >
                            <span className={"codicon " + symbol_icon_class(sym["kind"])} style={{"fontSize": "13px", "opacity": "0.8"}} />
                            <span>{sym["name"]}</span>
                        </span>
                    </span>
                    for sym in breadcrumb_path
                ]}
            </div>
        ) if loaded else None}
        <div style={{"flex": "1", "overflow": "hidden"}}>
            {(
                <Editor
                    path={path}
                    defaultValue={content}
                    theme="vs-dark"
                    beforeMount={handle_before_mount}
                    onMount={handle_mount}
                    onChange={handle_content_change}
                    keepCurrentModel={True}
                    options={{"automaticLayout": True, "minimap": {"enabled": True}, "glyphMargin": True}}
                />
            ) if loaded else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    Loading...
                </div>
            )}
            {(
                <InlineChatWidgetApp open={inline_chat_open} onClose={close_inline_chat} editorRef={editor_ref} monacoRef={monaco_ref} path={path} />
            ) if loaded else None}
        </div>
    </div>
}
