"""Wires Monaco's `registerReferenceProvider` to `lsp_client.jac`'s `get_references` RPC. Cross-file
opens reuse `jac_definition_provider.jac`'s `registerEditorOpener` — no second opener needed here,
since `handle_before_mount` always registers both providers together."""

import from src.workbench.lsp.lsp_client { get_references }

glob _registered: bool = False;

async def _provide_references(monaco: any, model: any, position: any, context: any) -> list[dict[str, any]] {
    path = model.uri.path;
    content = model.getValue();

    locations = await get_references(path, content, position.lineNumber, position.column);
    return [
        {
            "uri": monaco.Uri.file(loc["path"]),
            "range": {
                "startLineNumber": loc["line"],
                "startColumn": loc["column"],
                "endLineNumber": loc["line"],
                "endColumn": loc["column"]
            }
        }
        for loc in locations
    ];
}

def:pub register_jac_reference_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerReferenceProvider("jac", {
        "provideReferences": lambda (model: any, position: any, context: any) {
            return _provide_references(monaco, model, position, context);
        }
    });
}
