"""file_icon_class: shared icon-glyph mapping so `file_tree.jac` and `editor_tabs.jac` agree on a
file's icon. Extension-bucketed, not per-language -- matches VS Code's un-themed default, and
`@vscode/codicons` has no per-language glyphs anyway. Monochrome, like every other icon here."""

glob _CODE_EXTENSIONS: list[str] = [
    "jac", "py", "js", "jsx", "ts", "tsx", "mjs", "cjs", "go", "rs", "java", "kt", "c", "h",
    "cpp", "hpp", "cs", "rb", "php", "sh", "bash", "zsh", "sql", "html", "htm", "css", "scss",
    "less", "vue", "swift", "toml", "yaml", "yml", "ini", "cfg", "env"
];

glob _IMAGE_EXTENSIONS: list[str] = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico"];
glob _ARCHIVE_EXTENSIONS: list[str] = ["zip", "tar", "gz", "rar", "7z"];
glob _BINARY_EXTENSIONS: list[str] = ["exe", "dll", "so", "bin", "wasm"];
glob _TEXT_EXTENSIONS: list[str] = ["txt", "log"];

def:pub file_icon_class(name: str, is_dir: bool, is_open: bool) -> str {
    if is_dir {
        return "codicon-folder-opened" if is_open else "codicon-folder";
    }
    lower_name = name.lower();
    ext = lower_name.split(".")[-1] if "." in lower_name else "";
    if ext == "json" {
        return "codicon-json";
    }
    if ext == "md" or ext == "markdown" {
        return "codicon-markdown";
    }
    if ext == "pdf" {
        return "codicon-file-pdf";
    }
    if ext in _IMAGE_EXTENSIONS {
        return "codicon-file-media";
    }
    if ext in _ARCHIVE_EXTENSIONS {
        return "codicon-file-zip";
    }
    if ext in _BINARY_EXTENSIONS {
        return "codicon-file-binary";
    }
    if ext in _TEXT_EXTENSIONS {
        return "codicon-file-text";
    }
    if ext in _CODE_EXTENSIONS {
        return "codicon-file-code";
    }
    return "codicon-file";
}
