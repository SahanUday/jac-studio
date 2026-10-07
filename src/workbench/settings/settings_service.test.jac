import os;
import tempfile;
import from src.workbench.workspace.workspace_service { open_workspace, close_workspace, _reset_workspace_cache_for_tests }

def fresh_user_dir -> str {
    directory = tempfile.mkdtemp();
    os.environ["JAC_STUDIO_CONFIG_DIR"] = directory;
    return directory;
}

def fresh_workspace -> str {
    _reset_workspace_cache_for_tests();
    folder = tempfile.mkdtemp();
    open_workspace(folder);
    return folder;
}

test "get_setting returns the schema default when nothing is stored" {
    fresh_user_dir();
    close_workspace();
    assert get_setting("workbench.colorTheme", "x") == "dark";
    assert get_setting("editor.fontSize", 0) == 14;
    assert get_setting("no.such.key", "fallback") == "fallback";
}

test "set_setting then get_setting round-trips through settings.json" {
    directory = fresh_user_dir();
    close_workspace();
    assert set_setting("workbench.colorTheme", "light")["ok"];
    assert get_setting("workbench.colorTheme", "") == "light";
    assert os.path.exists(os.path.join(directory, "settings.json"));
}

test "setting one key does not disturb another" {
    fresh_user_dir();
    close_workspace();
    set_setting("workbench.colorTheme", "light");
    set_setting("editor.fontSize", 18);
    assert get_setting("workbench.colorTheme", "") == "light";
    assert get_setting("editor.fontSize", 0) == 18;
}

test "an invalid value is rejected with a message and nothing is written" {
    directory = fresh_user_dir();
    close_workspace();
    result = update_setting("user", "editor.fontSize", 1);
    assert not result["ok"] and result["error"] != "";
    assert not os.path.exists(os.path.join(directory, "settings.json"));
    assert not update_setting("user", "bogus.key", 1)["ok"];
}

test "workspace scope overrides user scope, and reset falls back to the user value" {
    fresh_user_dir();
    folder = fresh_workspace();
    update_setting("user", "editor.tabSize", 2);
    update_setting("workspace", "editor.tabSize", 8);
    assert get_setting("editor.tabSize", 0) == 8;
    assert os.path.exists(os.path.join(folder, ".jac-studio", "settings.json"));

    reset_setting("workspace", "editor.tabSize");
    assert get_setting("editor.tabSize", 0) == 2;
}

test "workspace scope is refused when no folder is open" {
    fresh_user_dir();
    _reset_workspace_cache_for_tests();
    close_workspace();
    result = update_setting("workspace", "editor.tabSize", 2);
    assert not result["ok"];
    assert ensure_settings_file("workspace") == "";
}

test "a hand-edited bad value or corrupt file falls back to defaults instead of raising" {
    directory = fresh_user_dir();
    close_workspace();
    with open(os.path.join(directory, "settings.json"), "w") as f {
        f.write("{\"editor.fontSize\": \"huge\", \"editor.wordWrap\": \"on\"}");
    }
    assert get_setting("editor.fontSize", 0) == 14;
    assert get_setting("editor.wordWrap", "") == "on";
    with open(os.path.join(directory, "settings.json"), "w") as f {
        f.write("[1, 2");
    }
    assert get_setting("editor.fontSize", 0) == 14;
}

test "reset_setting removes only that key" {
    fresh_user_dir();
    close_workspace();
    set_setting("editor.fontSize", 20);
    set_setting("editor.tabSize", 2);
    reset_setting("user", "editor.fontSize");
    view = get_settings_view();
    assert "editor.fontSize" not in view["user"];
    assert view["user"]["editor.tabSize"] == 2;
    assert view["effective"]["editor.fontSize"] == 14;
}

test "ensure_settings_file creates an empty object once and leaves existing content alone" {
    directory = fresh_user_dir();
    close_workspace();
    path = ensure_settings_file("user");
    assert path == os.path.join(directory, "settings.json");
    with open(path, "r") as f {
        assert f.read().strip() == "{}";
    }
    set_setting("editor.tabSize", 3);
    ensure_settings_file("user");
    assert get_setting("editor.tabSize", 0) == 3;
}

test "values in the old graph Settings node migrate to settings.json once, then the node is emptied" {
    directory = fresh_user_dir();
    close_workspace();
    existing = [root-->[?:Settings]];
    stored = existing[0] if existing else root ++> Settings();
    stored.values = {"workbench.colorTheme": "light", "terminal.integrated.fontSize": 99999, "old.unknown": 1};

    assert get_setting("workbench.colorTheme", "") == "light";
    assert get_settings_view()["user"] == {"workbench.colorTheme": "light"};
    assert os.path.exists(os.path.join(directory, "settings.json"));
    assert len([root-->[?:Settings]][0].values) == 0;
}
