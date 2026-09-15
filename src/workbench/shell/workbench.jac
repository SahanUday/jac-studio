"""Workbench shell: owns the editor-group state its sibling views share (`groups`,
`active_group_id`, `cursor_positions`, notifications, sidebar/panel selection) and routes every
command id through `handle_command`. Sidebar views and bottom panels mount once and hide via CSS,
never conditional render, so each keeps its own state across switches. Structural mutations
persist through `session_service.jac`. Reloads a clean tab (plain or `"gitdiff"`) on an external
file change reported by the workspace watcher, never a dirty one (ADR 0072). See `docs/roadmap.md`
Phases 2-4."""

import from "react" { useEffect }
import from "sonner" { Toaster, toast }
import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.search.search { app as SearchApp }
import from src.workbench.scm.scm { app as ScmApp }
import from src.workbench.outline.outline { app as OutlineApp }
import from src.workbench.ai.ai_chat { app as AIChatApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }
import from src.workbench.activity_bar.activity_bar { app as ActivityBarApp }
import from src.workbench.command_palette.command_palette { app as CommandPaletteApp }
import from src.workbench.quick_open.quick_open { app as QuickOpenApp }
import from src.workbench.title_bar.title_bar { app as TitleBarApp }
import from src.workbench.status_bar.status_bar { app as StatusBarApp }
import from src.workbench.terminal.terminal { app as TerminalApp }
import from src.workbench.output.output { app as OutputApp }
import from src.workbench.tasks.problems { app as ProblemsApp }
import from src.workbench.debug.debug_console { app as DebugConsoleApp }
import from src.workbench.tasks.task_picker { app as TaskPickerApp }
import from src.workbench.tasks.task_service { run_task }
import from src.workbench.commands.command_registry { list_commands }
import from src.workbench.session.session_service { load_session, save_session }
import from components.ui.resizable { ResizablePanelGroup, ResizablePanel, ResizableHandle }

