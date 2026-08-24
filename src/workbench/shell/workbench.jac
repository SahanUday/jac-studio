"""Workbench: the shared parent for Phase 2's workbench-shell pieces
(`docs/roadmap.md`) -- owns the "which files are open, which is active" state that
`file_tree.jac` (reports selections) and `editor_tabs.jac` (renders tabs + content) both need,
lifted here because they're siblings with no other way to share it (see `editor_tabs.jac`'s
docstring for why this is plain lifted React-style state, not a Phase 3 graph node).

`main.jac` mounts this in place of composing `FileTreeApp`/`TextEditorApp` directly, as it did
before Tabs existed.
"""

import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }

def:pub app -> JsxElement {
    has open_tabs: list[dict[str, str]] = [];
    has active_path: str = "";

    def open_tab(path: str, name: str) -> None;
    def select_tab(path: str) -> None;
    def close_tab(path: str) -> None;

    <div style={{"display": "flex", "height": "100vh"}}>
        <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #3c3c3c", "overflow": "hidden"}}>
            <FileTreeApp onOpenFile={open_tab} />
        </div>
        <div style={{"flex": "1", "overflow": "hidden"}}>
            <EditorTabsApp
                openTabs={open_tabs}
                activePath={active_path}
                onSelectTab={select_tab}
                onCloseTab={close_tab}
            />
        </div>
    </div>
}
