"""register_jac_reference_provider: wires Monaco's own reference-provider API
(`monaco.languages.registerReferenceProvider`) to `lsp_client.jac`'s `get_references` RPC -- the
fourth consumer of Phase 4's native Jac LSP client (`docs/roadmap.md`).

**No new cross-file navigation plumbing needed here, unlike `jac_definition_provider.jac`.** Monaco
ships its own built-in "Peek References" / "Find All References" widget (Shift+F12) that consumes
this provider directly -- the list-of-locations-plus-inline-preview UI is Monaco's, not something
this project builds. Opening a peek-list entry in a different file for real editing goes through
`ICodeEditorService.openCodeEditor`, the exact same call `jac_definition_provider.jac`'s
`registerEditorOpener` already intercepts -- Monaco supports multiple registered openers and tries
each in turn, so this file doesn't need (and doesn't register) a second one; it only needs the one
already in place, which `monaco_editor.impl.jac`'s `handle_before_mount` guarantees by always
registering both providers together, opener included, before either could ever be exercised.

**Idempotent by the same `_registered` guard every other provider in this project's LSP-client
family already established.**"""

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
