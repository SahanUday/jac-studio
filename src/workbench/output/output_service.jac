"""Output panel's data half: per-channel log lines, `jid(root)`-keyed, capped at
`_MAX_LINES_PER_CHANNEL` (oldest dropped first). No real producer yet; task runner/LSP/DAP clients
are the intended first callers. Server-side placement pin: tracker
`2026-08-31-anchor-free-root-using-module-pulled-client-wholesale`.
"""

glob _MAX_LINES_PER_CHANNEL: int = 5000;

obj OutputChannel {
    has name: str;
    has lines: list[str] = [];
}

glob _channels_cache: dict[str, dict[str, OutputChannel]] = {};

def:pub _reset_output_channels_cache_for_tests -> None {
    _channels_cache.clear();
}

def _get_channels -> dict[str, OutputChannel] {
    key = jid(root);
    if key not in _channels_cache {
        _channels_cache[key] = {};
    }
    return _channels_cache[key];
}

"""Creates `channel` on first use; no separate registration step needed."""
def:pub append_log(channel: str, line: str) -> None {
    channels = _get_channels();
    if channel not in channels {
        channels[channel] = OutputChannel(name=channel);
    }
    target = channels[channel];
    updated_lines = target.lines + [line];
    if len(updated_lines) > _MAX_LINES_PER_CHANNEL {
        updated_lines = updated_lines[len(updated_lines) - _MAX_LINES_PER_CHANNEL:];
    }
    target.lines = updated_lines;
}

def:pub list_channels -> list[str] {
    return list(_get_channels().keys());
}

def:pub get_channel_content(channel: str) -> str {
    channels = _get_channels();
    if channel not in channels {
        return "";
    }
    return "\n".join(channels[channel].lines);
}

def:pub clear_channel(channel: str) -> None {
    channels = _get_channels();
    if channel in channels {
        channels[channel].lines = [];
    }
}
