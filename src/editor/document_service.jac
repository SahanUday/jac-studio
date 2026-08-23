"""DocumentBuffer: a per-user, in-memory text document backed by the piece-tree buffer
(`piece_tree_text_buffer.jac`). This is Phase 1's first real attempt at a service-registry
consumer holding a *ported tree structure* -- and it hit a real blocker doing so, worth reading
before touching this file.

**Not a graph `node`, despite this project's own established service-registry pattern**
(`service-registry-spike/src/config_service.jac`'s `ConfigService`, a `node` reachable from
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
persistence-by-reachability: the document lives only for the server process's lifetime, not
across restarts. Acceptable for Phase 1 -- there's no save-to-disk action to wire up yet, and
nowhere to save *to* until a real file-system service exists.
"""

import from src.editor.core.range { Range }
import from src.editor.model.model_types { DEFAULT_END_OF_LINE_LF }
import from src.editor.model.piece_tree_text_buffer { PieceTreeTextBuffer, SingleEditOperation }
import from src.editor.model.piece_tree_text_buffer_builder { PieceTreeTextBufferBuilder }

glob SEED_TEXT: str = (
    "Welcome to jac-studio's editor core.\n\n"
    "This text is stored in a real piece-tree buffer -- the same data structure VS Code's own\n"
    "editor uses -- ported to Jac in translator/manifest.toml's piece-tree-base/piece-tree-\n"
    "text-buffer entries. Type here to try it out.\n"
);

obj DocumentBuffer {
    has buffer: PieceTreeTextBuffer postinit;

    def postinit {
        builder = PieceTreeTextBufferBuilder();
        builder.accept_chunk(SEED_TEXT);
        factory = builder.finish(True);
        self.buffer = factory.create(DEFAULT_END_OF_LINE_LF);
    }
}

glob _cached_document_buffers: dict[str, DocumentBuffer] = {};

def:pub get_document_buffer -> DocumentBuffer {
    key = jid(root);
    if key in _cached_document_buffers {
        return _cached_document_buffers[key];
    }
    svc = DocumentBuffer();
    _cached_document_buffers[key] = svc;
    return svc;
}

def:pub _reset_document_buffer_cache_for_tests {
    _cached_document_buffers.clear();
}

def:pub get_document_lines -> list[str] {
    svc = get_document_buffer();
    return svc.buffer.get_lines_content();
}

"""Apply one edit (typically a zero-width insert or a one-character-wide delete, matching what
the client sends per keystroke) and return the document's updated lines. A single round-trip
that both mutates and re-reads keeps the client's per-keystroke RPC surface to one call."""
def:pub apply_document_edit(
    start_line_number: int, start_column: int, end_line_number: int, end_column: int, text: str
) -> list[str] {
    svc = get_document_buffer();
    svc.buffer.apply_edits([SingleEditOperation(
        range=Range(
            start_line_number=start_line_number, start_column=start_column,
            end_line_number=end_line_number, end_column=end_column
        ),
        text=text
    )]);
    return svc.buffer.get_lines_content();
}
