"""Persists workbench session state (editor groups/tabs, cursor positions, terminal-open) as one
`WorkspaceSession` node's list/dict fields rather than per-tab graph nodes -- see ADR 0015.
Cursor positions save on a debounce after movement settles, not per keystroke.
See ADR 0029 for the jid-caching pattern this module uses.
"""

node WorkspaceSession {
    has groups: list[dict[str, any]] = [];
    has active_group_id: str = "";
    has next_group_id: int = 2;
    has terminal_open: bool = False;
    has cursor_positions: dict[str, dict[str, int]] = {};
}

glob _cached_session_jid: dict[str, str] = {};

def:pub _reset_session_cache_for_tests {
    _cached_session_jid.clear();
}

def get_session_node -> WorkspaceSession {
    key = jid(root);
    if key not in _cached_session_jid {
        existing = [root-->[?:WorkspaceSession]];
        session = existing[0] if existing else root ++> WorkspaceSession();
        _cached_session_jid[key] = jid(session);
        return session;
    }
    return jobj(_cached_session_jid[key]) as WorkspaceSession;
}

"""An empty `groups` list means both "never saved" and "saved with all tabs closed" -- indistinguishable to the caller, which already defaults to one empty group."""
def:pub load_session -> dict[str, any] {
    session = get_session_node();
    return {
        "groups": session.groups,
        "activeGroupId": session.active_group_id,
        "nextGroupId": session.next_group_id,
        "terminalOpen": session.terminal_open,
        "cursorPositions": session.cursor_positions
    };
}

def:pub save_session(
    groups: list[dict[str, any]],
    active_group_id: str,
    next_group_id: int,
    terminal_open: bool,
    cursor_positions: dict[str, dict[str, int]]
) {
    session = get_session_node();
    session.groups = groups;
    session.active_group_id = active_group_id;
    session.next_group_id = next_group_id;
    session.terminal_open = terminal_open;
    session.cursor_positions = cursor_positions;
}
