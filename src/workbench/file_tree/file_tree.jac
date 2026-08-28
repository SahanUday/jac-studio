"""FileTree: Phase 2's first workbench-shell deliverable (`docs/roadmap.md`) -- a sidebar that
browses a real directory, backed by `workspace_service.jac`'s lazy `Workspace/Folder/File` graph.

**Loads lazily, one level at a time.** `internal/workspace-graph-spike/` measured ~3 seconds
combined to eagerly scan-and-traverse a real-sized project; this component never does that --
every folder's children are fetched via `list_children_by_path` only the first time that folder
is expanded, then cached client-side in `children_by_path` so re-collapsing/re-expanding doesn't
refetch.

**No native folder-picker dialog yet** (that needs desktop-capability plumbing not built in this
phase) -- the user types an absolute path and clicks "Open", the same stand-in the spike itself
used for its own demo target.

**Hand-built tree rows, not a forced fit onto shadcn's `SidebarMenuSub`.** `docs/architecture.md`
already calls this out: shadcn's ~50-primitive set doesn't ship a tree component, and
`SidebarMenuSub` is shaped for a fixed one-level submenu, not arbitrary recursive depth. `Sidebar`/
`SidebarHeader`/`SidebarContent`/`ScrollArea` provide the real outer chrome; `FileTreeNode` below
is the hand-built, self-recursive row renderer the roadmap anticipated.

**Selecting a file highlights it and calls the `onOpenFile` prop** -- Phase 2's Tabs shell
(`src/workbench/shell/workbench.jac`) passes down its own `open_tab` method, so a click here opens
(or activates) that file's tab. This component itself still owns no tab/editor state -- it only
reports which file was clicked, matching the file tree's job in a real editor.

Handler bodies live in the paired `file_tree.impl.jac` annex, per the client-component
"handler annex" pattern -- see `jac-studio-code-organization`.

**Session restore (2026-08-28, `docs/roadmap.md` Phase 3)** -- on mount, this component asks
`workspace_service.jac`'s `get_current_workspace` whether a workspace was already opened in a
previous session and, if so, opens it the same way a manual "Open" click would
(`_open_path_into_tree`, factored out of `open_folder` so both paths share one implementation).
Skips straight to the empty "enter a folder path" state when nothing was ever opened, same as
today's first-ever-run behavior -- there's no third state to design for.

**"Select for Compare" via Alt+Click (2026-08-28, `docs/roadmap.md` Phase 3's diff-editor bullet)**
-- Alt+clicking a file marks it as `compare_pending_path` (highlighted distinctly, with a header
hint) instead of opening it; Alt+clicking a *different* file then calls the new `onCompareFiles`
prop with both paths, and `workbench.jac` opens a diff tab. Alt+clicking the *same* pending file
again cancels it. Deliberately a click gesture, not the file-tree context menu VS Code itself uses
for this (`ContextMenu`, right-click "Select for Compare" / "Compare with Selected") -- that menu
is its own, separate, later Phase 3 bullet (`docs/roadmap.md`), not a prerequisite for the
diff-editor mode itself; nothing here blocks wiring the same `onCompareFiles` prop into a real
context-menu item once that lands, without touching this gesture."""

import from src.workbench.workspace.workspace_service {
    open_workspace, list_children_by_path, get_current_workspace
}

import from components.ui.sidebar {
    SidebarProvider, Sidebar, SidebarHeader, SidebarContent
}
import from components.ui.scroll_area { ScrollArea }

glob ROW_BASE_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.35rem",
    "cursor": "pointer",
    "fontSize": "13px",
    "padding": "0.2rem 0.5rem",
    "borderRadius": "3px",
    "userSelect": "none",
    "whiteSpace": "nowrap"
};

