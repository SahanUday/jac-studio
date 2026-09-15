"""CommandPalette: shadcn `Command`/`CommandDialog` wired to `command_registry.jac`'s registry.
Fetches command metadata over RPC on mount; dispatch stays in `workbench.jac` via `onRunCommand`.
Open/close state lives in `workbench.jac`, not a local keydown listener, so `title_bar.jac`'s
Command Center button and `Ctrl+Shift+P` both dispatch `workbench.action.showCommands` the same way.
`recent_ids` is in-memory, session-only, capped at 5 -- doesn't survive a restart, by design."""

import from src.workbench.commands.command_registry { list_commands }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem, CommandShortcut
}

"""Prefers the always-on keybinding (`when == ""`) over a context-scoped one, so a shortcut only
live while e.g. the terminal has focus isn't shown as the command's general shortcut."""
def format_keybinding(keybindings: list[dict[str, str]]) -> str {
    if len(keybindings) == 0 {
        return "";
    }
    primary = keybindings[0];
    for kb in keybindings {
        if kb["when"] == "" {
            primary = kb;
            break;
        }
    }
    parts = primary["key"].split("+");
    return "+".join([p.capitalize() for p in parts]);
}

def:pub app(open: bool, onOpenChange: any, onRunCommand: any) -> JsxElement {
    has commands: list[dict[str, any]] = [];
    has recent_ids: list[str] = [];

    async can with entry {
        commands = await list_commands();
    }

    def handle_select(command_id: str) -> None;

    by_id = {c["id"]: c for c in commands};
    recent_commands = [by_id[cid] for cid in recent_ids if cid in by_id];
    other_commands = [c for c in commands if c["id"] not in recent_ids];

    <CommandDialog open={open} onOpenChange={onOpenChange}>
        <CommandInput prefix=">" placeholder="Type a command..." />
        <CommandList>
            <CommandEmpty>No matching commands.</CommandEmpty>
            {(
                <CommandGroup heading="recently used">
                    {[
                        <CommandItem key={c["id"]} value={c["id"]} onSelect={handle_select}>
                            {c["title"]}
                            {(<CommandShortcut>{format_keybinding(c["keybindings"])}</CommandShortcut>) if len(c["keybindings"]) > 0 else None}
                        </CommandItem>
                        for c in recent_commands
                    ]}
                </CommandGroup>
            ) if len(recent_commands) > 0 else None}
            <CommandGroup heading="other commands">
                {[
                    <CommandItem key={c["id"]} value={c["id"]} onSelect={handle_select}>
                        {c["title"]}
                        {(<CommandShortcut>{format_keybinding(c["keybindings"])}</CommandShortcut>) if len(c["keybindings"]) > 0 else None}
                    </CommandItem>
                    for c in other_commands
                ]}
            </CommandGroup>
        </CommandList>
    </CommandDialog>
}
