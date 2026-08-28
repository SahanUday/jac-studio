"""file_icon_class: Phase 3's file-type-icon bullet (`docs/roadmap.md`) -- one shared helper so
`file_tree.jac`'s rows and `editor_tabs.jac`'s tabs pick the same codicon glyph for the same file,
rather than two components independently guessing at a mapping and drifting apart.

**Extension-bucketed, not a full per-language table.** VS Code's own default (no icon theme
installed) icon set is this coarse too -- a handful of shapes (code, text, image, archive, pdf,
binary, config) rather than one glyph per language. `@vscode/codicons` (this project's icon set,
see `docs/architecture.md`'s Visual identity section) has no per-language glyphs at all, so
matching upstream's *default*, un-themed look is the actual fidelity target here, not an
approximation of a fuller icon theme extension.

**Monochrome, like every other icon already in this app.** Real icon themes color-code file icons
(e.g. a yellow braces glyph for JSON); codicons carries no such palette, and every other icon
already shipped in this project (chevrons, close, split, sidebar-toggle) is opacity-shaded
monochrome, not colored. Consistent with that rather than hand-picking colors for this one case.
"""

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
