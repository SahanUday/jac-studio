"""register_jac_completion_provider: wires Monaco's own completion-provider API
(`monaco.languages.registerCompletionItemProvider`) to `lsp_client.jac`'s `get_completions` RPC --
the first real consumer of Phase 4's native Jac LSP client (`docs/roadmap.md`).

**Idempotent by the same module-level `_registered` guard `jac_language.jac` already established**
for the identical reason: `beforeMount` fires once per mounted `<Editor>` instance, not once per
app, and `registerCompletionItemProvider` is a global registration on the `monaco` namespace, not
per-instance -- registering it again on every tab open would offer duplicate suggestions for the
same trigger, not throw or no-op safely.

**A named `async def`, not an inline lambda, for `provideCompletionItems`** -- Monaco's own
provider callback may return a `Promise`, and the RPC call to `get_completions` genuinely is one
(a server round-trip); an `async` function is what naturally produces that Promise. Jac lambdas
aren't declared `async`, so this needed a real function either way.

**The completion range comes from `model.getWordUntilPosition`, not from the LSP response's own
`textEdit`/`insertTextFormat` fields.** `jac lsp`'s completion items may carry a `textEdit` with
their own replacement range, or none at all (meaning "insert at cursor"), and some carry
snippet-formatted `insertText` (`insertTextFormat: 2`) that would need Monaco's own
`InsertTextRules.InsertAsSnippet` to expand correctly. Handling that whole surface is real
LSP-client completeness, deferred rather than half-built: this v1 always replaces the current word
under the cursor with plain, non-snippet `insertText`, matching the common case (completing an
identifier) correctly and degrading to "insert literally where the cursor is" for anything richer
-- a real, documented gap, not silently wrong for a mismatch nobody would notice.

**`kind` is translated via Monaco's own `CompletionItemKind` enum object at runtime
(`monaco.languages.CompletionItemKind[name]`), not a hardcoded integer table on the Monaco side.**
LSP's `CompletionItemKind` and Monaco's own enum use *different* integer values for the same
concept (LSP's `Function = 3`, Monaco's `Function = 1`) -- `_LSP_KIND_TO_MONACO_NAME` maps the LSP
integer to the shared *name* (`"Function"`), then looks that name up against Monaco's real enum
object, so a future Monaco upgrade that renumbers its own enum can't silently desync this mapping
the way two independently-hardcoded integer tables could.

**`sortText` preserves `jac lsp`'s own result ordering -- caught live, not assumed.** `jac lsp`
already returns document-relevant symbols first (verified directly against the raw RPC response:
completing `p.` on a `Person`-typed variable put `p`, `Person`, and `greet` -- the file's own
symbols -- ahead of a long tail of Python-typeshed globals its completion engine also considers in
scope). But Monaco's `provideCompletionItems` re-sorts by `label` when an item carries no
`sortText` of its own, which alphabetizes dunder builtins (`__build_class__`, `__doc__`, ...) to
the very top and buries the server's actual relevance ordering -- confirmed live by triggering a
real completion and reading the rendered suggest-widget rows, not just the raw JSON. Each
suggestion's `sortText` is a zero-padded index (`"00000"`, `"00001"`, ...) matching its position in
`get_completions`'s own returned list, so Monaco's sort is stable with the server's intended order
instead of silently overriding it."""

import from src.workbench.lsp.lsp_client { get_completions }

glob _registered: bool = False;

glob _LSP_KIND_TO_MONACO_NAME: dict[int, str] = {
    1: "Text", 2: "Method", 3: "Function", 4: "Constructor", 5: "Field",
    6: "Variable", 7: "Class", 8: "Interface", 9: "Module", 10: "Property",
    11: "Unit", 12: "Value", 13: "Enum", 14: "Keyword", 15: "Snippet",
    16: "Color", 17: "File", 18: "Reference", 19: "Folder", 20: "EnumMember",
    21: "Constant", 22: "Struct", 23: "Event", 24: "Operator", 25: "TypeParameter"
};

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
