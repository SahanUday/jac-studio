"""Wires Monaco's `registerDocumentFormattingEditProvider` to `lsp_client.jac`'s `get_formatting_edits`
RPC. `jac lsp` answers with one whole-document edit whose end line overshoots the file; Monaco clamps it."""

import from src.workbench.lsp.lsp_client { get_formatting_edits }

glob _registered: bool = False;

async def _provide_formatting(model: any) -> list[dict[str, any]] {
    edits = await get_formatting_edits(model.uri.path, model.getValue());
    return [
        {
            "range": {
                "startLineNumber": e["startLine"],
                "startColumn": e["startColumn"],
                "endLineNumber": e["endLine"],
                "endColumn": e["endColumn"]
            },
            "text": e["newText"]
        }
        for e in edits
    ];
}

def:pub register_jac_formatting_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerDocumentFormattingEditProvider("jac", {
        "provideDocumentFormattingEdits": lambda (model: any) {
            return _provide_formatting(model);
        }
    });
}
