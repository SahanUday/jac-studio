impl app.handle_before_mount(monaco: any) -> None {
    register_jac_language(monaco);
    register_jac_completion_provider(monaco);
    register_jac_hover_provider(monaco);
    register_jac_definition_provider(monaco, onOpenLocation);
    register_jac_reference_provider(monaco);
    register_jac_rename_provider(monaco);
}

impl app.handle_mount(editor: any, monaco: any) -> None {
    editor_ref.current = editor;
    monaco_ref.current = monaco;
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, handle_save);
    editor.onDidChangeCursorPosition(handle_cursor_change);
    if initialCursor {
        restored_position = {"lineNumber": initialCursor["line"], "column": initialCursor["column"]};
        editor.setPosition(restored_position);
        editor.revealPositionInCenter(restored_position);
    }
    position = editor.getPosition();
    onCursorChange(path, position.lineNumber, position.column);
    decorations_ref.current = editor.createDecorationsCollection([]);
    apply_git_decorations();
}

impl app.handle_save -> None {
    if not editor_ref.current {
        return;
    }
    saved_content = editor_ref.current.getValue();
    await save_document(path, saved_content);
    if dirty {
        dirty = False;
        onDirtyChange(path, False);
    }
    await apply_git_decorations();
    await notify_document_save(path, saved_content);
}

"""Fetches the current `HEAD`-vs-working-tree line ranges and paints them into the gutter --
called once at mount and again after every save, never on a live keystroke (matching this file's
own "no per-keystroke round-trip" convention for content itself)."""
impl app.apply_git_decorations -> None {
    if not decorations_ref.current or not monaco_ref.current {
        return;
    }
    changes = await get_line_changes(path);
    monaco = monaco_ref.current;
    js_decorations = [];
    for change in changes {
        class_name = "git-gutter-" + change["type"];
        js_decorations.append({
            "range": new(monaco.Range, change["startLine"], 1, change["endLine"], 1),
            "options": {"isWholeLine": True, "linesDecorationsClassName": class_name}
        });
    }
    decorations_ref.current.set(js_decorations);
}

impl app.handle_cursor_change(e: any) -> None {
    onCursorChange(path, e.position.lineNumber, e.position.column);
}

impl app.handle_content_change(e: any) -> None {
    if not dirty {
        dirty = True;
        onDirtyChange(path, True);
    }
}
