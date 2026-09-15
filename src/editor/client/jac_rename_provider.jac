"""Wires Monaco's `registerRenameProvider` to `lsp_client.jac`'s `get_rename_edits` RPC. Applies
edits by hand rather than via Monaco's bulk-edit service, since that service requires a live
model for every edited file and a rename can touch files with no open tab — open models get
`pushEditOperations`, closed files go through `apply_disk_rename_edits`. No
`resolveRenameLocation`: Monaco falls back to the word under the cursor (documented gap)."""

import from src.workbench.lsp.lsp_client { get_rename_edits, apply_disk_rename_edits }

glob _registered: bool = False;

def _to_monaco_range(edit: dict[str, any]) -> dict[str, any] {
    return {
        "startLineNumber": edit["startLine"],
        "startColumn": edit["startColumn"],
        "endLineNumber": edit["endLine"],
        "endColumn": edit["endColumn"]
    };
}

async def _provide_rename_edits(monaco: any, model: any, position: any, new_name: any) -> dict[str, any] {
    path = model.uri.path;
    content = model.getValue();

    edits = await get_rename_edits(path, content, position.lineNumber, position.column, new_name);

    by_path = {};
    for edit in edits {
        if edit["path"] not in by_path {
            by_path[edit["path"]] = [];
        }
        by_path[edit["path"]].append(edit);
    }

    # Grouped per file, applied in one call: jac lsp computes positions against the original
    # document, so applying edits one at a time would shift later positions out from under them.
    for (edit_path, path_edits) in by_path.items() {
        target_model = monaco.editor.getModel(monaco.Uri.file(edit_path));
        if target_model is not None {
            js_edits = [{"range": _to_monaco_range(e), "text": e["newText"]} for e in path_edits];
            target_model.pushEditOperations([], js_edits, lambda (inverse: any) { None; });
        } else {
            await apply_disk_rename_edits(edit_path, path_edits);
        }
    }

    return {"edits": []};
}

def:pub register_jac_rename_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerRenameProvider("jac", {
        "provideRenameEdits": lambda (model: any, position: any, new_name: any) {
            return _provide_rename_edits(monaco, model, position, new_name);
        }
    });
}
