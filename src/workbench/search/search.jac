"""Search: Phase 4's search-in-files sidebar view (`docs/roadmap.md`), the second real entry in
`activity_bar.jac`'s `VIEWS` -- the exact addition that module's own docstring anticipated ("Once
Phase 4 adds a second real view... that's a one-entry-plus-one-branch addition").

**Submit on Enter/click, not live-as-you-type.** Unlike Quick Open's client-side fuzzy filter over
an already-fetched file list, every keystroke here would mean a fresh server-side workspace-wide
content scan (`search_service.jac` reads every candidate file's bytes) -- genuinely expensive to
run per keystroke, unlike a client-side filter. An explicit submit (matching real VS Code's own
"press Enter to search," not its live-refine-after-first-search behavior) is the honest MVP scope
here, not a corner cut silently -- a debounced live search is a legitimate future widen once this
ships and the cost profile is worth revisiting.

**Results are grouped by file, matches indented beneath**, mirroring `search_service.jac`'s own
response shape (`{"path", "name", "matches": [{"line", "column", "preview"}]}`) directly rather
than flattening it -- the natural read of "which files, and where in each" a grep-style result set
needs.

**Clicking a match reports `(path, name, line, column)` up to `workbench.jac`'s `open_search_result`**
-- not just `(path, name)` like `FileTreeApp`/`QuickOpenApp`'s `onOpenFile` -- because a search
result's whole point is "jump to this specific line," not just "open this file." See
`workbench.jac`'s own docstring for how it reuses the exact session-restore cursor-seeding
mechanism (`cursor_positions` assigned before the tab exists) rather than inventing a new one.
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
