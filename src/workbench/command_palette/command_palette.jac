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

**Global Ctrl/Cmd+Shift+P, no scoping yet.** `docs/roadmap.md` lists the "keybinding when-clause
context system" as its own, later Phase 2 bullet specifically so keybindings for *other* commands
can be scoped (e.g. "only when the editor has focus") -- the palette's own shortcut has always been
global in every real editor (nothing to scope: it should open no matter what has focus), so this
ships with a plain unconditional `keydown` listener rather than waiting on that system.

**Manually-written `useEffect`, not `can with entry`.** The listener registered on mount must be
the exact same function reference `removeEventListener`s on unmount, and Jac's `entry`/`exit`
lower to *separate* `useEffect` closures -- a handle from one is invisible in the other (see
`jac-cl-components`). This acquire-then-release pair is the one case that guide calls out as a
real reason to import `useEffect` directly instead of `can with entry`/`can with exit`.
"""

import from "react" { useEffect }
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

def:pub app(onRunCommand: any) -> JsxElement {
    has open: bool = False;
    has commands: list[dict[str, any]] = [];

    async can with entry {
        commands = await list_commands();
    }

    useEffect(lambda {
        handle_key = lambda (e: any) {
            is_palette_shortcut = (e.key == "P" or e.key == "p") and (e.ctrlKey or e.metaKey) and e.shiftKey;
            if is_palette_shortcut {
                e.preventDefault();
                open = not open;
            }
        };
        document.addEventListener("keydown", handle_key);
        return lambda { document.removeEventListener("keydown", handle_key); };
    }, []);

    def handle_open_change(next_open: bool) -> None;
    def handle_select(command_id: str) -> None;

    <CommandDialog open={open} onOpenChange={handle_open_change}>
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
