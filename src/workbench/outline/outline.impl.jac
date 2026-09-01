impl app.refresh_outline -> None {
    if path == "" {
        symbols = [];
        return;
    }
    loading = True;
    loaded = await open_document(path);
    symbols = await get_document_symbols(path, loaded["content"]);
    loading = False;
}

"""A variable-key dict literal (`{id: value}`) miscompiles client-side (see `jac-language` skill's
gotcha list) -- built via a spread copy plus a bracket assignment instead, the same workaround
`file_tree.impl.jac`'s own toggle uses."""
impl app.toggle_symbol(id: str) -> None {
    updated: dict[str, bool] = {**expanded};
    updated[id] = not (expanded[id] if id in expanded else True);
    expanded = updated;
}
