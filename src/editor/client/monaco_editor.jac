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
"""

import from "@monaco-editor/react" { Editor }
import from src.editor.document_service { open_document, save_document }

def:pub app(path: str, onCursorChange: any, initialCursor: any) -> JsxElement {
    has content: str = "";
    has loaded: bool = False;
    has editor_ref: Ref[any] = Ref();

    async can with entry {
        result = await open_document(path);
        content = result["content"];
        loaded = True;
    }

    def handle_mount(editor: any, monaco: any) -> None;
    async def handle_save -> None;
    def handle_cursor_change(e: any) -> None;

    <div style={{"height": "100%", "width": "100%"}}>
        {(
            <Editor
                path={path}
                defaultValue={content}
                theme="vs-dark"
                onMount={handle_mount}
                keepCurrentModel={True}
                options={{"automaticLayout": True, "minimap": {"enabled": False}}}
            />
        ) if loaded else (
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                Loading...
            </div>
        )}
    </div>
}
