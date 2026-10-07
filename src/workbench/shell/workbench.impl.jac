"""Handler bodies for `workbench.jac`. A `has` field holding a list or dict is only picked up
reactively when the field itself is reassigned, so every update here rebuilds a fresh object
rather than mutating in place. Every method that changes `groups`/`active_group_id`/
`next_group_id`/`terminal_open` awaits `_save_session`; `handle_cursor_change` debounces instead,
since it fires on every keystroke."""

impl app._save_session -> None {
    await save_session(groups, active_group_id, next_group_id, terminal_open, cursor_positions);
}

impl app._toggle_panel(panel_id: str) -> None {
    if terminal_open and active_bottom_panel == panel_id {
        terminal_open = False;
    } else {
        terminal_open = True;
        active_bottom_panel = panel_id;
    }
    await _save_session();
}

impl app._upsert_tab_in_active_group(tab: dict[str, any]) -> list[dict[str, any]] {
    updated_groups = [];
    for g in groups {
        if g["id"] != active_group_id {
            updated_groups.append(g);
            continue;
        }
        already_open = [t for t in g["tabs"] if t["path"] == tab["path"]];
        new_tabs = g["tabs"] if len(already_open) > 0 else g["tabs"] + [tab];
        updated_groups.append({"id": g["id"], "tabs": new_tabs, "activePath": tab["path"]});
    }
    return updated_groups;
}

"""Dirty flags are the only unsaved-work signal the shell has; the buffers live inside Monaco."""
impl app._confirm_discard_dirty -> bool {
    unsaved = [flag for flag in dirty_paths.values() if flag];
    if len(unsaved) == 0 {
        return True;
    }
    return confirm("You have unsaved changes. Discard them and switch workspace?");
}

"""A different workspace gets a clean editor state; per-workspace session restore is not built."""
impl app.open_workspace_folder(path: str) -> None {
    folder_picker_open = False;
    if path == "" or path == workspace_path {
        return;
    }
    if not _confirm_discard_dirty() {
        return;
    }
    opened = await open_workspace(path);
    await add_recent_workspace(opened["root_path"]);
    groups = [{"id": "group-1", "tabs": [], "activePath": ""}];
    active_group_id = "group-1";
    next_group_id = 2;
    dirty_paths = {};
    cursor_positions = {};
    symbols_by_path = {};
    workspace_path = opened["root_path"];
    workspace_name = opened["name"];
    await _save_session();
}

impl app.close_workspace_folder -> None {
    if workspace_path == "" or not _confirm_discard_dirty() {
        return;
    }
    await close_workspace();
    groups = [_welcome_group()];
    active_group_id = "group-1";
    next_group_id = 2;
    dirty_paths = {};
    cursor_positions = {};
    symbols_by_path = {};
    workspace_path = "";
    workspace_name = "";
    await _save_session();
}

impl app.open_welcome_tab -> None {
    groups = _upsert_tab_in_active_group({"path": WELCOME_PATH, "name": "Welcome", "kind": "welcome"});
    await _save_session();
}

impl app.refresh_settings -> None {
    latest = await get_effective_settings();
    settings = latest;
    apply_editor_settings(latest);
    onThemeChange(latest["workbench.colorTheme"]);
}

impl app.refresh_commands -> None {
    commands = await list_commands();
}

impl app.open_keybindings_tab -> None {
    groups = _upsert_tab_in_active_group({"path": "keybindings://", "name": "Keyboard Shortcuts", "kind": "keybindings"});
    await _save_session();
}

impl app.open_keybindings_json -> None {
    path = await ensure_keybindings_file();
    await open_tab(path, "keybindings.json");
}

impl app.open_settings_tab -> None {
    groups = _upsert_tab_in_active_group({"path": "settings://", "name": "Settings", "kind": "settings"});
    await _save_session();
}

impl app.open_settings_json(scope: str) -> None {
    path = await ensure_settings_file(scope);
    if path == "" {
        add_notification("Open a folder to edit workspace settings.", "info", "Settings");
        return;
    }
    await open_tab(path, "settings.json (User)" if scope == "user" else "settings.json (Workspace)");
}

impl app.set_folder_picker_open(next_open: bool) -> None {
    folder_picker_open = next_open;
}

impl app.show_folder_picker(mode: str) -> None {
    folder_picker_mode = mode;
    folder_picker_open = True;
}

