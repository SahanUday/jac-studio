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
for this, at the time this was built -- the context menu was its own, separate, later Phase 3
bullet, not a prerequisite for the diff-editor mode itself. That menu now exists too (see
`FileTreeNode`'s own docstring below) and calls the exact same `compare_select` handler via a
"Select for Compare"/"Compare with Selected" item, without touching this gesture -- both trigger
paths coexist rather than one replacing the other.

**File-tree context menu (2026-08-28, `docs/roadmap.md` Phase 3)** -- new file/folder (folder rows
and the workspace-root header), rename, delete, via the shadcn `ContextMenu` primitive
(`jac install --shadcn context-menu`). `workspace_service.jac` gained the four corresponding
mutating functions; this component's job is thin: prompt for input (`prompt()`/`confirm()` --
there's no inline-rename-in-tree affordance yet, a deliberately simpler v1 than real VS Code's own
in-place text field), call the RPC, then `refresh_children` the *affected parent* so the tree
reflects the change without a full re-open. Building this surfaced two real, previously-unknown
jaseci persistence gaps -- see `docs/architecture.md`'s service-registry section and tracker
entries `2026-08-28-edge-deletion-not-committed-across-real-http-requests` and
`2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` for the full record; the
practical upshot is that `list_children_by_path` (`workspace_service.jac`) now double-checks
`os.path.exists` on every child before returning it, rather than trusting graph edge state alone.

**File-type icons (2026-08-28, `docs/roadmap.md` Phase 3's tab-affordances bullet)** -- each row now
renders a second glyph (folder/folder-opened, or an extension-bucketed file glyph) alongside the
existing expand chevron, via the shared `file_icons.jac` helper -- shared with `editor_tabs.jac`'s
tab labels so both surfaces agree on which glyph a given file gets, rather than drifting apart.

**Git status decorations (2026-08-31, `docs/roadmap.md` Phase 4's SCM bullet)** -- the "tree
decorations" half of that bullet (`monaco_editor.jac`'s gutter is the other half). `gitStatus`
(`dict[path, statusLetter]`, forwarded unmodified through every `FileTreeNode` recursion the same
way `expanded`/`selected_path` already are) is owned by `workbench.jac`, not fetched here --
`scm.jac`'s own `refresh_status` reports it up via `onStatusChange` every time *that* view
refreshes, so this component stays a pure consumer, same "leaf renders, parent owns cross-view
state" shape already used for `dirty_paths`. A row with no entry in the map renders exactly as
before (no badge, default color) -- this is additive, not a rewrite of the existing row shape."""

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