def:pub app(onToggleTheme: any) -> JsxElement {
    has groups: list[dict[str, any]] = [{"id": "group-1", "tabs": [], "activePath": ""}];
    has active_group_id: str = "group-1";
    has next_group_id: int = 2;
    has cursor_positions: dict[str, dict[str, int]] = {};
    has dirty_paths: dict[str, bool] = {};
    has files_pending_reload: dict[str, int] = {};
    has next_reload_nonce: int = 1;
    has terminal_open: bool = False;
    has active_bottom_panel: str = "terminal";
    has quick_open_open: bool = False;
    has command_palette_open: bool = False;
    has active_view_id: str = "explorer";
    has commands: list[dict[str, any]] = [];
    has context: dict[str, bool] = {};
    has cursor_save_timer: Ref[any] = Ref();
    has notifications: list[dict[str, any]] = [];
    has next_notification_id: int = 1;
    has notification_panel_open: bool = False;
    has git_status_by_path: dict[str, str] = {};
    has task_picker_open: bool = False;
    has ai_pending_prompt: str = "";
    has ai_pending_auto_send: bool = False;
    has ai_pending_nonce: int = 0;
    has ai_chat_maximized: bool = False;

    async def _save_session -> None;
    async def _toggle_panel(panel_id: str) -> None;
    def _upsert_tab_in_active_group(tab: dict[str, any]) -> list[dict[str, any]];
    async def open_tab(path: str, name: str) -> None;
    async def open_search_result(path: str, name: str, line: int, column: int) -> None;
    async def open_diff_tab(path_a: str, name_a: str, path_b: str, name_b: str) -> None;
    async def open_scm_diff(path: str, name: str, staged: bool) -> None;
    async def select_tab(group_id: str, path: str) -> None;
    async def close_tab(group_id: str, path: str) -> None;
    async def split_group(group_id: str) -> None;
    async def handle_command(command_id: str) -> None;
    def handle_cursor_change(path: str, line: int, column: int) -> None;
    def handle_dirty_change(path: str, is_dirty: bool) -> None;
    def handle_files_changed_externally(paths: list[str]) -> None;
    def set_context(key: str, value: bool) -> None;
    def context_matches(when: str) -> bool;
    def handle_keydown(e: any) -> None;
    def set_quick_open_open(next_open: bool) -> None;
    def set_command_palette_open(next_open: bool) -> None;
    def select_view(view_id: str) -> None;
    def add_notification(message: str, severity: str, source: str) -> None;
    def dismiss_notification(notification_id: int) -> None;
    def clear_notifications -> None;
    def set_notification_panel_open(next_open: bool) -> None;
    def set_git_status(status_map: dict[str, str]) -> None;
    def set_task_picker_open(next_open: bool) -> None;
    async def run_selected_task(label: str) -> None;
    def handle_ask_ai(promptText: str, autoSend: bool) -> None;
    def toggle_ai_chat_maximized -> None;

    async can with entry {
        commands = await list_commands();
        session = await load_session();
        if len(session["groups"]) > 0 {
            # cursor_positions must land before groups: groups going non-empty is what mounts each
            # tab's MonacoEditorApp, and initialCursor is read exactly once at that mount. Assign
            # groups first and every editor reports Monaco's default (1,1) back up, overwriting the
            # just-restored value and persisting the corruption on the next save.
            cursor_positions = session["cursorPositions"];
            active_group_id = session["activeGroupId"];
            next_group_id = session["nextGroupId"];
            terminal_open = session["terminalOpen"];
            groups = session["groups"];
        }
    }

    useEffect(lambda {
        listener = lambda (e: any) { handle_keydown(e); };
        document.addEventListener("keydown", listener, True);
        return lambda { document.removeEventListener("keydown", listener, True); };
    }, []);

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
                    initialCursors={cursor_positions}
                    dirtyPaths={dirty_paths}
                    onDirtyChange={handle_dirty_change}
                    filesPendingReload={files_pending_reload}
                    onOpenLocation={open_search_result}
                    onOpenCommandPalette={lambda (e: any) { handle_command("workbench.action.showCommands"); }}
                    onAskAI={handle_ask_ai}
                />
            </ResizablePanel>
        );
        if idx < panel_count - 1 {
            panel_children.append(<ResizableHandle key={g["id"] + "-handle"} />);
        }
    }

    <div style={{"display": "flex", "flexDirection": "column", "height": "100vh"}}>
        <Toaster theme="dark" position="bottom-right" />
        <CommandPaletteApp open={command_palette_open} onOpenChange={set_command_palette_open} onRunCommand={handle_command} />
        <QuickOpenApp open={quick_open_open} onOpenChange={set_quick_open_open} onOpenFile={open_tab} />
        <TaskPickerApp open={task_picker_open} onOpenChange={set_task_picker_open} onRunTask={run_selected_task} />
        <TitleBarApp onOpenCommandPalette={lambda (e: any) { handle_command("workbench.action.showCommands"); }} />
        <div style={{"display": "flex", "flex": "1", "overflow": "hidden"}}>
            <ActivityBarApp activeViewId={active_view_id} onSelectView={select_view} />
            <ResizablePanelGroup direction="horizontal" style={{"flex": "1"}}>
                <ResizablePanel defaultSize={18} minSize={12} maxSize={60} style={{"borderRight": "1px solid #2A2B2C", "overflow": "hidden", "position": "relative", "background": "#191A1B"}}>
                    <div style={{"display": "block" if active_view_id == "explorer" else "none", "height": "100%"}}>
                        <FileTreeApp onOpenFile={open_tab} onCompareFiles={open_diff_tab} gitStatus={git_status_by_path} onFilesChangedExternally={handle_files_changed_externally} />
                    </div>
                    <div style={{"display": "block" if active_view_id == "search" else "none", "height": "100%"}}>
                        <SearchApp onOpenResult={open_search_result} />
                    </div>
                    <div style={{"display": "block" if active_view_id == "scm" else "none", "height": "100%"}}>
                        <ScmApp active={active_view_id == "scm"} onOpenDiff={open_scm_diff} onOpenFile={open_tab} onNotify={add_notification} onStatusChange={set_git_status} />
                    </div>
                    <div style={{"display": "block" if active_view_id == "outline" else "none", "height": "100%"}}>
                        <OutlineApp
                            active={active_view_id == "outline"}
                            path={active_tab_path}
                            onOpenLocation={open_search_result}
                            cursorLine={active_cursor["line"]}
                            cursorColumn={active_cursor["column"]}
                        />
                    </div>
                    <div style={{"display": "block" if active_view_id == "ai_chat" else "none", "height": "100%"}}>
                        <AIChatApp
                            active={active_view_id == "ai_chat"}
                            pendingPrompt={ai_pending_prompt}
                            pendingAutoSend={ai_pending_auto_send}
                            pendingNonce={ai_pending_nonce}
                            maximized={ai_chat_maximized}
                            onToggleMaximize={toggle_ai_chat_maximized}
                        />
                    </div>
                </ResizablePanel>
                <ResizableHandle />
                <ResizablePanel defaultSize={82} minSize={30} style={{"overflow": "hidden"}}>
                    <ResizablePanelGroup direction="horizontal">
                        {panel_children}
                    </ResizablePanelGroup>
                </ResizablePanel>
            </ResizablePanelGroup>
        </div>
        <div style={{
            "display": "flex" if terminal_open else "none",
            "flexDirection": "column",
            "height": "220px",
            "flexShrink": "0",
            "borderTop": "1px solid #2A2B2C",
            "background": "#191A1B",
            "position": "relative",
            "zIndex": "20"
        }}>
            <div role="tablist" aria-label="Panel" style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between", "padding": "0 0.5rem", "borderBottom": "1px solid #2A2B2C", "fontSize": "12px", "fontFamily": "system-ui, sans-serif", "flexShrink": "0"}}>
                <div style={{"display": "flex", "gap": "1rem"}}>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "terminal"}
                        onClick={lambda (e: any) { _toggle_panel("terminal"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "terminal" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "terminal" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Terminal
                    </button>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "output"}
                        onClick={lambda (e: any) { _toggle_panel("output"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "output" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "output" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Output
                    </button>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "problems"}
                        onClick={lambda (e: any) { _toggle_panel("problems"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "problems" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "problems" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Problems
                    </button>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "debug"}
                        onClick={lambda (e: any) { _toggle_panel("debug"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "debug" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "debug" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Debug Console
                    </button>
                </div>
                <span
                    aria-label="Close Panel"
                    onClick={lambda (e: any) { handle_command("workbench.action.terminal.toggle"); }}
                    className="codicon codicon-close"
                    style={{"cursor": "pointer", "opacity": "0.7", "fontSize": "14px", "lineHeight": "1", "color": "#8C8C8C"}}
                />
            </div>
            <div style={{"flex": "1", "overflow": "hidden", "position": "relative"}}>
                <div style={{"display": "block" if active_bottom_panel == "terminal" else "none", "height": "100%"}}>
                    <TerminalApp
                        onFocusChange={lambda (focused: bool) { set_context("terminalFocus", focused); }}
                        onNotify={add_notification}
                    />
                </div>
                <div style={{"display": "block" if active_bottom_panel == "output" else "none", "height": "100%"}}>
                    <OutputApp active={terminal_open and active_bottom_panel == "output"} />
                </div>
                <div style={{"display": "block" if active_bottom_panel == "problems" else "none", "height": "100%"}}>
                    <ProblemsApp active={terminal_open and active_bottom_panel == "problems"} onOpenLocation={open_search_result} />
                </div>
                <div style={{"display": "block" if active_bottom_panel == "debug" else "none", "height": "100%"}}>
                    <DebugConsoleApp active={terminal_open and active_bottom_panel == "debug"} path={active_tab_path} onOpenLocation={open_search_result} />
                </div>
            </div>
        </div>
        <StatusBarApp
            line={active_cursor["line"]}
            column={active_cursor["column"]}
            path={active_tab_path}
            notifications={notifications}
            notificationPanelOpen={notification_panel_open}
            onNotificationPanelChange={set_notification_panel_open}
            onDismissNotification={dismiss_notification}
            onClearNotifications={clear_notifications}
        />
    </div>
}
