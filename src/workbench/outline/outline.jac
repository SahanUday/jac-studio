"""Outline sidebar view: `jac lsp`'s `textDocument/documentSymbol` via `lsp_client.jac`, rendered
as a collapsible symbol tree that defaults to expanded. Refetch is `useEffect([active, path])`,
not `can with entry` -- the view mounts once at startup and hides via CSS, so an entry ability
would fire before any file is open and never again. Reads the file's last-saved content through
`open_document`, not the live Monaco buffer. Handler bodies live in `outline.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.lsp.lsp_client { get_document_symbols }
import from src.editor.document_service { open_document }
import from src.workbench.symbol_icons.symbol_icons { symbol_icon_class }
import from src.editor.client.breadcrumb_symbols { symbol_path_at_position }

glob ROW_BASE_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.35rem",
    "cursor": "pointer",
    "fontSize": "13px",
    "fontFamily": "system-ui, sans-serif",
    "padding": "0.2rem 0.5rem",
    "borderRadius": "3px",
    "userSelect": "none",
    "whiteSpace": "nowrap"
};

def _symbol_id(item: dict[str, any]) -> str {
    return item["name"] + ":" + str(item["line"]);
}

def:pub OutlineNode(props: any) -> JsxElement {
    item = props["node"];
    depth = props["depth"];
    path = props["path"];
    on_open = props["onOpen"];
    expanded = props["expanded"];
    on_toggle = props["onToggle"];
    current_chain_ids = props["currentChainIds"];

    has_children = len(item["children"]) > 0;
    id = _symbol_id(item);
    is_open = expanded[id] if id in expanded else True;
    is_current = id in current_chain_ids;
    indent = 8 + depth * 14;

    <div role="none">
        <div
            role="button"
            tabIndex={0}
            aria-expanded={is_open if has_children else None}
            onClick={lambda (e: any) {
                if has_children {
                    on_toggle(id);
                }
                on_open(path, path.split("/")[-1], item["line"], item["column"]);
            }}
            style={{
                **ROW_BASE_STYLE,
                "paddingLeft": str(indent) + "px",
                "color": "#CCCCCC",
                "background": "#FFFFFF22" if is_current else "transparent"
            }}
        >
            <span
                className={("codicon " + ("codicon-chevron-down" if is_open else "codicon-chevron-right")) if has_children else ""}
                style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.75"}}
            />
            <span
                className={"codicon " + symbol_icon_class(item["kind"])}
                style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.85"}}
            />
            <span style={{"overflow": "hidden", "textOverflow": "ellipsis"}}>{item["name"]}</span>
        </div>
        {(
            <div role="group">
                {[
                    <OutlineNode
                        key={_symbol_id(child)}
                        node={child}
                        depth={depth + 1}
                        path={path}
                        onOpen={on_open}
                        expanded={expanded}
                        onToggle={on_toggle}
                        currentChainIds={current_chain_ids}
                    />
                    for child in item["children"]
                ]}
            </div>
        ) if (has_children and is_open) else None}
    </div>
}

def:pub app(active: bool, path: str, onOpenLocation: any, cursorLine: int, cursorColumn: int) -> JsxElement {
    has symbols: list[dict[str, any]] = [];
    has loading: bool = False;
    has expanded: dict[str, bool] = {};

    async def refresh_outline -> None;
    def toggle_symbol(id: str) -> None;

    useEffect(lambda {
        if active and path != "" {
            refresh_outline();
        }
    }, [active, path]);

    current_chain = symbol_path_at_position(symbols, cursorLine, cursorColumn);
    current_chain_ids = {_symbol_id(s) for s in current_chain};

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%"}}>
        <div
            style={{
                "display": "flex",
                "alignItems": "center",
                "gap": "0.4rem",
                "padding": "0.4rem 0.5rem",
                "borderBottom": "1px solid #2A2B2C",
                "fontSize": "11px",
                "textTransform": "uppercase",
                "letterSpacing": "0.04em",
                "color": "#8C8C8C",
                "fontFamily": "system-ui, sans-serif"
            }}
        >
            <span style={{"flex": "1"}}>Outline</span>
            <span
                role="button"
                title="Refresh"
                aria-label="Refresh outline"
                onClick={lambda (e: any) { refresh_outline(); }}
                className="codicon codicon-refresh"
                style={{"cursor": "pointer", "opacity": "0.85"}}
            />
        </div>
        <div style={{"flex": "1", "overflow": "auto"}}>
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    Loading...
                </div>
            ) if loading else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    No symbols in this file.
                </div>
            ) if (not loading and path != "" and len(symbols) == 0) else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    Open a file to see its outline.
                </div>
            ) if (not loading and path == "") else None}
            {[
                <OutlineNode
                    key={_symbol_id(s)}
                    node={s}
                    depth={0}
                    path={path}
                    onOpen={onOpenLocation}
                    expanded={expanded}
                    onToggle={toggle_symbol}
                    currentChainIds={current_chain_ids}
                />
                for s in symbols
            ]}
        </div>
    </div>
}
