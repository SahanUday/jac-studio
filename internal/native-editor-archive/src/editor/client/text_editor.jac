"""TextEditor: Phase 1's minimal client editor component -- roadmap.md's exit criteria ("a
single text buffer that can be created, edited, and displayed... open a file's content into a
buffer, type, delete, save -- as a standalone demo, no surrounding app").

Deliberately basic per the roadmap: no syntax highlighting, no multi-cursor, no undo/redo UI
beyond what the ported piece-tree buffer gives for free. This is the working prototype the
roadmap's Phase 1 "decision point" (native rendering vs. a Monaco-embed bridge) gets made from --
see `docs/architecture.md`'s open-questions section.

**Phase 2 addition: takes a `path` prop.** `src/workbench/editor_tabs/editor_tabs.jac` mounts one
instance of this component per open tab, keyed by path, so each tab gets its own independent
`lines`/cursor state and its own server-side buffer (`document_service.jac`'s per-path cache) --
switching tabs never reloads or cross-contaminates another tab's content. Used standalone (no
parent Tabs shell) it still works exactly as it did in Phase 1, given any `path`.

**Not a `<textarea>`.** A plain `<textarea value={...} onChange={...}>` (see `notes-app`'s example)
would trivially "work" but wouldn't exercise anything this project built -- the browser's own
native text editing would own every keystroke, and the piece-tree buffer would just be a mirror of
whatever the DOM already did. This component instead renders each line as its own element and
tracks (line, column) cursor state itself, so every insert/delete genuinely round-trips through
`document_service.jac`'s `PieceTreeTextBuffer`, the same way a real custom editor surface (or
Monaco) would own its own model.

**Server round-trip per edit, full-content re-render, no virtualization.** Every keystroke that
mutates content calls `apply_document_edit` and replaces the entire `lines` list with the
server's response; cursor movement (arrow keys) is pure client-side state, needing no round-trip
since the client already holds the current line lengths locally. Deliberately not virtualized or
diffed -- the roadmap explicitly scopes performance characteristics out of this phase, and
per-keystroke latency/feel is itself one of the signals the native-vs-Monaco decision point needs.

Handler bodies live in the paired `text_editor.impl.jac` annex (the standard client-component
"handler annex" pattern -- see `jac-impl-files`), keeping this file a readable state-plus-render
surface.
"""

import from src.editor.document_service { open_document, apply_document_edit }

glob EDITOR_CONTAINER_STYLE: dict[str, str] = {
    "fontFamily": "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    "fontSize": "14px",
    "lineHeight": "1.5",
    "whiteSpace": "pre",
    "padding": "1rem",
    "border": "1px solid #3c3c3c",
    "borderRadius": "4px",
    "backgroundColor": "#1e1e1e",
    "color": "#d4d4d4",
    "outline": "none",
    "minHeight": "300px",
    "cursor": "text"
};

glob CURSOR_STYLE: dict[str, str] = {
    "display": "inline-block",
    "width": "2px",
    "backgroundColor": "#ffffff",
    "verticalAlign": "text-bottom"
};

def:pub app(props: any) -> JsxElement {
    has path: str = props["path"];
    has lines: list[str] = [];
    has cursor_line: int = 1;
    has cursor_column: int = 1;
    has loaded: bool = False;
    has busy: bool = False;
    has queued_keys: list[str] = [];

    async can with entry { await load(); }

    async def load -> None;

    def move_left -> None;
    def move_right -> None;
    def move_up -> None;
    def move_down -> None;

    async def insert_at_cursor(text: str) -> None;
    async def delete_before_cursor -> None;
    async def delete_after_cursor -> None;

    def is_handled_key(key: str) -> bool;
    async def apply_key(key: str) -> None;
    async def drain_key_queue -> None;
    async def handle_key_down(e: KeyboardEvent) -> None;

    <div>
        <div tabIndex={0} onKeyDown={handle_key_down} style={EDITOR_CONTAINER_STYLE}>
            {"Loading..." if not loaded else None}
            {for (idx, line_text) in enumerate(lines) {
                if (idx + 1) != cursor_line {
                    <div key={idx}>{line_text if line_text != "" else " "}</div>
                } else {
                    <div key={idx}>
                        {line_text[0:cursor_column - 1]}
                        <span style={CURSOR_STYLE}>&nbsp;</span>
                        {line_text[cursor_column - 1:]}
                    </div>
                }
            }}
        </div>
    </div>
}
