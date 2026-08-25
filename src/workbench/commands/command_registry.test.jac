"""Only `list_commands` is exercised directly -- `register_command`/`get_command_registry` are
plain (non-`:pub`) implementation details, reached only through the one client-facing entry point,
per `document_service.jac`/`workspace_service.jac`'s precedent of testing the public surface."""

test "list_commands seeds and returns the built-in Phase 2 command set" {
    _reset_command_registry_cache_for_tests();

    commands = list_commands();

    assert len(commands) == len(BUILTIN_COMMANDS);
    ids = [c["id"] for c in commands];
    for spec in BUILTIN_COMMANDS {
        assert spec["id"] in ids;
    }
}

test "each returned command carries its registered title" {
    _reset_command_registry_cache_for_tests();

    commands = list_commands();

    by_id = {c["id"]: c["title"] for c in commands};
    for spec in BUILTIN_COMMANDS {
        assert by_id[spec["id"]] == spec["title"];
    }
}

test "each returned command carries its registered keybindings" {
    _reset_command_registry_cache_for_tests();

    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    for spec in BUILTIN_COMMANDS {
        assert by_id[spec["id"]] == spec["keybindings"];
    }
}

test "calling list_commands twice does not duplicate entries" {
    _reset_command_registry_cache_for_tests();

    first = list_commands();
    second = list_commands();

    assert len(first) == len(BUILTIN_COMMANDS);
    assert len(second) == len(BUILTIN_COMMANDS);
}

"""Directly manufactures the duplicate-node graph state that the commit-timing race described in
`_registry_lock`'s docstring can leave behind, bypassing `register_command`'s own dedup so this
test exercises `list_commands`'s read-side dedup itself rather than the lock that fails to prevent
the duplicate in the first place."""
test "list_commands collapses two Command nodes sharing one command_id into one entry" {
    _reset_command_registry_cache_for_tests();
    reg = get_command_registry();
    spec = BUILTIN_COMMANDS[0];
    reg +>:Contributes():+> Command(command_id=spec["id"], title=spec["title"], keybindings=spec["keybindings"]);
    reg +>:Contributes():+> Command(command_id=spec["id"], title=spec["title"], keybindings=spec["keybindings"]);

    commands = list_commands();

    matching = [c for c in commands if c["id"] == spec["id"]];
    assert len(matching) == 1;
}
