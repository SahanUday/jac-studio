"""Command metadata as graph contributions; execution is entirely client-side in `workbench.jac`.
Commands are seeded lazily on the first `list_commands` call. User keybindings are not graph state:
they come from `keybindings.json` (VS Code's format, rules in `keybindings_model.jac`) merged over
each command's defaults on every call, so a resync from `BUILTIN_COMMANDS` can never revert them."""

import os;
import threading;
import from src.workbench.user_data.user_data { user_data_dir, read_json_path, write_json_path }
import from src.workbench.commands.keybindings_model {
    normalize_key, key_error, resolve_command_keybindings, is_modified,
    rules_without_command, rules_cleared, rules_with_binding
}

node CommandRegistry {}

node Command {
    has command_id: str;
    has title: str;
    has keybindings: list[dict[str, str]] = [];
}

edge Contributes: CommandRegistry --> Command {}

glob BUILTIN_COMMANDS: list[dict[str, any]] = [
    {"id": "workbench.action.files.openFolder", "title": "File: Open Folder...", "keybindings": []},
    {"id": "workbench.action.openRecent", "title": "File: Open Recent...", "keybindings": []},
    {"id": "workbench.action.files.closeFolder", "title": "File: Close Folder", "keybindings": []},
    {"id": "workbench.action.files.save", "title": "File: Save", "keybindings": []},
    {"id": "workbench.view.explorer", "title": "View: Show Explorer", "keybindings": []},
    {"id": "workbench.view.outline", "title": "View: Show Outline", "keybindings": []},
    {"id": "workbench.view.aiChat", "title": "View: Show AI Chat", "keybindings": []},
    {"id": "undo", "title": "Edit: Undo", "keybindings": []},
    {"id": "redo", "title": "Edit: Redo", "keybindings": []},
    {"id": "actions.find", "title": "Edit: Find", "keybindings": []},
    {"id": "editor.action.startFindReplaceAction", "title": "Edit: Replace", "keybindings": []},
    {"id": "editor.action.commentLine", "title": "Edit: Toggle Line Comment", "keybindings": []},
    {"id": "editor.action.formatDocument", "title": "Edit: Format Document", "keybindings": []},
    {"id": "selectAll", "title": "Selection: Select All", "keybindings": []},
    {"id": "editor.action.smartSelect.expand", "title": "Selection: Expand Selection", "keybindings": []},
    {"id": "editor.action.smartSelect.shrink", "title": "Selection: Shrink Selection", "keybindings": []},
    {"id": "editor.action.copyLinesUpAction", "title": "Selection: Copy Line Up", "keybindings": []},
    {"id": "editor.action.copyLinesDownAction", "title": "Selection: Copy Line Down", "keybindings": []},
    {"id": "editor.action.moveLinesUpAction", "title": "Selection: Move Line Up", "keybindings": []},
    {"id": "editor.action.moveLinesDownAction", "title": "Selection: Move Line Down", "keybindings": []},
    {"id": "editor.action.duplicateSelection", "title": "Selection: Duplicate Selection", "keybindings": []},
    {"id": "editor.action.insertCursorAbove", "title": "Selection: Add Cursor Above", "keybindings": []},
    {"id": "editor.action.insertCursorBelow", "title": "Selection: Add Cursor Below", "keybindings": []},
    {"id": "editor.action.gotoLine", "title": "Go: Go to Line...", "keybindings": []},
    {"id": "editor.action.quickOutline", "title": "Go: Go to Symbol in Editor...", "keybindings": []},
    {"id": "workbench.action.openSettings", "title": "Preferences: Open Settings", "keybindings": [{"key": "ctrl+,", "when": ""}]},
    {"id": "workbench.action.openKeybindings", "title": "Preferences: Open Keyboard Shortcuts", "keybindings": []},
    {"id": "workbench.action.openKeybindingsJson", "title": "Preferences: Open Keyboard Shortcuts (JSON)", "keybindings": []},
    {"id": "workbench.action.openSettingsJson", "title": "Preferences: Open Settings (JSON)", "keybindings": []},
    {"id": "workbench.action.openWorkspaceSettingsJson", "title": "Preferences: Open Workspace Settings (JSON)", "keybindings": []},
    {"id": "workbench.action.showWelcome", "title": "Help: Welcome", "keybindings": []},
    {"id": "workbench.action.splitEditorRight", "title": "View: Split Editor Right", "keybindings": []},
    {"id": "workbench.action.closeActiveEditor", "title": "View: Close Editor", "keybindings": []},
    {
        "id": "workbench.action.terminal.toggle",
        "title": "View: Toggle Terminal",
        "keybindings": [
            {"key": "ctrl+`", "when": ""},
            {"key": "escape", "when": "terminalFocus"}
        ]
    },
    {
        "id": "workbench.action.output.toggle",
        "title": "View: Toggle Output",
        "keybindings": [{"key": "ctrl+shift+u", "when": ""}]
    },
    {
        "id": "workbench.action.debug.toggle",
        "title": "View: Toggle Debug Console",
        "keybindings": [{"key": "ctrl+shift+y", "when": ""}]
    },
    {
        "id": "workbench.action.showSearch",
        "title": "View: Show Search",
        "keybindings": [{"key": "ctrl+shift+f", "when": ""}]
    },
    {
        "id": "workbench.action.showScm",
        "title": "View: Show Source Control",
        "keybindings": [{"key": "ctrl+shift+g", "when": ""}]
    },
    {"id": "workbench.action.tasks.runTask", "title": "Tasks: Run Task", "keybindings": []},
    {"id": "workbench.action.toggleColorTheme", "title": "Preferences: Toggle Color Theme", "keybindings": []},
    {"id": "workbench.action.quickOpen", "title": "Go to File...", "keybindings": [{"key": "ctrl+p", "when": ""}]},
    {"id": "workbench.action.showCommands", "title": "Show All Commands", "keybindings": [{"key": "ctrl+shift+p", "when": ""}]},
    {"id": "workbench.action.showNotifications", "title": "Notifications: Show", "keybindings": []}
];