impl app.open_tab(path: str, name: str) -> None {
    groups = _upsert_tab_in_active_group({"path": path, "name": name});
    await _save_session();
}

"""Seeds `cursor_positions` if `path` isn't open yet; otherwise jumps its live editor directly."""
impl app.open_search_result(path: str, name: str, line: int, column: int) -> None {
    already_open = False;
    for g in groups {
        if g["id"] == active_group_id and len([t for t in g["tabs"] if t["path"] == path]) > 0 {
            already_open = True;
        }
    }
    if not already_open {
        updated_cursor_positions = {**cursor_positions};
        updated_cursor_positions[path] = {"line": line, "column": column};
        cursor_positions = updated_cursor_positions;
    }
    groups = _upsert_tab_in_active_group({"path": path, "name": name});
    await _save_session();
    if already_open {
        reveal_position_in_editor(path, line, column);
    }
}

"""Stores only `{filePath, staged}`; `scm_diff_editor.jac` fetches the diff content itself on mount."""
impl app.open_scm_diff(path: str, name: str, staged: bool) -> None {
    suffix = "::staged" if staged else "::unstaged";
    groups = _upsert_tab_in_active_group({
        "path": "gitdiff::" + path + suffix,
        "name": name + (" (Staged)" if staged else " (Working Tree)"),
        "kind": "gitdiff",
        "filePath": path,
        "staged": staged
    });
    await _save_session();
}

impl app.open_diff_tab(path_a: str, name_a: str, path_b: str, name_b: str) -> None {
    diff_path = "diff::" + path_a + "::" + path_b;
    groups = _upsert_tab_in_active_group({
        "path": diff_path,
        "name": name_a + " ↔ " + name_b,
        "kind": "diff",
        "originalPath": path_a,
        "modifiedPath": path_b
    });
    await _save_session();
}

impl app.select_tab(group_id: str, path: str) -> None {
    updated_groups = [];
    for g in groups {
        if g["id"] == group_id {
            updated_groups.append({"id": g["id"], "tabs": g["tabs"], "activePath": path});
        } else {
            updated_groups.append(g);
        }
    }
    groups = updated_groups;
    active_group_id = group_id;
    await _save_session();
}

impl app.close_tab(group_id: str, path: str) -> None {
    updated_groups = [];
    removed_group_id = "";
    for idx in range(len(groups)) {
        g = groups[idx];
        if g["id"] != group_id {
            updated_groups.append(g);
            continue;
        }
        remaining = [t for t in g["tabs"] if t["path"] != path];
        if len(remaining) == 0 and len(groups) > 1 {
            removed_group_id = g["id"];
            continue;
        }
        new_active = g["activePath"];
        if g["activePath"] == path {
            new_active = remaining[-1]["path"] if len(remaining) > 0 else "";
        }
        updated_groups.append({"id": g["id"], "tabs": remaining, "activePath": new_active});
    }
    groups = updated_groups;
    if removed_group_id != "" and active_group_id == removed_group_id {
        active_group_id = updated_groups[0]["id"];
    }
    if dirty_paths.get(path, False) {
        updated_dirty_paths = {**dirty_paths};
        updated_dirty_paths[path] = False;
        dirty_paths = updated_dirty_paths;
    }
    await _save_session();
}

impl app.split_group(group_id: str) -> None {
    source = [g for g in groups if g["id"] == group_id];
    if len(source) == 0 or source[0]["activePath"] == "" {
        return;
    }
    active_tab = [t for t in source[0]["tabs"] if t["path"] == source[0]["activePath"]];
    if len(active_tab) == 0 {
        return;
    }
    new_group_id = "group-" + str(next_group_id);
    new_group = {"id": new_group_id, "tabs": [active_tab[0]], "activePath": active_tab[0]["path"]};
    updated_groups = [];
    for g in groups {
        updated_groups.append(g);
        if g["id"] == group_id {
            updated_groups.append(new_group);
        }
    }
    groups = updated_groups;
    next_group_id = next_group_id + 1;
    active_group_id = new_group_id;
    await _save_session();
}

impl app.handle_cursor_change(path: str, line: int, column: int) -> None {
    updated_cursor_positions = {**cursor_positions};
    updated_cursor_positions[path] = {"line": line, "column": column};
    cursor_positions = updated_cursor_positions;

