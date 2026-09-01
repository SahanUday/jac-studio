impl app.refresh_files -> None {
    files = await list_all_files();
}

impl app.handle_select(path: str) -> None {
    onOpenChange(False);
    matches = [f for f in files if f["path"] == path];
    name = matches[0]["name"] if len(matches) > 0 else path;
    onOpenFile(path, name);
    updated_recent = [path] + [p for p in recent_paths if p != path];
    recent_paths = updated_recent[:5];
}
