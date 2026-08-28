test "folder rows get the closed or opened folder glyph" {
    assert file_icon_class("src", True, False) == "codicon-folder";
    assert file_icon_class("src", True, True) == "codicon-folder-opened";
}

test "known extensions map to specific glyphs" {
    assert file_icon_class("main.jac", False, False) == "codicon-file-code";
    assert file_icon_class("app.py", False, False) == "codicon-file-code";
    assert file_icon_class("data.json", False, False) == "codicon-json";
    assert file_icon_class("README.md", False, False) == "codicon-markdown";
    assert file_icon_class("photo.PNG", False, False) == "codicon-file-media";
    assert file_icon_class("archive.zip", False, False) == "codicon-file-zip";
    assert file_icon_class("app.wasm", False, False) == "codicon-file-binary";
    assert file_icon_class("notes.txt", False, False) == "codicon-file-text";
}

test "unknown or missing extension falls back to the generic file glyph" {
    assert file_icon_class("Makefile", False, False) == "codicon-file";
    assert file_icon_class("weird.xyz123", False, False) == "codicon-file";
}
