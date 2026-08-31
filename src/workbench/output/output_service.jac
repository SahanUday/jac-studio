"""OutputService: the data half of VS Code's Output panel (`workbench/contrib/output`, the
`output`/`logs` row `docs/vscode-complete-triage.md` already scoped), moved to the front of Phase 4
(`docs/roadmap.md`) alongside the notification center -- "the natural place to surface `jac lsp`'s
and the DAP client's own logs," and needed to debug the task runner/LSP/DAP work this same phase
builds next, not just as a later user-facing feature.

**No real producer exists yet -- same deliberate, precedented scope cut `diagnostics.jac` made in
Phase 3.** `append_log` has no caller anywhere in this PR; the task runner and the LSP/DAP clients
(later in this same Phase 4) are the intended first callers, the same relationship Phase 3's
`Diagnostic` node type had to this phase's task runner. Building the channel-storage contract and
the panel UI now, ahead of any real writer, means those features get somewhere to log to from day
one instead of inventing their own ad-hoc logging shape under time pressure.

**A plain `obj`, `jid(root)`-keyed, not a graph node.** Checked against `docs/architecture.md`'s
three node-earning criteria: output log lines don't need to survive a process restart (VS Code's
own Output panel starts empty on every relaunch too -- it's a debugging aid, not domain data),
aren't reached by graph traversal from anywhere, and need no permission scoping beyond what the
`jid(root)` key already gives a single-user local session. Same shape `document_service.jac`'s
`DocumentBuffer` already established for exactly this "ephemeral, cached, no graph" combination --
see that module's docstring and `docs/architecture.md`'s "Not every service needs to be a node"
section.

**Bounded per channel, not an unbounded list.** Unlike a settings/session record (small, written
rarely), a log channel is exactly the kind of thing that grows without bound over a long session --
capped at `_MAX_LINES_PER_CHANNEL`, dropping the oldest lines first, matching VS Code's own output
channels (which also cap and truncate rather than growing forever)."""

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

"""Creates `channel` on first use -- callers never need a separate "register this channel" step,
matching `command_registry.jac`'s own register-on-first-use posture for `Command` nodes."""
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
