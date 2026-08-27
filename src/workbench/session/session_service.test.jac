test "load_session on a never-saved root returns the empty default shape" {
    _reset_session_cache_for_tests();

    session = load_session();

    assert session["groups"] == [];
    assert session["activeGroupId"] == "";
    assert session["nextGroupId"] == 2;
    assert not session["terminalOpen"];
    assert session["cursorPositions"] == {};
}

test "save_session then load_session round-trips every field" {
    _reset_session_cache_for_tests();
    groups = [{"id": "group-1", "tabs": [{"path": "/a.txt", "name": "a.txt"}], "activePath": "/a.txt"}];
    cursor_positions = {"/a.txt": {"line": 4, "column": 9}};

    save_session(groups, "group-1", 2, True, cursor_positions);
    session = load_session();

    assert session["groups"] == groups;
    assert session["activeGroupId"] == "group-1";
    assert session["nextGroupId"] == 2;
    assert session["terminalOpen"];
    assert session["cursorPositions"] == cursor_positions;
}

test "a later save fully replaces the previous session, not merges into it" {
    _reset_session_cache_for_tests();
    save_session(
        [{"id": "group-1", "tabs": [{"path": "/a.txt", "name": "a.txt"}], "activePath": "/a.txt"}],
        "group-1", 2, True, {"/a.txt": {"line": 1, "column": 1}}
    );

    save_session([], "", 2, False, {});
    session = load_session();

    assert session["groups"] == [];
    assert not session["terminalOpen"];
    assert session["cursorPositions"] == {};
}

test "next_group_id survives a restore so restored group ids never collide with new ones" {
    _reset_session_cache_for_tests();
    save_session(
        [
            {"id": "group-1", "tabs": [], "activePath": ""},
            {"id": "group-2", "tabs": [], "activePath": ""}
        ],
        "group-2", 3, False, {}
    );

    session = load_session();

    assert session["nextGroupId"] == 3;
}
