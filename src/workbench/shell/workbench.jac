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

**Workspace-state persistence (2026-08-28, `docs/roadmap.md` Phase 3)** -- `groups`/
`active_group_id`/`next_group_id`/`terminal_open`/`cursor_positions` restore from
`session_service.jac`'s `load_session()` on mount (falling back to today's single-empty-group
default when nothing was ever saved) and save back via `_save_session` after every *structural*
mutation (`open_tab`, `select_tab`, `close_tab`, `split_group`, the terminal-toggle branch of
`handle_command`) -- all of which is why those methods are `async` now, not just cosmetic.
`handle_cursor_change` deliberately does **not** call `_save_session` synchronously on every
firing -- it fires on every keystroke (typing moves the cursor), the same per-keystroke frequency
this project already refused to round-trip for the editor's own content
(`docs/architecture.md`'s Monaco-embed "no per-keystroke RPC round-trip" decision). Instead it
debounces through `cursor_save_timer` (a plain `setTimeout`/`clearTimeout` pair stashed in a `Ref`,
the same "value that survives re-renders without triggering one" idiom `monaco_editor.jac` uses
for its own `editor_ref`): each keystroke resets an 800ms timer, so a session save only actually
fires once cursor movement settles, and always reads whatever `cursor_positions` holds at that
later moment rather than a stale snapshot from when the timer was set.

**Restore ordering is load-bearing, not incidental (caught live, `jac browse`, a real restart)**:
inside the `can with entry` restore block, `cursor_positions` is assigned *before* `groups` on
purpose. `groups` becoming non-empty is what causes each tab's `MonacoEditorApp` to mount for the
first time, and `monaco_editor.jac`'s `initialCursor` prop is only ever read once, at that mount
(`handle_mount` never re-fires on a later prop change, matching how it can't re-run for an
already-mounted third-party Monaco instance). Assigning `groups` first previously mounted every
restored tab with a still-empty `cursor_positions`, so each one immediately reported Monaco's
default `(1, 1)` back up through `onCursorChange` -- which didn't just fail to restore the display,
it *overwrote* the just-loaded correct value in state, and the debounce in
`handle_cursor_change` then dutifully persisted that overwritten `(1, 1)` back to the server,
silently destroying the real data on the very next save. Setting `cursor_positions` first ensures
it's already correct by the time `groups`'s update causes anything to mount.

**Diff tabs (2026-08-28, `docs/roadmap.md` Phase 3)** -- `open_diff_tab` is `open_tab`'s sibling:
both insert a tab dict into the active group via the shared `_upsert_tab_in_active_group` helper
(factored out of `open_tab`'s own logic once a second caller needed the identical
"insert-or-activate in the active group, dedupe by `path`" shape), differing only in the tab dict's
own shape -- a diff tab's synthetic `path` (`"diff::" + path_a + "::" + path_b`) is what `close_tab`/
`select_tab` key off unchanged, no special-casing needed there. `path_a`/`path_b` come from
`file_tree.jac`'s Alt+Click "select for compare" gesture (see its own docstring); nothing here
assumes any particular UI trigger, so a future context-menu "Compare with Selected" item can call
the same `open_diff_tab` directly.

**Activity bar (2026-08-28, `docs/roadmap.md` Phase 3)** -- `active_view_id` names which sidebar
view is showing; `ActivityBarApp` reports clicks via `select_view`, same "leaf reports, parent owns
state" shape as everything else here.

**Search, the second real sidebar view (2026-08-31, `docs/roadmap.md` Phase 4)** -- resolves the
tradeoff the paragraph above used to leave open: with a real second view now in hand, switching
away from Search would lose an in-progress query/result set exactly the way switching bottom-panel
tabs would lose terminal scrollback if it weren't for the same convention -- so both `FileTreeApp`
and `SearchApp` now follow the mount-once-hide-via-CSS convention `editor_tabs.jac`'s
`MonacoEditorApp` instances and the bottom panel already use, not the plain conditional *render*
Phase 3 shipped when there was nothing yet to lose. `open_search_result` is `open_tab`'s sibling for
the "jump to a specific line" case a search result (unlike a plain file-tree click) needs: it seeds
`cursor_positions[path]` *before* the tab is inserted into `groups`, reusing the exact
session-restore mechanism ("Restore ordering is load-bearing" above) that already makes a freshly-
mounted `MonacoEditorApp` seek to a given line/column at mount via its `initialCursor` prop --  no
new Monaco-side plumbing needed. **Known, deliberate limitation**: this only actually jumps the
cursor when the tab wasn't already open (a fresh mount is what reads `initialCursor` at all,
per `monaco_editor.jac`'s own docstring) -- clicking a search result for an already-open tab
activates it but doesn't force a re-scroll. Not silently swept under the rug: a real gap, worth a
follow-up (an imperative `revealLine` call against the mounted editor's own ref) once it's
actually felt in practice, not invented speculatively now.

**Source control, the third real sidebar view (2026-08-31, `docs/roadmap.md` Phase 4)** -- `ScmApp`
follows the same mount-once-hide-via-CSS convention `FileTreeApp`/`SearchApp` already use, for the
same reason: switching away from Source Control mid-typed-commit-message shouldn't lose it.
`open_scm_diff` is `open_search_result`'s sibling for "open a view-specific derived tab" rather than
a plain file -- it upserts a `"kind": "gitdiff"` tab (`{"filePath", "staged"}`, no real second path
the way `open_diff_tab`'s compare-two-files tabs have) into the active group; see
`editor_tabs.jac`'s and `scm_diff_editor.jac`'s own docstrings for why a git diff's content is
fetched by the tab itself rather than passed in. `ScmApp` reports staged/unstaged/untracked commits
and errors up through the same `onNotify={add_notification}` prop `terminal.jac` already uses --
one notification mechanism for every Phase 4 feature, not a second one invented for SCM.

**Title bar (2026-08-28, `docs/roadmap.md` Phase 3)** -- `command_palette_open` moved here from
being `command_palette.jac`'s own private state, specifically so `TitleBarApp`'s Command Center
button has something to call: `onOpenCommandPalette` dispatches through `handle_command`'s
`workbench.action.showCommands` branch, the exact same path `Ctrl+Shift+P` now uses too (see
`command_palette.jac`'s docstring for the full reasoning behind that move).

**Tab affordances / unsaved-changes indicator (2026-08-28, `docs/roadmap.md` Phase 3, the phase's
last bullet)** -- `dirty_paths` (a `dict[str, bool]`, keyed by tab path) is fed by
`monaco_editor.jac`'s `onDirtyChange` report and forwarded to `EditorTabsApp` as `dirtyPaths`,
which uses it to swap a tab's close button for an unsaved-changes dot (see `editor_tabs.jac`'s own
docstring for the display logic). Deliberately **not** part of the persisted session -- unlike
`cursor_positions`, dirty state describes in-memory Monaco buffer content that a page reload
already can't recover (this project's Monaco integration never round-trips unsaved keystrokes to
the server, see `monaco_editor.jac`'s "no per-keystroke RPC round-trip" decision), so persisting
just the boolean flag without the actual unsaved content it describes would be misleading rather
than useful. `close_tab` resets a path's entry to `False` when its tab closes (never deletes the
key -- `dict` key deletion has no client-codegen lowering yet, see tracker entry
`2026-08-28-client-dict-del-unsupported-by-jac2js`; overwriting with `False` is functionally
identical for a value this component only ever reads via `.get(path, False)`), so reopening the
same file later starts clean rather than showing a stale dot left over from before the close.

**Toast + notification center (2026-08-31, `docs/roadmap.md` Phase 4's first bullet)** --
`notifications`/`next_notification_id`/`notification_panel_open` are the single source of truth
`notifications.jac`'s docstring describes; `add_notification` is the one call site that both
appends to the persistent history list and pops the ephemeral `sonner` toast, so every future
Phase 4 feature (search, SCM, the task runner, the LSP/DAP clients) that needs to report a
background success/failure gets `onNotify={add_notification}` threaded to it the same way
`FileTreeApp` already receives `onOpenFile`, not a second notification mechanism. Deliberately
**not** persisted across a restart, matching `dirty_paths` above and real VS Code's own behavior
(a fresh session starts with an empty notification history, not yesterday's). The terminal is the
first real producer, wired below: a non-zero process exit code surfaces as an error toast, the
same "background task completion surfaces as a toast" behavior Phase 4's own exit criteria names
for the task runner -- proving the mechanism end-to-end now rather than shipping it with no
caller, unlike the Phase 3 `Diagnostic` node type's deliberate data-model-only landing.

**Output panel + a real bottom-panel tab strip (2026-08-31, `docs/roadmap.md` Phase 4)** --
`terminal_open` (already persisted via `session_service.jac`) is reinterpreted, not renamed, to
mean "is the bottom panel area open" rather than "is the terminal specifically open" -- an old
saved session's `terminal_open=True` still means exactly what it used to (the panel shows,
defaulting to the Terminal tab), so this doesn't touch the persisted schema at all.
`active_bottom_panel` (`"terminal" | "output"`) is new, deliberately **not** persisted -- same call
already made for `dirty_paths` above, an ephemeral UI-focus detail a fresh session doesn't need to
remember. `_toggle_panel` is the one place both `workbench.action.terminal.toggle` and the new
`workbench.action.output.toggle` route through: re-selecting the already-active tab closes the
panel, selecting the other tab (or opening from closed) switches to it and opens -- avoids writing
the same open/close/switch logic twice for what was, until this bullet, a single hardcoded panel.
`OutputApp` mounts unconditionally alongside `TerminalApp`, same "mount once, hide via CSS"
convention (never conditionally rendered, so `terminal.jac`'s own scrollback-preserving mount-once
concern isn't reintroduced for the new tab) -- its `active` prop (only true while it's both the
selected tab *and* the panel is open) is what lets it poll for new content without a background
timer running for a panel nobody's looking at, see its own docstring.

**`position: relative; zIndex: 20` on the panel container is load-bearing, found live, not
decorative** -- `components/ui/sidebar.jac`'s vendored desktop wrapper is `position: fixed;
inset-y-0; height: 100svh; z-index: 10` (matches VS Code's own always-full-height sidebar, but
means it paints, and intercepts *clicks*, above any later-DOM sibling within its horizontal width
that has no stacking context of its own -- confirmed live via `jac browse`, both visually (the tab
labels were fully invisible, painted under the sidebar) and functionally (a synthetic click on the
Terminal tab's real coordinates landed on the sidebar's scroll-area viewport instead). This
predates this bullet -- the single old "Terminal" label had the identical bug, just never a second
real interactive element in that column to make a user-visible click failure obvious. Giving this
container its own positioned stacking context above `z-index: 10` fixes it without touching the
vendored `Sidebar` primitive (which `jac install --shadcn sidebar` would silently regenerate over
any hand-patch anyway, the same regeneration pitfall Phase 3's icon-set migration already hit). See
tracker entry `2026-08-31-fixed-sidebar-overlaps-and-intercepts-clicks-on-bottom-panel`.
"""

import from "react" { useEffect }
import from "sonner" { Toaster, toast }
import from src.workbench.file_tree.file_tree { app as FileTreeApp }
import from src.workbench.search.search { app as SearchApp }
import from src.workbench.scm.scm { app as ScmApp }
import from src.workbench.editor_tabs.editor_tabs { app as EditorTabsApp }
import from src.workbench.activity_bar.activity_bar { app as ActivityBarApp }
import from src.workbench.command_palette.command_palette { app as CommandPaletteApp }
import from src.workbench.quick_open.quick_open { app as QuickOpenApp }
import from src.workbench.title_bar.title_bar { app as TitleBarApp }
import from src.workbench.status_bar.status_bar { app as StatusBarApp }
import from src.workbench.terminal.terminal { app as TerminalApp }
import from src.workbench.output.output { app as OutputApp }
import from src.workbench.commands.command_registry { list_commands }
import from src.workbench.session.session_service { load_session, save_session }
import from components.ui.resizable { ResizablePanelGroup, ResizablePanel, ResizableHandle }

def:pub app(onToggleTheme: any) -> JsxElement {
    has groups: list[dict[str, any]] = [{"id": "group-1", "tabs": [], "activePath": ""}];
    has active_group_id: str = "group-1";
    has next_group_id: int = 2;
    has cursor_positions: dict[str, dict[str, int]] = {};
    has dirty_paths: dict[str, bool] = {};
    has terminal_open: bool = False;
    has active_bottom_panel: str = "terminal";
    has quick_open_open: bool = False;
    has command_palette_open: bool = False;
    has active_view_id: str = "explorer";
    has commands: list[dict[str, any]] = [];
    has context: dict[str, bool] = {};
    has cursor_save_timer: Ref[any] = Ref();
    has notifications: list[dict[str, any]] = [];
    has next_notification_id: int = 1;
    has notification_panel_open: bool = False;

    async def _save_session -> None;
    async def _toggle_panel(panel_id: str) -> None;
    def _upsert_tab_in_active_group(tab: dict[str, any]) -> list[dict[str, any]];
    async def open_tab(path: str, name: str) -> None;
    async def open_search_result(path: str, name: str, line: int, column: int) -> None;
    async def open_diff_tab(path_a: str, name_a: str, path_b: str, name_b: str) -> None;
    async def open_scm_diff(path: str, name: str, staged: bool) -> None;
    async def select_tab(group_id: str, path: str) -> None;
    async def close_tab(group_id: str, path: str) -> None;
    async def split_group(group_id: str) -> None;
    async def handle_command(command_id: str) -> None;
    def handle_cursor_change(path: str, line: int, column: int) -> None;
    def handle_dirty_change(path: str, is_dirty: bool) -> None;
    def set_context(key: str, value: bool) -> None;
    def context_matches(when: str) -> bool;
    def handle_keydown(e: any) -> None;
    def set_quick_open_open(next_open: bool) -> None;
    def set_command_palette_open(next_open: bool) -> None;
    def select_view(view_id: str) -> None;
    def add_notification(message: str, severity: str, source: str) -> None;
    def dismiss_notification(notification_id: int) -> None;
    def clear_notifications -> None;
    def set_notification_panel_open(next_open: bool) -> None;

    async can with entry {
        commands = await list_commands();
        session = await load_session();
        if len(session["groups"]) > 0 {
            # cursor_positions must land before groups: groups is what causes each tab's
            # MonacoEditorApp to mount for the first time, and its initialCursor prop is only
            # ever read once, at that mount -- if cursor_positions hadn't been assigned yet, the
            # editor would mount with a stale default and then report it right back up,
            # corrupting the just-restored value (found live, see this file's own docstring)
            cursor_positions = session["cursorPositions"];
            active_group_id = session["activeGroupId"];
            next_group_id = session["nextGroupId"];
            terminal_open = session["terminalOpen"];
            groups = session["groups"];
        }
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
                    initialCursors={cursor_positions}
                    dirtyPaths={dirty_paths}
                    onDirtyChange={handle_dirty_change}
                />
            </ResizablePanel>
        );
        if idx < panel_count - 1 {
            panel_children.append(<ResizableHandle key={g["id"] + "-handle"} />);
        }
    }

    <div style={{"display": "flex", "flexDirection": "column", "height": "100vh"}}>
        <Toaster theme="dark" position="bottom-right" />
        <CommandPaletteApp open={command_palette_open} onOpenChange={set_command_palette_open} onRunCommand={handle_command} />
        <QuickOpenApp open={quick_open_open} onOpenChange={set_quick_open_open} onOpenFile={open_tab} />
        <TitleBarApp onOpenCommandPalette={lambda (e: any) { handle_command("workbench.action.showCommands"); }} />
        <div style={{"display": "flex", "flex": "1", "overflow": "hidden"}}>
            <ActivityBarApp activeViewId={active_view_id} onSelectView={select_view} />
            <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #2A2B2C", "overflow": "hidden", "position": "relative"}}>
                <div style={{"display": "block" if active_view_id == "explorer" else "none", "height": "100%"}}>
                    <FileTreeApp onOpenFile={open_tab} onCompareFiles={open_diff_tab} />
                </div>
                <div style={{"display": "block" if active_view_id == "search" else "none", "height": "100%"}}>
                    <SearchApp onOpenResult={open_search_result} />
                </div>
                <div style={{"display": "block" if active_view_id == "scm" else "none", "height": "100%"}}>
                    <ScmApp active={active_view_id == "scm"} onOpenDiff={open_scm_diff} onNotify={add_notification} />
                </div>
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
            "borderTop": "1px solid #2A2B2C",
            "background": "#191A1B",
            "position": "relative",
            "zIndex": "20"
        }}>
            <div role="tablist" aria-label="Panel" style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between", "padding": "0 0.5rem", "borderBottom": "1px solid #2A2B2C", "fontSize": "12px", "fontFamily": "system-ui, sans-serif", "flexShrink": "0"}}>
                <div style={{"display": "flex", "gap": "1rem"}}>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "terminal"}
                        onClick={lambda (e: any) { _toggle_panel("terminal"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "terminal" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "terminal" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Terminal
                    </button>
                    <button
                        role="tab"
                        aria-selected={active_bottom_panel == "output"}
                        onClick={lambda (e: any) { _toggle_panel("output"); }}
                        style={{
                            "background": "transparent",
                            "border": "none",
                            "borderBottom": "1px solid " + ("#bfbfbf" if active_bottom_panel == "output" else "transparent"),
                            "color": "#CCCCCC" if active_bottom_panel == "output" else "#8C8C8C",
                            "padding": "0.4rem 0",
                            "cursor": "pointer"
                        }}
                    >
                        Output
                    </button>
                </div>
                <span
                    aria-label="Close Panel"
                    onClick={lambda (e: any) { handle_command("workbench.action.terminal.toggle"); }}
                    className="codicon codicon-close"
                    style={{"cursor": "pointer", "opacity": "0.7", "fontSize": "14px", "lineHeight": "1", "color": "#8C8C8C"}}
                />
            </div>
            <div style={{"flex": "1", "overflow": "hidden", "position": "relative"}}>
                <div style={{"display": "block" if active_bottom_panel == "terminal" else "none", "height": "100%"}}>
                    <TerminalApp
                        onFocusChange={lambda (focused: bool) { set_context("terminalFocus", focused); }}
                        onNotify={add_notification}
                    />
                </div>
                <div style={{"display": "block" if active_bottom_panel == "output" else "none", "height": "100%"}}>
                    <OutputApp active={terminal_open and active_bottom_panel == "output"} />
                </div>
            </div>
        </div>
        <StatusBarApp
            line={active_cursor["line"]}
            column={active_cursor["column"]}
            path={active_tab_path}
            notifications={notifications}
            notificationPanelOpen={notification_panel_open}
            onNotificationPanelChange={set_notification_panel_open}
            onDismissNotification={dismiss_notification}
            onClearNotifications={clear_notifications}
        />
    </div>
}
