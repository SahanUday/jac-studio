impl app.browse(path: str) -> None {
    result = await list_directories(path, show_hidden);
    listing = result;
    path_input = result["path"];
}

impl app.load_recent -> None {
    recent = await list_recent_workspaces();
}

impl app.forget_recent(path: str) -> None {
    await remove_recent_workspace(path);
    await load_recent();
}
