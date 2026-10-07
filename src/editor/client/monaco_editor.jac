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
import from src.editor.client.jac_theme { register_jac_theme, THEME_NAME }
import from src.editor.client.editor_settings { monaco_options_from_settings }
import from src.editor.client.jac_completion_provider { register_jac_completion_provider }
import from src.editor.client.jac_hover_provider { register_jac_hover_provider }
import from src.editor.client.jac_formatting_provider { register_jac_formatting_provider }
import from src.editor.client.jac_semantic_tokens_provider { register_jac_semantic_tokens_provider }
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

glob _SYMBOLS_SETTLE_MS: int = 2000;
glob _focused_editor_handlers: dict[str, dict[str, any]] = {};
glob _global_keybindings_registered: bool = False;
glob _monaco_instance: any = None;
glob _editor_settings: dict[str, any] = {};
glob _last_focused_editor: any = None;

"""Stores the effective settings and pushes them to every live editor; later mounts and re-renders read
`_editor_settings` too, since the `options` prop would otherwise reset them (`@monaco-editor/react`
re-applies it on each render)."""
def:pub apply_editor_settings(settings: dict[str, any]) -> None {
    _editor_settings = settings;
    if _monaco_instance is None {
        return;
    }
    options = monaco_options_from_settings(settings);
    for e in _monaco_instance.editor.getEditors() {
        e.updateOptions(options);
    }
}

def _track_editor(editor: any, monaco: any) -> None {
    _monaco_instance = monaco;
    editor.onDidFocusEditorText(lambda { _last_focused_editor = editor; });
}

"""The live editor showing `path`, preferring the one that last had focus (a split can show one file
twice). Callers click away from Monaco first, so its own focus check can't pick the target."""
def _editor_for(path: str) -> any {
    if _monaco_instance is None {
        return None;
    }
    candidates = [e for e in _monaco_instance.editor.getEditors() if e.getModel() and e.getModel().uri.path == path];
    if len(candidates) == 0 {
        return None;
    }
    target = candidates[0];
    for e in candidates {
        if e == _last_focused_editor {
            target = e;
        }
    }
    return target;
}

def _language_name(language_id: str) -> str {
    for lang in _monaco_instance.languages.getLanguages() {
        if lang.id == language_id {
            return lang.aliases[0] if (lang.aliases and len(lang.aliases) > 0) else language_id;
        }
    }
    return language_id;
}

"""Language, line ending and indentation of the editor showing `path`, for the status bar; `None` when
no editor shows it."""
def:pub get_editor_status(path: str) -> dict[str, any] | None {
    editor = _editor_for(path);
    if editor is None {
        return None;
    }
    model = editor.getModel();
    options = model.getOptions();
    language_id = model.getLanguageId();
    return {
        "language": language_id,
        "languageName": _language_name(language_id),
        "eol": "CRLF" if model.getEOL() == "\r\n" else "LF",
        "insertSpaces": options.insertSpaces,
        "tabSize": options.tabSize
    };
}

"""Every language Monaco knows, by display name."""
def:pub list_editor_languages -> list[dict[str, str]] {
    if _monaco_instance is None {
        return [];
    }
    named = [{"id": l.id, "name": _language_name(l.id)} for l in _monaco_instance.languages.getLanguages()];
    return sorted(named, key=lambda (l: dict[str, str]) { l["name"].lower(); });
}

"""`kind` is `indent` (value `{insertSpaces, tabSize}`), `eol` (`"LF"` or `"CRLF"`) or `language` (an id).
Applies to this editor's model only; nothing is written to settings."""
def:pub set_editor_option(path: str, kind: str, value: any) -> bool {
    editor = _editor_for(path);
    if editor is None {
        return False;
    }
    model = editor.getModel();
    if kind == "indent" {
        model.updateOptions(value);
    } elif kind == "eol" {
        model.setEOL(1 if value == "CRLF" else 0);
    } elif kind == "language" {
        _monaco_instance.editor.setModelLanguage(model, value);
    } else {
        return False;
    }
    return True;
}

"""Runs a menu or palette command on the active editor; see `_editor_for` for which one."""
def:pub run_editor_command(path: str, command: str) -> bool {
    if command == "save" {
        handlers = _focused_editor_handlers.get(path);
        if not handlers {
            return False;
        }
        handlers["save"]();
        return True;
    }
    target = _editor_for(path);
    if target is None {
        return False;
    }
    target.focus();
    if command == "selectAll" {
        target.setSelection(target.getModel().getFullModelRange());
        return True;
    }
    if command in ["undo", "redo"] {
        target.trigger("menu", command, None);
        return True;
    }
    action = target.getAction(command);
    if not action {
        return False;
    }
    action.run();
    return True;
}

"""Jumps a tab's live editor -- `initialCursor` only applies at mount, not after."""
def:pub reveal_position_in_editor(path: str, line: int, column: int) -> bool {
    handlers = _focused_editor_handlers.get(path);
    if not handlers {
        return False;
    }
    handlers["reveal"](line, column);
    return True;
}

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

def:pub app(path: str, onCursorChange: any, initialCursor: any, onDirtyChange: any, onOpenLocation: any, onOpenCommandPalette: any, onAskAI: any, reloadNonce: any, onSymbolsChange: any) -> JsxElement {
    has content: str = "";
    has loaded: bool = False;
    has dirty: bool = False;
    has editor_ref: Ref[any] = Ref();
    has monaco_ref: Ref[any] = Ref();
    has decorations_ref: Ref[any] = Ref();
    has breakpoints_ref: Ref[any] = Ref();
    has suppress_dirty_ref: Ref[any] = Ref();
    has symbols_timer_ref: Ref[any] = Ref();
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
            setTimeout(lambda { refresh_symbols_and_breadcrumb(loaded_content); }, 4000);
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
    async def refresh_symbols_and_breadcrumb(current_content: str) -> None;
    def update_breadcrumb -> None;
    def handle_breadcrumb_click(target_line: int, target_column: int) -> None;
    def handle_reveal_position(line: int, column: int) -> None;
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
                    theme={THEME_NAME}
                    beforeMount={handle_before_mount}
                    onMount={handle_mount}
                    onChange={handle_content_change}
                    keepCurrentModel={True}
                    options={{"automaticLayout": True, "glyphMargin": True, "semanticHighlighting.enabled": True, **monaco_options_from_settings(_editor_settings)}}
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
