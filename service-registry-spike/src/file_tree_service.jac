"""FileTreeService: a toy workspace file tree, reached the same way ConfigService is.

Deliberately demonstrates service-to-service interaction *through the graph*, not a
constructor-injected reference: FileTreeService reads its default root folder name from
ConfigService at creation time, the same way any two services would talk to each other in
this pattern.
"""

import from .config_service { config_get }

node FileTreeService {
    has root_name: str = "workspace";
}

node FileEntry {
    has name: str;
    has is_dir: bool = False;
}

edge Contains {}

glob _cached_file_tree_service: FileTreeService | None = None;

def:pub get_file_tree_service -> FileTreeService {
    if _cached_file_tree_service is not None {
        return _cached_file_tree_service;
    }
    existing = [root-->[?:FileTreeService]];
    if existing {
        _cached_file_tree_service = existing[0];
        return _cached_file_tree_service;
    }
    default_root = config_get("workspace.rootFolderName", "workspace");
    fresh = root ++> FileTreeService(root_name=default_root as str);
    _cached_file_tree_service = fresh;
    return fresh;
}

def:pub _reset_file_tree_service_cache_for_tests {
    _cached_file_tree_service = None;
}

def:pub seed_entry(svc: FileTreeService, entry_name: str, is_dir: bool = False) -> FileEntry {
    matches = [svc->:Contains:->[?:FileEntry]];
    for existing_entry in matches {
        if existing_entry.name == entry_name {
            return existing_entry;
        }
    }
    fresh = FileEntry(name=entry_name, is_dir=is_dir);
    svc +>:Contains():+> fresh;
    return fresh;
}

def:pub list_entries(svc: FileTreeService) -> list[str] {
    entries = [svc->:Contains:->[?:FileEntry]];
    return [e.name for e in entries];
}
