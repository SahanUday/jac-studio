glob CMDS: list[dict[str, any]] = [
    {"id": "workbench.action.quickOpen", "title": "Go to File...", "keybindings": [{"key": "ctrl+p", "when": "", "source": "default"}]},
    {"id": "workbench.action.showCommands", "title": "Show All Commands", "keybindings": [{"key": "ctrl+shift+p", "when": "", "source": "default"}]},
    {"id": "workbench.action.files.openFolder", "title": "File: Open Folder...", "keybindings": []}
];

test "visible_commands with no query returns everything sorted by title" {
    assert [c["title"] for c in visible_commands(CMDS, "")] == ["File: Open Folder...", "Go to File...", "Show All Commands"];
}

test "visible_commands matches title, id and keys, any case, every word required" {
    assert [c["id"] for c in visible_commands(CMDS, "open folder")] == ["workbench.action.files.openFolder"];
    assert [c["id"] for c in visible_commands(CMDS, "QUICKOPEN")] == ["workbench.action.quickOpen"];
    assert len(visible_commands(CMDS, "ctrl+shift+p")) == 1;
    assert [c["id"] for c in visible_commands(CMDS, "Ctrl+P")] == ["workbench.action.quickOpen"];
    assert len(visible_commands(CMDS, "shift p")) == 1;
    assert visible_commands(CMDS, "nothing like this") == [];
}

test "conflicts_for lists other commands on the chord and never the command itself" {
    assert conflicts_for(CMDS, "ctrl+p", "workbench.action.showCommands") == ["Go to File..."];
    assert conflicts_for(CMDS, "ctrl+p", "workbench.action.quickOpen") == [];
    assert conflicts_for(CMDS, "ctrl+9", "x") == [];
}
