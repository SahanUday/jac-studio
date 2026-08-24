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

**Command palette (2026-08-25, `docs/roadmap.md` Phase 2)** -- `CommandPaletteApp` mounts here
because it needs to invoke the same group-mutating abilities (`split_group`, `close_tab`) that
`EditorTabsApp`'s buttons already call directly; `handle_command` is the one place that maps a
command id from the palette onto one of them, so adding a new palette-reachable command later is a
one-line dispatch addition here, not a new prop threaded through every layer.

**Status bar (2026-08-25, `docs/roadmap.md` Phase 2)** -- `cursor_positions` is keyed by tab path,
not a single global `(line, column)`, so switching to an already-open tab (no remount, so no fresh
`onDidChangeCursorPosition` fires) still shows that tab's own last-known position instead of a
stale reading left over from whichever tab was active before. The status bar itself always reflects
`active_group_id`'s active tab -- `docs/roadmap.md` scopes this bullet to cursor position only, so
there's no per-group status bar yet.
"""

import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }
import from src.workbench.command_palette.command_palette { app as CommandPaletteApp }
import from src.workbench.status_bar.status_bar { app as StatusBarApp }
import from components.ui.resizable { ResizablePanelGroup, ResizablePanel, ResizableHandle }

def:pub app -> JsxElement {
    has groups: list[dict[str, any]] = [{"id": "group-1", "tabs": [], "activePath": ""}];
    has active_group_id: str = "group-1";
    has next_group_id: int = 2;
    has cursor_positions: dict[str, dict[str, int]] = {};

    def open_tab(path: str, name: str) -> None;
    def select_tab(group_id: str, path: str) -> None;
    def close_tab(group_id: str, path: str) -> None;
    def split_group(group_id: str) -> None;
    def handle_command(command_id: str) -> None;
    def handle_cursor_change(path: str, line: int, column: int) -> None;

    active_group_list = [g for g in groups if g["id"] == active_group_id];
    active_tab_path = active_group_list[0]["activePath"] if len(active_group_list) > 0 else "";
    active_cursor = cursor_positions[active_tab_path] if active_tab_path in cursor_positions else {"line": 1, "column": 1};

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
                    onCursorChange={handle_cursor_change}
                />
            </ResizablePanel>
        );
        if idx < panel_count - 1 {
            panel_children.append(<ResizableHandle key={g["id"] + "-handle"} />);
        }
    }

    <div style={{"display": "flex", "flexDirection": "column", "height": "100vh"}}>
        <CommandPaletteApp onRunCommand={handle_command} />
        <div style={{"display": "flex", "flex": "1", "overflow": "hidden"}}>
            <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #3c3c3c", "overflow": "hidden"}}>
                <FileTreeApp onOpenFile={open_tab} />
            </div>
            <div style={{"flex": "1", "overflow": "hidden"}}>
                <ResizablePanelGroup direction="horizontal">
                    {panel_children}
                </ResizablePanelGroup>
            </div>
        </div>
        <StatusBarApp line={active_cursor["line"]} column={active_cursor["column"]} path={active_tab_path} />
    </div>
}