glob _cached_command_registries: dict[str, CommandRegistry] = {};

def:pub _keybindings_file -> str {
    return os.path.join(user_data_dir(), "keybindings.json");
}

"""Anything that isn't a JSON list reads as no rules, so a corrupt file can't break startup."""
def _read_rules -> list[any] {
    data = read_json_path(_keybindings_file(), []);
    return data if isinstance(data, list) else [];
}

def _builtin_defaults(command_id: str) -> list[dict[str, str]] | None {
    for spec in BUILTIN_COMMANDS {
        if spec["id"] == command_id {
            return spec["keybindings"];
        }
    }
    return None;
}

"""Only narrows the create-duplicate race -- a `def:pub`'s commit happens after this lock releases,
so `list_commands`'s de-dup of its return value is the actual guarantee."""
glob _registry_lock: threading.Lock = threading.Lock();

def:pub _reset_command_registry_cache_for_tests {
    _cached_command_registries.clear();
}

def get_command_registry -> CommandRegistry {
    key = jid(root);
    if key in _cached_command_registries {
        return _cached_command_registries[key];
    }
    existing = [root-->[?:CommandRegistry]];
    reg = existing[0] if existing else root ++> CommandRegistry();
    _cached_command_registries[key] = reg;
    return reg;
}

"""Resyncs `title`/`keybindings` on every call, not just at creation: the graph outlives the process,
so a node created under an older `BUILTIN_COMMANDS` would otherwise serve its creation-time metadata
forever."""
def register_command(command_id: str, title: str, keybindings: list[dict[str, str]]) -> Command {
    reg = get_command_registry();
    matches = [reg->:Contributes:->[?:Command]];
    for existing_command in matches {
        if existing_command.command_id == command_id {
            # only write on a real change: concurrent callers each rewriting an unchanged node
            # raise WriteConflict
            if existing_command.title != title or existing_command.keybindings != keybindings {
                existing_command.title = title;
                existing_command.keybindings = keybindings;
            }
            return existing_command;
        }
    }
    fresh = Command(command_id=command_id, title=title, keybindings=keybindings);
    reg +>:Contributes():+> fresh;
    return fresh;
}

"""De-dupes by `command_id` on the read path -- keeping the first match is safe since any duplicate
came from the same `BUILTIN_COMMANDS` entry. A node whose id is no longer built in (a command removed
in a later release) is left in the graph but never returned."""
def:pub list_commands -> list[dict[str, any]] {
    with _registry_lock {
        for spec in BUILTIN_COMMANDS {
            register_command(spec["id"], spec["title"], spec["keybindings"]);
        }
        reg = get_command_registry();
        commands = [reg->:Contributes:->[?:Command]];
        rules = _read_rules();
        builtin_ids = {spec["id"] for spec in BUILTIN_COMMANDS};
        seen_ids: set[str] = set();
        deduped = [];
        for c in commands {
            if c.command_id in seen_ids or c.command_id not in builtin_ids {
                continue;
            }
            seen_ids.add(c.command_id);
            deduped.append({
                "id": c.command_id,
                "title": c.title,
                "keybindings": resolve_command_keybindings(c.command_id, c.keybindings, rules),
                "defaults": c.keybindings,
                "modified": is_modified(c.command_id, rules)
            });
        }
        return deduped;
    }
}

"""Rebinds `command_id` to a single chord, replacing its defaults and earlier user bindings. The
result is `{"ok", "error"}` so the editor can show the message inline."""
def:pub set_command_keybinding(command_id: str, key: str, when: str) -> dict[str, any] {
    defaults = _builtin_defaults(command_id);
    if defaults is None {
        return {"ok": False, "error": "Unknown command: " + command_id};
    }
    error = key_error(key);
    if error != "" {
        return {"ok": False, "error": error};
    }
    write_json_path(_keybindings_file(), rules_with_binding(_read_rules(), command_id, defaults, key, when));
    return {"ok": True, "error": ""};
}

"""Leaves the command with no binding at all."""
def:pub clear_command_keybinding(command_id: str) -> None {
    defaults = _builtin_defaults(command_id);
    if defaults is None {
        return;
    }
    write_json_path(_keybindings_file(), rules_cleared(_read_rules(), command_id, defaults));
}

"""Drops every user rule for the command, restoring its defaults."""
def:pub reset_command_keybinding(command_id: str) -> None {
    rules = _read_rules();
    if is_modified(command_id, rules) {
        write_json_path(_keybindings_file(), rules_without_command(rules, command_id));
    }
}

"""Creates an empty rule list so the editor tab opens on something saveable."""
def:pub ensure_keybindings_file -> str {
    path = _keybindings_file();
    if not os.path.exists(path) {
        write_json_path(path, []);
    }
    return path;
}
