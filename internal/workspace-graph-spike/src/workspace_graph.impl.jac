impl scan_directory(
    parent: (Workspace | Folder), path: str, exclude_dirs: list[str] = DEFAULT_EXCLUDED_DIRS
) -> tuple[int, int] {
    folder_count = 0;
    file_count = 0;

    entries = sorted(os.listdir(path));
    for entry_name in entries {
        entry_path = os.path.join(path, entry_name);
        if os.path.isdir(entry_path) {
            if entry_name in exclude_dirs {
                continue;
            }
            folder = Folder(name=entry_name, path=entry_path);
            parent +>:Contains():+> folder;
            folder_count += 1;
            (sub_folders, sub_files) = scan_directory(folder, entry_path, exclude_dirs);
            folder_count += sub_folders;
            file_count += sub_files;
        } else {
            file_node = File(name=entry_name, path=entry_path);
            parent +>:Contains():+> file_node;
            file_count += 1;
        }
    }

    return (folder_count, file_count);
}

impl list_children(parent: (Workspace | Folder)) -> list[(Folder | File)] {
    return [parent->:Contains:->];
}

impl count_subtree(parent: (Workspace | Folder)) -> tuple[int, int] {
    folder_count = 0;
    file_count = 0;

    for child in list_children(parent) {
        if isinstance(child, Folder) {
            folder_count += 1;
            (sub_folders, sub_files) = count_subtree(child);
            folder_count += sub_folders;
            file_count += sub_files;
        } else {
            file_count += 1;
        }
    }

    return (folder_count, file_count);
}

impl find_by_path(parent: (Workspace | Folder), target_path: str) -> (Folder | File | None) {
    queue: list[(Workspace | Folder)] = [parent];
    while len(queue) > 0 {
        current = queue.pop(0);
        for child in list_children(current) {
            if child.path == target_path {
                return child;
            }
            if isinstance(child, Folder) {
                queue.append(child);
            }
        }
    }
    return None;
}
