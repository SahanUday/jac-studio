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
