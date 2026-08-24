"""EditorTabs: Phase 2's second workbench-shell deliverable (`docs/roadmap.md`) -- a tab bar plus
content area for open files, sitting next to `file_tree.jac`'s sidebar under a shared
`src/workbench/shell/workbench.jac` parent that owns which files are open and which is active.

**Purely presentational -- owns no state of its own.** Unlike `file_tree.jac`'s and
`text_editor.jac`'s top-level `app`s, this component takes `openTabs`/`activePath` plus
`onSelectTab`/`onCloseTab`/`onOpenTab` callbacks as props and renders from them. The state itself
lives in the shared parent (`Workbench`) because both this component and the file tree need to
read and mutate the same "which files are open" list -- lifting it to their common parent is the
standard fix for that, the same reasoning `docs/architecture.md`'s contribution-registry pattern
uses at the graph level, just applied to plain React-style prop flow here since this state is
ephemeral UI state, not graph state (see `document_service.jac`'s docstring on why the Phase 3
`EditorGroup`/`Tab` nodes aren't built yet).

**Hand-built tab row, not shadcn's `Tabs`/`TabsTrigger`.** A close ("x") button belongs inside
each tab per real-editor convention, but Radix's `TabsTrigger` renders as a `<button>`, and a
`<button>` inside a `<button>` is invalid HTML (and breaks the trigger's own click/keyboard
handling). Same call `file_tree.jac` already made for its rows against `SidebarMenuSub` -- use the
primitive where it fits, hand-roll where it doesn't.

**Every open tab's `TextEditorApp` stays mounted**, hidden via `display: none` rather than
conditionally rendered, so switching tabs never re-fetches content or resets a tab's cursor
position -- the whole reason this doesn't use Radix `TabsContent`, which unmounts inactive panels
by default.
"""

import from src.editor.client.text_editor { app as TextEditorApp }

glob TAB_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.4rem",
    "padding": "0.35rem 0.5rem",
    "fontSize": "12px",
    "fontFamily": "system-ui, sans-serif",
    "cursor": "pointer",
    "userSelect": "none",
    "borderRight": "1px solid #3c3c3c",
    "whiteSpace": "nowrap"
};

def:pub app(props: any) -> JsxElement {
    open_tabs = props["openTabs"];
    active_path = props["activePath"];
    on_select_tab = props["onSelectTab"];
    on_close_tab = props["onCloseTab"];

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "overflow": "hidden"}}>
        <div style={{"display": "flex", "borderBottom": "1px solid #3c3c3c", "background": "#252526", "flexShrink": "0"}}>
            {[
                <div
                    key={t["path"]}
                    onClick={lambda (e: any) { on_select_tab(t["path"]); }}
                    style={{
                        **TAB_STYLE,
                        "background": "#1e1e1e" if t["path"] == active_path else "transparent",
                        "color": "#d4d4d4" if t["path"] == active_path else "#969696"
                    }}
                >
                    <span>{t["name"]}</span>
                    <span
                        onClick={lambda (e: any) { e.stopPropagation(); on_close_tab(t["path"]); }}
                        style={{"opacity": "0.6", "fontSize": "13px", "lineHeight": "1"}}
                    >
                        &times;
                    </span>
                </div>
                for t in open_tabs
            ]}
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0.75rem"}}>
            {(
                [
                    <div key={t["path"]} style={{"display": "block" if t["path"] == active_path else "none", "height": "100%"}}>
                        <TextEditorApp path={t["path"]} />
                    </div>
                    for t in open_tabs
                ]
            ) if len(open_tabs) > 0 else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                    No file open. Select one from the file tree.
                </div>
            )}
        </div>
    </div>
}
