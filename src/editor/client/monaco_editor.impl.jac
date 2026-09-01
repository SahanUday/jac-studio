impl app.handle_before_mount(monaco: any) -> None {
    register_jac_language(monaco);
    register_jac_completion_provider(monaco);
    register_jac_hover_provider(monaco);
    register_jac_definition_provider(monaco, onOpenLocation);
    register_jac_reference_provider(monaco);
    register_jac_rename_provider(monaco);
    register_conflict_codelens_provider(monaco);
    register_command_palette_override(onOpenCommandPalette);
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

"""Fetches `path`'s current symbol outline (`lsp_client.jac`'s `get_document_symbols`) -- called
once alongside content load and again after every save, the same freshness policy
`apply_git_decorations` already uses for the gutter, and for the same reason: a live keystroke-by-
keystroke refresh would mean a `jac lsp` round trip on every edit, the exact cost this project's
Monaco integration already refuses to pay for its own content sync."""
impl app.refresh_symbols(current_content: str) -> None {
    fetched = await get_document_symbols(path, current_content);
    symbols = fetched;
}

"""The scheduled retry `can with entry` fires once if the first `refresh_symbols` came back empty
-- see this module's own docstring for why. `update_breadcrumb` runs afterward so the visible
breadcrumb actually picks up newly-arrived symbols without needing another cursor move."""
impl app.retry_refresh_symbols(current_content: str) -> None {
    await refresh_symbols(current_content);
    update_breadcrumb();
}

"""Recomputes `breadcrumb_path` from the live editor's current cursor position against whatever
`symbols` currently holds -- called at mount, on every cursor move, and after a save's fresh
`refresh_symbols` (a save can shift symbol ranges out from under the previously-computed chain, not
just leave it stale in content)."""
impl app.update_breadcrumb -> None {
    if not editor_ref.current {
        breadcrumb_path = [];
        return;
    }
    position = editor_ref.current.getPosition();
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

"""Paints a red dot into the glyph margin for every line in `breakpoint_lines` -- called once at
mount (after the stored breakpoints load) and again after every toggle, the same "the action that
changes state re-applies the decorations" convention `apply_git_decorations` already uses."""
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

"""Toggles a breakpoint on the clicked line and persists it via `dap_client.jac`'s
`set_breakpoints` -- only reacts to a click inside the glyph margin specifically
(`MouseTargetType.GUTTER_GLYPH_MARGIN`), not the line-decorations lane the git gutter already owns
or a click on the line's own text."""
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
    if not dirty {
        dirty = True;
        onDirtyChange(path, True);
    }
}
