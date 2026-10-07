"""Dict fields are copied, bracket-assigned and reassigned: a variable-key dict literal miscompiles
client-side, and in-place mutation wouldn't re-render."""

impl app.refresh -> None {
    view = await get_settings_view();
}

impl app.set_error(key: str, message: str) -> None {
    updated = {**errors};
    if message == "" {
        if key in updated {
            del updated[key];
        }
    } else {
        updated[key] = message;
    }
    errors = updated;
}

impl app.change(key: str, value: any) -> None {
    result = await update_setting(scope, key, value);
    set_error(key, result["error"]);
    if result["ok"] {
        updated_drafts = {**drafts};
        if key in updated_drafts {
            del updated_drafts[key];
        }
        drafts = updated_drafts;
        await refresh();
        onChanged();
    }
}

impl app.reset(key: str) -> None {
    await reset_setting(scope, key);
    set_error(key, "");
    await refresh();
    onChanged();
}

impl app.edit_draft(key: str, text: str) -> None {
    updated = {**drafts};
    updated[key] = text;
    drafts = updated;
}

impl app.commit_number(key: str) -> None {
    if key not in drafts {
        return;
    }
    parsed = parseFloat(drafts[key]);
    if isNaN(parsed) {
        set_error(key, "Expected a number.");
        return;
    }
    await change(key, int(parsed) if parsed == int(parsed) else parsed);
}
