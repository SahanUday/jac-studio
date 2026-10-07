impl app.refresh -> None {
    recent = await list_recent_workspaces();
    show_on_startup = await get_show_welcome();
}

impl app.toggle_show_on_startup(next_value: bool) -> None {
    show_on_startup = next_value;
    await set_show_welcome(next_value);
}
