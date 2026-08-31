"""Every group update rebuilds `groups` as a fresh list of fresh dicts rather than mutating in
place, per this project's established reactivity convention for `has` fields holding
lists/dicts (see `file_tree.impl.jac`'s docstring) -- a `has` field write is only picked up
reactively when the field itself is reassigned to a new object.

`_save_session` is called (`await`-ed, not fire-and-forget) at the end of every method here that
changes `groups`/`active_group_id`/`next_group_id`/`terminal_open` -- see `workbench.jac`'s
"Workspace-state persistence" docstring section for why `handle_cursor_change` is the one
exception, debouncing instead."""

impl app._save_session -> None {
    await save_session(groups, active_group_id, next_group_id, terminal_open, cursor_positions);
}

"""Re-selecting the already-active tab closes the panel; selecting the other tab (or opening from
closed) switches to it and opens -- see `workbench.jac`'s "Output panel + a real bottom-panel tab
strip" docstring section for why this replaced two separate hardcoded toggles."""
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
