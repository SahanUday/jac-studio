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

**Cache the jid, not the node, for anything a call site will *mutate* (2026-08-28).** A raw node
object reused across separate requests silently drops any `has`-field mutation made through it --
verified live against a real `jac run --serve --dev` restart, not just a page reload: opening a
*different* folder correctly updated `Workspace.root_path` in memory (this function's own return
value looked right for the rest of that process's life) but the mutation never reached the
database, so a later restart reverted back to whatever `root_path` was durably committed before.
Edge creation/traversal through that same kind of cached object is **not** affected -- verified
separately, `parent +>:Contains():+> child` below survives a real restart just fine -- so
`_path_index`'s cache of `Folder`/`File` objects for *reading* children is unaffected by this
finding and stays as-is. Only the two field mutations in this file (`get_or_create_workspace`'s
`root_path`/`scanned` reset, `_ensure_scanned`'s `scanned = True`) needed the fix: re-resolve via
`jobj(cached_jid)` (the `jac-sv-persistence` guide's own canonical "UPDATE" pattern) immediately
before mutating. See tracker entry `2026-08-28-field-mutation-on-cached-node-not-persisted` for the
full repro, and `settings_service.jac`'s docstring for where this was first found.
"""

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
    _cached_workspace_jid.clear();
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

"""Resolves an already-scanned path straight to its `File` node, for callers that need the node
itself rather than the plain-dict shape `list_children_by_path` returns -- `diagnostics.jac` is
the first such caller (`File --Reports--> Diagnostic` needs a real node to attach the edge to).
Returns `None` for a path that hasn't been scanned into the tree yet (nothing to resolve) or that
resolves to a `Folder` instead of a `File`; unlike `list_children_by_path`, this never scans on the
caller's behalf, since a diagnostics producer has no reason to trigger a directory listing as a
side effect of reporting on one specific file."""
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

"""The file tree's session-restore entry point (`docs/roadmap.md`'s Phase 3 workspace-state
bullet) -- returns the previously opened workspace, if any, re-running it through
`get_or_create_workspace` (not a bare read of the `Workspace` node) so `_path_index` is populated
the same way a fresh `open_workspace` call would populate it; `list_children_by_path` depends on
that index existing, restore or not. Passing the node's own `root_path` back into
`get_or_create_workspace` is a no-op past the identity check (`ws.root_path != root_path` is
false), so this never triggers a rescan of an already-scanned tree. Returns `None` when nothing
was ever opened in this root -- a fresh install, or one where the workspace tree was never used --
so `file_tree.jac` can fall back to its own "enter a folder path" empty state."""
def:pub get_current_workspace -> dict[str, str] | None {
    existing = [root-->[?:Workspace]];
    if len(existing) == 0 {
        return None;
    }
    ws = get_or_create_workspace(existing[0].root_path);
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
same real directory entry, so their fields are identical.

**Also filters out any child whose path no longer exists on disk (2026-08-28, the file-tree context
menu's rename/delete bullet) -- a real, load-bearing check, not defensive padding.** Found live,
not assumed: `rename_path`/`delete_path` both try to detach the old graph node's edges (`del e` on
an `[edge node ->:Contains:->]`/`<-:Contains:<-` query result), but this does **not** reliably take
effect across separate real HTTP requests, the same class of gap already documented for field
mutation (`2026-08-28-field-mutation-on-cached-node-not-persisted`) but for edge deletion instead --
confirmed live (`jac browse` against a real `jac run --serve --dev` process, not `jac test`, which
never crosses that boundary and so never caught it): deleting a file via the context menu removed it
from disk correctly but it kept reappearing in the next `list_children_by_path` call, and the exact
same graph-level `del e` code passed every `jac test` run in isolation. Rather than chase edge
deletion's reliability further, this filter makes the *read* path the actual source of truth against
the real filesystem, the same "guarantee the display is correct regardless of what the graph
underneath ends up holding" stance the de-dup step above already takes for a different failure mode.
`rename_path`/`delete_path` still attempt the edge cleanup (harmless best-effort, and matches the
existing "detach and let it become graph garbage" convention if it ever does take effect), but
nothing here depends on it succeeding anymore. See tracker entry
`2026-08-28-edge-deletion-not-committed-across-real-http-requests` for the full record."""
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

"""Quick Open's (`docs/roadmap.md` Phase 3) data source -- a flat list of every file under the
current workspace root, for client-side fuzzy filtering. Deliberately bypasses the
`Workspace`/`Folder`/`File` graph entirely rather than reusing `list_children_by_path`'s lazy
per-folder scan recursively: walking the whole tree into graph nodes just to list paths would pay
exactly the ~3-second-at-real-scale node-creation cost `docs/architecture.md`'s workspace section
already ruled out for the file tree itself (tracker entry
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale`). A plain `os.walk` has none of
that overhead -- it's a filesystem read, not a graph write -- so this stays a stateless, ungraphed
helper next to the graph-backed functions above, called fresh on every Quick Open, not cached.

Prunes `DEFAULT_EXCLUDED_DIRS` from `os.walk`'s own traversal (mutating `dirnames` in place, the
standard way to stop `os.walk` descending into a subtree) rather than filtering results
afterward -- the excluded directories are exactly the ones that would be enormous to walk
(`node_modules`), so skipping them during the walk, not after, is the difference between this
being fast and not."""
def:pub list_all_files -> list[dict[str, str]] {
    key = jid(root);
    if key not in _cached_workspace_jid {
        return [];
    }
    ws = jobj(_cached_workspace_jid[key]) as Workspace;
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

"""The file-tree context menu's (`docs/roadmap.md` Phase 3) write operations -- new file/folder,
rename, delete. All four require `parent_path`/`old_path`/`path` to already be a key in
`_path_index`, same precondition `list_children_by_path` enforces on `parent_path` -- a mutation
targeting a path the tree hasn't scanned into yet has nothing to attach to or resolve.

**Edge creation doesn't need the `jobj(jid(...))` re-resolve; field mutation does** -- the
distinction this module's own docstring already establishes. `create_file`/`create_folder` only
attach a new `Contains` edge, so the plain `_path_index`-cached `parent` reference is fine as-is.
`rename_path`/`delete_path` mutate an existing node's own `name`/`path` fields (or need a stable
identity to detach edges from), so both re-resolve via `jobj(jid(...))` first, matching
`_ensure_scanned`'s already-established pattern."""
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

"""Renaming creates a brand-new node and detaches the old one, rather than mutating the existing
node's own `name`/`path` fields in place -- **not the first design tried, and not a style choice**.
The mutate-in-place version passed every `jac test` (isolated a separate, real, now-fixed bug that
way -- see below) but still produced a live duplicate once actually exercised over real HTTP
requests (`jac browse` against a real `jac run --serve --dev` process, not just `jac test`):
renaming a file left **two** entries in the next `list_children_by_path` call, one correctly
bearing the new name, one a phantom still bearing the *old* name at a path that no longer existed
on disk. `jac test` never crosses the real request/response commit boundary a served app does
(`_finalize_call_response` in `jaclang/runtimelib/impl/server.impl.jac` is what actually commits a
`def:pub`'s writes, and only fires for a real served call) -- exactly the boundary the project's
existing `jac-studio-implementation` "cache the jid" discipline was written around, and apparently
one this specific field-mutation-then-immediately-read-elsewhere shape still crosses badly, even
after resolving fresh via `jobj(jid(...))` first. Switching to create-a-new-node-and-detach-the-old
one sidesteps it entirely, reusing only the already-proven-safe primitives this same module already
relies on elsewhere (`get_or_create_workspace`'s root-switch, `delete_path` below): create the node,
attach one edge, delete edges -- no field mutation on an already-attached node at all. Verified
against the identical repro (rename over real HTTP, then re-list) after the fix: exactly one entry,
correctly named. See tracker entry `2026-08-28-rename-field-mutation-duplicates-node-over-real-http`
for the full record (the mutate-in-place version's own code, the exact duplicate reproduced, and
why `jac test` alone couldn't have caught it).

A renamed folder's already-scanned descendants are not cascade-rewritten to the new path prefix --
the new folder node starts `scanned=False`, the identical "let it become unreachable graph garbage,
re-scan lazily next expand" trade-off `get_or_create_workspace` already makes when switching
workspace roots. A rewrite-in-place would need a recursive walk of however much of the subtree
happened to be scanned; a fresh, unscanned node is correct either way, since the next expand-click
re-derives fresh paths from the real (already-moved) filesystem anyway.

**Still never `del`s the stale `old_path` entry out of `_path_index`** -- a second, separate real
jaseci runtime finding, from before this rewrite: empirically isolated (`jac test`, bisecting
line-by-line against a minimal repro) that deleting a dict entry holding the *last* Python-level
reference to a node still reachable via a live edge elsewhere corrupts that *unrelated* edge's
later visibility to a plain `[parent-->]` traversal -- reproduced as the parent's child list coming
back completely empty right after the `del`. See tracker entry
`2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` for that isolation.
`delete_path` below does the equivalent `del` safely, confirmed by the same bisection: its node is
*already* fully edge-detached first, unlike a rename's old node at the point this function stops
touching it -- that appears to be the actual load-bearing difference. Leaving the stale `old_path`
key behind is harmless -- nothing will ever legitimately look it up again, since the path no longer
exists on disk."""
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
