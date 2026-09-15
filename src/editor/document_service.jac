"""File load/save for the editor. Monaco owns the text model/undo entirely client-side, so
`open_document`/`save_document` are stateless read/write — no per-path buffer cache.
Editor-core decision: `2026-08-25-editor-core-decision-reversed-to-monaco`."""

import os;

def _read_file_content(path: str) -> str {
    if not os.path.isfile(path) {
        return "";
    }
    with open(path, "r", encoding="utf-8", errors="replace") as f {
        return f.read();
    }
}

"""A path with no file on disk yet starts from empty content rather than erroring."""
def:pub open_document(path: str) -> dict[str, any] {
    return {
        "path": path,
        "name": os.path.basename(path.rstrip("/")) or path,
        "content": _read_file_content(path)
    };
}

def:pub save_document(path: str, content: str) {
    with open(path, "w", encoding="utf-8") as f {
        f.write(content);
    }
}
