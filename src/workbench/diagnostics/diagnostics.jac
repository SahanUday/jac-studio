"""Diagnostic: the data-model half of VS Code's Problems panel (the `markers` contrib in
`docs/vscode-complete-triage.md`), staged in Phase 3 per `docs/roadmap.md` so Phase 4's task-runner
and problem-matcher work, and later language-intelligence providers, have somewhere to write to
from day one -- **no producer exists yet**; nothing in this phase calls `add_diagnostic`.

Follows `docs/architecture.md`'s data model verbatim: a `Diagnostic` is a `node`, reached from the
`File` node it's about via a `Reports` edge (`File --Reports--> Diagnostic`), the same
node-per-domain-entity shape `workspace_service.jac`'s `Workspace/Folder/File` and
`command_registry.jac`'s `Command` already use -- persistence-by-reachability for free, no separate
save/load path to write.

**Diagnostics attach only to a `File` node already reachable via `workspace_service.jac`'s lazy
scan** (`get_file_node_by_path`) -- a path that hasn't been expanded into the tree yet has no node
to attach to. `add_diagnostic` reports whether it found one rather than silently minting a detached
`File` node no UI would ever traverse to; a real Phase 4 producer is expected to open or otherwise
reach a file (which scans its parent folder as a side effect) before reporting diagnostics on it.

`severity` is a plain string (`"error" | "warning" | "info" | "hint"`, matching upstream's
`vscode.DiagnosticSeverity` names) rather than an enum -- nothing here validates or branches on it
yet (no Problems panel to sort/group by it), so an enum would be machinery with no current
consumer; promote it once a real UI reads this field.

**A real producer landed (2026-08-31, `docs/roadmap.md` Phase 4's task-runner bullet)**:
`task_service.jac`'s problem matchers are the first caller of `add_diagnostic`. That surfaced a real
need this Phase-3 version didn't have yet -- a Problems panel showing diagnostics across the whole
workspace, not one already-known file at a time -- so `_diagnostic_paths` (a `jid(root)`-keyed
`dict[str, set[str]]`, following the same service-registry caching discipline
`jac-studio-architecture` requires for anything cached off `root`) tracks which paths currently
have at least one attached diagnostic, and `list_all_diagnostics` iterates just that small tracked
set rather than a broader graph walk of every `File` node ever scanned -- correct because a path
only ever enters the set via this same module's own `add_diagnostic`, so anything with a live
`Reports` edge is guaranteed to be in it (and `clear_diagnostics` removes it the moment that's no
longer true)."""

import from src.workbench.workspace.workspace_service { get_file_node_by_path }

node Diagnostic {
    has message: str;
    has severity: str = "error";
    has line: int = 1;
    has column: int = 1;
    has source: str = "";
}

edge Reports {}

glob _diagnostic_paths: dict[str, set[str]] = {};

def:pub _reset_diagnostic_tracking_for_tests {
    _diagnostic_paths.clear();
}

"""Returns `False` (and attaches nothing) when `path` has no `File` node yet -- see the module
docstring for why this doesn't fall back to creating one."""
def:pub add_diagnostic(path: str, message: str, severity: str, line: int, column: int, source: str) -> bool {
    file = get_file_node_by_path(path);
    if file is None {
        return False;
    }
    file +>:Reports():+> Diagnostic(message=message, severity=severity, line=line, column=column, source=source);
    key = jid(root);
    if key not in _diagnostic_paths {
        _diagnostic_paths[key] = set();
    }
    _diagnostic_paths[key].add(path);
    return True;
}

def:pub list_diagnostics(path: str) -> list[dict[str, any]] {
    file = get_file_node_by_path(path);
    if file is None {
        return [];
    }
    diags = [file->:Reports:->[?:Diagnostic]];
    return [
        {"message": d.message, "severity": d.severity, "line": d.line, "column": d.column, "source": d.source}
        for d in diags
    ];
}

"""Detaches every `Reports` edge from `path`'s `File` node. Deletes the edge only, matching
`workspace_service.jac`'s own accepted trade-off for graph cleanup in a local, single-user dev
tool (`get_or_create_workspace`'s docstring) -- the now-unreachable `Diagnostic` nodes are left as
graph garbage rather than walked and `del`-ed individually."""
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

"""Every diagnostic currently attached anywhere in the workspace, each entry carrying its own
`path` (unlike `list_diagnostics`, which is scoped to one already-known file) -- the Problems
panel's one data source."""
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
