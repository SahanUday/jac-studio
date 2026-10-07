test "chord_from_event orders modifiers ctrl, shift, alt and lowercases the key" {
    assert chord_from_event(True, True, False, "P") == "ctrl+shift+p";
    assert chord_from_event(True, True, True, "ArrowUp") == "ctrl+shift+alt+arrowup";
    assert chord_from_event(False, False, False, "Escape") == "escape";
    assert chord_from_event(True, False, False, "`") == "ctrl+`";
}

test "chord_from_event is empty while only a modifier is held" {
    for modifier in ["Control", "Shift", "Alt", "Meta", "AltGraph"] {
        assert chord_from_event(True, True, True, modifier) == "";
    }
    assert chord_from_event(False, False, False, "") == "";
}

test "chord_from_event spells space and plus so a chord never contains a stray separator" {
    assert chord_from_event(True, False, False, " ") == "ctrl+space";
    assert chord_from_event(True, True, False, "+") == "ctrl+shift+plus";
}
