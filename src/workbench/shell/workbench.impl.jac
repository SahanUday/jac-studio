"""Every group update rebuilds `groups` as a fresh list of fresh dicts rather than mutating in
place, per this project's established reactivity convention for `has` fields holding
lists/dicts (see `file_tree.impl.jac`'s docstring) -- a `has` field write is only picked up
reactively when the field itself is reassigned to a new object."""

impl app.open_tab(path: str, name: str) -> None {
    updated_groups = [];
    for g in groups {
        if g["id"] != active_group_id {
            updated_groups.append(g);
            continue;
        }
        already_open = [t for t in g["tabs"] if t["path"] == path];
        new_tabs = g["tabs"] if len(already_open) > 0 else g["tabs"] + [{"path": path, "name": name}];
        updated_groups.append({"id": g["id"], "tabs": new_tabs, "activePath": path});
    }
    groups = updated_groups;
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
}

impl app.handle_command(command_id: str) -> None {
    if command_id == "workbench.action.splitEditorRight" {
        split_group(active_group_id);
        return;
    }
    if command_id == "workbench.action.closeActiveEditor" {
        active_group = [g for g in groups if g["id"] == active_group_id];
        if len(active_group) == 0 or active_group[0]["activePath"] == "" {
            return;
        }
        close_tab(active_group_id, active_group[0]["activePath"]);
    }
}
