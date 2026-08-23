"""FileTreeService: a toy workspace file tree, reached the same way ConfigService is.

Deliberately demonstrates service-to-service interaction *through the graph*, not a
constructor-injected reference: FileTreeService reads its default root folder name from
ConfigService at creation time, the same way any two services would talk to each other in
this pattern. Cache is keyed by `jid(root)` -- see config_service.jac's docstring for why a
single bare cached value is unsafe.
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

glob _cached_file_tree_services: dict[str, FileTreeService] = {};

def:pub get_file_tree_service -> FileTreeService {
    key = jid(root);
    if key in _cached_file_tree_services {
        return _cached_file_tree_services[key];
    }
    existing = [root-->[?:FileTreeService]];
    if existing {
        _cached_file_tree_services[key] = existing[0];
        return _cached_file_tree_services[key];
    }
    default_root = config_get("workspace.rootFolderName", "workspace");
    fresh = root ++> FileTreeService(root_name=default_root as str);
    _cached_file_tree_services[key] = fresh;
    return fresh;
}

def:pub _reset_file_tree_service_cache_for_tests {
    _cached_file_tree_services.clear();
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
