"""`refresh` re-fetches both the channel list and the selected channel's content on every poll tick
-- a channel list read is cheap (one server-side dict's keys) and doing it every tick, not just on
first mount, is what lets a brand-new channel a background producer just started writing to (the
task runner/LSP client, once they exist) show up in the dropdown without the user having to close
and reopen the panel."""

impl app.refresh -> None {
    fetched_channels = await list_channels();
    channels = fetched_channels;
    next_selected = selected_channel;
    if next_selected == "" or next_selected not in fetched_channels {
        next_selected = fetched_channels[0] if len(fetched_channels) > 0 else "";
    }
    selected_channel = next_selected;
    content = await get_channel_content(next_selected) if next_selected != "" else "";
}

impl app.handle_select_channel(next_channel: str) -> None {
    selected_channel = next_channel;
}

impl app.handle_clear -> None {
    if selected_channel == "" {
        return;
    }
    await clear_channel(selected_channel);
    content = "";
}
