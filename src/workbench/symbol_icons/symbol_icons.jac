"""symbol_icon_class: shared codicon mapping so `outline.jac` and `monaco_editor.jac`'s breadcrumb
agree on a symbol's icon. Only covers the 5 `SymbolKind` values `jac lsp`'s outline builder ever
emits (Function/Enum/Class/Module/Variable) -- `codicon-symbol-misc` is the honest fallback, not
full LSP `SymbolKind` coverage."""

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
