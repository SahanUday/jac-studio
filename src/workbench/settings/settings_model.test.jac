glob SPECS: list[dict[str, any]] = [
    {"key": "editor.minimap.enabled", "category": "Editor", "description": "Controls whether the minimap is shown.", "default": True},
    {"key": "editor.fontSize", "category": "Editor", "description": "Controls the font size in pixels.", "default": 14},
    {"key": "terminal.integrated.fontSize", "category": "Terminal", "description": "Font size of the terminal.", "default": 13}
];

test "setting_title spaces camelCase and prefixes the category" {
    assert setting_title(SPECS[0]) == "Editor: Minimap Enabled";
    assert setting_title(SPECS[1]) == "Editor: Font Size";
    assert setting_title(SPECS[2]) == "Terminal: Integrated Font Size";
}

test "matches_query needs every word, in key, title or description, ignoring case" {
    assert matches_query(SPECS[1], "");
    assert matches_query(SPECS[1], "FONT size");
    assert matches_query(SPECS[1], "pixels");
    assert matches_query(SPECS[1], "editor.fontsize");
    assert not matches_query(SPECS[1], "font minimap");
}

test "categories_of counts settings per category in first-seen order" {
    assert categories_of(SPECS) == [{"name": "Editor", "count": 2}, {"name": "Terminal", "count": 1}];
}

test "visible_settings filters by query and category together" {
    assert len(visible_settings(SPECS, "", "")) == 3;
    assert len(visible_settings(SPECS, "font", "")) == 2;
    assert [s["key"] for s in visible_settings(SPECS, "font", "Terminal")] == ["terminal.integrated.fontSize"];
    assert visible_settings(SPECS, "nothing matches this", "") == [];
}

test "shown_value: a scope shows its own value, workspace inherits user, else the default" {
    spec = SPECS[1];
    assert shown_value(spec, "user", {}, {}) == 14;
    assert shown_value(spec, "user", {"editor.fontSize": 20}, {"editor.fontSize": 8}) == 20;
    assert shown_value(spec, "workspace", {"editor.fontSize": 20}, {}) == 20;
    assert shown_value(spec, "workspace", {"editor.fontSize": 20}, {"editor.fontSize": 8}) == 8;
}

test "is_modified only counts the scope's own file" {
    spec = SPECS[1];
    assert is_modified(spec, "user", {"editor.fontSize": 20}, {});
    assert not is_modified(spec, "workspace", {"editor.fontSize": 20}, {});
    assert is_modified(spec, "workspace", {}, {"editor.fontSize": 8});
}
