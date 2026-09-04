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
    start_watching(root_path);
}

"""Opens (or re-opens, aborting whatever connection was already running) a persistent watch on
`path` -- see `app`'s own docstring for the general, VS-Code-style design this replaces the earlier
AI-specific signal with. Fire-and-forget from the caller's side (`_open_path_into_tree` never
`await`s this): the loop below runs for as long as the connection stays open, which is the whole
remaining lifetime of this mounted component under normal use, not something a caller should block
on."""
impl app.start_watching(path: str) -> None {
    if watch_abort_controller.current {
        watch_abort_controller.current.abort();
    }
    controller = new(AbortController);
    watch_abort_controller.current = controller;

    try {
        resp = await fetch("/function/watch_workspace_changes", {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": JSON.stringify({"root_path": path}),
            "signal": controller.signal
        });
        reader = resp.body.getReader();
        decoder = new(TextDecoder);
        nl = chr(10);
        buf = "";
        feeding = True;
        while feeding {
            part = await reader.read();
            if part.done {
                feeding = False;
                continue;
            }
            buf = buf + decoder.decode(part.value, {"stream": True});
            raw_frames = buf.split(nl + nl);
            buf = raw_frames.pop();
            for frame in raw_frames {
                for line in frame.split(nl) {
                    if line.startswith("data: ") and not frame.startswith("event:") {
                        chunk = JSON.parse(line[6:]) as str;
                        event = JSON.parse(chunk) as dict[str, any];
                        await handle_watch_event(event);
                    }
                }
            }
        }
    } except Exception {
        # Either an intentional abort (a new root was opened, see the guard above) or the
        # connection genuinely dropped -- neither is a real error to surface. An intentional
        # abort already has its replacement watch starting right after it; an unintentional drop
        # just means external changes go unnoticed until the folder is reopened, not a crash.
    }
}

"""Refreshes only the directories this component actually has loaded (`children_by_path`) among
whichever ones changed -- a directory this tree has never expanded gets its fresh listing for free
the first time it *is* expanded, so refreshing it now would be a wasted round-trip for content
nobody's looking at yet."""
impl app.handle_watch_event(event: dict[str, any]) -> None {
    if event.get("type", "") != "changed" {
        return;
    }
    for d in event.get("dirs", []) {
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
