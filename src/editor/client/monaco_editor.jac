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
"""

import from "@monaco-editor/react" { Editor }
import from src.editor.document_service { open_document, save_document }

def:pub app(path: str, onCursorChange: any) -> JsxElement {
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
                options={{"automaticLayout": True, "minimap": {"enabled": False}}}
            />
        ) if loaded else (
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                Loading...
            </div>
        )}
    </div>
}
