"""Wires Monaco's `registerCompletionItemProvider` to `lsp_client.jac`'s `get_completions` RPC.
Guarded by `_registered` since `beforeMount` fires per editor instance while the Monaco
registration is global. Always replaces the word under the cursor with plain `insertText`,
ignoring LSP `textEdit`/`insertTextFormat` snippets — a known gap, not a mismatch."""

import from src.workbench.lsp.lsp_client { get_completions }

glob _registered: bool = False;

# Maps by name, not int: LSP and Monaco assign different integers to the same CompletionItemKind.
glob _LSP_KIND_TO_MONACO_NAME: dict[int, str] = {
    1: "Text", 2: "Method", 3: "Function", 4: "Constructor", 5: "Field",
    6: "Variable", 7: "Class", 8: "Interface", 9: "Module", 10: "Property",
    11: "Unit", 12: "Value", 13: "Enum", 14: "Keyword", 15: "Snippet",
    16: "Color", 17: "File", 18: "Reference", 19: "Folder", 20: "EnumMember",
    21: "Constant", 22: "Struct", 23: "Event", 24: "Operator", 25: "TypeParameter"
};

# Named async def, not a lambda: Jac lambdas can't be async, and Monaco's provider callback
# must return a Promise for the get_completions round-trip.
async def _provide_completions(monaco: any, model: any, position: any) -> dict[str, any] {
    path = model.uri.path;
    content = model.getValue();
    word_info = model.getWordUntilPosition(position);
    completion_range = {
        "startLineNumber": position.lineNumber,
        "endLineNumber": position.lineNumber,
        "startColumn": word_info.startColumn,
        "endColumn": word_info.endColumn
    };

    items = await get_completions(path, content, position.lineNumber, position.column);

    suggestions = [];
    # sortText preserves jac lsp's relevance order; Monaco otherwise re-sorts by label,
    # burying it under alphabetized dunder builtins (caught live).
    for (idx, item) in enumerate(items) {
        kind_name = _LSP_KIND_TO_MONACO_NAME.get(item["kind"], "Text");
        suggestions.append({
            "label": item["label"],
            "kind": monaco.languages.CompletionItemKind[kind_name],
            "detail": item["detail"],
            "insertText": item["insertText"],
            "range": completion_range,
            "sortText": str(idx).rjust(5, "0")
        });
    }
    return {"suggestions": suggestions};
}

def:pub register_jac_completion_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerCompletionItemProvider("jac", {
        "triggerCharacters": [".", ":"],
        "provideCompletionItems": lambda (model: any, position: any) {
            return _provide_completions(monaco, model, position);
        }
    });
}