def:pub FileTreeNode(props: any) -> JsxElement {
    item = props["node"];
    depth = props["depth"];
    expanded = props["expanded"];
    children_by_path = props["children_by_path"];
    selected_path = props["selected_path"];
    compare_pending_path = props["comparePendingPath"];
    on_toggle = props["onToggle"];
    on_select = props["onSelect"];
    on_compare_select = props["onCompareSelect"];

    is_dir = item["is_dir"];
    path = item["path"];
    is_open = expanded[path] if path in expanded else False;
    is_selected = (path == selected_path);
    is_compare_pending = (not is_dir) and (path == compare_pending_path);
    indent = 8 + depth * 14;

    <div role="none">
        <div
            role="treeitem"
            aria-level={depth + 1}
            aria-selected={is_selected}
            aria-expanded={is_open if is_dir else None}
            tabIndex={0 if is_selected else -1}
            title={"Alt+Click another file to compare, or Alt+Click again to cancel" if is_compare_pending else ""}
            onClick={lambda (e: any) {
                if is_dir {
                    on_toggle(path);
                } elif e.altKey {
                    on_compare_select(path, item["name"]);
                } else {
                    on_select(path, item["name"]);
                }
            }}
            style={{
                **ROW_BASE_STYLE,
                "paddingLeft": str(indent) + "px",
                "background": "#37373d" if is_selected else ("#3d3d1e" if is_compare_pending else "transparent"),
                "outline": "1px dashed #d7ba7d" if is_compare_pending else "none"
            }}
        >
            <span style={{"width": "12px", "display": "inline-block", "fontSize": "10px", "opacity": "0.75"}}>
                {("v" if is_open else ">") if is_dir else ""}
            </span>
            <span>{item["name"]}</span>
        </div>
        {(
            <div role="group">
                {[
                    <FileTreeNode
                        key={c["path"]}
                        node={c}
                        depth={depth + 1}
                        expanded={expanded}
                        children_by_path={children_by_path}
                        selected_path={selected_path}
                        comparePendingPath={compare_pending_path}
                        onToggle={on_toggle}
                        onSelect={on_select}
                        onCompareSelect={on_compare_select}
                    />
                    for c in (children_by_path[path] if path in children_by_path else [])
                ]}
            </div>
        ) if (is_dir and is_open) else None}
    </div>
}

def:pub app(props: any) -> JsxElement {
    has on_open_file: any = props["onOpenFile"];
    has on_compare_files: any = props["onCompareFiles"];
    has opened: bool = False;
    has root_path: str = "";
    has root_name: str = "";
    has input_value: str = "";
    has expanded: dict[str, bool] = {};
    has children_by_path: dict[str, list[dict]] = {};
    has selected_path: str = "";
    has compare_pending_path: str = "";
    has compare_pending_name: str = "";

    async def _open_path_into_tree(path: str) -> None;
    async def open_folder -> None;
    async def toggle_folder(path: str) -> None;
    def select_file(path: str, name: str) -> None;
    def compare_select(path: str, name: str) -> None;

    async can with entry {
        restored = await get_current_workspace();
        if restored is not None {
            await _open_path_into_tree(restored["root_path"]);
        }
    }

    <SidebarProvider>
        <Sidebar>
            <SidebarHeader>
                <div style={{"padding": "0.5rem", "display": "flex", "gap": "0.4rem", "fontFamily": "system-ui, sans-serif"}}>
                    <input
                        value={input_value}
                        placeholder="Absolute folder path..."
                        onChange={lambda (e: any) { input_value = e.target.value; }}
                        style={{"flex": "1", "fontSize": "12px", "padding": "0.3rem 0.4rem"}}
                    />
                    <button onClick={lambda (e: any) { open_folder(); }} style={{"fontSize": "12px", "padding": "0.3rem 0.6rem"}}>
                        Open
                    </button>
                </div>
                {(
                    <div style={{"padding": "0 0.5rem 0.4rem", "fontSize": "12px", "fontWeight": "600", "fontFamily": "system-ui, sans-serif"}}>
                        {root_name}
                    </div>
                ) if opened else None}
                {(
                    <div style={{"padding": "0 0.5rem 0.4rem", "fontSize": "11px", "color": "#d7ba7d", "fontFamily": "system-ui, sans-serif"}}>
                        {"Alt+Click another file to compare with \"" + compare_pending_name + "\", or Alt+Click it again to cancel"}
                    </div>
                ) if compare_pending_path != "" else None}
            </SidebarHeader>
            <SidebarContent>
                <ScrollArea style={{"height": "70vh"}}>
                    {(
                        <div role="tree" aria-label={root_name if root_name != "" else "Files"}>
                            {[
                                <FileTreeNode
                                    key={c["path"]}
                                    node={c}
                                    depth={0}
                                    expanded={expanded}
                                    children_by_path={children_by_path}
                                    selected_path={selected_path}
                                    comparePendingPath={compare_pending_path}
                                    onToggle={toggle_folder}
                                    onSelect={select_file}
                                    onCompareSelect={compare_select}
                                />
                                for c in (children_by_path[root_path] if root_path in children_by_path else [])
                            ]}
                        </div>
                    ) if opened else (
                        <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                            Enter a folder path above and click Open.
                        </div>
                    )}
                </ScrollArea>
            </SidebarContent>
        </Sidebar>
    </SidebarProvider>
}