    if cursor_save_timer.current {
        clearTimeout(cursor_save_timer.current);
    }
    cursor_save_timer.current = setTimeout(lambda { _save_session(); }, 800);
}

impl app.handle_symbols_change(path: str, symbols: list[dict[str, any]]) -> None {
    updated_symbols = {**symbols_by_path};
    updated_symbols[path] = symbols;
    symbols_by_path = updated_symbols;
}

impl app.handle_dirty_change(path: str, is_dirty: bool) -> None {
    updated_dirty_paths = {**dirty_paths};
    updated_dirty_paths[path] = is_dirty;
    dirty_paths = updated_dirty_paths;
    # saving a settings.json applies it immediately, as in VS Code
    if not is_dirty and path.endswith("/settings.json") {
        refresh_settings();
    }
    if not is_dirty and path.endswith("/keybindings.json") {
        refresh_commands();
    }
}

# bumps a shared nonce for any open path (plain tab by `path`, gitdiff tab by `filePath`) whose
# file changed. No dirty_paths filter here -- reload_from_disk itself re-checks dirty (ADR 0072).
impl app.handle_files_changed_externally(paths: list[str]) -> None {
    open_paths = set();
    for g in groups {
        for t in g["tabs"] {
            if not t.get("kind") {
                open_paths.add(t["path"]);
            } elif t.get("kind") == "gitdiff" {
                open_paths.add(t["filePath"]);
            }
        }
    }
    updated_reload = {**files_pending_reload};
    next_nonce = next_reload_nonce;
    any_changed = False;
    for p in paths {
        if p in open_paths {
            updated_reload[p] = next_nonce;
            next_nonce = next_nonce + 1;
            any_changed = True;
        }
    }
    if any_changed {
        files_pending_reload = updated_reload;
        next_reload_nonce = next_nonce;
    }
}

impl app.handle_command(command_id: str) -> None {
    if command_id == "workbench.action.files.openFolder" {
        show_folder_picker("browse");
        return;
    }
    if command_id == "workbench.action.openRecent" {
        show_folder_picker("recent");
        return;
    }
    if command_id == "workbench.action.files.closeFolder" {
        await close_workspace_folder();
        return;
    }
    if command_id == "workbench.action.openSettings" {
        await open_settings_tab();
        return;
    }
    if command_id == "workbench.action.openKeybindings" {
        await open_keybindings_tab();
        return;
    }
    if command_id == "workbench.action.openKeybindingsJson" {
        await open_keybindings_json();
        return;
    }
    if command_id == "workbench.action.openSettingsJson" {
        await open_settings_json("user");
        return;
    }
    if command_id == "workbench.action.openWorkspaceSettingsJson" {
        await open_settings_json("workspace");
        return;
    }
    if command_id == "workbench.action.showWelcome" {
        await open_welcome_tab();
        return;
    }
    if command_id == "workbench.action.files.save" {
        run_editor_command(active_tab_path, "save");
        return;
    }
    if command_id == "workbench.view.explorer" {
        select_view("explorer");
        return;
    }
    if command_id == "workbench.view.outline" {
        select_view("outline");
        return;
    }
    if command_id == "workbench.view.aiChat" {
        select_view("ai_chat");
        return;
    }
    if command_id in EDITOR_COMMANDS {
        run_editor_command(active_tab_path, command_id);
        return;
    }
    if command_id == "workbench.action.splitEditorRight" {
        await split_group(active_group_id);
        return;
    }
    if command_id == "workbench.action.closeActiveEditor" {
        active_group = [g for g in groups if g["id"] == active_group_id];
        if len(active_group) == 0 or active_group[0]["activePath"] == "" {
            return;
        }
        await close_tab(active_group_id, active_group[0]["activePath"]);
        return;
    }
    if command_id == "workbench.action.terminal.toggle" {
        await _toggle_panel("terminal");
        return;
    }
    if command_id == "workbench.action.output.toggle" {
        await _toggle_panel("output");
        return;
    }
    if command_id == "workbench.action.debug.toggle" {
        await _toggle_panel("debug");
        return;
    }
    if command_id == "workbench.action.toggleColorTheme" {
        await onToggleTheme();
        return;
    }
    if command_id == "workbench.action.quickOpen" {
        quick_open_open = not quick_open_open;
        return;
    }
    if command_id == "workbench.action.showCommands" {
        command_palette_open = not command_palette_open;
        return;
    }
    if command_id == "workbench.action.showNotifications" {
        notification_panel_open = not notification_panel_open;
        return;
    }
    if command_id == "workbench.action.showSearch" {
        active_view_id = "search";
        return;
    }
    if command_id == "workbench.action.showScm" {
        active_view_id = "scm";
        return;
    }
    if command_id == "workbench.action.tasks.runTask" {
        task_picker_open = True;
    }
}

