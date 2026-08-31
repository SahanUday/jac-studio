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
just on completion requests. `handle_before_mount` now composes five registrations, not one --
`register_jac_language` (unchanged), `register_jac_completion_provider`
(`jac_completion_provider.jac`), `register_jac_hover_provider` (`jac_hover_provider.jac`,
2026-08-31), `register_jac_definition_provider` (`jac_definition_provider.jac`, 2026-08-31), and
`register_jac_reference_provider` (`jac_reference_provider.jac`, 2026-08-31, new in this PR) --
all idempotent-guarded internally, so calling all five on every tab's mount is safe.
`onOpenLocation` is the same `open_search_result(path, name, line, column)` handler
`problems.jac`/`search.jac` already reuse, threaded down through `editor_tabs.jac` -- see
`jac_definition_provider.jac`'s own docstring for why go-to-definition needs it at all (unlike
hover/completion, it can jump to a file whose tab isn't the active one); `jac_reference_provider.jac`
needs no separate wiring for the same reason -- see its own docstring for why it reuses that same
registered editor opener rather than needing `onOpenLocation` passed to it directly."""

import from "@monaco-editor/react" { Editor }
import from src.editor.document_service { open_document, save_document }
import from src.editor.client.jac_language { register_jac_language }
import from src.editor.client.jac_completion_provider { register_jac_completion_provider }
import from src.editor.client.jac_hover_provider { register_jac_hover_provider }
import from src.editor.client.jac_definition_provider { register_jac_definition_provider }
import from src.editor.client.jac_reference_provider { register_jac_reference_provider }
import from src.workbench.scm.git_service { get_line_changes }
import from src.workbench.lsp.lsp_client { notify_document_open, notify_document_save }

def:pub app(path: str, onCursorChange: any, initialCursor: any, onDirtyChange: any, onOpenLocation: any) -> JsxElement {
    has content: str = "";
    has loaded: bool = False;
    has dirty: bool = False;
    has editor_ref: Ref[any] = Ref();
    has monaco_ref: Ref[any] = Ref();
    has decorations_ref: Ref[any] = Ref();

    async can with entry {
        result = await open_document(path);
        loaded_content = result["content"];
        content = loaded_content;
        loaded = True;
        await notify_document_open(path, loaded_content);
    }

    def handle_before_mount(monaco: any) -> None;
    def handle_mount(editor: any, monaco: any) -> None;
    async def handle_save -> None;
    def handle_cursor_change(e: any) -> None;
    def handle_content_change(e: any) -> None;
    async def apply_git_decorations -> None;

    <div style={{"height": "100%", "width": "100%"}}>
        {(
            <Editor
                path={path}
                defaultValue={content}
                theme="vs-dark"
                beforeMount={handle_before_mount}
                onMount={handle_mount}
                onChange={handle_content_change}
                keepCurrentModel={True}
                options={{"automaticLayout": True, "minimap": {"enabled": True}}}
            />
        ) if loaded else (
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                Loading...
            </div>
        )}
    </div>
}
