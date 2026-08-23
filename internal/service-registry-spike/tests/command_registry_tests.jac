import from src.command_registry {
    CommandRegistry, get_command_registry, register_command, list_commands, run_command,
    _reset_command_registry_cache_for_tests
}

test "get_command_registry is idempotent" {
    _reset_command_registry_cache_for_tests();
    first = get_command_registry();
    second = get_command_registry();
    assert jid(first) == jid(second);
    assert len([root-->[?:CommandRegistry]]) == 1;
}

test "registering the same command id twice does not duplicate its metadata node" {
    _reset_command_registry_cache_for_tests();
    register_command("test.noop", "No-op", lambda { None; });
    register_command("test.noop", "No-op", lambda { None; });
    matches = [c for c in list_commands() if c.command_id == "test.noop"];
    assert len(matches) == 1;
}

test "run_command dispatches to the currently registered handler" {
    _reset_command_registry_cache_for_tests();
    register_command("test.echo", "Echo", lambda { return "first"; });
    assert run_command("test.echo") == "first";

    register_command("test.echo", "Echo", lambda { return "second"; });
    assert run_command("test.echo") == "second";
}

test "run_command raises for an unregistered id" {
    _reset_command_registry_cache_for_tests();
    with testraises(ValueError) {
        run_command("test.does-not-exist");
    }
}
