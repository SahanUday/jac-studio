"""Search-in-files sidebar view. Submits on Enter/click, not live-as-you-type, since every
keystroke would mean a fresh server-side workspace scan (`search_service.jac`), unlike Quick Open's
client-side filter. Results group by file, matches indented beneath, mirroring
`search_service.jac`'s response shape.
"""

def:pub app(onOpenResult: any) -> JsxElement {
    has query: str = "";
    has results: list[dict[str, any]] = [];
    has searching: bool = False;
    has searched: bool = False;

    async def handle_submit(e: any) -> None;
    def handle_query_change(e: any) -> None;

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%"}}>
        <form onSubmit={handle_submit} style={{"padding": "0.5rem", "borderBottom": "1px solid #2A2B2C"}}>
            <input
                type="text"
                value={query}
                onChange={handle_query_change}
                placeholder="Search in files..."
                aria-label="Search in files"
                style={{
                    "width": "100%",
                    "background": "#191A1B",
                    "color": "#CCCCCC",
                    "border": "1px solid #2A2B2C",
                    "borderRadius": "4px",
                    "fontSize": "12px",
                    "padding": "0.35rem 0.5rem",
                    "boxSizing": "border-box"
                }}
            />
        </form>
        <div style={{"flex": "1", "overflow": "auto"}}>
            {(<div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>Searching...</div>) if searching else None}
            {(<div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>No results found.</div>) if (not searching and searched and len(results) == 0) else None}
            {[
                <div key={r["path"]}>
                    <div style={{"display": "flex", "alignItems": "center", "gap": "0.3rem", "padding": "0.3rem 0.5rem", "fontSize": "12px", "color": "#CCCCCC", "fontFamily": "system-ui, sans-serif"}}>
                        <span className="codicon codicon-file" style={{"fontSize": "13px", "opacity": "0.8"}} />
                        <span>{r["name"]}</span>
                        <span style={{"color": "#8C8C8C", "fontSize": "11px"}}>{len(r["matches"])}</span>
                    </div>
                    {[
                        <div
                            key={str(m["line"]) + ":" + str(m["column"])}
                            role="button"
                            tabIndex={0}
                            onClick={lambda (e: any) { onOpenResult(r["path"], r["name"], m["line"], m["column"]); }}
                            style={{
                                "padding": "0.15rem 0.5rem 0.15rem 1.75rem",
                                "fontSize": "12px",
                                "fontFamily": "monospace",
                                "color": "#8C8C8C",
                                "cursor": "pointer",
                                "whiteSpace": "pre",
                                "overflow": "hidden",
                                "textOverflow": "ellipsis"
                            }}
                        >
                            <span style={{"color": "#5A5A5A", "marginRight": "0.5rem"}}>{m["line"]}</span>
                            {m["preview"]}
                        </div>
                        for m in r["matches"]
                    ]}
                </div>
                for r in results
            ]}
        </div>
    </div>
}
