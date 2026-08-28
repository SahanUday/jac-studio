"""CommandPalette: Phase 2's third workbench-shell deliverable (`docs/roadmap.md`) after Tabs and
editor-group splitting -- shadcn's `Command`/`CommandDialog` wired to
`src/workbench/commands/command_registry.jac`'s server-side registry.

**Metadata over RPC, dispatch through the parent.** This component fetches the command list
(`id`/`title`) from the server once on mount and renders it -- but it doesn't know how to run a
command; that logic lives in `workbench.jac`, which already owns the editor-group state every
Phase 2 command actually mutates. Selecting an item just calls the `onRunCommand` prop with the
picked command's id, same "leaf reports, parent owns behavior" shape `editor_tabs.jac` uses for
its own callbacks -- see `command_registry.jac`'s docstring for why there's no server-side handler
table to call into instead.

**Open/close state moved to `workbench.jac` (2026-08-28, Phase 3's title-bar bullet), reversing
this component's original self-contained `useEffect` keydown listener.** That earlier choice
(global `Ctrl/Cmd+Shift+P`, handled with a plain unconditional `keydown` listener inside this
component) was made because Phase 2's when-clause keybinding dispatch
(`workbench.jac`'s `handle_keydown`/`commands` matching) wasn't built yet -- `quick_open.jac`
already made the same move once that mechanism existed and was proven (terminal-toggle,
theme-toggle, quick-open). The concrete trigger for finally reversing it here too: `title_bar.jac`'s
Command Center button needs to open this same dialog, and there was no way for anything outside
this component to do that with `open` as private internal state. `workbench.action.showCommands`
is now a real `command_registry.jac` entry (`ctrl+shift+p`), dispatched through `handle_command`
like every other Phase 3 command -- the title bar's button and the keyboard shortcut both flow
through the identical path, rather than the title bar needing its own separate wiring.
"""

import from src.workbench.commands.command_registry { list_commands }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem, CommandShortcut
}

"""Picks the keybinding to show next to a palette entry: the always-on one (`when == ""`) if the
command has one, else the first scoped one -- showing a context-scoped shortcut (e.g. `escape`,
only live while the terminal has focus) as if it were the command's general shortcut would be
misleading. Formats a raw combo string (`"ctrl+`"`) for display (`"Ctrl+`"`) without a
platform-specific glyph layer (`⌘`/`⌃`/`⇧`) -- nothing here needs that polish yet."""
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

    async can with entry {
        commands = await list_commands();
    }

    def handle_select(command_id: str) -> None;

    <CommandDialog open={open} onOpenChange={onOpenChange}>
        <CommandInput placeholder="Type a command..." />
        <CommandList>
            <CommandEmpty>No matching commands.</CommandEmpty>
            <CommandGroup heading="Commands">
                {[
                    <CommandItem key={c["id"]} value={c["id"]} onSelect={handle_select}>
                        {c["title"]}
                        {(<CommandShortcut>{format_keybinding(c["keybindings"])}</CommandShortcut>) if len(c["keybindings"]) > 0 else None}
                    </CommandItem>
                    for c in commands
                ]}
            </CommandGroup>
        </CommandList>
    </CommandDialog>
}
