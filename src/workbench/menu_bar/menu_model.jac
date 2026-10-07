"""The menu bar's content as data: every item is a command id, so a menu click, the palette and a
keybinding all dispatch through `workbench.jac`'s `handle_command`. `shortcut` is a display hint for
actions Monaco binds itself; workbench commands take theirs from the registry. Only items that work
are listed."""

"""Monaco actions run against the active editor (`run_editor_command` in `monaco_editor.jac`)."""
glob:pub EDITOR_COMMANDS: list[str] = [
    "undo", "redo", "actions.find", "editor.action.startFindReplaceAction",
    "editor.action.commentLine", "editor.action.formatDocument",
    "selectAll", "editor.action.smartSelect.expand", "editor.action.smartSelect.shrink",
    "editor.action.copyLinesUpAction", "editor.action.copyLinesDownAction",
    "editor.action.moveLinesUpAction", "editor.action.moveLinesDownAction",
    "editor.action.duplicateSelection", "editor.action.insertCursorAbove", "editor.action.insertCursorBelow",
    "editor.action.gotoLine", "editor.action.quickOutline"
];

glob SEPARATOR: dict[str, any] = {"separator": True};

def _item(command: str, label: str, needs: str, shortcut: str) -> dict[str, any] {
    return {"command": command, "label": label, "needs": needs, "shortcut": shortcut};
}

glob:pub MENUS: list[dict[str, any]] = [
    {"label": "File", "items": [
        _item("workbench.action.files.openFolder", "Open Folder...", "", ""),
        _item("workbench.action.openRecent", "Open Recent...", "", ""),
        _item("workbench.action.files.closeFolder", "Close Folder", "workspace", ""),
        SEPARATOR,
        _item("workbench.action.files.save", "Save", "editor", "Ctrl+S"),
        _item("workbench.action.closeActiveEditor", "Close Editor", "tab", ""),
        SEPARATOR,
        _item("workbench.action.openSettings", "Settings", "", ""),
        _item("workbench.action.openSettingsJson", "Open Settings (JSON)", "", ""),
        _item("workbench.action.openWorkspaceSettingsJson", "Open Workspace Settings (JSON)", "workspace", ""),
        _item("workbench.action.toggleColorTheme", "Toggle Color Theme", "", "")
    ]},
    {"label": "Edit", "items": [
        _item("undo", "Undo", "editor", "Ctrl+Z"),
        _item("redo", "Redo", "editor", "Ctrl+Y"),
        SEPARATOR,
        _item("actions.find", "Find", "editor", "Ctrl+F"),
        _item("editor.action.startFindReplaceAction", "Replace", "editor", "Ctrl+H"),
        SEPARATOR,
        _item("editor.action.commentLine", "Toggle Line Comment", "editor", "Ctrl+/"),
        _item("editor.action.formatDocument", "Format Document", "editor", "Shift+Alt+F")
    ]},
    {"label": "Selection", "items": [
        _item("selectAll", "Select All", "editor", "Ctrl+A"),
        _item("editor.action.smartSelect.expand", "Expand Selection", "editor", "Shift+Alt+Right"),
        _item("editor.action.smartSelect.shrink", "Shrink Selection", "editor", "Shift+Alt+Left"),
        SEPARATOR,
        _item("editor.action.copyLinesUpAction", "Copy Line Up", "editor", "Shift+Alt+Up"),
        _item("editor.action.copyLinesDownAction", "Copy Line Down", "editor", "Shift+Alt+Down"),
        _item("editor.action.moveLinesUpAction", "Move Line Up", "editor", "Alt+Up"),
        _item("editor.action.moveLinesDownAction", "Move Line Down", "editor", "Alt+Down"),
        _item("editor.action.duplicateSelection", "Duplicate Selection", "editor", ""),
        SEPARATOR,
        _item("editor.action.insertCursorAbove", "Add Cursor Above", "editor", "Ctrl+Alt+Up"),
        _item("editor.action.insertCursorBelow", "Add Cursor Below", "editor", "Ctrl+Alt+Down")
    ]},
    {"label": "View", "items": [
        _item("workbench.action.showCommands", "Command Palette...", "", ""),
        SEPARATOR,
        _item("workbench.view.explorer", "Explorer", "", ""),
        _item("workbench.action.showSearch", "Search", "", ""),
        _item("workbench.action.showScm", "Source Control", "", ""),
        _item("workbench.view.outline", "Outline", "", ""),
        _item("workbench.view.aiChat", "AI Chat", "", ""),
        SEPARATOR,
        _item("workbench.action.terminal.toggle", "Terminal", "", ""),
        _item("workbench.action.output.toggle", "Output", "", ""),
        _item("workbench.action.debug.toggle", "Debug Console", "", ""),
        SEPARATOR,
        _item("workbench.action.splitEditorRight", "Split Editor Right", "tab", "")
    ]},
    {"label": "Go", "items": [
        _item("workbench.action.quickOpen", "Go to File...", "workspace", ""),
        _item("editor.action.gotoLine", "Go to Line...", "editor", "Ctrl+G"),
        _item("editor.action.quickOutline", "Go to Symbol in Editor...", "editor", "Ctrl+Shift+O")
    ]},
    {"label": "Run", "items": [
        _item("workbench.action.tasks.runTask", "Run Task...", "workspace", ""),
        _item("workbench.action.debug.toggle", "Debug Console", "", "")
    ]},
    {"label": "Terminal", "items": [
        _item("workbench.action.terminal.toggle", "Toggle Terminal", "", ""),
        _item("workbench.action.tasks.runTask", "Run Task...", "workspace", "")
    ]},
    {"label": "Help", "items": [
        _item("workbench.action.showWelcome", "Welcome", "", ""),
        _item("workbench.action.showCommands", "Show All Commands", "", "")
    ]}
];

"""`needs` is "" (always), "workspace" (a folder is open), "tab" (any tab is open) or "editor" (the
active tab is a text editor)."""
def:pub item_enabled(item: dict[str, any], has_workspace: bool, has_tab: bool, has_editor: bool) -> bool {
    needs = item.get("needs", "");
    if needs == "tab" {
        return has_tab;
    }
    if needs == "workspace" {
        return has_workspace;
    }
    if needs == "editor" {
        return has_editor;
    }
    return True;
}

"""A command's workbench keybinding if the registry has one, else the static hint."""
def:pub item_shortcut(item: dict[str, any], registry_label: str) -> str {
    return registry_label if registry_label != "" else item.get("shortcut", "");
}
