"""register_jac_definition_provider: wires Monaco's own definition-provider API
(`monaco.languages.registerDefinitionProvider`) to `lsp_client.jac`'s `get_definition` RPC -- the
third consumer of Phase 4's native Jac LSP client, and the first that needs to navigate *across*
files, not just annotate the buffer already open under the cursor (unlike `jac_hover_provider.jac`).

**Standalone Monaco (this project's editor engine, `docs/architecture.md`) has no built-in notion
of "open a different file's editor" -- `monaco.editor.registerEditorOpener` is the real escape
hatch, not `provideDefinition`'s return value alone.** `provideDefinition` only tells Monaco *where*
a definition is (a `Location`); what happens when the user actually activates it (F12, Ctrl+click,
"Go to Definition") is `ICodeEditorService.openCodeEditor`'s job, which a real VS Code workbench
implements to switch editor tabs -- the standalone editor this project embeds has no such workbench,
so without a registered opener, jumping to a definition in a file whose tab isn't already the active
one silently does nothing. `registerEditorOpener` intercepts every such open (same-file or
cross-file) and hands it to `onOpenLocation` -- the exact same `open_search_result(path, name, line,
column)` handler `problems.jac` and `search.jac` already reuse for "open or activate this file's tab
and jump to a line/column" -- rather than letting Monaco's own default handling run, which (since
every open tab keeps its own live `MonacoEditorApp` instance mounted, `monaco_editor.jac`'s own
`keepCurrentModel` docstring) could otherwise silently focus/reveal a *hidden*, not-currently-active
tab's underlying editor instance without updating this project's own tab-visibility state at all.
Always returning `True` (never falling through to Monaco's default behavior) keeps that one code
path in charge of every jump, active tab or not.

**`onOpenLocation` is called without `await`, matching `search.jac`'s own click handler** -- it's an
`async def:pub` server round-trip (mutates tab/cursor state, then persists the session), but
`openCodeEditor`'s contract only needs a same-tick `True`/`False` answer for "will this be
handled," not confirmation that the navigation finished, so this is a deliberate fire-and-forget,
not a dropped `await`.

**Idempotent by the same `_registered` guard `jac_completion_provider.jac`/`jac_hover_provider.jac`
already established**, covering both registrations this file makes (`registerDefinitionProvider`
and `registerEditorOpener`) with the one guard, since they're always registered together and neither
makes sense without the other here."""

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
