"""Wires Monaco's `registerHoverProvider` to `lsp_client.jac`'s `get_hover` RPC. Returns `None`,
not an empty `contents` array, when there's nothing to say — Monaco renders a visible empty widget
for the latter."""

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
