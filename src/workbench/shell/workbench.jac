"""Workbench: the shared parent for Phase 2's workbench-shell pieces
(`docs/roadmap.md`) -- owns the "which files are open, which is active" state that
`file_tree.jac` (reports selections) and `editor_tabs.jac` (renders tabs + content) both need,
lifted here because they're siblings with no other way to share it (see `editor_tabs.jac`'s
docstring for why this is plain lifted React-style state, not a Phase 3 graph node).

`main.jac` mounts this in place of composing `FileTreeApp`/`TextEditorApp` directly, as it did
before Tabs existed.

**Editor groups (2026-08-25, `docs/roadmap.md` Phase 2)** -- side-by-side, resizable editor
panes, VS Code's "split editor" feature. `open_tabs`/`active_path` became `groups`, a list of
`{"id", "tabs", "activePath"}` dicts, plus `active_group_id` naming which one newly-opened files
land in. `EditorTabsApp` itself didn't need to know it's one of several -- it already took its
tab list/active path as props, so it now also takes a plain `groupId` prop and forwards it on
every callback instead of the parent baking group identity into a per-iteration closure (see
`editor_tabs.jac`'s docstring for why that shape was chosen over closures-in-a-loop). Groups are
laid out with shadcn's `Resizable` primitive -- `ResizablePanelGroup` + one `ResizablePanel` per
group + a `ResizableHandle` between each pair, so panes are drag-resizable like every other
multi-pane split in a real editor.

**Command palette (2026-08-25, `docs/roadmap.md` Phase 2)** -- `CommandPaletteApp` mounts here
because it needs to invoke the same group-mutating abilities (`split_group`, `close_tab`) that
`EditorTabsApp`'s buttons already call directly; `handle_command` is the one place that maps a
command id from the palette onto one of them, so adding a new palette-reachable command later is a
one-line dispatch addition here, not a new prop threaded through every layer.

**Status bar (2026-08-25, `docs/roadmap.md` Phase 2)** -- `cursor_positions` is keyed by tab path,
not a single global `(line, column)`, so switching to an already-open tab (no remount, so no fresh
`onDidChangeCursorPosition` fires) still shows that tab's own last-known position instead of a
stale reading left over from whichever tab was active before. The status bar itself always reflects
`active_group_id`'s active tab -- `docs/roadmap.md` scopes this bullet to cursor position only, so
there's no per-group status bar yet.

**Integrated terminal (2026-08-25, `docs/roadmap.md` Phase 2)** -- `TerminalApp` mounts here,
always, hidden via CSS rather than conditionally rendered when `terminal_open` is false, same
"mount once, hide via CSS" convention `editor_tabs.jac` uses for `MonacoEditorApp` and for the same
reason: a conditionally-*rendered* terminal would remount (and lose its scrollback) every time it's
reopened. Its header chrome (title, close button) lives here rather than inside `terminal.jac`
itself, matching `editor_tabs.jac`'s own tab-bar-owns-the-chrome shape -- `terminal.jac` is just the
xterm.js mount surface, same role `MonacoEditorApp` plays for a single editor pane. The close button
dispatches through `handle_command` with the same id the command palette uses to open it, so there's
exactly one toggle implementation, not two.

**Keybinding "when clause" context system (2026-08-25, `docs/roadmap.md` Phase 2)** -- `commands`
(fetched the same way `command_palette.jac` fetches its own copy, via `list_commands()`) carries
each command's `keybindings`; `context` is a flat `dict[str, bool]` of named UI-state flags
(currently just `terminalFocus`, set by `terminal.jac`'s `onFocusChange`) that a `when` clause
checks against. `handle_keydown` is registered on `document` in the **capture** phase, not bubble
-- a capture-phase listener on `document` always runs before the event reaches its target (here,
xterm's own hidden textarea) and before anything downstream can call `stopPropagation`, so this
keeps working regardless of what any embedded library's own keydown handling does. This is a
manually-written `useEffect` rather than `can with entry`/`can with exit`, same reason as
`command_palette.jac`'s own keydown listener: `entry`/`exit` lower to separate closures, so a
handle acquired in one is invisible to the other's cleanup.

The motivating case this solves, concretely: `workbench.action.terminal.toggle`'s `escape`
keybinding is scoped to `when: "terminalFocus"` specifically because, without that guard, pressing
Escape *anywhere* in the app (typing in the editor, browsing the file tree) would unexpectedly
toggle the terminal open or closed -- a real bug this context-evaluation layer exists to prevent,
not a contrived example. (It can only ever *close* the terminal, never reopen it, despite
dispatching through the same toggle command as the always-on `ctrl+\`` binding: a `display: none`
element and its descendants can never hold DOM focus, so `terminalFocus` can only be true while the
panel is already open.)

**Settings persistence (2026-08-28, `docs/roadmap.md` Phase 3)** -- `workbench.action.toggleColorTheme`
is the first command whose effect lives outside this component's own state: the *value* being
toggled (`workbench.colorTheme`) is persisted by `src/workbench/settings/settings_service.jac`, and
the class it drives (`.dark`/`.light`) is applied at `main.jac`'s true root, above `WorkbenchApp`
entirely -- so `handle_command` can't just flip a local `has` field the way `terminal_open` does.
`onToggleTheme` is a plain prop callback `main.jac` hands down, same "leaf reports, parent owns
state" shape used everywhere else in this file, just one level further up the tree than usual since
the state in question (what wraps the *whole* app in a `.dark`/`.light` class) genuinely belongs
above this component, not inside it.
"""

