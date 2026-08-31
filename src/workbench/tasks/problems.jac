"""Problems: the Problems panel (`workbench/contrib/markers`, `docs/vscode-complete-triage.md`'s
`markers` row) -- the read side of `diagnostics.jac`'s `Diagnostic` node type staged in Phase 3, now
that Phase 4's task runner is the first real producer.

**A third bottom-panel tab, next to Terminal and Output** -- not a sidebar view. Real VS Code's
Problems panel lives in the same bottom-panel area as its own Terminal/Output, and
`workbench.jac`'s `_toggle_panel`/`active_bottom_panel` mechanism (generalized in Phase 4's Output
bullet specifically so a third tab would be a one-branch addition, not new plumbing) already
anticipated exactly this -- see that module's own docstring.

**Polls only while active, same as `output.jac`** -- mounted once, hidden via CSS, refetching
`list_all_diagnostics()` via `useEffect([active])` plus a light interval while visible so a task run
triggered from the picker (which this component has no direct signal from) still shows up without
requiring a manual reopen. Diagnostics don't change anywhere near output-log frequency, so the
interval is longer than `output.jac`'s (5s here vs. 2s there) -- there's no benefit to polling
project-wide diagnostics as aggressively as a live log tail.

**Grouped by file, matching `search.jac`'s own "which files, and where in each" shape** -- a
Problems list is naturally the same shape as a search-results list (a set of files, each with one
or more located hits), so this reuses that rendering pattern rather than inventing a flat sorted-by-
severity table VS Code's own richer Problems view has room for.

**Clicking a row reuses `open_search_result`, not a new handler** -- `workbench.jac`'s
`open_search_result(path, name, line, column)` already does exactly "open or activate this file's
tab and seed the cursor at a specific line/column," the same thing clicking a diagnostic needs; a
`Diagnostic`'s own `path`/`line`/`column` fields map onto that signature directly, so this component
takes an `onOpenLocation` prop that's really that same method, not a new one."""

import from "react" { useEffect }
import from src.workbench.diagnostics.diagnostics { list_all_diagnostics }
import from src.workbench.file_icons.file_icons { file_icon_class }

def _severity_color(severity: str) -> str {
    if severity == "error" {
        return "#f48771";
    }
    if severity == "warning" {
        return "#e2c08d";
    }
    return "#8C8C8C";
}

def _severity_icon(severity: str) -> str {
    if severity == "error" {
        return "codicon-error";
    }
    if severity == "warning" {
        return "codicon-warning";
    }
    return "codicon-info";
}

def:pub app(active: bool, onOpenLocation: any) -> JsxElement {
    has diagnostics: list[dict[str, any]] = [];

    async def refresh -> None;

    useEffect(lambda {
        if not active {
            return lambda {};
        }
        refresh();
        interval_id = setInterval(lambda { refresh(); }, 5000);
        return lambda { clearInterval(interval_id); };
    }, [active]);

    by_file: dict[str, list[dict[str, any]]] = {};
    order: list[str] = [];
    for d in diagnostics {
        path = d["path"];
        if path not in by_file {
            by_file[path] = [];
            order.append(path);
        }
        by_file[path].append(d);
    }

    <div style={{"height": "100%", "overflow": "auto", "fontFamily": "system-ui, sans-serif"}}>
        {(
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C"}}>
                No problems have been reported.
            </div>
        ) if len(diagnostics) == 0 else None}
        {[
            <div key={path}>
                <div style={{"display": "flex", "alignItems": "center", "gap": "0.3rem", "padding": "0.3rem 0.5rem", "fontSize": "12px", "color": "#CCCCCC"}}>
                    <span className={"codicon " + file_icon_class(path.split("/")[-1], False, False)} style={{"fontSize": "13px", "opacity": "0.8"}} />
                    <span>{path.split("/")[-1]}</span>
                    <span style={{"color": "#8C8C8C", "fontSize": "11px"}}>{path}</span>
                </div>
                {[
                    <div
                        key={str(d["line"]) + ":" + str(d["column"]) + ":" + d["message"]}
                        role="button"
                        tabIndex={0}
                        onClick={lambda (e: any) { onOpenLocation(path, path.split("/")[-1], d["line"], d["column"]); }}
                        style={{
                            "display": "flex",
                            "alignItems": "flex-start",
                            "gap": "0.4rem",
                            "padding": "0.15rem 0.5rem 0.15rem 1.75rem",
                            "fontSize": "12px",
                            "cursor": "pointer"
                        }}
                    >
                        <span className={"codicon " + _severity_icon(d["severity"])} style={{"fontSize": "13px", "color": _severity_color(d["severity"]), "flexShrink": "0", "marginTop": "0.1rem"}} />
                        <span style={{"color": "#CCCCCC"}}>{d["message"]}</span>
                        <span style={{"color": "#5A5A5A", "flexShrink": "0"}}>{"[" + d["source"] + "] " + str(d["line"]) + ":" + str(d["column"])}</span>
                    </div>
                    for d in by_file[path]
                ]}
            </div>
            for path in order
        ]}
    </div>
}
