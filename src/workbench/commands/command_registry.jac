"""CommandRegistry: the graph as the contribution registry, per `docs/architecture.md`'s
"Extension nodes ... Contribute Command/View/Menu nodes (the graph *is* the contribution
registry)" -- this is Phase 2's first real consumer of that pattern, promoted (same structural
shape) from the Phase 0 validation in `internal/service-registry-spike/src/command_registry.jac`.

**Metadata lives here; execution doesn't.** A `Command` node holds `command_id`/`title` --
genuinely persistent, query-reachable, multi-consumer state (what the palette lists, what a
future extension could contribute into). *Running* a command is a different question: every
command Phase 2 actually has (split the active editor group, close the active tab, toggle the
terminal) is a client-side workbench UI-state mutation, not something with a server-side effect to
invoke -- so unlike the spike's speculative `_handlers`/`run_command`, this version has no handler
table at all. `src/workbench/command_palette/command_palette.jac` fetches `list_commands()` over
RPC for display and dispatches execution through `workbench.jac`'s own `handle_command`, entirely
client-side. Add a server-side `run_command` here only once a real command needs one.

**Seeded lazily, not from a startup hook.** There's no dynamic extension-loading system yet
(Phase 2 has no `Extension` nodes contributing at runtime), so the fixed Phase 2 command set is
seeded the first time `list_commands` is called in a given `root`'s lifetime -- `register_command`
already de-dupes by id, so reseeding on every call is cheap and idempotent, and needs no explicit
app-boot wiring.

**Keybindings (2026-08-25, `docs/roadmap.md` Phase 2's "when clause" bullet)** -- each `Command`
carries zero or more `{"key", "when"}` pairs, a list rather than one scalar pair because a single
command legitimately wants more than one binding (`workbench.action.terminal.toggle` below has
both an always-on shortcut and one scoped to a specific context). This module still only holds
*metadata*, matching the split above: `workbench.jac` is what actually matches a keydown's combo
string against these, evaluates `when`, and dispatches -- see its docstring for the
context-evaluation layer itself. `when` is a single optionally-`!`-negated context-key name
(`"terminalFocus"`, `"!terminalFocus"`), not a full boolean-expression grammar like upstream's
`src/vs/platform/contextkey` (`&&`/`||` per `vscode-feature-gap-analysis.md`) -- nothing here
needs a compound condition yet, and a single-flag check is a two-line addition to extend into `&&`
later if something ever does.
"""

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
    }
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

"""De-dupes by `command_id` but still syncs `title`/`keybindings` onto an already-persisted node
every call, not just on first creation -- the workspace graph outlives a single dev-server process
(persisted, not in-memory-only), so a `Command` node created under an older build of
`BUILTIN_COMMANDS` would otherwise keep serving whatever metadata it had at creation time forever,
silently ignoring later changes to that command's declared title or keybindings. Caught live: a
`Command` node for `workbench.action.terminal.toggle` created before this file had a `keybindings`
field kept returning `[]` after the field was added, until this fix."""
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

def:pub list_commands -> list[dict[str, any]] {
    for spec in BUILTIN_COMMANDS {
        register_command(spec["id"], spec["title"], spec["keybindings"]);
    }
    reg = get_command_registry();
    commands = [reg->:Contributes:->[?:Command]];
    return [{"id": c.command_id, "title": c.title, "keybindings": c.keybindings} for c in commands];
}
