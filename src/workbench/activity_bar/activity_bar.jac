"""ActivityBar: the icon rail switching sidebar views. See ADR 0040.
Purely presentational (`activeViewId`/`onSelectView`), no own state, no `.impl.jac`.
`position: relative; zIndex: 20` is required: the vendored `sidebar.jac` wrapper is
`position: fixed; z-index: 10` and otherwise steals clicks in this column (same root cause
as `workbench.jac`'s bottom-panel overlap fix). Colors are hardcoded hex, not theme variables."""

glob VIEWS: list[dict[str, str]] = [
    {"id": "explorer", "title": "Explorer", "icon": "files"},
    {"id": "search", "title": "Search", "icon": "search"},
    {"id": "scm", "title": "Source Control", "icon": "source-control"},
    {"id": "outline", "title": "Outline", "icon": "list-tree"},
    {"id": "ai_chat", "title": "AI Chat", "icon": "sparkle"}
];

def:pub app(activeViewId: str, onSelectView: any) -> JsxElement {
    <div
        role="tablist"
        aria-label="Activity Bar"
        aria-orientation="vertical"
        style={{
            "display": "flex",
            "flexDirection": "column",
            "width": "48px",
            "flexShrink": "0",
            "background": "#191A1B",
            "borderRight": "1px solid #2A2B2C",
            "position": "relative",
            "zIndex": "20"
        }}
    >
        {[
            <button
                key={v["id"]}
                role="tab"
                aria-selected={v["id"] == activeViewId}
                title={v["title"]}
                aria-label={v["title"]}
                onClick={lambda (e: any) { onSelectView(v["id"]); }}
                style={{
                    "width": "48px",
                    "height": "48px",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "center",
                    "background": "#313233" if v["id"] == activeViewId else "transparent",
                    "border": "none",
                    "borderLeft": "2px solid " + ("#bfbfbf" if v["id"] == activeViewId else "transparent"),
                    "cursor": "pointer",
                    "padding": "0"
                }}
            >
                <span
                    className={"codicon codicon-" + v["icon"]}
                    style={{
                        "fontSize": "24px",
                        "color": "#bfbfbf" if v["id"] == activeViewId else "#8C8C8C"
                    }}
                />
            </button>
            for v in VIEWS
        ]}
    </div>
}
