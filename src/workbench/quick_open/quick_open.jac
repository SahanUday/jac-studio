"""QuickOpen: Phase 3's Quick Open (Ctrl+P fuzzy file switcher, `docs/roadmap.md`) -- the second
`quickaccess` provider alongside `command_palette.jac`, sharing the same shadcn `Command`
primitives and the same "leaf reports, parent owns behavior" shape.

**A delivery-slip item, not new scope.** `vscode-complete-triage.md`'s `quickaccess` row scoped
this into Phase 2 alongside the command palette ("a second provider, same phase, same registry"),
but Phase 2 shipped without it -- see `docs/phases/phase-2-workbench-shell.md`'s "what's left" item
7 and `docs/architecture.md`'s 2026-08-28 live-source-check note. Built now, in Phase 3, as the
carried-forward item it always was.

**Open/close state lives in `workbench.jac`, unlike `command_palette.jac`'s self-contained
`useEffect` keydown listener.** That earlier choice was made because Phase 2's when-clause
keybinding dispatch (`workbench.jac`'s `handle_keydown`/`commands` matching) wasn't built yet at
the time -- it exists now, already proven for the terminal-toggle and theme-toggle commands, so
Quick Open registers `workbench.action.quickOpen` in `command_registry.jac`'s `BUILTIN_COMMANDS`
(keybinding `ctrl+p`) and lets that generic mechanism dispatch through `handle_command` like every
other Phase 3 command, rather than adding a second bespoke keydown listener for a now-solved
problem. A real, not just theoretical, win from this choice: "Go to File..." is invocable from the
command palette itself (`Ctrl+Shift+P` then search) -- something `command_palette.jac`'s own
self-contained shortcut could never offer for itself, since there's no reason to invoke "open the
command palette" from inside the command palette. `handle_command`'s branch for this id just
toggles `quick_open_open`, the same "leaf reports, parent owns state" shape every other
workbench-shell piece already uses.

**Files fetched fresh on every open, not once on mount.** Unlike the command list (static for a
session), the workspace's file set can genuinely change while the app is running --
`useEffect(..., [open])` refetches via `workspace_service.jac`'s `list_all_files` each time the
dialog transitions to open, not on every keystroke (cmdk's own client-side fuzzy filter, the same
mechanism `command_palette.jac` already relies on, handles that).

**Selecting an item resolves the file's display name from the just-fetched `files` list**, since a
`CommandItem`'s `onSelect` callback only reports back the `value` it was given (the path, used for
fuzzy matching) -- `command_palette.jac`'s `handle_select(command_id)` has the identical shape, one
identifier in, a small lookup to get the rest.
"""

import from "react" { useEffect }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem
}
import from src.workbench.workspace.workspace_service { list_all_files }

def:pub app(open: bool, onOpenChange: any, onOpenFile: any) -> JsxElement {
    has files: list[dict[str, str]] = [];

    async def refresh_files -> None;
    def handle_select(path: str) -> None;

    useEffect(lambda {
        if open {
            refresh_files();
        }
    }, [open]);

    <CommandDialog open={open} onOpenChange={onOpenChange}>
        <CommandInput placeholder="Go to file..." />
        <CommandList>
            <CommandEmpty>No matching files.</CommandEmpty>
            <CommandGroup heading="Files">
                {[
                    <CommandItem key={f["path"]} value={f["path"]} onSelect={handle_select}>
                        <span>{f["name"]}</span>
                        <span style={{"marginLeft": "0.5rem", "fontSize": "11px", "color": "#8C8C8C"}}>
                            {f["path"]}
                        </span>
                    </CommandItem>
                    for f in files
                ]}
            </CommandGroup>
        </CommandList>
    </CommandDialog>
}
