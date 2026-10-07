glob DEFAULT_P: list[dict[str, str]] = [{"key": "ctrl+p", "when": ""}];

test "normalize_key canonicalises order, case and aliases" {
    assert normalize_key("ctrl+shift+p") == "ctrl+shift+p";
    assert normalize_key("Shift+Ctrl+P") == "ctrl+shift+p";
    assert normalize_key("cmd+s") == "ctrl+s";
    assert normalize_key("alt+ctrl+arrowup") == "ctrl+alt+arrowup";
    assert normalize_key("escape") == "escape";
    assert normalize_key("ctrl+`") == "ctrl+`";
}

test "normalize_key rejects anything that is not one well-formed chord" {
    for bad in ["", "   ", "ctrl", "shift+alt", "ctrl+", "ctrl+k ctrl+s", "hyper+p", "ctrl+bogus+p"] {
        assert normalize_key(bad) == "";
    }
}

test "key_error names the problem" {
    assert key_error("") != "";
    assert "sequence" in key_error("ctrl+k ctrl+s");
    assert key_error("ctrl+shift+p") == "";
    assert key_error("ctrl") != "";
}

test "resolve_command_keybindings with no rules returns the defaults tagged as default" {
    out = resolve_command_keybindings("x", DEFAULT_P, []);
    assert out == [{"key": "ctrl+p", "when": "", "source": "default"}];
}

test "a user rule adds a binding, and a duplicate of an existing one is not repeated" {
    rules = [{"key": "ctrl+alt+o", "command": "x"}, {"key": "ctrl+p", "command": "x"}, {"key": "Alt+Ctrl+O", "command": "x"}];
    out = resolve_command_keybindings("x", DEFAULT_P, rules);
    assert [b["key"] for b in out] == ["ctrl+p", "ctrl+alt+o"];
    assert out[1]["source"] == "user";
}

test "a -command rule removes only that default key" {
    defaults = [{"key": "ctrl+p", "when": ""}, {"key": "ctrl+shift+o", "when": ""}];
    out = resolve_command_keybindings("x", defaults, [{"key": "ctrl+p", "command": "-x"}]);
    assert [b["key"] for b in out] == ["ctrl+shift+o"];
}

test "rules for other commands, malformed rules and bad keys are ignored" {
    rules = ["junk", {"key": 5, "command": "x"}, {"command": "x"}, {"key": "ctrl", "command": "x"}, {"key": "ctrl+q", "command": "y"}];
    assert resolve_command_keybindings("x", DEFAULT_P, rules) == [{"key": "ctrl+p", "when": "", "source": "default"}];
}

test "a user rule carries its when clause" {
    out = resolve_command_keybindings("x", [], [{"key": "ctrl+t", "command": "x", "when": "terminalFocus"}]);
    assert out == [{"key": "ctrl+t", "when": "terminalFocus", "source": "user"}];
}

test "rules_with_binding replaces everything for the command and leaves other rules alone" {
    rules = [{"key": "ctrl+q", "command": "y"}, {"key": "ctrl+9", "command": "x"}];
    updated = rules_with_binding(rules, "x", DEFAULT_P, "Ctrl+Shift+O", "");
    assert {"key": "ctrl+q", "command": "y"} in updated;
    assert {"key": "ctrl+p", "command": "-x"} in updated;
    assert {"key": "ctrl+shift+o", "command": "x"} in updated;
    assert {"key": "ctrl+9", "command": "x"} not in updated;
    out = resolve_command_keybindings("x", DEFAULT_P, updated);
    assert [b["key"] for b in out] == ["ctrl+shift+o"];
}

test "rules_cleared leaves the command unbound, and rules_without_command resets it to its defaults" {
    cleared = rules_cleared([], "x", DEFAULT_P);
    assert resolve_command_keybindings("x", DEFAULT_P, cleared) == [];
    reset = rules_without_command(cleared, "x");
    assert reset == [];
    assert resolve_command_keybindings("x", DEFAULT_P, reset)[0]["key"] == "ctrl+p";
}

test "is_modified sees additions and removals but not other commands' rules" {
    assert not is_modified("x", []);
    assert is_modified("x", [{"key": "ctrl+p", "command": "-x"}]);
    assert is_modified("x", [{"key": "ctrl+9", "command": "x"}]);
    assert not is_modified("x", [{"key": "ctrl+9", "command": "y"}]);
}
