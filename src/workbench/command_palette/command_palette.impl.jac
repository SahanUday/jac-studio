impl app.handle_select(command_id: str) -> None {
    onOpenChange(False);
    onRunCommand(command_id);
    updated_recent = [command_id] + [cid for cid in recent_ids if cid != command_id];
    recent_ids = updated_recent[:5];
}
