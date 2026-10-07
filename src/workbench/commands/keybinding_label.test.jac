test "format_keybinding is empty for no keybindings" {
    assert format_keybinding([]) == "";
}

test "format_keybinding capitalizes each part and joins with +" {
    assert format_keybinding([{"key": "ctrl+shift+p", "when": ""}]) == "Ctrl+Shift+P";
}

test "format_keybinding prefers the always-on binding over a context-scoped one" {
    scoped_first = [{"key": "escape", "when": "terminalFocus"}, {"key": "ctrl+`", "when": ""}];
    assert format_keybinding(scoped_first) == "Ctrl+`";
}

test "format_keybinding falls back to the first binding when every one is context-scoped" {
    assert format_keybinding([{"key": "escape", "when": "terminalFocus"}]) == "Escape";
}
