"""Only `list_commands` is exercised directly -- `register_command`/`get_command_registry` are
plain (non-`:pub`) implementation details, reached only through the one client-facing entry point,
per `document_service.jac`/`workspace_service.jac`'s precedent of testing the public surface."""

test "list_commands seeds and returns the built-in Phase 2 command set" {
    _reset_command_registry_cache_for_tests();

    commands = list_commands();

    assert len(commands) == len(BUILTIN_COMMANDS);
    ids = [c["id"] for c in commands];
    for (command_id, _) in BUILTIN_COMMANDS {
        assert command_id in ids;
    }
}

test "each returned command carries its registered title" {
    _reset_command_registry_cache_for_tests();

    commands = list_commands();

    by_id = {c["id"]: c["title"] for c in commands};
    for (command_id, title) in BUILTIN_COMMANDS {
        assert by_id[command_id] == title;
    }
}

test "calling list_commands twice does not duplicate entries" {
    _reset_command_registry_cache_for_tests();

    first = list_commands();
    second = list_commands();

    assert len(first) == len(BUILTIN_COMMANDS);
    assert len(second) == len(BUILTIN_COMMANDS);
}
