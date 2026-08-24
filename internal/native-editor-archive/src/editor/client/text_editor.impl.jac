impl app.load -> None {
    result = await open_document(path);
    lines = result["lines"];
    loaded = True;
}

impl app.move_left -> None {
    if cursor_column > 1 {
        cursor_column -= 1;
    } elif cursor_line > 1 {
        cursor_line -= 1;
        cursor_column = len(lines[cursor_line - 1]) + 1;
    }
}

impl app.move_right -> None {
    current_line_text = lines[cursor_line - 1];
    if cursor_column <= len(current_line_text) {
        cursor_column += 1;
    } elif cursor_line < len(lines) {
        cursor_line += 1;
        cursor_column = 1;
    }
}

impl app.move_up -> None {
    if cursor_line > 1 {
        cursor_line -= 1;
        cursor_column = min(cursor_column, len(lines[cursor_line - 1]) + 1);
    }
}

impl app.move_down -> None {
    if cursor_line < len(lines) {
        cursor_line += 1;
        cursor_column = min(cursor_column, len(lines[cursor_line - 1]) + 1);
    }
}

impl app.insert_at_cursor(text: str) -> None {
    new_lines = await apply_document_edit(path, cursor_line, cursor_column, cursor_line, cursor_column, text);
    lines = new_lines;
    if text == "\n" {
        cursor_line += 1;
        cursor_column = 1;
    } else {
        cursor_column += len(text);
    }
}

impl app.delete_before_cursor -> None {
    if cursor_column > 1 {
        new_lines = await apply_document_edit(
            path, cursor_line, cursor_column - 1, cursor_line, cursor_column, ""
        );
        lines = new_lines;
        cursor_column -= 1;
    } elif cursor_line > 1 {
        prev_line_text = lines[cursor_line - 2];
        prev_end_column = len(prev_line_text) + 1;
        new_lines = await apply_document_edit(path, cursor_line - 1, prev_end_column, cursor_line, 1, "");
        lines = new_lines;
        cursor_line -= 1;
        cursor_column = prev_end_column;
    }
}

impl app.delete_after_cursor -> None {
    current_line_text = lines[cursor_line - 1];
    if cursor_column <= len(current_line_text) {
        new_lines = await apply_document_edit(
            path, cursor_line, cursor_column, cursor_line, cursor_column + 1, ""
        );
        lines = new_lines;
    } elif cursor_line < len(lines) {
        new_lines = await apply_document_edit(path, cursor_line, cursor_column, cursor_line + 1, 1, "");
        lines = new_lines;
    }
}

impl app.is_handled_key(key: str) -> bool {
    return len(key) == 1 or key in [
        "Enter", "Backspace", "Delete", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"
    ];
}

impl app.apply_key(key: str) -> None {
    if len(key) == 1 {
        await insert_at_cursor(key);
    } elif key == "Enter" {
        await insert_at_cursor("\n");
    } elif key == "Backspace" {
        await delete_before_cursor();
    } elif key == "Delete" {
        await delete_after_cursor();
    } elif key == "ArrowLeft" {
        move_left();
    } elif key == "ArrowRight" {
        move_right();
    } elif key == "ArrowUp" {
        move_up();
    } elif key == "ArrowDown" {
        move_down();
    }
}

impl app.drain_key_queue -> None {
    busy = True;
    while len(queued_keys) > 0 {
        key = queued_keys.pop(0);
        await apply_key(key);
    }
    busy = False;
}

impl app.handle_key_down(e: KeyboardEvent) -> None {
    if e.ctrlKey or e.metaKey or e.altKey {
        return;
    }

    key = e.key;
    if not is_handled_key(key) {
        return;
    }
    e.preventDefault();

    # Each edit is an await'd server round trip, so two keydowns fired before the first
    # response lands would otherwise race -- both computing their insert position from the
    # same stale cursor state (2026-08-23-client-editor-no-per-keystroke-request-queuing).
    # Queuing here, rather than dropping or debouncing, keeps every keystroke and processes
    # them strictly in order: nothing between `queued_keys.append` and `drain_key_queue`
    # setting `busy = True` yields control, so at most one drain loop ever runs at a time.
    queued_keys.append(key);
    if not busy {
        await drain_key_queue();
    }
}
