"""SessionService: Phase 3's "workspace state ... persisted the same way -- restoring a session on
reopen 'for free' via the graph" bullet (`docs/roadmap.md`). Persists exactly the shape
`workbench.jac` already keeps as ephemeral `has` state (`groups`, `active_group_id`,
`next_group_id`, `terminal_open`, `cursor_positions`) so save/restore is a straight field-for-field
copy in both directions, no translation layer to maintain.

**One `WorkspaceSession` node with list/dict fields, not `EditorGroup`/`Tab` graph nodes with
`Shows`/`Displays` edges.** `docs/architecture.md`'s original data-model sketch proposed the
latter; this deliberately deviates from that literal proposal, for two concrete reasons found while
actually building this bullet, consistent with the same doc's later "not every service needs to be
a node" refinement (added after the Phase 0 spike, which is itself later than the original data
model section):
1. `Tab --Displays--> File` would require a `File` graph node to exist for every open tab at
   restore time -- but `File` nodes only exist for paths `workspace_service.jac` has already lazily
   scanned (`docs/roadmap.md`'s file-tree bullet), so restoring tabs would be coupled to restoring
   the workspace tree scan order first, for no actual benefit: nothing here ever needs to traverse
   *from* a Tab *to* its File node (see the node-vs-obj test's criterion 2 in `docs/architecture.md`
   -- no graph-traversal need means no edge is earned). `document_service.jac` already treats a
   plain path string as the sole file identity for exactly this reason; `Tab` does the same.
2. Nothing outside this module ever needs to reach one specific `EditorGroup`/`Tab` by graph query
   either -- the only reader is `workbench.jac`, and it always wants the *whole* session shape at
   once (one `load_session()` call on mount), never "find the tab at this path." A single node's
   list/dict fields satisfy criterion 1 (survive a restart) without paying for graph modeling
   nothing here exercises, the same call already made for `Settings` in `settings_service.jac`.

**Cursor positions are saved opportunistically, not on every `onDidChangeCursorPosition` event.**
`workbench.jac`'s `handle_cursor_change` fires on literally every keystroke (typing moves the
cursor), the exact per-keystroke frequency this project already refused to round-trip to the server
for the *editor content itself* (`docs/architecture.md`'s Monaco-embed decision: "no per-keystroke
RPC round-trip"). The same instinct applies here: `save_session` is called on real structural
actions (open/close/select a tab, split a group, toggle the terminal -- already low-frequency, one
per user action) plus a short debounce after cursor movement settles, never synchronously per
keystroke. See `workbench.impl.jac`'s `handle_cursor_change` for the debounce itself.

**Cache the jid, not the node, and resolve via `jobj()` on every access.** Same finding as
`settings_service.jac`'s docstring (2026-08-28) -- a raw node object reused across separate
requests silently drops any `has`-field mutation made through it, verified live against a real
`jac run --serve --dev` restart, not just a page reload. `save_session` mutates five fields on an
existing node every call, exactly the shape that loses data this way. See tracker entry
`2026-08-28-field-mutation-on-cached-node-not-persisted`.
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

"""Returns the persisted shape verbatim, including an empty `groups` list for a session that was
never saved -- `workbench.jac` already defaults to a single empty group on first load, which is the
same shape an intentionally-all-closed-tabs session would also persist as, so there is no
meaningful "never saved" vs. "saved empty" distinction for the caller to act on differently."""
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
