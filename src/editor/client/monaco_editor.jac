"""MonacoEditorApp: wraps the real `@monaco-editor/react` npm package -- the editor engine for
v1, decided 2026-08-25 (see `docs/architecture.md`'s Editor Core section and tracker entry
`2026-08-25-editor-core-decision-reversed-to-monaco`). `@monaco-editor/react`'s `<Editor>`
component handles Monaco's own imperative mounting/disposal lifecycle declaratively, so this file
is a thin JSX + load/save integration layer, not a raw DOM-ref component -- `open_document`/
`save_document` (`document_service.jac`) are the only server round-trips, since Monaco owns the
live edit/undo/cursor state entirely client-side in between.

**`defaultValue`, not `value`.** A controlled `value` would fight Monaco for ownership of the text
on every keystroke -- exactly the per-keystroke server round-trip this switch was meant to remove.
Content is set once at mount from the loaded file; Monaco owns it entirely after that.

**Ctrl+S reads `editor.getValue()` on demand, not a `has`-tracked mirror of every keystroke** --
registered once in `onMount` via the live `editor` instance stashed in a `Ref` (the documented Jac
idiom for a value that survives re-renders without triggering one -- see `jac guide
jac-npm-packages`'s "Refs: `Ref[T]` fields" section), not `onChange`-into-`has`-state, which would
reintroduce a per-keystroke React update for no benefit.

**One instance per open tab**, same as the archived `text_editor.jac` -- `editor_tabs.jac` mounts
one per open file and toggles visibility via CSS, not conditional rendering, so switching tabs
never remounts or loses Monaco's own undo history for that file.

Handler bodies live in the paired `monaco_editor.impl.jac` annex, per the client-component
"handler annex" pattern -- see `jac-studio-code-organization`.

**Cursor position (2026-08-25, `docs/roadmap.md` Phase 2)** -- `onCursorChange` reports
`(path, line, column)` up to whichever parent wants it (`workbench.jac`, for the status bar),
same "leaf reports, parent owns state" shape as `editor_tabs.jac`'s callbacks. Registered via
`editor.onDidChangeCursorPosition` in `handle_mount` alongside the Ctrl+S command, and fired once
more right after mount so the status bar has a value for a freshly-opened tab before the user
moves the cursor at all, rather than depending on Monaco's own mount-time firing behavior.

**`initialCursor` (2026-08-28, `docs/roadmap.md` Phase 3 workspace-state persistence)** -- a
restored `{"line", "column"}` from `session_service.jac`'s persisted session, or `None` for an
ordinarily-opened tab. Applied via `editor.setPosition`/`revealPositionInCenter` in `handle_mount`
*before* the mount-time `onCursorChange` report below, so a restored tab reports (and visibly
scrolls to) where the user actually left off, instead of every restored tab silently reporting
Monaco's own default `(1, 1)` and clobbering the just-restored value in `workbench.jac`'s
`cursor_positions` the moment it mounts -- caught live (`jac browse`, a real restart): the session
round-tripped the correct persisted position through `load_session` correctly, but the status bar
still showed "Ln 1, Col 1" until this fix, because nothing told Monaco itself to seek there.

**`keepCurrentModel` (2026-08-25, caught live: splitting the editor then closing one copy of the
file left the *other* copy blank)** -- `@monaco-editor/react`'s `path` prop shares one underlying
Monaco text model across every `<Editor>` instance mounted with the same path
(`monaco.editor.getModel(uri) || createModel(...)`, read from the package's own source) -- exactly
what makes editor-group splitting work at all, since both groups' `MonacoEditorApp` instances for
the same file need to show the same live buffer. But its default unmount behavior
(`keepCurrentModel` defaults to `false`) *disposes* that shared model, on the assumption that one
editor owns one model 1:1 -- so closing the tab in *either* group destroyed the model the *other*
group's still-mounted editor was rendering, leaving it blank with no error. `keepCurrentModel=True`
switches that cleanup to just saving view state instead of disposing anything, the correct behavior
here since a model can legitimately outlive any single `MonacoEditorApp` instance that was showing
it. Trade-off: a closed tab's model is never explicitly disposed at all now, a deliberate accepted
leak (same trade-off already made for orphaned graph nodes in `workspace_service.jac`) rather than
tracking "is any other group still showing this path" just to free memory in a local, single-user
dev tool.

**Unsaved-changes indicator (2026-08-28, `docs/roadmap.md` Phase 3's tab-affordances bullet)** --
`onDirtyChange(path, isDirty)` reports up to `editor_tabs.jac`/`workbench.jac`, same "leaf reports,
parent owns state" shape as `onCursorChange`. Wired through `@monaco-editor/react`'s own `onChange`
prop rather than a manual `editor.onDidChangeModelContent` registration in `handle_mount` -- the two
are equivalent here (both fire per keystroke), but `onChange` is the documented prop for this and
needs no `Ref`-stashed instance to reach. Deliberately does **not** reintroduce the per-keystroke
`has`-state churn the module docstring above already ruled out for content: `dirty` only ever
transitions `False -> True` once per unsaved edit session (`handle_content_change` no-ops once
already dirty) and `True -> False` once on save, not on every keystroke -- so this stays a rare
state update, not a hot one, unlike a content mirror would be.

**Git gutter decorations (2026-08-31, `docs/roadmap.md` Phase 4's SCM bullet)** -- the "real
first-class workbench part with gutter... decorations" the roadmap calls for, distinct from the
sidebar tree decorations `file_tree.jac` doesn't yet carry (that's the SCM view's own file list,
not this component). `git_service.get_line_changes(path)` is fetched once alongside `content` in
`can with entry` (a no-op empty list for a file outside a repo, per that function's own docstring)
and applied via `editor.createDecorationsCollection` in `handle_mount` -- `linesDecorationsClassName`
paints a colored bar in the gutter's line-decorations lane for each added/modified/removed range,
matching real VS Code's own green/blue/red convention (`styles/global.css`'s
`.git-gutter-added/modified/removed` rules). Re-applied after every successful save
(`handle_save`, via the shared `_apply_git_decorations` helper) so the gutter reflects the file's
*new* diff against `HEAD` immediately, rather than staying stale until the tab is closed and
reopened -- the same "the action that changes state re-fetches it" convention `scm.jac` uses for
its own stage/unstage/discard/commit actions. `decorations_ref` (a `Ref`, same "survives re-renders
without triggering one" idiom `editor_ref` already uses) holds the live
`IEditorDecorationsCollection` returned by `createDecorationsCollection` so a later re-apply calls
`.set(...)` on the same collection instead of accumulating a fresh one on top of the last.

**LSP document sync (2026-08-31, `docs/roadmap.md` Phase 4's native LSP client bullet)** --
`notify_document_open` fires once, right after the file's own content loads (the LSP server needs
real text to index, not an empty placeholder), and `notify_document_save` fires from `handle_save`
alongside `save_document`, giving `jac lsp` a fresh full-content sync and triggering its own
`type_check` (which pushes updated `publishDiagnostics` into the Problems panel) on every save, not
just on completion requests. `handle_before_mount` now composes six registrations, not one --
`register_jac_language` (unchanged), `register_jac_completion_provider`
(`jac_completion_provider.jac`), `register_jac_hover_provider` (`jac_hover_provider.jac`,
2026-08-31), `register_jac_definition_provider` (`jac_definition_provider.jac`, 2026-08-31),
`register_jac_reference_provider` (`jac_reference_provider.jac`, 2026-08-31), and
`register_jac_rename_provider` (`jac_rename_provider.jac`, 2026-08-31, new in this PR) -- all
idempotent-guarded internally, so calling all six on every tab's mount is safe. `onOpenLocation` is
the same `open_search_result(path, name, line, column)` handler `problems.jac`/`search.jac` already
reuse, threaded down through `editor_tabs.jac` -- see `jac_definition_provider.jac`'s own docstring
for why go-to-definition needs it at all (unlike hover/completion, it can jump to a file whose tab
isn't the active one); `jac_reference_provider.jac`/`jac_rename_provider.jac` need no separate
wiring for the same reason -- see their own docstrings for why they reuse that same registered
editor opener (references) or apply edits directly rather than navigating at all (rename).

**`onOpenCommandPalette` overrides Monaco's own built-in `editor.action.quickCommand`
(2026-09-01), unifying `F1` with `Ctrl+Shift+P` the same way real VS Code does.** Real VS Code's
`F1` and `Ctrl+Shift+P` are the *same* command, both opening the one Command Palette -- but
embedded Monaco ships its own separate, editor-scoped `F1` action (real, but aware only of
Monaco's own commands, not `command_registry.jac`'s workbench-level ones). Registered via
`command_palette_override.jac`'s `register_command_palette_override`, **not** `editor.addAction`
with the built-in's own id -- a first attempt at exactly that was shipped and found live to create
a *second*, duplicate "Command Palette" context-menu entry rather than replacing the original
(`editor.addAction` and Monaco's static `registerEditorAction` are two entirely separate internal
registries; see `command_palette_override.jac`'s own docstring for the full investigation and why
re-registering Monaco's command id in `CommandsRegistry` is the correct fix instead). See
`workbench.jac`'s own docstring for the full prop-threading chain (`workbench.jac` →
`editor_tabs.jac` → here).

**AI code actions (2026-09-04, `docs/architecture.md`'s "Reframed 2026-09-03" AI section, item 1)**
-- `onAskAI` is threaded down the same `workbench.jac` → `editor_tabs.jac` → here chain as
`onOpenLocation`/`onOpenCommandPalette` above, and registered in `handle_before_mount` alongside
the other six providers via `register_ai_code_action_provider` (`ai_code_action_provider.jac`).
See that module's own docstring for the full "Fix"/"Explain"/"Modify" design and why it routes
through the already-shipped `AIChatApp` sidebar rather than a new UI surface.

**Breadcrumb bar (2026-08-31, `docs/roadmap.md` Phase 4's native LSP client bullet, closing out its
originally-scoped "outline/breadcrumbs" pair)** -- a thin strip above `<Editor>` showing the file
name plus the chain of symbols (`breadcrumb_symbols.jac`'s `symbol_path_at_position`, walked over
`get_document_symbols`' own tree) containing the cursor, e.g. `main.jac  ›  Person  ›  greet`.
Unlike `outline.jac`'s sidebar view, this component already has everything it needs locally --
`editor_ref` for the live cursor position, `symbols` fetched once alongside `content` and refreshed
after every save (`refresh_symbols`, the same "the action that changes state re-fetches it"
convention `apply_git_decorations` already uses) -- so no cross-component RPC or prop threading was
needed the way go-to-definition's cross-tab navigation required. `update_breadcrumb` recomputes the
chain from the live `editor_ref` position, called from `handle_mount` (once, mirroring
`onCursorChange`'s own "fire once at mount, not just on the live listener" convention),
`handle_cursor_change` (every cursor move -- **this call was missing entirely until 2026-09-01**,
reported live: the docstring here always described it, but the actual `handle_cursor_change` body
only ever called `onCursorChange`, so the breadcrumb silently froze at whatever it showed at mount
or the last save, never tracking the cursor at all -- restored, matching what was already documented
and already true of every other call site), and after `refresh_symbols` in `handle_save` (a save can
shift symbol ranges, e.g. adding a line before the current one, so the chain is recomputed against
the fresh tree, not just re-evaluated against the stale one). Clicking a segment calls
`editor_ref.current.setPosition`/`revealPositionInCenter` directly -- no `open_search_result`
needed, since every breadcrumb segment is always within the *current* file's own already-open tab.

**One bounded retry if the very first fetch comes back empty -- a real mitigation for a real,
measured problem, not speculative.** `jac lsp`'s own type-check dispatcher (confirmed live, on a
freshly restarted server with an otherwise-empty queue, not an artifact of a backlogged test
session) took over 30 seconds to check a single 7-line file in this dev-mode environment (the same
"single-threaded, 10-60+ second tasks" characteristic PR #52 already documented, seen here at the
higher end even for a trivial file) -- and `textDocument/documentSymbol` answers from whatever
`jac lsp`'s internal program hub currently holds, empty if the file's very first check hasn't
finished yet, not a wait-for-it request. Since nothing else re-triggers a fetch before the user's
first save, a freshly opened file would otherwise show an empty breadcrumb bar indefinitely, however
long that first check takes. `retry_refresh_symbols`, scheduled once via `setTimeout` (the same
fire-and-forget scheduling `workbench.jac`'s own `cursor_save_timer` already uses) 4 seconds after
the first empty result, catches the common case (many observed check times were well under 10
seconds) without adding a polling loop. **Explicitly not a full fix** -- a check that's still running
past 4 seconds (also observed, well past a minute in the worst case) leaves the breadcrumb empty
until the next save, same as before this retry existed; a real fix would need `jac lsp` itself to
push a "this file's outline changed" notification the way it already pushes `publishDiagnostics`,
which doesn't exist today and is out of scope here.

**Breakpoint gutter (2026-08-31, `docs/roadmap.md` Phase 4's DAP client bullet)** -- a second,
independent `IEditorDecorationsCollection` (`breakpoints_ref`, alongside `decorations_ref`'s git
gutter one -- Monaco's `createDecorationsCollection` supports any number of independent
collections, and the two paint into different lanes: `linesDecorationsClassName` for git changes,
`glyphMarginClassName` for breakpoints, so they never collide on the same line) painted from
`breakpoint_lines`, which loads once at mount from `dap_client.jac`'s `get_breakpoints(path)`
(this project's own stored state, not Monaco's) and is re-applied on every toggle. Clicking the
glyph margin (`editor.onMouseDown`, checking `e.target.type ==
monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN`) toggles that line in `breakpoint_lines` and
calls `dap_client.jac`'s `set_breakpoints(path, breakpoint_lines)` -- an ordinary RPC stub call
(imported directly, same as every LSP function above), not a stream, since setting a breakpoint has
one definite answer (which lines ended up verified), unlike a debug session's open-ended event
flow. `options.glyphMargin: True` is required for Monaco to reserve the glyph-margin lane at
all -- without it, `glyphMarginClassName` decorations are accepted but never rendered."""

