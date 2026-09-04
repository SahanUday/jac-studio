"""A dict literal with a variable (non-literal) key -- `{some_var: value}` -- miscompiles client-
side: `jac2js` emits `{__jacS_some_var.val: value}`, which is invalid JS (a reactive wrapper used
directly as an object key without `[...]`). Every dict update below goes through a copy-then-
bracket-assign instead (`updated = {**d}; updated[key] = value; d = updated;`), which avoids
computed keys inside a literal entirely while still reassigning the whole object each time, per
this project's reactivity convention (see `text_editor.impl.jac`'s `lines = new_lines;`)."""

impl app._open_path_into_tree(path: str) -> None {
    result = await open_workspace(path);
    root_path = result["root_path"];
    root_name = result["name"];
    input_value = root_path;
    expanded = {};
    selected_path = "";
    top_children = await list_children_by_path(root_path);
    fresh_children_by_path = {};
    fresh_children_by_path[root_path] = top_children;
    children_by_path = fresh_children_by_path;
    opened = True;
    await start_or_switch_watch(root_path);
}

"""One poll tick: calls `check_workspace_changes` (a plain, ordinary RPC call -- see `app`'s own
docstring for why this replaced an earlier, indefinite-SSE-stream design that broke
`list_children_by_path` server-wide, and later, why the polled function itself stopped doing a full
disk walk per call) and refreshes only the directories this component actually has loaded
(`children_by_path`) among whichever ones a real OS-level watch reported changed since the last
tick. A directory this tree has never expanded gets its fresh listing for free the first time it
*is* expanded, so refreshing it now would be a wasted round-trip for content nobody's looking at
yet."""
impl app.poll_workspace_changes -> None {
    result = await check_workspace_changes(root_path);
    for d in result["changed_dirs"] {
        if d in children_by_path {
            await refresh_children(d);
        }
    }
}

impl app.open_folder -> None {
    path = input_value.strip();
    if path == "" {
        return;
    }
    await _open_path_into_tree(path);
}

impl app.toggle_folder(path: str) -> None {
    is_open = expanded[path] if path in expanded else False;
    if is_open {
        updated_expanded = {**expanded};
        updated_expanded[path] = False;
        expanded = updated_expanded;
        return;
    }
    if path not in children_by_path {
        fetched = await list_children_by_path(path);
        updated_children = {**children_by_path};
        updated_children[path] = fetched;
        children_by_path = updated_children;
    }
    updated_expanded = {**expanded};
    updated_expanded[path] = True;
    expanded = updated_expanded;
}

impl app.select_file(path: str, name: str) -> None {
    selected_path = path;
    on_open_file(path, name);
}

impl app.compare_select(path: str, name: str) -> None {
    if compare_pending_path == "" {
        compare_pending_path = path;
        compare_pending_name = name;
        return;
    }
    if compare_pending_path == path {
        compare_pending_path = "";
        compare_pending_name = "";
        return;
    }
    on_compare_files(compare_pending_path, compare_pending_name, path, name);
    compare_pending_path = "";
    compare_pending_name = "";
}

impl app.refresh_children(parent_path: str) -> None {
    fetched = await list_children_by_path(parent_path);
    updated_children = {**children_by_path};
    updated_children[parent_path] = fetched;
    children_by_path = updated_children;
}

impl app.create_new_file(parent_path: str) -> None {
    name = prompt("New file name:");
    if not name {
        return;
    }
    try {
        await create_file(parent_path, name);
    } except Exception as err {
        alert(str(err));
        return;
    }
    await refresh_children(parent_path);
    updated_expanded = {**expanded};
    updated_expanded[parent_path] = True;
    expanded = updated_expanded;
}

impl app.create_new_folder(parent_path: str) -> None {
    name = prompt("New folder name:");
    if not name {
        return;
    }
    try {
        await create_folder(parent_path, name);
    } except Exception as err {
        alert(str(err));
        return;
    }
    await refresh_children(parent_path);
    updated_expanded = {**expanded};
    updated_expanded[parent_path] = True;
    expanded = updated_expanded;
}

impl app.rename_item(path: str, parent_path: str, current_name: str) -> None {
    new_name = prompt("Rename to:", current_name);
    if not new_name or new_name == current_name {
        return;
    }
    result: any = None;
    try {
        result = await rename_path(path, new_name);
    } except Exception as err {
        alert(str(err));
        return;
    }
    await refresh_children(parent_path);
    if selected_path == path {
        selected_path = result["path"];
    }
    if compare_pending_path == path {
        compare_pending_path = "";
        compare_pending_name = "";
    }
}

impl app.delete_item(path: str, parent_path: str, is_dir: bool) -> None {
    kind = "folder and everything inside it" if is_dir else "file";
    if not confirm("Delete this " + kind + "?") {
        return;
    }
    try {
        await delete_path(path);
    } except Exception as err {
        alert(str(err));
        return;
    }
    await refresh_children(parent_path);
    if selected_path == path {
        selected_path = "";
    }
    if compare_pending_path == path {
        compare_pending_path = "";
        compare_pending_name = "";
    }
}
