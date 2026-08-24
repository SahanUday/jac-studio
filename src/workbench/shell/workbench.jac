"""Workbench: the shared parent for Phase 2's workbench-shell pieces
(`docs/roadmap.md`) -- owns the "which files are open, which is active" state that
`file_tree.jac` (reports selections) and `editor_tabs.jac` (renders tabs + content) both need,
lifted here because they're siblings with no other way to share it (see `editor_tabs.jac`'s
docstring for why this is plain lifted React-style state, not a Phase 3 graph node).

`main.jac` mounts this in place of composing `FileTreeApp`/`TextEditorApp` directly, as it did
before Tabs existed.

**Editor groups (2026-08-25, `docs/roadmap.md` Phase 2)** -- side-by-side, resizable editor
panes, VS Code's "split editor" feature. `open_tabs`/`active_path` became `groups`, a list of
`{"id", "tabs", "activePath"}` dicts, plus `active_group_id` naming which one newly-opened files
land in. `EditorTabsApp` itself didn't need to know it's one of several -- it already took its
tab list/active path as props, so it now also takes a plain `groupId` prop and forwards it on
every callback instead of the parent baking group identity into a per-iteration closure (see
`editor_tabs.jac`'s docstring for why that shape was chosen over closures-in-a-loop). Groups are
laid out with shadcn's `Resizable` primitive -- `ResizablePanelGroup` + one `ResizablePanel` per
group + a `ResizableHandle` between each pair, so panes are drag-resizable like every other
multi-pane split in a real editor.
"""

import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }
import from components.ui.resizable { ResizablePanelGroup, ResizablePanel, ResizableHandle }

def:pub app -> JsxElement {
    has groups: list[dict[str, any]] = [{"id": "group-1", "tabs": [], "activePath": ""}];
    has active_group_id: str = "group-1";
    has next_group_id: int = 2;

    def open_tab(path: str, name: str) -> None;
    def select_tab(group_id: str, path: str) -> None;
    def close_tab(group_id: str, path: str) -> None;
    def split_group(group_id: str) -> None;

    panel_count = len(groups);
    panel_children = [];
    for idx in range(panel_count) {
        g = groups[idx];
        panel_children.append(
            <ResizablePanel key={g["id"]} defaultSize={100 / panel_count} minSize={15}>
                <EditorTabsApp
                    groupId={g["id"]}
                    openTabs={g["tabs"]}
                    activePath={g["activePath"]}
                    onSelectTab={select_tab}
                    onCloseTab={close_tab}
                    onSplitGroup={split_group}
                />
            </ResizablePanel>
        );
        if idx < panel_count - 1 {
            panel_children.append(<ResizableHandle key={g["id"] + "-handle"} />);
        }
    }

    <div style={{"display": "flex", "height": "100vh"}}>
        <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #3c3c3c", "overflow": "hidden"}}>
            <FileTreeApp onOpenFile={open_tab} />
        </div>
        <div style={{"flex": "1", "overflow": "hidden"}}>
            <ResizablePanelGroup direction="horizontal">
                {panel_children}
            </ResizablePanelGroup>
        </div>
    </div>
}
