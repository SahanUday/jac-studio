impl app.handle_mount(editor: any, monaco: any) -> None {
    editor_ref.current = editor;
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, handle_save);
}

impl app.handle_save -> None {
    if not editor_ref.current {
        return;
    }
    await save_document(path, editor_ref.current.getValue());
}
