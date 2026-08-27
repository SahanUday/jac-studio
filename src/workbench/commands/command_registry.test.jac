"""Only `list_commands` is exercised directly -- `register_command`/`get_command_registry` are
plain (non-`:pub`) implementation details, reached only through the one client-facing entry point,
per `document_service.jac`/`workspace_service.jac`'s precedent of testing the public surface."""

test "list_commands seeds and returns the built-in Phase 2 command set" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();

    commands = list_commands();

    assert len(commands) == len(BUILTIN_COMMANDS);
    ids = [c["id"] for c in commands];
    for spec in BUILTIN_COMMANDS {
        assert spec["id"] in ids;
    }
}

test "each returned command carries its registered title" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();

    commands = list_commands();

    by_id = {c["id"]: c["title"] for c in commands};
    for spec in BUILTIN_COMMANDS {
        assert by_id[spec["id"]] == spec["title"];
    }
}

test "each returned command carries its registered keybindings" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();

    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    for spec in BUILTIN_COMMANDS {
        assert by_id[spec["id"]] == spec["keybindings"];
    }
}

test "calling list_commands twice does not duplicate entries" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();

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
    _reset_keybinding_overrides_cache_for_tests();
    reg = get_command_registry();
    spec = BUILTIN_COMMANDS[0];
    reg +>:Contributes():+> Command(command_id=spec["id"], title=spec["title"], keybindings=spec["keybindings"]);
    reg +>:Contributes():+> Command(command_id=spec["id"], title=spec["title"], keybindings=spec["keybindings"]);

    commands = list_commands();

    matching = [c for c in commands if c["id"] == spec["id"]];
    assert len(matching) == 1;
}

test "set_keybinding_override replaces a command's keybindings in list_commands" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();
    spec = BUILTIN_COMMANDS[0];

    set_keybinding_override(spec["id"], [{"key": "ctrl+k ctrl+s", "when": ""}]);
    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    assert by_id[spec["id"]] == [{"key": "ctrl+k ctrl+s", "when": ""}];
}

test "an override for one command does not affect another command's default keybindings" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();
    overridden = BUILTIN_COMMANDS[0];
    untouched = BUILTIN_COMMANDS[2];

    set_keybinding_override(overridden["id"], [{"key": "ctrl+k ctrl+s", "when": ""}]);
    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    assert by_id[untouched["id"]] == untouched["keybindings"];
}

test "clear_keybinding_override reverts a command to its built-in default" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();
    spec = BUILTIN_COMMANDS[0];
    set_keybinding_override(spec["id"], [{"key": "ctrl+k ctrl+s", "when": ""}]);

    clear_keybinding_override(spec["id"]);
    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    assert by_id[spec["id"]] == spec["keybindings"];
}

test "clear_keybinding_override on a command with no override is a harmless no-op" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();

    clear_keybinding_override(BUILTIN_COMMANDS[0]["id"]);

    commands = list_commands();
    assert len(commands) == len(BUILTIN_COMMANDS);
}

test "a code change to a built-in command's default keybindings does not silently overwrite a user override" {
    _reset_command_registry_cache_for_tests();
    _reset_keybinding_overrides_cache_for_tests();
    spec = BUILTIN_COMMANDS[0];
    set_keybinding_override(spec["id"], [{"key": "ctrl+k ctrl+s", "when": ""}]);

    # simulates `register_command` re-syncing the Command node's own default on a later call --
    # the override lives in a separate node, so this must not touch it
    register_command(spec["id"], spec["title"], [{"key": "some+new+default", "when": ""}]);
    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    assert by_id[spec["id"]] == [{"key": "ctrl+k ctrl+s", "when": ""}];
}
