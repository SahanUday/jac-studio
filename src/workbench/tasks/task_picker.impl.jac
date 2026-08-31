impl app.refresh_tasks -> None {
    tasks = await list_tasks();
}

impl app.handle_select(label: str) -> None {
    onOpenChange(False);
    onRunTask(label);
}
