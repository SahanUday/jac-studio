import os;
import tempfile;

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

test "each returned command carries its registered keybindings, tagged as default" {
    _reset_command_registry_cache_for_tests();
    os.environ["JAC_STUDIO_CONFIG_DIR"] = tempfile.mkdtemp();

    commands = list_commands();

    by_id = {c["id"]: c["keybindings"] for c in commands};
    for spec in BUILTIN_COMMANDS {
        assert [(b["key"], b["when"]) for b in by_id[spec["id"]]] == [(b["key"], b["when"]) for b in spec["keybindings"]];
        assert all([b["source"] == "default" for b in by_id[spec["id"]]]);
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

def fresh_user_dir -> str {
    directory = tempfile.mkdtemp();
    os.environ["JAC_STUDIO_CONFIG_DIR"] = directory;
    return directory;
}

def keys_of(command_id: str) -> list[str] {
    return [b["key"] for c in list_commands() if c["id"] == command_id for b in c["keybindings"]];
}

test "with no keybindings.json every command keeps its built-in keybindings" {
    _reset_command_registry_cache_for_tests();
    fresh_user_dir();
    by_id = {c["id"]: [b["key"] for b in c["keybindings"]] for c in list_commands()};
    for spec in BUILTIN_COMMANDS {
        assert by_id[spec["id"]] == [b["key"] for b in spec["keybindings"]];
    }
}

test "set_command_keybinding replaces a command's bindings and leaves others alone" {
    _reset_command_registry_cache_for_tests();
    fresh_user_dir();
    assert set_command_keybinding("workbench.action.quickOpen", "Ctrl+Shift+O", "")["ok"];
    assert keys_of("workbench.action.quickOpen") == ["ctrl+shift+o"];
    assert keys_of("workbench.action.showCommands") == ["ctrl+shift+p"];
}

test "set_command_keybinding refuses an unknown command or a bad key and writes nothing" {
    _reset_command_registry_cache_for_tests();
    directory = fresh_user_dir();
    assert not set_command_keybinding("no.such.command", "ctrl+q", "")["ok"];
    assert not set_command_keybinding("workbench.action.quickOpen", "ctrl+k ctrl+s", "")["ok"];
    assert not set_command_keybinding("workbench.action.quickOpen", "ctrl", "")["ok"];
    assert not os.path.exists(os.path.join(directory, "keybindings.json"));
}

test "clear_command_keybinding leaves the command unbound and reset restores its default" {
    _reset_command_registry_cache_for_tests();
    fresh_user_dir();
    clear_command_keybinding("workbench.action.quickOpen");
    assert keys_of("workbench.action.quickOpen") == [];
    reset_command_keybinding("workbench.action.quickOpen");
    assert keys_of("workbench.action.quickOpen") == ["ctrl+p"];
}

test "list_commands marks modified commands and reports their defaults" {
    _reset_command_registry_cache_for_tests();
    fresh_user_dir();
    set_command_keybinding("workbench.action.quickOpen", "ctrl+shift+o", "");
    by_id = {c["id"]: c for c in list_commands()};
    assert by_id["workbench.action.quickOpen"]["modified"];
    assert by_id["workbench.action.quickOpen"]["defaults"][0]["key"] == "ctrl+p";
    assert not by_id["workbench.action.showCommands"]["modified"];
}

test "a hand-edited rule file is honoured, and a corrupt one falls back to defaults" {
    _reset_command_registry_cache_for_tests();
    directory = fresh_user_dir();
    path = os.path.join(directory, "keybindings.json");
    with open(path, "w") as f {
        f.write("[{\"key\": \"ctrl+alt+h\", \"command\": \"workbench.action.showWelcome\"}]");
    }
    assert keys_of("workbench.action.showWelcome") == ["ctrl+alt+h"];
    with open(path, "w") as f {
        f.write("{not json");
    }
    assert keys_of("workbench.action.quickOpen") == ["ctrl+p"];
}

test "ensure_keybindings_file creates an empty list once and keeps existing rules" {
    _reset_command_registry_cache_for_tests();
    directory = fresh_user_dir();
    path = ensure_keybindings_file();
    assert path == os.path.join(directory, "keybindings.json");
    set_command_keybinding("workbench.action.quickOpen", "ctrl+shift+o", "");
    ensure_keybindings_file();
    assert keys_of("workbench.action.quickOpen") == ["ctrl+shift+o"];
}

test "a command no longer in BUILTIN_COMMANDS is never returned, even if its node is still in the graph" {
    _reset_command_registry_cache_for_tests();
    fresh_user_dir();
    list_commands();
    register_command("removed.in.a.later.release", "Gone", [{"key": "ctrl+9", "when": ""}]);
    ids = [c["id"] for c in list_commands()];
    assert "removed.in.a.later.release" not in ids;
    assert len(ids) == len(BUILTIN_COMMANDS);
}

