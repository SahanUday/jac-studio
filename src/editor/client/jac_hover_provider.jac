"""register_jac_hover_provider: wires Monaco's own hover-provider API
(`monaco.languages.registerHoverProvider`) to `lsp_client.jac`'s `get_hover` RPC -- the second
consumer of Phase 4's native Jac LSP client (`docs/roadmap.md`), following the exact shape
`jac_completion_provider.jac` already established (idempotent `_registered` guard, a named `async
def` rather than an inline lambda since the RPC round-trip genuinely returns a `Promise`).

**No cross-file navigation concern here, unlike go-to-definition/find-references (a later PR)** --
hover is answered entirely in terms of the buffer already open under the cursor, so this file needs
no `open_search_result`-style callback threaded down from `workbench.jac`, just the `monaco`
instance `handle_before_mount` already has in hand.

**Returns `None` (not an empty contents array) when `get_hover` has nothing to say.** Monaco's own
`IHoverProvider` contract treats a falsy return as "no hover here" and shows nothing, the correct
behavior for whitespace or a token `jac lsp` couldn't resolve a symbol for -- an empty-but-present
`contents` array would instead render a visible, empty hover widget."""

import from src.workbench.lsp.lsp_client { get_hover }

glob _registered: bool = False;

async def _provide_hover(monaco: any, model: any, position: any) -> dict[str, any] | None {
    path = model.uri.path;
    content = model.getValue();

    text = await get_hover(path, content, position.lineNumber, position.column);
    if not text {
        return None;
    }
    return {"contents": [{"value": text}]};
}

def:pub register_jac_hover_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerHoverProvider("jac", {
        "provideHover": lambda (model: any, position: any) {
            return _provide_hover(monaco, model, position);
        }
    });
}
