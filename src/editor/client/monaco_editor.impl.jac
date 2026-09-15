impl app.handle_before_mount(monaco: any) -> None {
    register_jac_language(monaco);
    register_jac_completion_provider(monaco);
    register_jac_hover_provider(monaco);
    register_jac_definition_provider(monaco, onOpenLocation);
    register_jac_reference_provider(monaco);
    register_jac_rename_provider(monaco);
    register_conflict_codelens_provider(monaco);
    register_command_palette_override(onOpenCommandPalette);
    register_ai_code_action_provider(monaco, onAskAI);
}

impl app.handle_mount(editor: any, monaco: any) -> None {
    editor_ref.current = editor;
    monaco_ref.current = monaco;
    _focused_editor_handlers[path] = {"save": handle_save, "toggleInlineChat": toggle_inline_chat};
    _register_global_editor_keybindings(editor, monaco);
    editor.onDidChangeCursorPosition(handle_cursor_change);
    # must precede the mount-time onCursorChange below, or the restore is clobbered by Monaco's (1, 1)
    if initialCursor {
        restored_position = {"lineNumber": initialCursor["line"], "column": initialCursor["column"]};
        editor.setPosition(restored_position);
        editor.revealPositionInCenter(restored_position);
    }
    position = editor.getPosition();
    if position {
        onCursorChange(path, position.lineNumber, position.column);
    }
    update_breadcrumb();
    decorations_ref.current = editor.createDecorationsCollection([]);
    apply_git_decorations();
    breakpoints_ref.current = editor.createDecorationsCollection([]);
    apply_breakpoint_decorations();
    editor.onMouseDown(handle_gutter_click);
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
    await refresh_symbols(saved_content);
    update_breadcrumb();
}

"""Refetched at content load and after every save, never per keystroke."""
impl app.refresh_symbols(current_content: str) -> None {
    fetched = await get_document_symbols(path, current_content);
    symbols = fetched;
}

"""Fires once when the first symbol fetch came back empty; refreshes the visible breadcrumb too."""
impl app.retry_refresh_symbols(current_content: str) -> None {
    await refresh_symbols(current_content);
    update_breadcrumb();
}

impl app.update_breadcrumb -> None {
    if not editor_ref.current {
        breadcrumb_path = [];
        return;
    }
    position = editor_ref.current.getPosition();
    if not position {
        breadcrumb_path = [];
        return;
    }
    breadcrumb_path = symbol_path_at_position(symbols, position.lineNumber, position.column);
}

impl app.handle_breadcrumb_click(target_line: int, target_column: int) -> None {
    if not editor_ref.current {
        return;
    }
    target_position = {"lineNumber": target_line, "column": target_column};
    editor_ref.current.setPosition(target_position);
    editor_ref.current.revealPositionInCenter(target_position);
    editor_ref.current.focus();
}

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
    update_breadcrumb();
}

impl app.apply_breakpoint_decorations -> None {
    if not breakpoints_ref.current or not monaco_ref.current {
        return;
    }
    monaco = monaco_ref.current;
    js_decorations = [
        {
            "range": new(monaco.Range, line, 1, line, 1),
            "options": {"isWholeLine": True, "glyphMarginClassName": "breakpoint-glyph"}
        }
        for line in breakpoint_lines
    ];
    breakpoints_ref.current.set(js_decorations);
}

impl app.handle_gutter_click(e: any) -> None {
    if not monaco_ref.current {
        return;
    }
    monaco = monaco_ref.current;
    if e.target.type != monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN {
        return;
    }
    line = e.target.position.lineNumber;
    updated = [l for l in breakpoint_lines if l != line] if line in breakpoint_lines else breakpoint_lines + [line];
    breakpoint_lines = updated;
    apply_breakpoint_decorations();
    await set_breakpoints(path, updated);
}

impl app.handle_content_change(e: any) -> None {
    if suppress_dirty_ref.current {
        return;
    }
    if not dirty {
        dirty = True;
        onDirtyChange(path, True);
    }
}

# re-checks `dirty` even though workbench.jac already filtered -- closes the race where typing
# starts between that filter's decision and this effect running.
impl app.reload_from_disk -> None {
    if not editor_ref.current or dirty {
        return;
    }
    result = await open_document(path);
    fresh_content = result["content"];
    if fresh_content == content {
        return;
    }
    saved_position = editor_ref.current.getPosition();
    suppress_dirty_ref.current = True;
    editor_ref.current.setValue(fresh_content);
    suppress_dirty_ref.current = False;
    content = fresh_content;
    if saved_position {
        editor_ref.current.setPosition(saved_position);
        editor_ref.current.revealPositionInCenter(saved_position);
    }
    await apply_git_decorations();
    await notify_document_save(path, fresh_content);
    await refresh_symbols(fresh_content);
    update_breadcrumb();
}

impl app.toggle_inline_chat -> None {
    inline_chat_open = not inline_chat_open;
}

impl app.close_inline_chat -> None {
    inline_chat_open = False;
}
