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
