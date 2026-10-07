"""A variable-key dict literal (`{id: value}`) miscompiles client-side; copy, then bracket-assign."""
impl app.toggle_symbol(id: str) -> None {
    updated: dict[str, bool] = {**expanded};
    updated[id] = not (expanded[id] if id in expanded else True);
    expanded = updated;
}
