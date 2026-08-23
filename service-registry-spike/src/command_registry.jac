"""CommandRegistry: contributed command *metadata* lives on the graph (so a command palette
can list it); the *handler* a command id dispatches to is an in-memory table, not a graph field.

This split is itself a spike finding, not an oversight: a handler is a callable, and callables
are not the kind of thing this pattern's "persistent, query-reachable state" is for (see
docs/architecture.md's own hedge -- "reserving the graph pattern for things that are genuinely
persistent"). What's genuinely persistent here is *which commands exist and their titles* (real
UI-facing state, e.g. the command palette's listing); *how* a command id maps to code to run is a
build-time, in-process concern, so it stays a plain module-level table, same as VS Code's own
`CommandsRegistry` keeps its `ICommandHandler` map in memory rather than serializing it.
"""

node CommandRegistry {}

node Command {
    has command_id: str;
    has title: str;
}

edge Contributes {}

glob _handlers: dict[str, any] = {};
glob _cached_command_registry: CommandRegistry | None = None;

def:pub get_command_registry -> CommandRegistry {
    if _cached_command_registry is not None {
        return _cached_command_registry;
    }
    existing = [root-->[?:CommandRegistry]];
    reg = existing[0] if existing else root ++> CommandRegistry();
    _cached_command_registry = reg;
    return reg;
}

def:pub _reset_command_registry_cache_for_tests {
    _cached_command_registry = None;
    _handlers.clear();
}

def:pub register_command(cmd_id: str, title: str, handler: any) -> Command {
    reg = get_command_registry();
    matches = [reg->:Contributes:->[?:Command]];
    for existing_command in matches {
        if existing_command.command_id == cmd_id {
            _handlers[cmd_id] = handler;
            return existing_command;
        }
    }
    fresh = Command(command_id=cmd_id, title=title);
    reg +>:Contributes():+> fresh;
    _handlers[cmd_id] = handler;
    return fresh;
}

def:pub list_commands -> list[Command] {
    reg = get_command_registry();
    return [reg->:Contributes:->[?:Command]];
}

def:pub run_command(cmd_id: str) -> any {
    if cmd_id not in _handlers {
        raise ValueError(f"no handler registered for command '{cmd_id}'");
    }
    handler = _handlers[cmd_id];
    return handler();
}
