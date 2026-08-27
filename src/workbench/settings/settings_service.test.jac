test "get_setting returns the fallback when the key was never set" {
    _reset_settings_cache_for_tests();

    value = get_setting("workbench.colorTheme", "dark");

    assert value == "dark";
}

test "set_setting then get_setting round-trips the stored value" {
    _reset_settings_cache_for_tests();

    set_setting("workbench.colorTheme", "light");
    value = get_setting("workbench.colorTheme", "dark");

    assert value == "light";
}

test "setting one key does not disturb another key's stored value" {
    _reset_settings_cache_for_tests();
    set_setting("workbench.colorTheme", "light");

    set_setting("terminal.integrated.fontSize", 14);

    assert get_setting("workbench.colorTheme", "dark") == "light";
    assert get_setting("terminal.integrated.fontSize", 12) == 14;
}

test "set_setting on an existing key overwrites, not appends" {
    _reset_settings_cache_for_tests();
    set_setting("workbench.colorTheme", "light");

    set_setting("workbench.colorTheme", "dark");

    assert get_setting("workbench.colorTheme", "") == "dark";
}

test "a value persists across separate get_setting calls within the same root" {
    _reset_settings_cache_for_tests();
    set_setting("editor.wordWrap", True);

    first_read = get_setting("editor.wordWrap", False);
    second_read = get_setting("editor.wordWrap", False);

    assert first_read;
    assert second_read;
}
