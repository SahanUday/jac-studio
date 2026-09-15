"""Makes Monaco's built-in Command Palette (F1) open jac-studio's own `CommandPaletteApp`.
Re-registers the built-in's id in `CommandsRegistry` (most recent wins) rather than
`editor.addAction`, which only adds a duplicate entry — see `docs/libraries/monaco.md`.
`CommandsRegistry` isn't public `monaco.*`; reached via `monaco-editor`'s own ESM export map.
Tracker: `2026-09-01-monaco-addaction-cannot-override-builtin-context-menu-item`."""

import from "monaco-editor/platform/commands/common/commands.js" { CommandsRegistry }

glob _registered: bool = False;

def:pub register_command_palette_override(on_open_command_palette: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    CommandsRegistry.registerCommand("editor.action.quickCommand", lambda (accessor: any) {
        on_open_command_palette();
    });
}
