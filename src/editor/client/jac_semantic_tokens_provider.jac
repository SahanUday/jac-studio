"""Wires Monaco's `registerDocumentSemanticTokensProvider` to `lsp_client.jac`'s `get_semantic_tokens`
RPC. The legend is fixed at registration, so this waits on the server's `initialize` reply; with no
legend (gate off, no workspace) it registers nothing and the next editor mount tries again. `jac lsp`
serves tokens from its last finished type-check: empty before the first one, and ~1.5s stale after
an edit. Both schedule a bounded re-request."""

import from src.workbench.lsp.lsp_client { get_semantic_legend, get_semantic_tokens }

glob _registered: bool = False;
glob _change_listeners: list[any] = [];
glob _retries: dict[str, int] = {};
glob _MAX_RETRIES: int = 10;
glob _RETRY_MS: int = 4000;
glob _SETTLE_MS: int = 2000;
glob _last_content: dict[str, str] = {};
glob _settle_timer: any = None;

def _request_refresh -> None {
    for listener in _change_listeners {
        listener();
    }
}

def _schedule_settle_refresh -> None {
    if _settle_timer is not None {
        clearTimeout(_settle_timer);
    }
    _settle_timer = setTimeout(lambda { _request_refresh(); }, _SETTLE_MS);
}

async def _provide_tokens(model: any) -> dict[str, any] | None {
    path = model.uri.path;
    content = model.getValue();
    data = await get_semantic_tokens(path, content);
    if _last_content.get(path) != content {
        _last_content[path] = content;
        _schedule_settle_refresh();
    }
    if len(data) == 0 {
        attempts = _retries.get(path, 0);
        if attempts < _MAX_RETRIES {
            _retries[path] = attempts + 1;
            setTimeout(lambda { _request_refresh(); }, _RETRY_MS);
        }
        return None;
    }
    _retries[path] = 0;
    return {"data": (Uint32Array as any).from(data)};
}

def _on_did_change(listener: any) -> dict[str, any] {
    _change_listeners.append(listener);
    return {"dispose": lambda { _change_listeners.remove(listener); }};
}

async def:pub register_jac_semantic_tokens_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    legend = await get_semantic_legend();
    if not legend or len(legend.get("tokenTypes", [])) == 0 {
        return;
    }
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.registerDocumentSemanticTokensProvider("jac", {
        "onDidChange": _on_did_change,
        "getLegend": lambda {
            return legend;
        },
        "provideDocumentSemanticTokens": lambda (model: any) {
            return _provide_tokens(model);
        },
        "releaseDocumentSemanticTokens": lambda (resultId: any) {
            return None;
        }
    });
}