import from "@monaco-editor/react" { Editor }
import from src.editor.document_service { open_document, save_document }
import from src.editor.client.jac_language { register_jac_language }
import from src.editor.client.jac_completion_provider { register_jac_completion_provider }
import from src.editor.client.jac_hover_provider { register_jac_hover_provider }
import from src.editor.client.jac_definition_provider { register_jac_definition_provider }
import from src.editor.client.jac_reference_provider { register_jac_reference_provider }
import from src.editor.client.jac_rename_provider { register_jac_rename_provider }
import from src.editor.client.git_conflict_codelens_provider { register_conflict_codelens_provider }
import from src.editor.client.ai_code_action_provider { register_ai_code_action_provider }
import from src.workbench.scm.git_service { get_line_changes }
import from src.workbench.lsp.lsp_client { notify_document_open, notify_document_save, get_document_symbols }
import from src.workbench.symbol_icons.symbol_icons { symbol_icon_class }
import from src.editor.client.breadcrumb_symbols { symbol_path_at_position }
import from src.workbench.dap.dap_client { get_breakpoints, set_breakpoints }
import from src.editor.client.command_palette_override { register_command_palette_override }

def:pub app(path: str, onCursorChange: any, initialCursor: any, onDirtyChange: any, onOpenLocation: any, onOpenCommandPalette: any, onAskAI: any) -> JsxElement {
    has content: str = "";
    has loaded: bool = False;
    has dirty: bool = False;
    has editor_ref: Ref[any] = Ref();
    has monaco_ref: Ref[any] = Ref();
    has decorations_ref: Ref[any] = Ref();
    has breakpoints_ref: Ref[any] = Ref();
    has symbols: list[dict[str, any]] = [];
    has breadcrumb_path: list[dict[str, any]] = [];
    has breakpoint_lines: list[int] = [];

    async can with entry {
        result = await open_document(path);
        loaded_content = result["content"];
        content = loaded_content;
        loaded = True;
        await notify_document_open(path, loaded_content);
        await refresh_symbols(loaded_content);
        if len(symbols) == 0 {
            setTimeout(lambda { retry_refresh_symbols(loaded_content); }, 4000);
        }
        breakpoint_lines = await get_breakpoints(path);
    }

    def handle_before_mount(monaco: any) -> None;
    def handle_mount(editor: any, monaco: any) -> None;
    async def handle_save -> None;
    def handle_cursor_change(e: any) -> None;
    def apply_breakpoint_decorations -> None;
    async def handle_gutter_click(e: any) -> None;
    def handle_content_change(e: any) -> None;
    async def apply_git_decorations -> None;
    async def refresh_symbols(current_content: str) -> None;
    async def retry_refresh_symbols(current_content: str) -> None;
    def update_breadcrumb -> None;
    def handle_breadcrumb_click(target_line: int, target_column: int) -> None;

    <div style={{"height": "100%", "width": "100%", "display": "flex", "flexDirection": "column"}}>
        {(
            <div
                style={{
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "0.3rem",
                    "padding": "0.25rem 0.6rem",
                    "borderBottom": "1px solid #2A2B2C",
                    "background": "#191A1B",
                    "fontSize": "12px",
                    "fontFamily": "system-ui, sans-serif",
                    "color": "#8C8C8C",
                    "flexShrink": "0",
                    "overflow": "auto",
                    "whiteSpace": "nowrap"
                }}
            >
                <span style={{"display": "flex", "alignItems": "center", "gap": "0.25rem"}}>
                    <span className="codicon codicon-file" style={{"fontSize": "13px", "opacity": "0.8"}} />
                    <span>{path.split("/")[-1]}</span>
                </span>
                {[
                    <span key={sym["name"] + ":" + str(sym["line"])} style={{"display": "flex", "alignItems": "center", "gap": "0.25rem"}}>
                        <span className="codicon codicon-chevron-right" style={{"fontSize": "11px", "opacity": "0.5"}} />
                        <span
                            role="button"
                            tabIndex={0}
                            onClick={lambda (e: any) { handle_breadcrumb_click(sym["line"], sym["column"]); }}
                            style={{"display": "flex", "alignItems": "center", "gap": "0.25rem", "cursor": "pointer"}}
                        >
                            <span className={"codicon " + symbol_icon_class(sym["kind"])} style={{"fontSize": "13px", "opacity": "0.8"}} />
                            <span>{sym["name"]}</span>
                        </span>
                    </span>
                    for sym in breadcrumb_path
                ]}
            </div>
        ) if loaded else None}
        <div style={{"flex": "1", "overflow": "hidden"}}>
            {(
                <Editor
                    path={path}
                    defaultValue={content}
                    theme="vs-dark"
                    beforeMount={handle_before_mount}
                    onMount={handle_mount}
                    onChange={handle_content_change}
                    keepCurrentModel={True}
                    options={{"automaticLayout": True, "minimap": {"enabled": True}, "glyphMargin": True}}
                />
            ) if loaded else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    Loading...
                </div>
            )}
        </div>
    </div>
}
