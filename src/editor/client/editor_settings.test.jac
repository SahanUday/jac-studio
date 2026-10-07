test "monaco_options_from_settings maps every editor.* setting to its Monaco option" {
    options = monaco_options_from_settings({
        "editor.fontSize": 18, "editor.tabSize": 2, "editor.wordWrap": "on", "editor.lineNumbers": "relative",
        "editor.minimap.enabled": False, "editor.renderWhitespace": "all"
    });
    assert options == {
        "fontSize": 18, "tabSize": 2, "wordWrap": "on", "lineNumbers": "relative",
        "minimap": {"enabled": False}, "renderWhitespace": "all"
    };
}

test "monaco_options_from_settings falls back to Monaco-compatible defaults for missing keys" {
    options = monaco_options_from_settings({});
    assert options["fontSize"] == 14 and options["tabSize"] == 4;
    assert options["wordWrap"] == "off" and options["minimap"]["enabled"];
}

test "monaco_options_from_settings ignores settings outside editor.*" {
    options = monaco_options_from_settings({"workbench.colorTheme": "light", "terminal.integrated.fontSize": 20});
    assert "workbench.colorTheme" not in options and len(options) == 6;
}
