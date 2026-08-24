"""File load/save for the editor -- rewritten 2026-08-25 when jac-studio switched to embedding the
real `monaco-editor` npm package as the editor engine (see `docs/architecture.md`'s Editor Core
section and tracker entry `2026-08-25-editor-core-decision-reversed-to-monaco`). Monaco owns the
live text model, cursor/selection, and undo/redo entirely client-side once a file is open -- there
is nothing left for the server to keep in sync with on every keystroke, so unlike the archived
piece-tree-backed version of this file (`internal/native-editor-archive/src/editor/
document_service.jac`), there's no per-path buffer cache, no `DocumentBuffer` object, and no
per-keystroke RPC surface. `open_document`/`save_document` are both stateless: read the file, or
write it, and return.
"""

import os;

def _read_file_content(path: str) -> str {
    if not os.path.isfile(path) {
        return "";
    }
    with open(path, "r", encoding="utf-8", errors="replace") as f {
        return f.read();
    }
}

"""Reads `path` from disk and returns its display name plus raw content (a single string, not
split into lines -- Monaco's `editor.create`/`setValue` both take one string). A path with no file
on disk yet starts from empty content rather than erroring, so opening a not-yet-created file just
works."""
def:pub open_document(path: str) -> dict[str, any] {
    return {
        "path": path,
        "name": os.path.basename(path.rstrip("/")) or path,
        "content": _read_file_content(path)
    };
}

"""Writes `content` to `path`, overwriting whatever was there. The one write path this project
has -- Phase 1 had none yet, since there was no real file-system service to save into at the time
(`docs/phases/phase-1-editor-core.md`); `workspace_service.jac`'s real filesystem access made this
possible."""
def:pub save_document(path: str, content: str) {
    with open(path, "w", encoding="utf-8") as f {
        f.write(content);
    }
}
