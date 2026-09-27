"""Pure decision for applying a loaded session to workbench state: an empty session means
never-saved, so every field passes through unchanged; a non-empty one replaces all five together.
Extracted from workbench.jac's entry block so it's testable outside the client bundle."""

def:pub resolve_restored_state(
    session: dict[str, any],
    groups: list[dict[str, any]],
    active_group_id: str,
    next_group_id: int,
    terminal_open: bool,
    cursor_positions: dict[str, dict[str, int]]
) -> tuple[dict[str, dict[str, int]], str, int, bool, list[dict[str, any]]] {
    if len(session["groups"]) > 0 {
        # cursor_positions must land before groups: groups going non-empty is what mounts each
        # tab's MonacoEditorApp, and initialCursor is read exactly once at that mount.
        return (
            session["cursorPositions"], session["activeGroupId"], session["nextGroupId"],
            session["terminalOpen"], session["groups"]
        );
    }
    return (cursor_positions, active_group_id, next_group_id, terminal_open, groups);
}
