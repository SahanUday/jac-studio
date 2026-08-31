"""register_jac_rename_provider: wires Monaco's own rename-provider API
(`monaco.languages.registerRenameProvider`) to `lsp_client.jac`'s `get_rename_edits` RPC -- the
fifth consumer of Phase 4's native Jac LSP client, and the first that mutates buffers rather than
just reading or navigating them.

**Applied by hand, not handed to Monaco's own bulk-edit service.** Standalone Monaco's built-in
`StandaloneBulkEditService` (confirmed directly against its bundled source,
`node_modules/monaco-editor/esm/vs/editor/standalone/browser/standaloneServices.js`) can only ever
apply an edit to a resource that already has a live Monaco model: `this._modelService.getModel(edit.
resource)`, throwing `'bad edit - model not found'` otherwise. That's fine for a file with an open
tab (this project always has a live model for those, per `monaco_editor.jac`'s `keepCurrentModel`
docstring), but a rename can touch a file with **no** open tab at all -- every use of the renamed
symbol, wherever it lives -- which standalone Monaco has no workbench-level machinery to open,
create, or persist on its own. So this provider applies every edit itself instead of returning a
`WorkspaceEdit` for Monaco to apply: a file with a live model gets `model.pushEditOperations`
directly (the exact primitive `StandaloneBulkEditService.apply` uses internally, so an open tab's
dirty-indicator and undo stack behave identically to any other edit -- `onDidChangeModelContent`
fires the same way `monaco_editor.jac`'s own `onChange` already listens for); a file with no open
model goes through `lsp_client.jac`'s `apply_disk_rename_edits`, which reads, edits, and writes the
file directly, since there is no buffer for the user to see or explicitly save. Returning
`{"edits": []}` afterward is what stops Monaco's own bulk-edit service from trying (and failing) to
apply the same edits a second time.

**Edits are grouped by file before being applied, never one at a time.** `jac lsp` computes every
edit's position against the *original*, pre-rename document -- applying two edits to the same file
in sequence would let the first edit's splice shift the second one's still-unprocessed position out
from under it. Both apply paths (`pushEditOperations` here, `_apply_text_edits` in `lsp_client.jac`)
take a whole file's edits in one call for exactly this reason, matching how
`StandaloneBulkEditService.apply` itself batches per model rather than replaying edits individually.

**No `resolveRenameLocation`, a deliberate scope cut matching `jac_completion_provider.jac`'s own
precedent of not implementing every optional LSP-adjacent field.** Monaco falls back to the current
word under the cursor (`model.getWordAtPosition`) for the rename widget's initial highlighted range
and placeholder text without it -- the common case (renaming an identifier) works correctly; a
symbol whose renameable range differs from its literal word boundary is a real, documented gap, not
a silently wrong default."""

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
