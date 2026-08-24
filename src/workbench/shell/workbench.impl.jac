impl app.open_tab(path: str, name: str) -> None {
    already_open = [t for t in open_tabs if t["path"] == path];
    if len(already_open) > 0 {
        active_path = path;
        return;
    }
    open_tabs = open_tabs + [{"path": path, "name": name}];
    active_path = path;
}

impl app.select_tab(path: str) -> None {
    active_path = path;
}

impl app.close_tab(path: str) -> None {
    remaining = [t for t in open_tabs if t["path"] != path];
    was_active = (active_path == path);
    open_tabs = remaining;
    if was_active {
        active_path = remaining[-1]["path"] if len(remaining) > 0 else "";
    }
}
