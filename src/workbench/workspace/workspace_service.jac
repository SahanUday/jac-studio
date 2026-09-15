"""Workspace-as-graph: `Workspace --Contains--> Folder --Contains--> File`, scanned lazily one
directory level at a time (an eager scan of a real project costs ~3s:
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale`). Client-facing functions return
plain dicts; nodes stay server-side. Cache the jid and re-resolve via `jobj()` immediately before
any field mutation (`2026-08-28-field-mutation-on-cached-node-not-persisted`)."""

import os;
import shutil;
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

glob _cached_workspace_jid: dict[str, str] = {};
glob _path_index: dict[str, dict[str, (Workspace | Folder | File)]] = {};

"""Only narrows the check-then-create race -- a `def:pub`'s commit happens after this lock releases,
so `list_children_by_path`'s de-dup by path is the actual guarantee."""
glob _workspace_lock: threading.Lock = threading.Lock();

def:pub _reset_workspace_cache_for_tests {
    _cached_workspace_jid.clear();
    _path_index.clear();
}

"""Switching roots detaches the old `Contains` subtree and leaves it as unreachable graph garbage --
a recursive delete isn't worth it for a local single-user tool. `_path_index` is only reset when the
root actually changed: every SCM call routes through here, and resetting unconditionally wiped the
tree cache mid-session (`2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss`)."""
def get_or_create_workspace(root_path: str) -> Workspace {
    with _workspace_lock {
        key = jid(root);
        if key in _cached_workspace_jid {
            ws = jobj(_cached_workspace_jid[key]) as Workspace;
        } else {
            existing = [root-->[?:Workspace]];
            ws = existing[0] if existing else root ++> Workspace(root_path=root_path);
            _cached_workspace_jid[key] = jid(ws);
        }
        if ws.root_path != root_path {
            for e in [edge ws ->:Contains:->] {
                del e;
            }
            ws.root_path = root_path;
            ws.scanned = False;
            _path_index[key] = {ws.root_path: ws};
        } elif key not in _path_index {
            _path_index[key] = {ws.root_path: ws};
        }
        return ws;
    }
}

"""Materializes one directory level under `parent`, idempotent via the `scanned` flag. Deliberately
has no self-heal for a `scanned=True`-but-edgeless folder: three attempts each passed `jac check`
and `jac test` then failed differently live
(`2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss`)."""
def _ensure_scanned(parent: (Workspace | Folder)) -> None {
    with _workspace_lock {
        if parent.scanned {
            return;
        }
        fresh_parent = jobj(jid(parent)) as (Workspace | Folder);
        dir_path = fresh_parent.root_path if isinstance(fresh_parent, Workspace) else fresh_parent.path;
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
            fresh_parent +>:Contains():+> child;
        }
        fresh_parent.scanned = True;
    }
}

"""Resolves an already-scanned path to its `File` node, or `None` -- never scans on the caller's behalf."""
def:pub get_file_node_by_path(path: str) -> File | None {
    key = jid(root);
    if key not in _path_index or path not in _path_index[key] {
        return None;
    }
    found = _path_index[key][path];
    return found if isinstance(found, File) else None;
}

def:pub open_workspace(root_path: str) -> dict[str, str] {
    ws = get_or_create_workspace(root_path);
    return {"root_path": ws.root_path, "name": os.path.basename(ws.root_path.rstrip("/")) or ws.root_path};
}

"""Session restore. Goes through `get_or_create_workspace` rather than reading the node directly so
`_path_index` gets populated; passing back the node's own `root_path` never triggers a rescan."""
def:pub get_current_workspace -> dict[str, str] | None {
    existing = [root-->[?:Workspace]];
    if len(existing) == 0 {
        return None;
    }
    ws = get_or_create_workspace(existing[0].root_path);
    return {"root_path": ws.root_path, "name": os.path.basename(ws.root_path.rstrip("/")) or ws.root_path};
}

