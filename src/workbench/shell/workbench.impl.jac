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

impl app.open_tab(path: str, name: str) -> None {
    groups = _upsert_tab_in_active_group({"path": path, "name": name});
    await _save_session();
}

"""Seeds `cursor_positions[path]` before inserting the tab, so the editor picks the position up as
`initialCursor` at mount rather than needing an imperative jump."""
impl app.open_search_result(path: str, name: str, line: int, column: int) -> None {
    updated_cursor_positions = {**cursor_positions};
    updated_cursor_positions[path] = {"line": line, "column": column};
    cursor_positions = updated_cursor_positions;
    groups = _upsert_tab_in_active_group({"path": path, "name": name});
    await _save_session();
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

impl app.handle_dirty_change(path: str, is_dirty: bool) -> None {
    updated_dirty_paths = {**dirty_paths};
    updated_dirty_paths[path] = is_dirty;
    dirty_paths = updated_dirty_paths;
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

impl app.handle_keydown(e: any) -> None {
    parts = [];
    if e.ctrlKey or e.metaKey {
        parts.append("ctrl");
    }
    if e.shiftKey {
        parts.append("shift");
    }
    parts.append(e.key.lower());
    combo = "+".join(parts);
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
