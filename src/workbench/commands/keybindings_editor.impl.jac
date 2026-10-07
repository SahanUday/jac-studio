impl app.refresh -> None {
    commands = await list_commands();
}

impl app.start_recording(command_id: str) -> None {
    editing = command_id;
    recorded = "";
    error = "";
}

impl app.cancel_recording -> None {
    editing = "";
    recorded = "";
    error = "";
}

"""Enter accepts, Escape cancels; every other key is captured as the chord. Modifier-only presses
record nothing, so the chord appears once the real key lands."""
impl app.record_key(e: any) -> None {
    e.preventDefault();
    e.stopPropagation();
    if e.key == "Escape" {
        cancel_recording();
        return;
    }
    if e.key == "Enter" {
        if recorded != "" {
            commit();
        }
        return;
    }
    chord = chord_from_event(e.ctrlKey or e.metaKey, e.shiftKey, e.altKey, e.key);
    if chord != "" {
        recorded = chord;
        error = "";
    }
}

impl app.commit -> None {
    result = await set_command_keybinding(editing, recorded, "");
    if not result["ok"] {
        error = result["error"];
        return;
    }
    cancel_recording();
    await refresh();
    onChanged();
}

impl app.clear(command_id: str) -> None {
    await clear_command_keybinding(command_id);
    await refresh();
    onChanged();
}

impl app.reset(command_id: str) -> None {
    await reset_command_keybinding(command_id);
    await refresh();
    onChanged();
}
