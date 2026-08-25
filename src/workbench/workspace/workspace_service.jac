"""Workspace-as-graph, production version: `Workspace --Contains--> Folder --Contains--> File`
per `docs/architecture.md`'s data model, promoted from `internal/workspace-graph-spike/` once that
spike validated the shape at real scale (2,974 nodes) -- see the spike's README and tracker entry
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale` for why this version scans lazily,
one directory level at a time, instead of the spike's recursive eager scan: eagerly building and
traversing a real-sized project took ~3 seconds combined, too slow for a file tree that needs to
feel instant on open.

`Workspace` is a real graph `node` (not a cached `obj`) for the same reason the spike's docstring
gives: workspace state needs to survive a restart and be reached by graph traversal, not just
process-lifetime lookup.

Client-facing functions (`open_workspace`, `list_children_by_path`) return plain dicts/lists, not
node objects, matching `document_service.jac`'s precedent -- nodes stay server-side.
"""

import os;
import threading;

node Workspace {
    has root_path: str;
    has scanned: bool = False;
}

node Folder {
    has name: str, path: str;
    has scanned: bool = False;
}

node File {
    has name: str, path: str;
}

edge Contains {}

glob DEFAULT_EXCLUDED_DIRS: list[str] = [
    "node_modules", ".git", ".jac", "dist", "__pycache__", ".venv", "venv"
];

glob _cached_workspaces: dict[str, Workspace] = {};
glob _path_index: dict[str, dict[str, (Workspace | Folder)]] = {};

"""Narrows, but does not close, the check-existing-else-create race in this module
(`get_or_create_workspace`'s creation branch, `_ensure_scanned`'s check-then-scan-then-flag).
**Confirmed insufficient by itself, live** (see `command_registry.jac`'s `_registry_lock` docstring
for the full root-cause writeup): `asyncio.to_thread` genuinely serializes the Python function body
across concurrent calls, but the actual Postgres commit for a `def:pub` happens *after* the
function returns, in server-side `_finalize_call_response` -- this lock releases before that
commit, so a second call can start executing after the first one's Python code finished and still
read a pre-commit view of the graph. jaseci's documented `SERIALIZABLE`-transaction-plus-replay
protection for exactly this case doesn't currently fire either (`WriteConflict` is never raised in
the runtime, and `Session.commit`'s conflict recovery re-flushes the same writes rather than
re-running the check). Kept because it still narrows the race window for free, but the actual
guarantee against a user-visible duplicate is `list_children_by_path` de-duping its *return value*
by path (see there) -- the layer this module can control without reaching into unsupported jaseci
transaction internals. One process-wide lock, not per-parent: none of this is a hot path (one
`os.listdir` plus a handful of node creations, at most once per folder), so serializing globally is
simpler than per-key lock bookkeeping and costs nothing observable."""
glob _workspace_lock: threading.Lock = threading.Lock();

def:pub _reset_workspace_cache_for_tests {
    _cached_workspaces.clear();
    _path_index.clear();
}

"""Caught live via real browser testing, not by inspection: this used to return an already-cached
workspace unconditionally, silently ignoring a *different* `root_path` on every call after the
first -- confirmed by requesting `.../src/workbench` and getting back `.../src` (whatever the
first-ever call in this root's lifetime had opened). Now detaches the stale `Contains` subtree
(old Folder/File nodes for the previous root, unreachable from `ws` once their edges are gone --
not `del`-ed outright, since a Folder's own nested children would need a recursive walk to clean up
too, and leaving them as unreachable graph garbage is a fine trade-off for a local, single-user dev
tool) and re-points `ws` at the newly requested path with a fresh `scanned=False`, so opening a
different folder actually re-scans it instead of silently continuing to show the old one."""
def get_or_create_workspace(root_path: str) -> Workspace {
    with _workspace_lock {
        key = jid(root);
        if key in _cached_workspaces {
            ws = _cached_workspaces[key];
        } else {
            existing = [root-->[?:Workspace]];
            ws = existing[0] if existing else root ++> Workspace(root_path=root_path);
            _cached_workspaces[key] = ws;
        }
        if ws.root_path != root_path {
            for e in [edge ws ->:Contains:->] {
                del e;
            }
            ws.root_path = root_path;
            ws.scanned = False;
        }
        _path_index[key] = {ws.root_path: ws};
        return ws;
    }
}

"""Materialize one directory level's worth of Folder/File children under `parent`, if it hasn't
been scanned yet. Idempotent per `parent` via the `scanned` flag, guarded by `_workspace_lock` so
the check-then-scan-then-flag sequence is atomic across concurrent calls (see `_workspace_lock`'s
own docstring) -- never re-reads the directory or duplicates children on repeat calls, which is
what makes lazy expand-on-demand safe to call on every UI expand click, including several
near-simultaneous ones."""
def _ensure_scanned(parent: (Workspace | Folder)) -> None {
    with _workspace_lock {
        if parent.scanned {
            return;
        }
        dir_path = parent.root_path if isinstance(parent, Workspace) else parent.path;
        entries = sorted(os.listdir(dir_path)) if os.path.isdir(dir_path) else [];
        for name in entries {
            if name in DEFAULT_EXCLUDED_DIRS {
                continue;
            }
            child_path = os.path.join(dir_path, name);
            child = (
                Folder(name=name, path=child_path)
                    if os.path.isdir(child_path)
                    else File(name=name, path=child_path)
            );
            parent +>:Contains():+> child;
        }
        parent.scanned = True;
    }
}

def:pub open_workspace(root_path: str) -> dict[str, str] {
    ws = get_or_create_workspace(root_path);
    return {"root_path": ws.root_path, "name": os.path.basename(ws.root_path.rstrip("/")) or ws.root_path};
}

"""The one function the file-tree UI calls on every expand click. Resolves `parent_path` against
the current user's workspace via `_path_index` (never a graph query -- see `jac-studio-architecture`
skill's service-registry caching rules), lazily scans it if needed, and returns its children as
plain dicts sorted folders-first then alphabetically, ready for the client to render.

De-dupes by `path` before returning -- `_workspace_lock` narrows but doesn't close the race that
can leave two `Folder`/`File` nodes for the same path (see its own docstring), so this is the
actual guarantee the file tree never shows a duplicate, regardless of what the graph underneath
ends up holding. Safe to keep just the first match: a duplicate here was always scanned from the
same real directory entry, so their fields are identical."""
def:pub list_children_by_path(parent_path: str) -> list[dict] {
    key = jid(root);
    if key not in _path_index or parent_path not in _path_index[key] {
        return [];
    }
    parent = _path_index[key][parent_path];
    _ensure_scanned(parent);

    children = [parent->:Contains:->];
    seen_paths: set[str] = set();
    deduped_children = [];
    for child in children {
        if child.path in seen_paths {
            continue;
        }
        seen_paths.add(child.path);
        deduped_children.append(child);
        _path_index[key][child.path] = child;
    }

    folders = sorted([c for c in deduped_children if isinstance(c, Folder)], key=lambda (c: (Folder | File)) { c.name; });
    files = sorted([c for c in deduped_children if isinstance(c, File)], key=lambda (c: (Folder | File)) { c.name; });
    ordered = folders + files;
    return [
        {"name": c.name, "path": c.path, "is_dir": isinstance(c, Folder)}
        for c in ordered
    ];
}
