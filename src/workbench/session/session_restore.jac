"""Session-restore decision for the workbench shell: empty session passes fields through
unchanged; a saved one replaces all five together."""

def:pub resolve_restored_state(
    session: dict[str, any],
    groups: list[dict[str, any]],
    active_group_id: str,
    next_group_id: int,
    terminal_open: bool,
    cursor_positions: dict[str, dict[str, int]]
) -> tuple[dict[str, dict[str, int]], str, int, bool, list[dict[str, any]]] {
    if len(session["groups"]) > 0 {
        # cursor_positions must precede groups, or Monaco's initial mount overwrites it.
        return (
            session["cursorPositions"], session["activeGroupId"], session["nextGroupId"],
            session["terminalOpen"], session["groups"]
        );
    }
    return (cursor_positions, active_group_id, next_group_id, terminal_open, groups);
}
