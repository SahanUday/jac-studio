"""`symbol_path_at_position` is `monaco_editor.jac`'s breadcrumb bar's whole reason to exist --
these cases exercise it directly against a hand-built two-level symbol tree, without needing
`lsp_client.jac`'s own conversion (only the `startLine`/`startColumn`/`endLine`/`endColumn`/
`children` fields the containment check actually reads matter here)."""

glob _BREADCRUMB_SYMBOLS: list[dict[str, any]] = [
    {
        "name": "Person", "kind": 5, "line": 1, "column": 6,
        "startLine": 1, "startColumn": 1, "endLine": 8, "endColumn": 2,
        "children": [
            {
                "name": "greet", "kind": 12, "line": 5, "column": 5,
                "startLine": 5, "startColumn": 5, "endLine": 7, "endColumn": 6,
                "children": []
            }
        ]
    }
];

test "symbol_path_at_position finds the top-level symbol containing the cursor" {
    assert symbol_path_at_position(_BREADCRUMB_SYMBOLS, 2, 5) == [
        {
            "name": "Person", "kind": 5, "line": 1, "column": 6,
            "startLine": 1, "startColumn": 1, "endLine": 8, "endColumn": 2,
            "children": _BREADCRUMB_SYMBOLS[0]["children"]
        }
    ];
}

test "symbol_path_at_position finds the full root-to-leaf chain inside a nested symbol" {
    path = symbol_path_at_position(_BREADCRUMB_SYMBOLS, 6, 5);
    assert len(path) == 2;
    assert path[0]["name"] == "Person";
    assert path[1]["name"] == "greet";
}

test "symbol_path_at_position returns an empty list outside every symbol" {
    assert symbol_path_at_position(_BREADCRUMB_SYMBOLS, 20, 1) == [];
}

"""A cursor sitting exactly on a symbol's opening or closing boundary line/column is still inside
it -- ranges are inclusive on both ends, matching real editor selection semantics."""
test "symbol_path_at_position treats range boundaries as inclusive" {
    assert len(symbol_path_at_position(_BREADCRUMB_SYMBOLS, 1, 1)) == 1;
    assert len(symbol_path_at_position(_BREADCRUMB_SYMBOLS, 8, 2)) == 1;
}
