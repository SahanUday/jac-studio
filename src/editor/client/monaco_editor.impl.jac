impl app.handle_mount(editor: any, monaco: any) -> None {
    editor_ref.current = editor;
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, handle_save);
    editor.onDidChangeCursorPosition(handle_cursor_change);
    if initialCursor {
        restored_position = {"lineNumber": initialCursor["line"], "column": initialCursor["column"]};
        editor.setPosition(restored_position);
        editor.revealPositionInCenter(restored_position);
    }
    position = editor.getPosition();
    onCursorChange(path, position.lineNumber, position.column);
}

impl app.handle_save -> None {
    if not editor_ref.current {
        return;
    }
    await save_document(path, editor_ref.current.getValue());
}

impl app.handle_cursor_change(e: any) -> None {
    onCursorChange(path, e.position.lineNumber, e.position.column);
}
