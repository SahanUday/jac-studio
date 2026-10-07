"""Server-side directory listing for the Open Folder dialog: a web page can't read the local
filesystem, so the picker browses it through here. Directories only, never file contents."""

import os;

"""Nearest existing directory at or above `path`, so a mistyped path lands somewhere useful."""
def:pub _nearest_directory(path: str) -> str {
    target = os.path.abspath(os.path.expanduser(path)) if path != "" else os.path.expanduser("~");
    while not os.path.isdir(target) and target != os.path.dirname(target) {
        target = os.path.dirname(target);
    }
    return target;
}

"""`path` is the directory actually listed, which differs from the request when it didn't exist.
`error` is non-empty when the directory exists but cannot be read."""
def:pub list_directories(path: str, show_hidden: bool) -> dict[str, any] {
    target = _nearest_directory(path);
    entries = [];
    error = "";
    try {
        for name in sorted(os.listdir(target), key=lambda (n: str) { n.lower(); }) {
            full = os.path.join(target, name);
            if (show_hidden or not name.startswith(".")) and os.path.isdir(full) {
                entries.append({"name": name, "path": full});
            }
        }
    } except Exception as e {
        error = str(e);
    }
    parent = os.path.dirname(target);
    return {
        "path": target,
        "parent": parent if parent != target else "",
        "home": os.path.expanduser("~"),
        "entries": entries,
        "error": error
    };
}
