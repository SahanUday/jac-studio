"""Outline sidebar view: a collapsible symbol tree, expanded by default, of the symbols the active
editor publishes (`workbench.jac`'s `symbols_by_path`), so it tracks the live buffer rather than
the last save. Handler bodies live in `outline.impl.jac`."""

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

def:pub app(path: str, symbols: list[dict[str, any]], onOpenLocation: any, cursorLine: int, cursorColumn: int) -> JsxElement {
    has expanded: dict[str, bool] = {};

    def toggle_symbol(id: str) -> None;

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
        </div>
        <div style={{"flex": "1", "overflow": "auto"}}>
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    No symbols in this file.
                </div>
            ) if (path != "" and len(symbols) == 0) else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    Open a file to see its outline.
                </div>
            ) if path == "" else None}
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
