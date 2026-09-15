"""FileTree: the Explorer sidebar, backed by `workspace_service.jac`'s lazy `Workspace/Folder/File`
graph. Children are fetched per folder on first expand and cached in `children_by_path`; eager
whole-workspace traversal was measured too slow (tracker
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale`). `gitStatus` is owned by
`workbench.jac` and only consumed here. `<Sidebar collapsible="none">` is required -- the default
offcanvas variant is `position: fixed` at the viewport edge and swallows activity-bar clicks."""

import from src.workbench.workspace.workspace_service {
    open_workspace, list_children_by_path, get_current_workspace,
    create_file, create_folder, rename_path, delete_path
}
import from src.workbench.file_icons.file_icons { file_icon_class }

import from components.ui.sidebar {
    SidebarProvider, Sidebar, SidebarHeader, SidebarContent
}
import from components.ui.scroll_area { ScrollArea }
import from components.ui.context_menu {
    ContextMenu, ContextMenuTrigger, ContextMenuContent, ContextMenuItem, ContextMenuSeparator
}

def _git_status_color(letter: str) -> str {
    if letter == "M" { return "#e2c08d"; }
    if letter == "A" { return "#73c991"; }
    if letter == "D" { return "#f48771"; }
    if letter == "U" { return "#73c991"; }
    return "#73c991";
}

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
    parent_path = props["parentPath"];
    expanded = props["expanded"];
    children_by_path = props["children_by_path"];
    selected_path = props["selected_path"];
    compare_pending_path = props["comparePendingPath"];
    git_status = props["gitStatus"];
    on_toggle = props["onToggle"];
    on_select = props["onSelect"];
    on_compare_select = props["onCompareSelect"];
    on_create_file = props["onCreateFile"];
    on_create_folder = props["onCreateFolder"];
    on_rename = props["onRename"];
    on_delete = props["onDelete"];

    is_dir = item["is_dir"];
    path = item["path"];
    is_open = expanded[path] if path in expanded else False;
    is_selected = (path == selected_path);
    is_compare_pending = (not is_dir) and (path == compare_pending_path);
    has_compare_pending = compare_pending_path != "";
    indent = 8 + depth * 14;
    git_status_letter = git_status[path] if (path in git_status) else "";

    <div role="none">
        <ContextMenu>
            <ContextMenuTrigger asChild={True}>
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
                        "background": "#FFFFFF22" if is_selected else ("#e5ba7d26" if is_compare_pending else "transparent"),
                        "outline": "1px dashed #e5ba7d" if is_compare_pending else "none"
                    }}
                >
                    <span
                        className={("codicon " + ("codicon-chevron-down" if is_open else "codicon-chevron-right")) if is_dir else ""}
                        style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.75"}}
                    />
                    <span
                        className={"codicon " + file_icon_class(item["name"], is_dir, is_open)}
                        style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.85"}}
                    />
                    <span style={{"flex": "1", "color": _git_status_color(git_status_letter) if git_status_letter != "" else "inherit"}}>
                        {item["name"]}
                    </span>
                    {(
                        <span
                            aria-hidden="true"
                            style={{"fontSize": "11px", "fontWeight": "600", "flexShrink": "0", "color": _git_status_color(git_status_letter)}}
                        >
                            {git_status_letter}
                        </span>
                    ) if git_status_letter != "" else None}
                </div>
            </ContextMenuTrigger>
            <ContextMenuContent>
                {(<ContextMenuItem onSelect={lambda (e: any) { on_create_file(path); }}>New File</ContextMenuItem>) if is_dir else None}
                {(<ContextMenuItem onSelect={lambda (e: any) { on_create_folder(path); }}>New Folder</ContextMenuItem>) if is_dir else None}
                {(<ContextMenuSeparator />) if is_dir else None}
                {(
                    <ContextMenuItem onSelect={lambda (e: any) { on_compare_select(path, item["name"]); }}>
                        {"Cancel Compare" if is_compare_pending else ("Compare with Selected" if has_compare_pending else "Select for Compare")}
                    </ContextMenuItem>
                ) if not is_dir else None}
                {(<ContextMenuSeparator />) if not is_dir else None}
                <ContextMenuItem onSelect={lambda (e: any) { on_rename(path, parent_path, item["name"]); }}>Rename...</ContextMenuItem>
                <ContextMenuItem variant="destructive" onSelect={lambda (e: any) { on_delete(path, parent_path, is_dir); }}>Delete</ContextMenuItem>
            </ContextMenuContent>
        </ContextMenu>
        {(
            <div role="group">
                {[
                    <FileTreeNode
                        key={c["path"]}
                        node={c}
                        depth={depth + 1}
                        parentPath={path}
                        expanded={expanded}
                        children_by_path={children_by_path}
                        selected_path={selected_path}
                        comparePendingPath={compare_pending_path}
                        gitStatus={git_status}
                        onToggle={on_toggle}
                        onSelect={on_select}
                        onCompareSelect={on_compare_select}
                        onCreateFile={on_create_file}
                        onCreateFolder={on_create_folder}
                        onRename={on_rename}
                        onDelete={on_delete}
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

    git_status = props["gitStatus"] if "gitStatus" in props else {};

    async def _open_path_into_tree(path: str) -> None;
    async def open_folder -> None;
    async def toggle_folder(path: str) -> None;
    async def refresh_children(parent_path: str) -> None;
    def select_file(path: str, name: str) -> None;
    def compare_select(path: str, name: str) -> None;
    async def create_new_file(parent_path: str) -> None;
    async def create_new_folder(parent_path: str) -> None;
    async def rename_item(path: str, parent_path: str, current_name: str) -> None;
    async def delete_item(path: str, parent_path: str, is_dir: bool) -> None;

    async can with entry {
        restored = await get_current_workspace();
        if restored is not None {
            await _open_path_into_tree(restored["root_path"]);
        }
    }

    <SidebarProvider>
        <Sidebar collapsible="none">
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
                    <ContextMenu>
                        <ContextMenuTrigger asChild={True}>
                            <div style={{"padding": "0 0.5rem 0.4rem", "fontSize": "12px", "fontWeight": "600", "fontFamily": "system-ui, sans-serif"}}>
                                {root_name}
                            </div>
                        </ContextMenuTrigger>
                        <ContextMenuContent>
                            <ContextMenuItem onSelect={lambda (e: any) { create_new_file(root_path); }}>New File</ContextMenuItem>
                            <ContextMenuItem onSelect={lambda (e: any) { create_new_folder(root_path); }}>New Folder</ContextMenuItem>
                        </ContextMenuContent>
                    </ContextMenu>
                ) if opened else None}
                {(
                    <div style={{"padding": "0 0.5rem 0.4rem", "fontSize": "11px", "color": "#e5ba7d", "fontFamily": "system-ui, sans-serif"}}>
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
                                    parentPath={root_path}
                                    expanded={expanded}
                                    children_by_path={children_by_path}
                                    selected_path={selected_path}
                                    comparePendingPath={compare_pending_path}
                                    gitStatus={git_status}
                                    onToggle={toggle_folder}
                                    onSelect={select_file}
                                    onCompareSelect={compare_select}
                                    onCreateFile={create_new_file}
                                    onCreateFolder={create_new_folder}
                                    onRename={rename_item}
                                    onDelete={delete_item}
                                />
                                for c in (children_by_path[root_path] if root_path in children_by_path else [])
                            ]}
                        </div>
                    ) if opened else (
                        <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                            Enter a folder path above and click Open.
                        </div>
                    )}
                </ScrollArea>
            </SidebarContent>
        </Sidebar>
    </SidebarProvider>
}
