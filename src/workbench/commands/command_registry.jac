"""CommandRegistry: the graph as the contribution registry, per `docs/architecture.md`'s
"Extension nodes ... Contribute Command/View/Menu nodes (the graph *is* the contribution
registry)" -- this is Phase 2's first real consumer of that pattern, promoted (same structural
shape) from the Phase 0 validation in `internal/service-registry-spike/src/command_registry.jac`.

**Metadata lives here; execution doesn't.** A `Command` node holds `command_id`/`title` --
genuinely persistent, query-reachable, multi-consumer state (what the palette lists, what a
future extension could contribute into). *Running* a command is a different question: every
command Phase 2 actually has (split the active editor group, close the active tab) is a
client-side workbench UI-state mutation, not something with a server-side effect to invoke -- so
unlike the spike's speculative `_handlers`/`run_command`, this version has no handler table at
all. `src/workbench/command_palette/command_palette.jac` fetches `list_commands()` over RPC for
display and dispatches execution through `workbench.jac`'s own `handle_command`, entirely
client-side. Add a server-side `run_command` here only once a real command needs one.

**Seeded lazily, not from a startup hook.** There's no dynamic extension-loading system yet
(Phase 2 has no `Extension` nodes contributing at runtime), so the fixed Phase 2 command set is
seeded the first time `list_commands` is called in a given `root`'s lifetime -- `register_command`
already de-dupes by id, so reseeding on every call is cheap and idempotent, and needs no explicit
app-boot wiring.
"""

node CommandRegistry {}

node Command {
    has command_id: str;
    has title: str;
}

edge Contributes {}

glob BUILTIN_COMMANDS: list[tuple[str, str]] = [
    ("workbench.action.splitEditorRight", "View: Split Editor Right"),
    ("workbench.action.closeActiveEditor", "View: Close Editor")
];

glob _cached_command_registries: dict[str, CommandRegistry] = {};

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

def register_command(command_id: str, title: str) -> Command {
    reg = get_command_registry();
    matches = [reg->:Contributes:->[?:Command]];
    for existing_command in matches {
        if existing_command.command_id == command_id {
            return existing_command;
        }
    }
    fresh = Command(command_id=command_id, title=title);
    reg +>:Contributes():+> fresh;
    return fresh;
}

def:pub list_commands -> list[dict[str, str]] {
    for (command_id, title) in BUILTIN_COMMANDS {
        register_command(command_id, title);
    }
    reg = get_command_registry();
    commands = [reg->:Contributes:->[?:Command]];
    return [{"id": c.command_id, "title": c.title} for c in commands];
}
