"""EditorTabs: tab bar plus content area for one editor group. Purely presentational -- open tabs,
active path and every callback come from `workbench.jac`, and `groupId` is forwarded as the first
argument of each callback. Every tab's editor stays mounted and is hidden with `display: none`, so
switching tabs never refetches content or loses Monaco undo history. A tab's optional `kind`
(`"diff"` / `"gitdiff"`) selects which editor component renders its panel; both reload on a clean
external change via `filesPendingReload` (ADR 0072), a `"gitdiff"` tab unconditionally since it has
no dirty state of its own.
Hide-on-hover here must use opacity, never `display`: codicon's own
`.codicon[class*='codicon-']{display:inline-block}` outranks Tailwind's `.hidden` on specificity."""

import from src.editor.client.monaco_editor { app as MonacoEditorApp }
import from src.editor.client.monaco_diff_editor { app as MonacoDiffEditorApp }
import from src.workbench.scm.scm_diff_editor { app as ScmDiffEditorApp }
import from components.ui.button { Button }
import from src.workbench.file_icons.file_icons { file_icon_class }

"""Jac comprehensions cannot tuple-unpack (`for i, t in enumerate(...)` fails to parse), so DOM ids
derive from the path, not a loop index -- safe since a group never holds two tabs for one path."""
def _tab_dom_id(group_id: str, path: str) -> str {
    return "tab-" + group_id + "-" + path;
}

glob TAB_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.4rem",
    "padding": "0.35rem 0.5rem",
    "fontSize": "12px",
    "fontFamily": "system-ui, sans-serif",
    "cursor": "pointer",
    "userSelect": "none",
    "borderRight": "1px solid #2A2B2C",
    "whiteSpace": "nowrap"
};

def:pub app(props: any) -> JsxElement {
    group_id = props["groupId"];
    open_tabs = props["openTabs"];
    active_path = props["activePath"];
    on_select_tab = props["onSelectTab"];
    on_close_tab = props["onCloseTab"];
    on_split_group = props["onSplitGroup"];
    on_cursor_change = props["onCursorChange"];
    initial_cursors = props["initialCursors"];
    dirty_paths = props["dirtyPaths"];
    on_dirty_change = props["onDirtyChange"];
    files_pending_reload = props["filesPendingReload"] if "filesPendingReload" in props else {};
    on_open_location = props["onOpenLocation"];
    on_open_command_palette = props["onOpenCommandPalette"];
    on_ask_ai = props["onAskAI"];

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "overflow": "hidden"}}>
        <div role="tablist" aria-label="Open editors" style={{"display": "flex", "alignItems": "center", "borderBottom": "1px solid #2A2B2C", "background": "#191A1B", "flexShrink": "0"}}>
            <div style={{"display": "flex", "flex": "1", "overflow": "auto"}}>
                {[
                    <div
                        key={t["path"]}
                        id={_tab_dom_id(group_id, t["path"])}
                        role="tab"
                        aria-selected={t["path"] == active_path}
                        aria-controls={"panel-" + _tab_dom_id(group_id, t["path"])}
                        tabIndex={0 if t["path"] == active_path else -1}
                        onClick={lambda (e: any) { on_select_tab(group_id, t["path"]); }}
                        className="group"
                        style={{
                            **TAB_STYLE,
                            "background": "#121314" if t["path"] == active_path else "transparent",
                            "color": "#bfbfbf" if t["path"] == active_path else "#8C8C8C"
                        }}
                    >
                        <span
                            className={"codicon " + ("codicon-diff" if t.get("kind") in ["diff", "gitdiff"] else file_icon_class(t["name"], False, False))}
                            style={{"fontSize": "14px", "opacity": "0.85"}}
                        />
                        <span>{t["name"]}</span>
                        {(
                            <span
                                className="codicon codicon-circle-filled opacity-80 group-hover:opacity-0 transition-opacity"
                                style={{"fontSize": "10px", "lineHeight": "1"}}
                            />
                        ) if dirty_paths.get(t["path"], False) else None}
                        <span
                            role="button"
                            aria-label={"Close " + t["name"]}
                            onClick={lambda (e: any) { e.stopPropagation(); on_close_tab(group_id, t["path"]); }}
                            className={"codicon codicon-close transition-opacity " + ("opacity-0 pointer-events-none group-hover:opacity-60 group-hover:pointer-events-auto" if dirty_paths.get(t["path"], False) else "opacity-60")}
                            style={{"fontSize": "13px", "lineHeight": "1"}}
                        />
                    </div>
                    for t in open_tabs
                ]}
            </div>
            <Button
                variant="ghost"
                size="icon-sm"
                title="Split editor right"
                onClick={lambda (e: any) { on_split_group(group_id); }}
                style={{"flexShrink": "0", "marginRight": "0.25rem"}}
            >
                <span className="codicon codicon-split-horizontal" style={{"fontSize": "16px"}} />
            </Button>
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0.75rem"}}>
            {(
                [
                    <div
                        key={t["path"]}
                        id={"panel-" + _tab_dom_id(group_id, t["path"])}
                        role="tabpanel"
                        aria-labelledby={_tab_dom_id(group_id, t["path"])}
                        style={{"display": "block" if t["path"] == active_path else "none", "height": "100%"}}
                    >
                        {(
                            <MonacoDiffEditorApp originalPath={t["originalPath"]} modifiedPath={t["modifiedPath"]} />
                        ) if t.get("kind") == "diff" else (
                            <ScmDiffEditorApp
                                filePath={t["filePath"]}
                                staged={t["staged"]}
                                reloadNonce={files_pending_reload[t["filePath"]] if t["filePath"] in files_pending_reload else 0}
                            />
                        ) if t.get("kind") == "gitdiff" else (
                            <MonacoEditorApp
                                path={t["path"]}
                                onCursorChange={on_cursor_change}
                                initialCursor={initial_cursors[t["path"]] if t["path"] in initial_cursors else None}
                                onDirtyChange={on_dirty_change}
                                reloadNonce={files_pending_reload[t["path"]] if t["path"] in files_pending_reload else 0}
                                onOpenLocation={on_open_location}
                                onOpenCommandPalette={on_open_command_palette}
                                onAskAI={on_ask_ai}
                            />
                        )}
                    </div>
                    for t in open_tabs
                ]
            ) if len(open_tabs) > 0 else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    No file open. Select one from the file tree.
                </div>
            )}
        </div>
    </div>
}