"""Children of `parent_path`, folders first then alphabetical -- called on every file-tree expand.

The `os.path.exists` filter is load-bearing, not defensive: edge deletion does not reliably commit
across separate real HTTP requests, so deleted and renamed-away nodes keep reappearing
(`2026-08-28-edge-deletion-not-committed-across-real-http-requests`). The filesystem is authoritative
here, and the path de-dup likewise guarantees the display regardless of what the graph holds."""
def:pub list_children_by_path(parent_path: str) -> list[dict] {
    key = jid(root);
    if key not in _path_index or parent_path not in _path_index[key] {
        return [];
    }
    parent = _path_index[key][parent_path] as (Workspace | Folder);
    _ensure_scanned(parent);

    children = [parent->:Contains:->];
    seen_paths: set[str] = set();
    deduped_children = [];
    for child in children {
        if child.path in seen_paths or not os.path.exists(child.path) {
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

"""Flat file list for Quick Open. Bypasses the graph entirely -- walking the whole tree into nodes
would pay the ~3s eager-scan cost this module exists to avoid -- and prunes `dirnames` in place so
`os.walk` never descends into `node_modules`.

Falls back to a graph query on a cache miss rather than returning `[]`: a `glob` cache can read back
empty when reached via a cross-module `def:pub` call
(`2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`)."""
def:pub list_all_files -> list[dict[str, str]] {
    key = jid(root);
    if key in _cached_workspace_jid {
        ws = jobj(_cached_workspace_jid[key]) as Workspace;
    } else {
        existing = [root-->[?:Workspace]];
        if len(existing) == 0 {
            return [];
        }
        ws = existing[0];
        _cached_workspace_jid[key] = jid(ws);
    }
    if ws.root_path == "" or not os.path.isdir(ws.root_path) {
        return [];
    }

    results = [];
    for (dirpath, dirnames, filenames) in os.walk(ws.root_path) {
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_EXCLUDED_DIRS];
        for name in sorted(filenames) {
            results.append({"name": name, "path": os.path.join(dirpath, name)});
        }
    }
    return results;
}

"""The context menu's write operations all require their target path to already be in `_path_index`.
Edge creation is safe through a cached node, so only the functions that mutate fields or detach
edges re-resolve via `jobj(jid(...))` first."""
def:pub create_file(parent_path: str, name: str) -> dict[str, any] {
    key = jid(root);
    if key not in _path_index or parent_path not in _path_index[key] {
        raise ValueError("Unknown parent path: " + parent_path);
    }
    parent = _path_index[key][parent_path] as (Workspace | Folder);
    _ensure_scanned(parent);
    new_path = os.path.join(parent_path, name);
    if os.path.exists(new_path) {
        raise ValueError("Already exists: " + new_path);
    }
    open(new_path, "w").close();
    child = File(name=name, path=new_path);
    parent +>:Contains():+> child;
    _path_index[key][new_path] = child;
    return {"name": name, "path": new_path, "is_dir": False};
}

def:pub create_folder(parent_path: str, name: str) -> dict[str, any] {
    key = jid(root);
    if key not in _path_index or parent_path not in _path_index[key] {
        raise ValueError("Unknown parent path: " + parent_path);
    }
    parent = _path_index[key][parent_path] as (Workspace | Folder);
    _ensure_scanned(parent);
    new_path = os.path.join(parent_path, name);
    if os.path.exists(new_path) {
        raise ValueError("Already exists: " + new_path);
    }
    os.makedirs(new_path);
    # a brand-new folder is known to be empty -- scanned=True skips a pointless first listdir
    child = Folder(name=name, path=new_path, scanned=True);
    parent +>:Contains():+> child;
    _path_index[key][new_path] = child;
    return {"name": name, "path": new_path, "is_dir": True};
}

"""Creates a new node and detaches the old one instead of mutating `name`/`path` in place: the
mutate-in-place version passed `jac test` but duplicated the entry over real HTTP
(`2026-08-28-rename-field-mutation-duplicates-node-over-real-http`). Descendants are not
cascade-rewritten; the new node starts unscanned and re-derives paths on the next expand.

The stale `old_path` key is deliberately left in `_path_index` -- `del`ing the last reference to a
still-edge-attached node corrupts that edge's reachability
(`2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability`); `delete_path`'s own `del` is
safe only because its node is fully detached first."""
def:pub rename_path(old_path: str, new_name: str) -> dict[str, any] {
    key = jid(root);
    if key not in _path_index or old_path not in _path_index[key] {
        raise ValueError("Unknown path: " + old_path);
    }
    cached = _path_index[key][old_path];
    new_path = os.path.join(os.path.dirname(old_path), new_name);
    if os.path.exists(new_path) {
        raise ValueError("Already exists: " + new_path);
    }
    os.rename(old_path, new_path);

    old_node = jobj(jid(cached)) as (Folder | File);
    is_dir = isinstance(old_node, Folder);
    parents = [old_node <-:Contains:<-];
    new_node = Folder(name=new_name, path=new_path) if is_dir else File(name=new_name, path=new_path);
    if len(parents) > 0 {
        parents[0] +>:Contains():+> new_node;
    }
    for e in [edge old_node ->:Contains:->] {
        del e;
    }
    for e in [edge old_node <-:Contains:<-] {
        del e;
    }

    _path_index[key][new_path] = new_node;
    return {"name": new_name, "path": new_path, "is_dir": is_dir};
}

"""Scans top-down toward `path` so a file the Explorer never expanded still resolves to a `File`
node. Returns `None` for a path outside the workspace, the root itself, or one not on disk.

Reads each level off the `Contains` edge, not `_path_index`: `_ensure_scanned` creates nodes without
indexing them, so an index lookup finds nothing it just scanned. Falls back to a graph query on a
cache miss for the same reason `list_all_files` does
(`2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`)."""
def:pub ensure_path_reachable(path: str) -> File | None {
    key = jid(root);
    if key in _cached_workspace_jid {
        ws = jobj(_cached_workspace_jid[key]) as Workspace;
    } else {
        existing = [root-->[?:Workspace]];
        if len(existing) == 0 {
            return None;
        }
        ws = existing[0];
        _cached_workspace_jid[key] = jid(ws);
    }
    if ws.root_path == "" or not os.path.isdir(ws.root_path) {
        return None;
    }
    if key not in _path_index {
        _path_index[key] = {};
    }
    norm_path = os.path.normpath(path);
    root_norm = os.path.normpath(ws.root_path);
    if norm_path != root_norm and not norm_path.startswith(root_norm + os.sep) {
        return None;
    }
    if norm_path == root_norm {
        return None;
    }
    rel = os.path.relpath(norm_path, root_norm);
    parts = rel.split(os.sep);
    current: (Workspace | Folder) = ws;
    for idx in range(len(parts)) {
        _ensure_scanned(current);
        children = [current->:Contains:->];
        matches = [c for c in children if c.name == parts[idx] and os.path.exists(c.path)];
        if len(matches) == 0 {
            return None;
        }
        found = matches[0];
        _path_index[key][found.path] = found;
        if idx == len(parts) - 1 {
            return (found as File) if isinstance(found, File) else None;
        }
        if not isinstance(found, Folder) {
            return None;
        }
        current = found;
    }
    return None;
}

def:pub delete_path(path: str) -> None {
    key = jid(root);
    if key not in _path_index or path not in _path_index[key] {
        return;
    }
    cached = _path_index[key][path];
    fresh = jobj(jid(cached)) as (Folder | File);
    if isinstance(fresh, Folder) {
        shutil.rmtree(path);
    } else {
        os.remove(path);
    }
    for e in [edge fresh ->:Contains:->] {
        del e;
    }
    for e in [edge fresh <-:Contains:<-] {
        del e;
    }
    del _path_index[key][path];
}
