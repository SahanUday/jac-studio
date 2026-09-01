"""register_command_palette_override: makes Monaco's own built-in "Command Palette" (F1,
`editor.action.quickCommand`) open jac-studio's real workbench `CommandPaletteApp` instead of
Monaco's internal, editor-scoped one -- fixing a duplicate-menu-entry bug found live (2026-09-01)
in the first attempt at this unification (`monaco_editor.impl.jac`'s `editor.addAction({"id":
"editor.action.quickCommand", ...})`).

**Why `editor.addAction` with the built-in's own id does not replace it -- confirmed by reading
the bundled source, not assumed.** Monaco's F1 action (`GotoLineAction`, `monaco-editor/esm/vs/
editor/standalone/browser/quickAccess/standaloneCommandsQuickAccess.js`) is registered once,
globally, at module-import time via `registerEditorAction`, which stores it in a completely
separate registry (`EditorContributionRegistry`) from the per-editor-instance `addAction` dictionary
(`this._actions`, `standaloneCodeEditor.js`). `editor.addAction` never touches that static
registration: reading its own implementation shows it generates a *new*, unique command id
(`editor.getId() + ':' + id`) and appends a *second*, independent context-menu item via
`MenuRegistry.appendMenuItem` -- the built-in item is never removed, so both show up side by side,
both labeled "Command Palette", both bound to F1 (only their `run` behavior differs).

**The fix: re-register the built-in's own command id in `CommandsRegistry`, not add a competing
action.** Both the F1 keybinding and the static context-menu item's click resolve their behavior
the same way -- through `commandService.executeCommand('editor.action.quickCommand')`, which looks
up `CommandsRegistry.getCommand(id)`. `CommandsRegistry.registerCommand` stores each id's handlers
in a list and `unshift`s new registrations to the front (`commands.js`), and `getCommand` returns
the front of that list -- i.e. **the most recently registered handler for an id wins**, the same
override mechanism VS Code itself uses. Calling `registerCommand` again for the same id after
Monaco's own registration has already run (it runs at import time, before this ever mounts)
replaces which handler answers that id, for every caller, without adding or removing a single menu
item -- Monaco's one original "Command Palette" entry stays exactly where it was, now just running
this app's handler instead of Monaco's internal quick-access.

**`CommandsRegistry` isn't part of the public `monaco.*` namespace** (`@monaco-editor/react` only
hands components the documented `monaco`/`editor` objects) **but is a real, stable ESM export the
installed `monaco-editor` package's own `exports` map allows reaching directly** --
`"./*.js": "./esm/vs/*.js"` in `monaco-editor/package.json` -- confirmed by reading that file, not
guessed. This is a deliberate, narrow reach into Monaco's private platform layer where no public API
covers the need, the same "read the bundled source directly, verify empirically" discipline
`jac_rename_provider.jac`'s own docstring already documents for a different Monaco internals
question. See tracker entry `2026-09-01-monaco-addaction-cannot-override-builtin-context-menu-item`
for the full investigation."""

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
