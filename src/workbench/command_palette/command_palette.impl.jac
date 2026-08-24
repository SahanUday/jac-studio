impl app.handle_open_change(next_open: bool) -> None {
    open = next_open;
}

impl app.handle_select(command_id: str) -> None {
    open = False;
    onRunCommand(command_id);
}
