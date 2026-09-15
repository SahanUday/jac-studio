"""Wires Monaco's `registerDefinitionProvider` to `lsp_client.jac`'s `get_definition` RPC, plus a
`registerEditorOpener` for cross-file jumps — standalone Monaco has no workbench notion of opening
another file's tab, so without this a jump to a file whose tab isn't active silently does nothing.
Always returns `True` so this project's own tab-visibility state stays in charge of every jump."""

import from src.workbench.lsp.lsp_client { get_definition }

glob _registered: bool = False;

async def _provide_definition(monaco: any, model: any, position: any) -> dict[str, any] | None {
    path = model.uri.path;
    content = model.getValue();

    location = await get_definition(path, content, position.lineNumber, position.column);
    if location is None {
        return None;
    }
    return {
        "uri": monaco.Uri.file(location["path"]),
        "range": {
            "startLineNumber": location["line"],
            "startColumn": location["column"],
            "endLineNumber": location["line"],
            "endColumn": location["column"]
        }
    };
}

def _open_editor(resource: any, selection_or_position: any, onOpenLocation: any) -> bool {
    path = resource.path;
    name = path.split("/")[-1];
    line = selection_or_position.startLineNumber if selection_or_position and selection_or_position.startLineNumber else (
        selection_or_position.lineNumber if selection_or_position and selection_or_position.lineNumber else 1
    );
    column = selection_or_position.startColumn if selection_or_position and selection_or_position.startColumn else (
        selection_or_position.column if selection_or_position and selection_or_position.column else 1
    );
    # Fire-and-forget: openCodeEditor's contract only needs a same-tick True/False, not
    # confirmation the async navigation finished.
    onOpenLocation(path, name, line, column);
    return True;
}

def:pub register_jac_definition_provider(monaco: any, onOpenLocation: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerDefinitionProvider("jac", {
        "provideDefinition": lambda (model: any, position: any) {
            return _provide_definition(monaco, model, position);
        }
    });
    monaco.editor.registerEditorOpener({
        "openCodeEditor": lambda (source: any, resource: any, selection_or_position: any) {
            return _open_editor(resource, selection_or_position, onOpenLocation);
        }
    });
}
