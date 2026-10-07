"""Which directory the Explorer toolbar's New File and New Folder create in: the selected folder, the
selected file's parent, else the workspace root. Pure; reads the tree's loaded listings."""

def:pub target_directory(selected_path: str, root_path: str, children_by_path: dict[str, list[dict[str, any]]]) -> str {
    if selected_path == "" {
        return root_path;
    }
    for parent in children_by_path.keys() {
        for item in children_by_path[parent] {
            if item["path"] == selected_path {
                return selected_path if item["is_dir"] else parent;
            }
        }
    }
    return root_path;
}
