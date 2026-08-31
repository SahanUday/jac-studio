"""symbol_icon_class: one shared helper so `outline.jac`'s tree rows and `monaco_editor.jac`'s
breadcrumb bar pick the same codicon glyph for the same LSP `SymbolKind`, rather than two
components independently guessing at a mapping and drifting apart -- the same reasoning
`file_icons.jac`'s own docstring gives for file-type icons.

**Only the five `SymbolKind` values `jac lsp`'s own outline builder ever emits, not the full LSP
enum.** Confirmed against `utils.impl.jac`'s `kind_map`: `Function`(12)/`Enum`(10)/`Class`(5)/
`Module`(2)/`Variable`(13) are the only kinds `get_symbols_for_outline` produces, so mapping the
rest of LSP's ~26-value `SymbolKind` enum would be dead code until `jac lsp` itself grows richer
outline data -- `codicon-symbol-misc` is the honest fallback for anything else, not a silently
wrong guess."""

glob _SYMBOL_KIND_ICON: dict[int, str] = {
    2: "codicon-symbol-module",
    5: "codicon-symbol-class",
    10: "codicon-symbol-enum",
    12: "codicon-symbol-method",
    13: "codicon-symbol-variable"
};

def:pub symbol_icon_class(kind: int) -> str {
    return _SYMBOL_KIND_ICON.get(kind, "codicon-symbol-misc");
}
