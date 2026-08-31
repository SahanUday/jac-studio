"""symbol_path_at_position: the breadcrumb bar's containment lookup -- deliberately its own tiny,
placement-neutral client module, not a function inside `lsp_client.jac` alongside
`get_document_symbols`. **Load-bearing, not organizational tidiness, caught before it shipped
wrong.** Any function imported by client code from a server-anchored module (`lsp_client.jac` has
real server evidence -- `root`/`jid`/subprocess spawning) is compiled as an async RPC stub
regardless of whether the original function was ever `async` at all -- confirmed directly against
the checker's own error (`E1042`, "'sv import' (server) functions are async RPC stubs on the
client and always need 'await'"). `monaco_editor.jac`'s breadcrumb bar calls this on *every cursor
move* (`handle_cursor_change`); if it lived in `lsp_client.jac`, each keystroke's cursor move would
mean a full network round trip to jaseci's own server just to answer "which symbol contains this
position" -- purely local, already-fetched-data arithmetic that has no business leaving the
browser at all, the exact per-keystroke RPC cost this project's own Monaco integration already
refuses to pay for its own content sync. Moving these two pure functions into their own module
with zero server evidence (no `root`/`jid`, no import of anything server-anchored) lets the
placement solver -- confirmed live, not assumed -- place it client-side on its own; the module also
carries an explicit `[placement.pins]` entry anyway, matching every other client-only module in
this LSP-client family, since the cost of a wrong default here (silently reintroducing the very
RPC-per-keystroke bug this file exists to avoid) is worse than one redundant pin.

**A real `.test.jac` annex, unlike the `monaco.*`-dependent provider files.** `jac_completion_provider.jac`/
`jac_hover_provider.jac`/etc. have no test file because their entire body depends on a live
`monaco` object no unit test can construct; this module needs nothing but its own two functions and
plain dicts, so it gets the same "write tests alongside the code" treatment the LSP client's other
pure helpers (`_extract_hover_text`, `_lsp_location_to_dict`, `_apply_text_edits`, ...) already
have."""

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

"""Walks `symbols` (`lsp_client.jac`'s own nested `{name, kind, line, column, startLine,
startColumn, endLine, endColumn, children}` shape) to find the chain of symbols containing
`(line, column)`, root to leaf -- e.g. `[Person, greet]` for a cursor inside `greet`'s body within
a `Person` archetype. At each level, at most one sibling can contain a given position (symbol
bodies at the same nesting level don't overlap), so descending into the first match and recursing
into *its* children is enough -- no need to check every sibling once one has already matched.
Returns `[]` for a position outside every top-level symbol (e.g. a blank line, or an import
statement before the first declaration)."""
def:pub symbol_path_at_position(symbols: list[dict[str, any]], line: int, column: int) -> list[dict[str, any]] {
    for sym in symbols {
        if _position_in_range(line, column, sym["startLine"], sym["startColumn"], sym["endLine"], sym["endColumn"]) {
            return [sym] + symbol_path_at_position(sym["children"], line, column);
        }
    }
    return [];
}
