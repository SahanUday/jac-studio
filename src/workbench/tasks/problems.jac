"""Problems panel: the bottom-panel read side of `diagnostics.jac`'s `Diagnostic` node type,
grouped by file like `search.jac`'s results.
Polls only while active (`useEffect([active])`, 5s interval) since a task run has no direct signal
to this component otherwise. Clicking a row reuses `workbench.jac`'s `open_search_result`.
"""

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
