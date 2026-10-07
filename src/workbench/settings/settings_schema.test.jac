test "every setting has a key, type, default, category and description, and its default validates" {
    seen = set();
    for s in SETTINGS {
        assert s["key"] not in seen;
        seen.add(s["key"]);
        assert s["type"] in ["boolean", "number", "enum", "string"];
        assert s["category"] != "" and s["description"] != "";
        assert validate_setting(s["key"], s["default"]) == "";
    }
}

test "validate_setting accepts good values and names the problem for bad ones" {
    assert validate_setting("editor.fontSize", 16) == "";
    assert validate_setting("editor.fontSize", 14.5) == "";
    assert validate_setting("editor.fontSize", 2) != "";
    assert validate_setting("editor.fontSize", "big") != "";
    assert validate_setting("editor.minimap.enabled", False) == "";
    assert validate_setting("editor.minimap.enabled", "yes") != "";
    assert validate_setting("editor.wordWrap", "on") == "";
    assert validate_setting("editor.wordWrap", "sideways") != "";
    assert validate_setting("no.such.setting", 1) != "";
}

test "a bool is never accepted as a number, nor a number as a bool" {
    assert validate_setting("editor.fontSize", True) != "";
    assert validate_setting("editor.minimap.enabled", 1) != "";
}

test "merge_settings layers defaults, user, then workspace" {
    merged = merge_settings({"editor.fontSize": 18, "editor.tabSize": 2}, {"editor.tabSize": 8});
    assert merged["editor.fontSize"] == 18;
    assert merged["editor.tabSize"] == 8;
    assert merged["editor.wordWrap"] == "off";
    assert len(merged) == len(SETTINGS);
}

test "merge_settings skips unknown keys and invalid values instead of raising" {
    merged = merge_settings({"editor.fontSize": "huge", "bogus": 1, "editor.wordWrap": "on"}, {});
    assert merged["editor.fontSize"] == 14;
    assert "bogus" not in merged;
    assert merged["editor.wordWrap"] == "on";
}
