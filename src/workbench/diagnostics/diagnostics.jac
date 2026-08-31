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
set rather than a broader graph walk of every `File` node ever scanned.

**`list_diagnostics` filters by `batch`, a field on `Diagnostic` itself, never an in-memory index --
two live-caught findings, not one, before landing here.** The first version's `clear_diagnostics`
just detached every `Reports` edge (`del e`) and read `[file->:Reports:->[?:Diagnostic]]` fresh on
every `list_diagnostics` call, the same shape `workspace_service.jac`'s `rename_path`/`delete_path`
already needed a fix for -- and hit the *identical*, already-documented gap
(`2026-08-28-edge-deletion-not-committed-across-real-http-requests`): confirmed live by running the
same task twice over two separate real HTTP requests and watching the diagnostic count for one file
grow by the same batch size on *every* run (3, then 6 -- never reset back to 3).

**A second attempt -- an in-memory `_latest_jids` index (`jid(root) -> path -> list[Diagnostic
jid]`) that `list_diagnostics` filtered its graph read against, `add_diagnostic` appending to it and
`clear_diagnostics` resetting it -- also failed the identical live repro, still landing on 6, not
3.** Unlike `_cached_workspace_jid` (confirmed genuinely invisible across a cross-module call in the
already-documented finding), `_diagnostic_paths` -- the *same* `jid(root)`-keyed shape, mutated by
the same cross-module caller (`task_service.jac`) -- demonstrably *did* stay visible across those
same separate requests (`list_all_diagnostics` correctly found the touched path every time). So this
isn't the earlier bug recurring; `_latest_jids` specifically failed to reflect a `clear_diagnostics`
reset across requests for a reason not fully isolated -- logged as its own open question, not
conflated with the earlier one.

**The actual fix carries the "current batch" marker on the `Diagnostic` node itself
(`has batch: float`), not in any in-memory structure at all.** `task_service.jac`'s `run_task`
generates one `time.time()` value per run and stamps every diagnostic from that run with it;
`list_diagnostics` reads every `Reports`-connected `Diagnostic` fresh (never trusting any cache,
in-memory or otherwise) and keeps only the ones whose `batch` equals the *maximum* `batch` among
them -- a stale diagnostic from an earlier run always has a strictly smaller `batch` than a fresh
one, so it's mechanically filtered out regardless of whether `clear_diagnostics`'s own `del e` on
its `Reports` edge ever actually took effect. This is the only genuinely *graph-only* fix tried --
no glob dict of any shape sits between a write and the next read, so there's no cross-request
visibility question left to have. Verified against the identical repro (`jac browse`, two separate
real HTTP requests running the same task): stayed at exactly 3 diagnostics, not 6, after the second
run. `clear_diagnostics`'s `del e` is kept as a best-effort graph-hygiene step (bounding how much
stale-batch garbage accumulates over a long session, the same "accept it as unreachable-or-not
graph garbage either way" trade-off `workspace_service.jac` already makes elsewhere) -- but nothing
here depends on it succeeding anymore."""

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

"""Returns `False` (and attaches nothing) when `path` has no `File` node yet -- see the module
docstring for why this doesn't fall back to creating one. `batch` should be the same value for
every diagnostic a single producer run reports (`task_service.jac`'s `run_task` generates one
`time.time()` per run) -- see the module docstring for why this is what `list_diagnostics` uses to
tell a fresh run's diagnostics apart from a stale, no-longer-relevant previous run's."""
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

"""Reads `path`'s `Reports` edges fresh from the graph on every call and keeps only the ones
carrying the *maximum* `batch` value among them -- see the module docstring for why this, not an
in-memory index of any shape, is what actually makes a stale previous run's diagnostics stop
showing up."""
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

"""Detaches every `Reports` edge from `path`'s `File` node -- best-effort graph hygiene only (see
the module docstring for why this is no longer load-bearing for correctness): a stale diagnostic
whose edge fails to detach is still correctly excluded from `list_diagnostics` by its own `batch`
field being older than whatever the next run stamps."""
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