import from "react" { useEffect }
import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }
import from src.workbench.command_palette.command_palette { app as CommandPaletteApp }
import from src.workbench.status_bar.status_bar { app as StatusBarApp }
import from src.workbench.terminal.terminal { app as TerminalApp }
import from src.workbench.commands.command_registry { list_commands }
import from components.ui.resizable { ResizablePanelGroup, ResizablePanel, ResizableHandle }

def:pub app(onToggleTheme: any) -> JsxElement {
    has groups: list[dict[str, any]] = [{"id": "group-1", "tabs": [], "activePath": ""}];
    has active_group_id: str = "group-1";
    has next_group_id: int = 2;
    has cursor_positions: dict[str, dict[str, int]] = {};
    has terminal_open: bool = False;
    has commands: list[dict[str, any]] = [];
    has context: dict[str, bool] = {};

    def open_tab(path: str, name: str) -> None;
    def select_tab(group_id: str, path: str) -> None;
    def close_tab(group_id: str, path: str) -> None;
    def split_group(group_id: str) -> None;
    def handle_command(command_id: str) -> None;
    def handle_cursor_change(path: str, line: int, column: int) -> None;
    def set_context(key: str, value: bool) -> None;
    def context_matches(when: str) -> bool;
    def handle_keydown(e: any) -> None;

    async can with entry {
        commands = await list_commands();
    }

    useEffect(lambda {
        listener = lambda (e: any) { handle_keydown(e); };
        document.addEventListener("keydown", listener, True);
        return lambda { document.removeEventListener("keydown", listener, True); };
    }, []);

    active_group_list = [g for g in groups if g["id"] == active_group_id];
    active_tab_path = active_group_list[0]["activePath"] if len(active_group_list) > 0 else "";
    active_cursor = cursor_positions[active_tab_path] if active_tab_path in cursor_positions else {"line": 1, "column": 1};

    panel_count = len(groups);
    panel_children = [];
    for idx in range(panel_count) {
        g = groups[idx];
        panel_children.append(
            <ResizablePanel key={g["id"]} defaultSize={100 / panel_count} minSize={15}>
                <EditorTabsApp
                    groupId={g["id"]}
                    openTabs={g["tabs"]}
                    activePath={g["activePath"]}
                    onSelectTab={select_tab}
                    onCloseTab={close_tab}
                    onSplitGroup={split_group}
                    onCursorChange={handle_cursor_change}
                />
            </ResizablePanel>
        );
        if idx < panel_count - 1 {
            panel_children.append(<ResizableHandle key={g["id"] + "-handle"} />);
        }
    }

    <div style={{"display": "flex", "flexDirection": "column", "height": "100vh"}}>
        <CommandPaletteApp onRunCommand={handle_command} />
        <div style={{"display": "flex", "flex": "1", "overflow": "hidden"}}>
            <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #3c3c3c", "overflow": "hidden"}}>
                <FileTreeApp onOpenFile={open_tab} />
            </div>
            <div style={{"flex": "1", "overflow": "hidden"}}>
                <ResizablePanelGroup direction="horizontal">
                    {panel_children}
                </ResizablePanelGroup>
            </div>
        </div>
        <div style={{
            "display": "flex" if terminal_open else "none",
            "flexDirection": "column",
            "height": "220px",
            "flexShrink": "0",
            "borderTop": "1px solid #3c3c3c",
            "background": "#1e1e1e"
        }}>
            <div style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between", "padding": "0.25rem 0.5rem", "borderBottom": "1px solid #3c3c3c", "fontSize": "12px", "color": "#969696", "fontFamily": "system-ui, sans-serif", "flexShrink": "0"}}>
                <span>Terminal</span>
                <span
                    onClick={lambda (e: any) { handle_command("workbench.action.terminal.toggle"); }}
                    style={{"cursor": "pointer", "opacity": "0.7", "fontSize": "14px", "lineHeight": "1"}}
                >
                    &times;
                </span>
            </div>
            <div style={{"flex": "1", "overflow": "hidden"}}>
                <TerminalApp onFocusChange={lambda (focused: bool) { set_context("terminalFocus", focused); }} />
            </div>
        </div>
        <StatusBarApp line={active_cursor["line"]} column={active_cursor["column"]} path={active_tab_path} />
    </div>
}
