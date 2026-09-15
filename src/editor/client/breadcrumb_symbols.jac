"""Breadcrumb bar's containment lookup, kept in its own module rather than `lsp_client.jac`.
Importing a function from a server-anchored module compiles it as an async RPC stub regardless of
the original function's asyncness (checker error `E1042`) — living there would cost a network
round trip on every cursor move. Carries an explicit `[placement.pins]` entry so the placement
solver can't default it server-side."""

def _position_in_range(line: int, column: int, start_line: int, start_column: int, end_line: int, end_column: int) -> bool {
    if line < start_line or line > end_line {
        return False;
    }
    if line == start_line and column < start_column {
        return False;
    }
    if line == end_line and column > end_column {
        return False;
    }
    return True;
}

"""Chain of symbols containing `(line, column)`, root to leaf. Descends into the first matching
sibling only, since sibling symbol bodies at a nesting level never overlap."""
def:pub symbol_path_at_position(symbols: list[dict[str, any]], line: int, column: int) -> list[dict[str, any]] {
    for sym in symbols {
        if _position_in_range(line, column, sym["startLine"], sym["startColumn"], sym["endLine"], sym["endColumn"]) {
            return [sym] + symbol_path_at_position(sym["children"], line, column);
        }
    }
    return [];
}
