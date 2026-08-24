"""Workspace-as-graph: Workspace/Folder/File as real graph nodes, linked by `Contains` edges,
per docs/architecture.md's proposed data model (`Workspace --Contains--> Folder --Contains-->
File`). Phase 0's service-registry-spike validated the graph for *service lookup* (a handful of
small, mostly-static objects); this spike specifically tests the gap that leaves open: a real,
deep, editable file tree at realistic scale, since nothing has exercised that yet.

`Workspace` is a real `node` (not a plain cached `obj`, unlike document_service.jac's
DocumentBuffer) because it clears the bar `architecture.md`'s "not every service needs to be a
node" test sets: real workspace state needs to survive a restart independent of any single file,
and needs to be reached by graph traversal (a file-tree UI queries "children of this folder"
directly against the graph, it doesn't route through a cached Python object).
"""

import os;

node Workspace {
    has root_path: str;
}

node Folder {
    has name: str, path: str;
}

node File {
    has name: str, path: str;
}

edge Contains {}

glob DEFAULT_EXCLUDED_DIRS: list[str] = [
    "node_modules", ".git", ".jac", "dist", "__pycache__", ".venv", "venv"
];

glob _cached_workspaces: dict[str, Workspace] = {};

def:pub get_or_create_workspace(root_path: str) -> Workspace {
    key = jid(root);
    if key in _cached_workspaces {
        return _cached_workspaces[key];
    }
    existing = [root-->[?:Workspace]];
    if existing {
        _cached_workspaces[key] = existing[0];
        return _cached_workspaces[key];
    }
    fresh = root ++> Workspace(root_path=root_path);
    _cached_workspaces[key] = fresh;
    return fresh;
}

def:pub _reset_workspace_cache_for_tests {
    _cached_workspaces.clear();
}

"""Recursively scans `path` off disk and builds it into the graph under `parent` (a `Workspace`
or `Folder`), skipping any directory name in `exclude_dirs`. Returns (folder_count, file_count)
for the subtree just scanned."""
def:pub scan_directory(
    parent: (Workspace | Folder), path: str, exclude_dirs: list[str] = DEFAULT_EXCLUDED_DIRS
) -> tuple[int, int];

"""All direct `File`/`Folder` children of `parent`, in whatever order the graph returns them."""
def:pub list_children(parent: (Workspace | Folder)) -> list[(Folder | File)];

"""Depth-first count of every `Folder`/`File` node reachable from `parent`, including itself's
children transitively -- a real traversal, not a cached counter, to measure query cost separately
from construction cost."""
def:pub count_subtree(parent: (Workspace | Folder)) -> tuple[int, int];

"""Find a `File` or `Folder` by its exact `path`, searching breadth-first from `parent`. Returns
`None` if nothing matches."""
def:pub find_by_path(parent: (Workspace | Folder), target_path: str) -> (Folder | File | None);
