"""DocumentBuffer: a per-user, in-memory text document backed by the piece-tree buffer
(`piece_tree_text_buffer.jac`). Phase 1 held exactly one buffer per user, seeded with placeholder
text. Phase 2's Tabs feature (`docs/roadmap.md`) needs one buffer *per open file path*, so the
cache below is now keyed by `jid(root)` then by `path`, and a buffer's initial content is read from
the real file on disk (via `workspace_service.jac`'s same filesystem, not a seed string) rather
than invented.

**Not a graph `node`, despite this project's own established service-registry pattern**
(`internal/service-registry-spike/src/config_service.jac`'s `ConfigService`, a `node` reachable from
`root`). Attaching a node whose fields transitively hold a self-referential object graph -- which
is exactly what a ported red-black-tree sentinel is (`piece_tree_base.jac`'s `SENTINEL.parent ==
SENTINEL`, the same idiom `interval_tree.jac` already established and documented) -- crashes with
`RecursionError: maximum recursion depth exceeded` at graph-commit time. Confirmed with a minimal
repro isolated down to a two-node self-loop with no piece-tree involved at all: node persistence
walks an attached node's fields with no cycle detection. Logged as
`2026-08-23-node-persistence-crashes-on-self-referential-fields` (`workaround-found`, not
`resolved` -- the correct fix is cycle-aware persistence, at which point `DocumentBuffer` should
go back to being a real node).

**Workaround**: `DocumentBuffer` is a plain `obj`, held directly in the `jid(root)`-keyed cache
dict below -- never attached to the graph. This keeps the correct per-user isolation the
service-registry pattern's caching rule requires (same reasoning as `config_service.jac`: `root`
is bound to whoever is calling, not a process-wide constant, so a single bare cached value would
leak one user's document into another user's request -- see `2026-08-23-service-registry-
query-cost` / `2026-08-23-service-cache-test-isolation`), but gives up real
persistence-by-reachability: an open document lives only for the server process's lifetime, not
across restarts -- `docs/architecture.md` explicitly calls workspace/tab state a Phase 3 candidate
for that, not Phase 2's job. `close_document` below frees a path's buffer explicitly (tab close),
since nothing else would ever reclaim it for a long-lived process.

**Not the Phase 3 `EditorGroup`/`Tab` graph nodes yet** (`docs/architecture.md`'s data-model
section) -- the open-tabs list itself lives as client-side state in
`src/workbench/editor_tabs/editor_tabs.jac`, not here. This module only tracks *buffer content per
path*; which paths are open, in what order, and which is active is presentation state, not
document state.
"""

import os;

import from src.editor.core.range { Range }
import from src.editor.model.model_types { DEFAULT_END_OF_LINE_LF }
import from src.editor.model.piece_tree_text_buffer { PieceTreeTextBuffer, SingleEditOperation }
import from src.editor.model.piece_tree_text_buffer_builder { PieceTreeTextBufferBuilder }

def _read_file_content(path: str) -> str {
    if not os.path.isfile(path) {
        return "";
    }
    with open(path, "r", encoding="utf-8", errors="replace") as f {
        return f.read();
    }
}

obj DocumentBuffer {
    has path: str;
    has buffer: PieceTreeTextBuffer postinit;

    def postinit {
        builder = PieceTreeTextBufferBuilder();
        builder.accept_chunk(_read_file_content(self.path));
        factory = builder.finish(True);
        self.buffer = factory.create(DEFAULT_END_OF_LINE_LF);
    }
}

glob _cached_document_buffers: dict[str, dict[str, DocumentBuffer]] = {};

def:pub _reset_document_buffer_cache_for_tests {
    _cached_document_buffers.clear();
}

def get_or_create_document_buffer(path: str) -> DocumentBuffer {
    key = jid(root);
    if key not in _cached_document_buffers {
        _cached_document_buffers[key] = {};
    }
    buffers = _cached_document_buffers[key];
    if path in buffers {
        return buffers[path];
    }
    buf = DocumentBuffer(path=path);
    buffers[path] = buf;
    return buf;
}

"""Opens `path` (reading it from disk the first time; returning the already-open in-memory buffer
on every call after, edits included) and returns its display name plus current lines -- the one
call the Tabs UI makes when a file is selected in the tree or an existing tab is revisited."""
def:pub open_document(path: str) -> dict[str, any] {
    buf = get_or_create_document_buffer(path);
    return {
        "path": path,
        "name": os.path.basename(path.rstrip("/")) or path,
        "lines": buf.buffer.get_lines_content()
    };
}

"""Apply one edit (typically a zero-width insert or a one-character-wide delete, matching what
the client sends per keystroke) and return the document's updated lines. A single round-trip
that both mutates and re-reads keeps the client's per-keystroke RPC surface to one call."""
def:pub apply_document_edit(
    path: str, start_line_number: int, start_column: int, end_line_number: int, end_column: int, text: str
) -> list[str] {
    buf = get_or_create_document_buffer(path);
    buf.buffer.apply_edits([SingleEditOperation(
        range=Range(
            start_line_number=start_line_number, start_column=start_column,
            end_line_number=end_line_number, end_column=end_column
        ),
        text=text
    )]);
    return buf.buffer.get_lines_content();
}

"""Frees a path's in-memory buffer (tab close). Idempotent -- closing an already-closed or
never-opened path is a no-op, not an error, since the client doesn't track server-side buffer
lifecycle and shouldn't have to."""
def:pub close_document(path: str) {
    key = jid(root);
    if key in _cached_document_buffers and path in _cached_document_buffers[key] {
        del _cached_document_buffers[key][path];
    }
}
