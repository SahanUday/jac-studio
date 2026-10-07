impl app.refresh -> None {
    recent = await list_recent_workspaces();
    show_on_startup = (await get_setting("workbench.startupEditor", "welcomePage")) == "welcomePage";
}

impl app.toggle_show_on_startup(next_value: bool) -> None {
    show_on_startup = next_value;
    await set_setting("workbench.startupEditor", "welcomePage" if next_value else "none");
}