impl app.set_quick_open_open(next_open: bool) -> None {
    quick_open_open = next_open;
}

impl app.set_command_palette_open(next_open: bool) -> None {
    command_palette_open = next_open;
}

impl app.select_view(view_id: str) -> None {
    active_view_id = view_id;
}

"""`ai_pending_nonce` increments on every call, not just when `promptText` changes, so triggering
the same code action twice in a row still fires `AIChatApp`'s `useEffect`."""
impl app.handle_ask_ai(promptText: str, autoSend: bool) -> None {
    active_view_id = "ai_chat";
    ai_pending_prompt = promptText;
    ai_pending_auto_send = autoSend;
    ai_pending_nonce += 1;
}

"""Style-only toggle on the same mounted instance -- remounting to a second mount point would lose
`messages`/`session_id`/`pending_approvals`."""
impl app.toggle_ai_chat_maximized -> None {
    ai_chat_maximized = not ai_chat_maximized;
}

impl app.add_notification(message: str, severity: str, source: str) -> None {
    updated = notifications + [{
        "id": next_notification_id,
        "message": message,
        "severity": severity,
        "source": source
    }];
    notifications = updated;
    next_notification_id = next_notification_id + 1;

    if severity == "error" {
        toast.error(message);
    } elif severity == "warning" {
        toast.warning(message);
    } else {
        toast(message);
    }
}

impl app.dismiss_notification(notification_id: int) -> None {
    notifications = [n for n in notifications if n["id"] != notification_id];
}

impl app.clear_notifications -> None {
    notifications = [];
}

impl app.set_notification_panel_open(next_open: bool) -> None {
    notification_panel_open = next_open;
}

impl app.set_git_status(status_map: dict[str, str]) -> None {
    git_status_by_path = status_map;
}

impl app.set_task_picker_open(next_open: bool) -> None {
    task_picker_open = next_open;
}

impl app.run_selected_task(label: str) -> None {
    result = await run_task(label);
    if result["success"] {
        add_notification("Task \"" + label + "\" completed.", "info", "Tasks");
    } else {
        message = result["error"] if result["error"] else ("Task \"" + label + "\" failed (exit code " + str(result["exitCode"]) + ").");
        add_notification(message, "error", "Tasks");
    }
}

impl app.set_context(key: str, value: bool) -> None {
    updated_context = {**context};
    updated_context[key] = value;
    context = updated_context;
}

impl app.context_matches(when: str) -> bool {
    if when == "" {
        return True;
    }
    if when.startswith("!") {
        return not context.get(when[1:], False);
    }
    return context.get(when, False);
}

"""Plain mousedown/mousemove drag, not `react-resizable-panels` -- see ADR 0079."""
impl app.start_panel_resize(e: any) -> None {
    start_y = e.clientY;
    start_height = bottom_panel_height;
    handle_move = lambda (move_e: any) {
        delta = start_y - move_e.clientY;
        next_height = start_height + delta;
        min_height = 100;
        max_height = window.innerHeight - 150;
        if next_height < min_height {
            next_height = min_height;
        }
        if next_height > max_height {
            next_height = max_height;
        }
        bottom_panel_height = next_height;
    };
    handle_up = lambda (up_e: any) {
        window.removeEventListener("mousemove", handle_move);
        window.removeEventListener("mouseup", handle_up);
    };
    window.addEventListener("mousemove", handle_move);
    window.addEventListener("mouseup", handle_up);
}

impl app.handle_keydown(e: any) -> None {
    # the shortcut recorder owns every key while it has focus
    if e.target and e.target.closest and e.target.closest("[data-recording-keybinding]") {
        return;
    }
    combo = chord_from_event(e.ctrlKey or e.metaKey, e.shiftKey, e.altKey, e.key);
    if combo == "" {
        return;
    }
    for cmd in commands {
        for kb in cmd["keybindings"] {
            if kb["key"] == combo and context_matches(kb["when"]) {
                e.preventDefault();
                handle_command(cmd["id"]);
                return;
            }
        }
    }
}
