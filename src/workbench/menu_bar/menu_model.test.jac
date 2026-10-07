test "every menu item is a separator or names a command, label and needs" {
    for menu in MENUS {
        assert len(menu["items"]) > 0;
        for item in menu["items"] {
            if item.get("separator") {
                continue;
            }
            assert item["command"] != "" and item["label"] != "";
            assert item["needs"] in ["", "workspace", "tab", "editor"];
        }
    }
}

test "no menu starts, ends or doubles up on a separator" {
    for menu in MENUS {
        items = menu["items"];
        assert not items[0].get("separator") and not items[-1].get("separator");
        for i in range(1, len(items)) {
            assert not (items[i].get("separator") and items[i - 1].get("separator"));
        }
    }
}

test "every Monaco-bound command in a menu is listed in EDITOR_COMMANDS" {
    for menu in MENUS {
        for item in menu["items"] {
            if item.get("separator") {
                continue;
            }
            is_workbench = item["command"].startswith("workbench.");
            assert is_workbench or item["command"] in EDITOR_COMMANDS;
        }
    }
}

test "item_enabled gates on workspace, tab and editor, and an ungated item is always on" {
    always = {"needs": ""};
    needs_ws = {"needs": "workspace"};
    needs_tab = {"needs": "tab"};
    needs_ed = {"needs": "editor"};
    assert item_enabled(always, False, False, False);
    assert not item_enabled(needs_ws, False, False, False);
    assert item_enabled(needs_ws, True, False, False);
    assert not item_enabled(needs_tab, True, False, False);
    assert item_enabled(needs_tab, True, True, False);
    assert not item_enabled(needs_ed, True, True, False);
    assert item_enabled(needs_ed, True, True, True);
}

test "item_shortcut prefers the registry's binding over the static hint" {
    item = {"shortcut": "Ctrl+S"};
    assert item_shortcut(item, "Ctrl+Shift+P") == "Ctrl+Shift+P";
    assert item_shortcut(item, "") == "Ctrl+S";
    assert item_shortcut({}, "") == "";
}
