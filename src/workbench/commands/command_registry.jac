"""Command metadata as graph contributions; execution is entirely client-side in `workbench.jac`.
Commands are seeded lazily on the first `list_commands` call; user keybinding overrides live in their
own node so `register_command`'s per-call resync from `BUILTIN_COMMANDS` can't revert them, and that
node caches the jid and re-resolves via `jobj()` before mutating
(`2026-08-28-field-mutation-on-cached-node-not-persisted`)."""

import threading;

node CommandRegistry {}

node Command {
    has command_id: str;
    has title: str;
    has keybindings: list[dict[str, str]] = [];
}

edge Contributes {}

glob BUILTIN_COMMANDS: list[dict[str, any]] = [
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

node KeybindingOverrides {
    has overrides: dict[str, list[dict[str, str]]] = {};
}

glob _cached_command_registries: dict[str, CommandRegistry] = {};
glob _cached_keybinding_overrides_jid: dict[str, str] = {};

def:pub _reset_keybinding_overrides_cache_for_tests {
    _cached_keybinding_overrides_jid.clear();
}

def get_keybinding_overrides -> KeybindingOverrides {
    key = jid(root);
    if key not in _cached_keybinding_overrides_jid {
        existing = [root-->[?:KeybindingOverrides]];
        overrides_node = existing[0] if existing else root ++> KeybindingOverrides();
        _cached_keybinding_overrides_jid[key] = jid(overrides_node);
        return overrides_node;
    }
    return jobj(_cached_keybinding_overrides_jid[key]) as KeybindingOverrides;
}

"""Replaces a command's whole `keybindings` list; there is no per-entry patch."""
def:pub set_keybinding_override(command_id: str, keybindings: list[dict[str, str]]) {
    store = get_keybinding_overrides();
    updated = {**store.overrides};
    updated[command_id] = keybindings;
    store.overrides = updated;
}

def:pub clear_keybinding_override(command_id: str) -> None {
    store = get_keybinding_overrides();
    if command_id not in store.overrides {
        return;
    }
    updated = {**store.overrides};
    del updated[command_id];
    store.overrides = updated;
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
            existing_command.title = title;
            existing_command.keybindings = keybindings;
            return existing_command;
        }
    }
    fresh = Command(command_id=command_id, title=title, keybindings=keybindings);
    reg +>:Contributes():+> fresh;
    return fresh;
}

"""De-dupes by `command_id` on the read path -- keeping the first match is safe since any duplicate
came from the same `BUILTIN_COMMANDS` entry."""
def:pub list_commands -> list[dict[str, any]] {
    with _registry_lock {
        for spec in BUILTIN_COMMANDS {
            register_command(spec["id"], spec["title"], spec["keybindings"]);
        }
        reg = get_command_registry();
        commands = [reg->:Contributes:->[?:Command]];
        overrides = get_keybinding_overrides().overrides;
        seen_ids: set[str] = set();
        deduped = [];
        for c in commands {
            if c.command_id in seen_ids {
                continue;
            }
            seen_ids.add(c.command_id);
            keybindings = overrides[c.command_id] if c.command_id in overrides else c.keybindings;
            deduped.append({"id": c.command_id, "title": c.title, "keybindings": keybindings});
        }
        return deduped;
    }
}
