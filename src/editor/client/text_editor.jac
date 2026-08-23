"""TextEditor: Phase 1's minimal client editor component -- roadmap.md's exit criteria ("a
single text buffer that can be created, edited, and displayed... open a file's content into a
buffer, type, delete, save -- as a standalone demo, no surrounding app").

Deliberately basic per the roadmap: no syntax highlighting, no multi-cursor, no undo/redo UI
beyond what the ported piece-tree buffer gives for free. This is the working prototype the
roadmap's Phase 1 "decision point" (native rendering vs. a Monaco-embed bridge) gets made from --
see `docs/architecture.md`'s open-questions section.

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
"""

import from src.editor.document_service { get_document_lines, apply_document_edit }

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

def:pub app -> JsxElement {
    has lines: list[str] = [];
    has cursor_line: int = 1;
    has cursor_column: int = 1;
    has loaded: bool = False;

    async can with entry {
        lines = await get_document_lines();
        loaded = True;
    }

    def move_left {
        if cursor_column > 1 {
            cursor_column -= 1;
        } elif cursor_line > 1 {
            cursor_line -= 1;
            cursor_column = len(lines[cursor_line - 1]) + 1;
        }
    }

    def move_right {
        current_line_text = lines[cursor_line - 1];
        if cursor_column <= len(current_line_text) {
            cursor_column += 1;
        } elif cursor_line < len(lines) {
            cursor_line += 1;
            cursor_column = 1;
        }
    }

    def move_up {
        if cursor_line > 1 {
            cursor_line -= 1;
            cursor_column = min(cursor_column, len(lines[cursor_line - 1]) + 1);
        }
    }

    def move_down {
        if cursor_line < len(lines) {
            cursor_line += 1;
            cursor_column = min(cursor_column, len(lines[cursor_line - 1]) + 1);
        }
    }

    async def insert_at_cursor(text: str) {
        new_lines = await apply_document_edit(cursor_line, cursor_column, cursor_line, cursor_column, text);
        lines = new_lines;
        if text == "\n" {
            cursor_line += 1;
            cursor_column = 1;
        } else {
            cursor_column += len(text);
        }
    }

    async def delete_before_cursor {
        if cursor_column > 1 {
            new_lines = await apply_document_edit(
                cursor_line, cursor_column - 1, cursor_line, cursor_column, ""
            );
            lines = new_lines;
            cursor_column -= 1;
        } elif cursor_line > 1 {
            prev_line_text = lines[cursor_line - 2];
            prev_end_column = len(prev_line_text) + 1;
            new_lines = await apply_document_edit(cursor_line - 1, prev_end_column, cursor_line, 1, "");
            lines = new_lines;
            cursor_line -= 1;
            cursor_column = prev_end_column;
        }
    }

    async def delete_after_cursor {
        current_line_text = lines[cursor_line - 1];
        if cursor_column <= len(current_line_text) {
            new_lines = await apply_document_edit(
                cursor_line, cursor_column, cursor_line, cursor_column + 1, ""
            );
            lines = new_lines;
        } elif cursor_line < len(lines) {
            new_lines = await apply_document_edit(cursor_line, cursor_column, cursor_line + 1, 1, "");
            lines = new_lines;
        }
    }

    async def handle_key_down(e: KeyboardEvent) {
        if e.ctrlKey or e.metaKey or e.altKey {
            return;
        }

        key = e.key;
        if len(key) == 1 {
            e.preventDefault();
            await insert_at_cursor(key);
        } elif key == "Enter" {
            e.preventDefault();
            await insert_at_cursor("\n");
        } elif key == "Backspace" {
            e.preventDefault();
            await delete_before_cursor();
        } elif key == "Delete" {
            e.preventDefault();
            await delete_after_cursor();
        } elif key == "ArrowLeft" {
            e.preventDefault();
            move_left();
        } elif key == "ArrowRight" {
            e.preventDefault();
            move_right();
        } elif key == "ArrowUp" {
            e.preventDefault();
            move_up();
        } elif key == "ArrowDown" {
            e.preventDefault();
            move_down();
        }
    }

    <div>
        <h1 style={{"fontFamily": "system-ui, sans-serif", "fontSize": "18px"}}>
            jac-studio -- editor core (Phase 1 prototype)
        </h1>
        <p style={{"fontFamily": "system-ui, sans-serif", "color": "#666", "fontSize": "13px"}}>
            {"Click below, then type. Backed by a real ported piece-tree buffer, not a <textarea>."}
        </p>
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
