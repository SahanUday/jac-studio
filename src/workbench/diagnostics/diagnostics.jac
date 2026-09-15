"""Problems-panel data model: `File --Reports--> Diagnostic`, attached only to a `File` node already
reachable via `workspace_service.jac`'s lazy scan.

Staleness is filtered by the `batch` field, not by edge deletion: edge deletion does not commit
across separate real HTTP requests (`2026-08-28-edge-deletion-not-committed-across-real-http-requests`)."""

import from src.workbench.workspace.workspace_service { get_file_node_by_path }

node Diagnostic {
    has message: str;
    has severity: str = "error";
    has line: int = 1;
    has column: int = 1;
    has source: str = "";
    has batch: float = 0.0;
}

edge Reports {}

glob _diagnostic_paths: dict[str, set[str]] = {};

def:pub _reset_diagnostic_tracking_for_tests {
    _diagnostic_paths.clear();
}

"""Returns `False` when `path` has no `File` node yet; `batch` must be one shared value per producer run."""
def:pub add_diagnostic(path: str, message: str, severity: str, line: int, column: int, source: str, batch: float) -> bool {
    file = get_file_node_by_path(path);
    if file is None {
        return False;
    }
    file +>:Reports():+> Diagnostic(message=message, severity=severity, line=line, column=column, source=source, batch=batch);
    key = jid(root);
    if key not in _diagnostic_paths {
        _diagnostic_paths[key] = set();
    }
    _diagnostic_paths[key].add(path);
    return True;
}

"""Reads the `Reports` edges fresh and keeps only the highest `batch`, so stale runs drop out."""
def:pub list_diagnostics(path: str) -> list[dict[str, any]] {
    file = get_file_node_by_path(path);
    if file is None {
        return [];
    }
    diags = [file->:Reports:->[?:Diagnostic]];
    if len(diags) == 0 {
        return [];
    }
    latest_batch = max([d.batch for d in diags]);
    return [
        {"message": d.message, "severity": d.severity, "line": d.line, "column": d.column, "source": d.source}
        for d in diags
        if d.batch == latest_batch
    ];
}

"""Best-effort graph hygiene only -- `batch` filtering, not this detach, is what excludes stale rows."""
def:pub clear_diagnostics(path: str) -> None {
    file = get_file_node_by_path(path);
    if file is None {
        return;
    }
    for e in [edge file ->:Reports:->] {
        del e;
    }
    key = jid(root);
    if key in _diagnostic_paths {
        _diagnostic_paths[key].discard(path);
    }
}

"""Every attached diagnostic in the workspace, each entry carrying its own `path`."""
def:pub list_all_diagnostics -> list[dict[str, any]] {
    key = jid(root);
    paths = _diagnostic_paths.get(key, set());
    results = [];
    for path in paths {
        for d in list_diagnostics(path) {
            diag_entry = {**d};
            diag_entry["path"] = path;
            results.append(diag_entry);
        }
    }
    return results;
}
