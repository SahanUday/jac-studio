test "an empty session (never saved) leaves every current value unchanged" {
    session = {"groups": [], "activeGroupId": "", "nextGroupId": 2, "terminalOpen": False, "cursorPositions": {}};
    current_groups = [{"id": "group-1", "tabs": [], "activePath": ""}];
    current_cursor_positions = {"/a.txt": {"line": 3, "column": 5}};

    (cursor_positions, active_group_id, next_group_id, terminal_open, groups) = resolve_restored_state(
        session, current_groups, "group-1", 2, False, current_cursor_positions
    );

    assert groups == current_groups;
    assert active_group_id == "group-1";
    assert next_group_id == 2;
    assert not terminal_open;
    assert cursor_positions == current_cursor_positions;
}

test "a saved session replaces every field, ignoring the current values entirely" {
    session = {
        "groups": [{"id": "group-2", "tabs": [{"path": "/b.txt", "name": "b.txt"}], "activePath": "/b.txt"}],
        "activeGroupId": "group-2",
        "nextGroupId": 3,
        "terminalOpen": True,
        "cursorPositions": {"/b.txt": {"line": 9, "column": 1}}
    };

    (cursor_positions, active_group_id, next_group_id, terminal_open, groups) = resolve_restored_state(
        session, [{"id": "group-1", "tabs": [], "activePath": ""}], "group-1", 2, False, {}
    );

    assert groups == session["groups"];
    assert active_group_id == "group-2";
    assert next_group_id == 3;
    assert terminal_open;
    assert cursor_positions == session["cursorPositions"];
}

test "cursor_positions is returned ahead of groups in the tuple" {
    session = {
        "groups": [{"id": "group-1", "tabs": [], "activePath": ""}],
        "activeGroupId": "group-1",
        "nextGroupId": 2,
        "terminalOpen": False,
        "cursorPositions": {"/a.txt": {"line": 1, "column": 1}}
    };

    result = resolve_restored_state(session, [], "", 2, False, {});

    assert result[0] == session["cursorPositions"];
    assert result[4] == session["groups"];
}
