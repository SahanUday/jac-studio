"""Piece-tree text buffer core, ported from VS Code's pieceTreeTextBuffer/{pieceTreeBase.ts,
rbTreeBase.ts} (src/vs/editor/common/model/pieceTreeTextBuffer/). Backs the real editor's text
storage: an augmented red-black tree of `Piece`s pointing into either the original-content
buffer(s) or a single append-only "changes" buffer, giving O(log n) insert/delete/line-offset
lookups without ever copying the whole document on every edit. This is the foundational module
everything else in the editor core is layered on -- `risk_tier = "foundational"` in
translator/manifest.toml, per the project's own risk-tiering.

Merged from two upstream files (`rbTreeBase.ts` + `pieceTreeBase.ts`) into one Jac module --
deliberate redesign of the *module boundary*, not the algorithm. Upstream splits them because
`TreeNode` (rbTreeBase.ts) needs `Piece` (pieceTreeBase.ts) as a field type, while the tree
algorithm functions in rbTreeBase.ts need `PieceTreeBase` (pieceTreeBase.ts) as a parameter type --
a genuine two-way type dependency, fine under TS's hoisted ES-module type system. Tried the same
split in Jac first and confirmed empirically it's a bad idea here: two `.jac` files importing
types from each other still pass `jac check`, but the compiler falls back to interpreted "server
codespace" compilation with a real type-resolution note (`Type is Unknown, cannot access
attribute`), silently losing native lowering for both sides. Logged as
`2026-08-23-circular-import-degrades-native-lowering`. One file sidesteps the issue entirely, and
matches this project's own precedent (`interval_tree.jac` already keeps its tree's node type and
algorithm together in one file rather than following intervalTree.ts's own internal section
comments as if they were file boundaries).

Idiom notes:
- `node`/`include` are reserved Jac keywords; every local/field that upstream calls `node` is `nd`
  here (project-wide convention, see the `jac-language` skill and `interval_tree.jac`).
- `NodeColor` is plain int constants (`NODE_COLOR_BLACK`/`NODE_COLOR_RED`), not a Jac `enum` --
  upstream's `const enum` is just numbers under the hood; same idiom as `interval_tree.jac`,
  `word_character_classifier.jac`, `char_code.jac`, and `model_types.jac`.
- `TreeNode.detach()` points `parent`/`left`/`right` back at itself rather than upstream's
  `null!` -- Jac `obj` fields aren't nullable without an explicit `| None` type, and a self-loop
  sentinel is the same idiom `interval_tree.jac`'s `IntervalNode.detach()` already uses.
  `SENTINEL` is a genuine shared mutable singleton, same as upstream and same as
  `interval_tree.jac`'s own `SENTINEL` -- identity comparison (`nd == SENTINEL`) is exactly the
  semantics a red-black tree's "is this the sentinel" checks need, and works here because `==` on
  a plain `obj` is identity comparison in this Jac build (see
  `2026-08-23-obj-equality-not-structural`). `PieceTreeSearchCache.validate()`'s "is this cache
  entry stale because its node was detached" check becomes `nd.parent == nd` (self-loop) instead
  of upstream's `=== null`, for the same reason.
- Upstream's `iterate(node, callback)` -- a recursive in-order traversal taking a closure that can
  early-exit by returning `false` -- is replaced by `collect_nodes_in_order(root) ->
  list[TreeNode]` plus a plain for-loop at each call site. This drops nothing observable (every
  call site either processes every node or exits early on a condition a for-loop's
  `break`/`return` expresses just as well) and avoids depending on Jac closures mutating enclosing
  -function state, which nothing in this project has exercised yet. Implemented iteratively with
  an explicit stack (not upstream's recursion) so it doesn't hit Python's recursion limit on a
  large real document.
- Typed-array buffer sizing (`createUintArray` picking `Uint16Array` vs `Uint32Array`) is a V8
  memory micro-optimization with no correctness role; line-start offsets are plain `list[int]`
  here. Upstream's `createLineStartsFast` (no cr/lf/crlf/isBasicASCII tracking) is ported as
  `create_line_starts`, used throughout this module's own internal logic, which never reads those
  extra fields. The counting variant, `createLineStarts`, is also ported
  (`create_line_starts_with_counts`/`LineStarts`) despite nothing in *this* module needing it --
  `PieceTreeTextBufferBuilder` (a separate file) does, for EOL auto-detection.
- `Math.floor` guards on offsets are dropped where the parameter is typed `int` -- JS numbers are
  always float64, Jac has a real `int` type, so the guard is structurally unnecessary.
- `positionInBuffer(node, remainder, ret?)`'s in-place-mutate overload (avoids one allocation in a
  hot search loop) collapses to a single `position_in_buffer` that always returns a fresh
  `BufferCursor` -- Jac has no overload resolution on arity, and allocating a small value object
  per iteration isn't worth the complexity here.
- `startWithLF`/`endWithCR` are each a TS union overload (`string | TreeNode`); split into
  `start_with_lf_str`/`start_with_lf_node` and `end_with_cr_str`/`end_with_cr_node`, called
  according to what each real call site actually passes (verified against upstream, not guessed).
- `find_matches_in_node`/`find_matches_line_by_line`/`_find_matches_in_line` (search) depend on
  `Searcher`/`create_find_match`, ported separately in `text_model_search.jac` (a one-way
  dependency -- that file imports nothing back from here, so no circular-import risk). Upstream's
  `resultLen: number` + `result[resultLen++] = x` pattern (threading an explicit index alongside a
  pre-sized array, needed in JS to build a result array across several cooperating methods) is
  dropped in favor of a plain `result: list[FindMatch]` mutated via `.append()` -- Jac lists, like
  Python's, are passed by reference and track their own length, so the index has no job to do
  here; call sites check `len(result)` against the limit directly instead of comparing a threaded
  return value.
- `nodeAt2`'s declared TS return type is the non-nullable `NodePosition`, and its final `return
  null!` reads like dead-code protection -- until a real ported test (`#45892`, an empty document
  searched via `find_matches_line_by_line`) proved it isn't: on an empty tree, both of `nodeAt2`'s
  scan loops exit immediately without ever returning, so the `null!` path is genuinely reachable
  and upstream's own type annotation is optimistic, not accurate. `node_at2` here is typed
  `NodePosition | None` for real, and `find_matches_line_by_line` ports upstream's
  `if (startPosition === null) return [];` guard as real, load-bearing logic rather than dead code.
  The other two callers (`get_value_in_range`, `get_line_char_code`) don't hit this in practice --
  a degenerate same-start/end range short-circuits before reaching it in the first, and nothing
  currently calls the second against an out-of-bounds position -- so they assert non-null instead
  of threading the `None` case through their own signatures, matching upstream's equally
  unguarded behavior there while still failing loudly (not silently) if that assumption ever
  breaks. `node_at` (the offset-based sibling) has the identical unreached-`null!`-that-isn't
  shape and the identical unguarded callers upstream; left as raising on that path here since
  nothing has yet proven it reachable the way `#45892` proved it for `node_at2` -- revisit with
  the same fix if a future test does.
"""

import re;
import from src.editor.core.char_code { TAB, LINE_FEED, CARRIAGE_RETURN }
import from src.editor.core.position { Position }
import from src.editor.core.range { Range }
import from src.editor.model.model_types { FindMatch, SearchData }
import from src.editor.model.text_model_search { Searcher, create_find_match, is_valid_match }

glob NODE_COLOR_BLACK: int = 0;
glob NODE_COLOR_RED: int = 1;

glob AVERAGE_BUFFER_SIZE: int = 65535;

obj BufferCursor {
    has line: int, column: int;
}

obj Piece {
    has buffer_index: int, start: BufferCursor, end: BufferCursor, line_feed_cnt: int, length: int;
}

obj StringBuffer {
    has buffer: str, line_starts: list[int];
}

"""Line-start byte offsets for `text`, including a leading 0 (upstream's `createLineStartsFast`)."""
def create_line_starts(text: str) -> list[int] {
    starts: list[int] = [0];
    i = 0;
    length = len(text);
    while i < length {
        ch = ord(text[i]);
        if ch == CARRIAGE_RETURN {
            if i + 1 < length and ord(text[i + 1]) == LINE_FEED {
                starts.append(i + 2);
                i += 1;
            } else {
                starts.append(i + 1);
            }
        } elif ch == LINE_FEED {
            starts.append(i + 1);
        }
        i += 1;
    }
    return starts;
}

"""Line-start offsets plus per-buffer cr/lf/crlf counts and an `is_basic_ascii` flag (upstream's
`createLineStarts`, the counting variant `create_line_starts` above deliberately didn't port).
Needed by `PieceTreeTextBufferBuilder` (see piece_tree_text_buffer.jac) for EOL auto-detection
(majority-vote over cr/lf/crlf across every accepted chunk) and RTL/unusual-line-terminator
gating (skip the regex scan on already-known-ASCII chunks) -- real behavior the builder layer
needs, unlike `PieceTreeBase`'s own internal use of line starts, which never reads these counts."""
obj LineStarts {
    has line_starts: list[int], cr: int, lf: int, crlf: int, is_basic_ascii: bool;
}

def create_line_starts_with_counts(text: str) -> LineStarts {
    starts: list[int] = [0];
    cr = 0;
    lf = 0;
    crlf = 0;
    is_basic_ascii = True;
    i = 0;
    length = len(text);
    while i < length {
        ch = ord(text[i]);
        if ch == CARRIAGE_RETURN {
            if i + 1 < length and ord(text[i + 1]) == LINE_FEED {
                crlf += 1;
                starts.append(i + 2);
                i += 1;
            } else {
                cr += 1;
                starts.append(i + 1);
            }
        } elif ch == LINE_FEED {
            lf += 1;
            starts.append(i + 1);
        } else {
            if is_basic_ascii and ch != TAB and (ch < 32 or ch > 126) {
                is_basic_ascii = False;
            }
        }
        i += 1;
    }
    return LineStarts(line_starts=starts, cr=cr, lf=lf, crlf=crlf, is_basic_ascii=is_basic_ascii);
}

obj TreeNode {
    has piece: Piece, color: int;
    has parent: TreeNode postinit;
    has left: TreeNode postinit;
    has right: TreeNode postinit;
    has size_left: int postinit;
    has lf_left: int postinit;

    def postinit -> None;

    def next -> TreeNode;

    def prev -> TreeNode;

    def detach -> None;
}

glob SENTINEL: TreeNode = TreeNode(
    piece=Piece(
        buffer_index=0, start=BufferCursor(line=0, column=0), end=BufferCursor(line=0, column=0),
        line_feed_cnt=0, length=0
    ),
    color=NODE_COLOR_BLACK
);

with entry {
    SENTINEL.parent = SENTINEL;
    SENTINEL.left = SENTINEL;
    SENTINEL.right = SENTINEL;
}

def leftest(nd: TreeNode) -> TreeNode {
    while nd.left != SENTINEL {
        nd = nd.left;
    }
    return nd;
}

def rightest(nd: TreeNode) -> TreeNode {
    while nd.right != SENTINEL {
        nd = nd.right;
    }
    return nd;
}

"""In-order traversal of `subtree_root`'s subtree, skipping SENTINEL (matching every upstream
`iterate` callback's own `if (node === SENTINEL) return true;` skip-and-continue)."""
def collect_nodes_in_order(subtree_root: TreeNode) -> list[TreeNode] {
    result: list[TreeNode] = [];
    stack: list[TreeNode] = [];
    nd = subtree_root;
    while nd != SENTINEL or len(stack) > 0 {
        while nd != SENTINEL {
            stack.append(nd);
            nd = nd.left;
        }
        nd = stack.pop();
        result.append(nd);
        nd = nd.right;
    }
    return result;
}

obj NodePosition {
    has nd: TreeNode, remainder: int, node_start_offset: int;
}

obj CacheEntry {
    has nd: TreeNode, node_start_offset: int, node_start_line_number: int;
}

obj PieceTreeSearchCache {
    has limit: int;
    has cache: list[CacheEntry] postinit;

    def postinit -> None;

    def get(offset: int) -> CacheEntry | None;

    def get2(line_number: int) -> CacheEntry | None;

    def set(ent: CacheEntry) -> None;

    def validate(offset: int) -> None;
}

obj PieceTreeBase {
    has init_chunks: list[StringBuffer], init_eol: str, init_eol_normalized: bool;

    has tree_root: TreeNode postinit;
    has buffers: list[StringBuffer] postinit;
    has line_cnt: int postinit;
    has length: int postinit;
    has eol: str postinit;
    has eol_length: int postinit;
    has eol_normalized: bool postinit;
    has last_change_buffer_pos: BufferCursor postinit;
    has search_cache: PieceTreeSearchCache postinit;
    has last_visited_line_number: int postinit;
    has last_visited_line_value: str postinit;

    def postinit -> None;

    def create(chunks: list[StringBuffer], eol: str, eol_normalized: bool) -> None;

    def normalize_eol(eol: str) -> None;

    # region Buffer API
    def get_eol -> str;

    def set_eol(new_eol: str) -> None;

    def create_snapshot(bom: str) -> PieceTreeSnapshot;

    def equal(other: PieceTreeBase) -> bool;

    def get_offset_at(line_number: int, column: int) -> int;

    def get_position_at(offset: int) -> Position;

    def get_value_in_range(rng: Range, eol: str = "") -> str;

    def get_value_in_range2(start_position: NodePosition, end_position: NodePosition) -> str;

    def get_lines_content -> list[str];

    def get_length -> int;

    def get_line_count -> int;

    def get_line_content(line_number: int) -> str;

    def _get_char_code(node_pos: NodePosition) -> int;

    def get_line_char_code(line_number: int, index: int) -> int;

    def get_line_length(line_number: int) -> int;

    def get_char_code(offset: int) -> int;

    def get_nearest_chunk(offset: int) -> str;
    # endregion

    # region Piece Table
    def insert(offset: int, value: str, eol_normalized: bool = False) -> None;

    def delete(offset: int, cnt: int) -> None;

    def insert_content_to_node_left(value: str, nd: TreeNode) -> None;

    def insert_content_to_node_right(value: str, nd: TreeNode) -> None;

    def position_in_buffer(nd: TreeNode, remainder: int) -> BufferCursor;

    def get_line_feed_cnt(buffer_index: int, start: BufferCursor, end: BufferCursor) -> int;

    def offset_in_buffer(buffer_index: int, cursor: BufferCursor) -> int;

    def delete_nodes(nodes: list[TreeNode]) -> None;

    def create_new_pieces(text: str) -> list[Piece];

    def get_lines_raw_content -> str;

    def get_line_raw_content(line_number: int, end_offset: int) -> str;

    def compute_buffer_metadata -> None;

    # region node operations
    def get_index_of(nd: TreeNode, accumulated_value: int) -> tuple[int, int];

    def get_accumulated_value(nd: TreeNode, index: int) -> int;

    def delete_node_tail(nd: TreeNode, pos: BufferCursor) -> None;

    def delete_node_head(nd: TreeNode, pos: BufferCursor) -> None;

    def shrink_node(nd: TreeNode, start: BufferCursor, end: BufferCursor) -> None;

    def append_to_node(nd: TreeNode, value: str) -> None;

    def node_at(offset: int) -> NodePosition;

    def node_at2(line_number: int, column: int) -> NodePosition | None;

    def node_char_code_at(nd: TreeNode, offset: int) -> int;

    def offset_of_node(nd: TreeNode) -> int;
    # endregion

    # region CRLF
    def should_check_crlf -> bool;

    def start_with_lf_str(val: str) -> bool;

    def start_with_lf_node(nd: TreeNode) -> bool;

    def end_with_cr_str(val: str) -> bool;

    def end_with_cr_node(nd: TreeNode) -> bool;

    def validate_crlf_with_prev_node(next_nd: TreeNode) -> None;

    def validate_crlf_with_next_node(nd: TreeNode) -> None;

    def fix_crlf(prev: TreeNode, next_nd: TreeNode) -> None;

    def adjust_carriage_return_from_next(value: str, nd: TreeNode) -> bool;
    # endregion

    # region Tree operations
    def get_node_content(nd: TreeNode) -> str;

    def get_piece_content(piece: Piece) -> str;

    def rb_insert_right(nd: TreeNode, p: Piece) -> TreeNode;

    def rb_insert_left(nd: TreeNode, p: Piece) -> TreeNode;

    def get_content_of_subtree(nd: TreeNode) -> str;
    # endregion

    # region Search
    def find_matches_in_node(
        nd: TreeNode, searcher: Searcher, start_line_number: int, start_column: int,
        start_cursor: BufferCursor, end_cursor: BufferCursor, capture_matches: bool,
        limit_result_count: int, result: list[FindMatch]
    ) -> None;

    def find_matches_line_by_line(
        search_range: Range, search_data: SearchData, capture_matches: bool, limit_result_count: int
    ) -> list[FindMatch];

    def _find_matches_in_line(
        search_data: SearchData, searcher: Searcher, text: str, line_number: int, delta_offset: int,
        result: list[FindMatch], capture_matches: bool, limit_result_count: int
    ) -> None;
    # endregion
}

"""Readonly snapshot for the piece tree, ported from upstream's `PieceTreeSnapshot`. Structurally
satisfies the `read() -> str | None` `ITextSnapshot` contract documented in `model_types.jac` --
no formal interface type is declared for it, per that file's own note."""
obj PieceTreeSnapshot {
    has tree: PieceTreeBase, bom: str;
    has pieces: list[Piece] postinit;
    has index: int postinit;

    def postinit -> None;

    def read -> str | None;
}

def calculate_size(nd: TreeNode) -> int {
    if nd == SENTINEL {
        return 0;
    }
    return nd.size_left + nd.piece.length + calculate_size(nd.right);
}

def calculate_lf(nd: TreeNode) -> int {
    if nd == SENTINEL {
        return 0;
    }
    return nd.lf_left + nd.piece.line_feed_cnt + calculate_lf(nd.right);
}

def reset_sentinel {
    SENTINEL.parent = SENTINEL;
}

def left_rotate(tree: PieceTreeBase, x: TreeNode) {
    y = x.right;

    y.size_left += x.size_left + (x.piece.length if x != SENTINEL else 0);
    y.lf_left += x.lf_left + (x.piece.line_feed_cnt if x != SENTINEL else 0);
    x.right = y.left;

    if y.left != SENTINEL {
        y.left.parent = x;
    }
    y.parent = x.parent;
    if x.parent == SENTINEL {
        tree.tree_root = y;
    } elif x.parent.left == x {
        x.parent.left = y;
    } else {
        x.parent.right = y;
    }
    y.left = x;
    x.parent = y;
}

def right_rotate(tree: PieceTreeBase, y: TreeNode) {
    x = y.left;
    y.left = x.right;
    if x.right != SENTINEL {
        x.right.parent = y;
    }
    x.parent = y.parent;

    y.size_left -= x.size_left + (x.piece.length if x != SENTINEL else 0);
    y.lf_left -= x.lf_left + (x.piece.line_feed_cnt if x != SENTINEL else 0);

    if y.parent == SENTINEL {
        tree.tree_root = x;
    } elif y == y.parent.right {
        y.parent.right = x;
    } else {
        y.parent.left = x;
    }

    x.right = y;
    y.parent = x;
}

def rb_delete(tree: PieceTreeBase, z: TreeNode) {
    x: TreeNode = SENTINEL;
    y: TreeNode = SENTINEL;

    if z.left == SENTINEL {
        y = z;
        x = y.right;
    } elif z.right == SENTINEL {
        y = z;
        x = y.left;
    } else {
        y = leftest(z.right);
        x = y.right;
    }

    if y == tree.tree_root {
        tree.tree_root = x;

        x.color = NODE_COLOR_BLACK;
        z.detach();
        reset_sentinel();
        tree.tree_root.parent = SENTINEL;

        return;
    }

    y_was_red = y.color == NODE_COLOR_RED;

    if y == y.parent.left {
        y.parent.left = x;
    } else {
        y.parent.right = x;
    }

    if y == z {
        x.parent = y.parent;
        recompute_tree_metadata(tree, x);
    } else {
        if y.parent == z {
            x.parent = y;
        } else {
            x.parent = y.parent;
        }

        recompute_tree_metadata(tree, x);

        y.left = z.left;
        y.right = z.right;
        y.parent = z.parent;
        y.color = z.color;

        if z == tree.tree_root {
            tree.tree_root = y;
        } else {
            if z == z.parent.left {
                z.parent.left = y;
            } else {
                z.parent.right = y;
            }
        }

        if y.left != SENTINEL {
            y.left.parent = y;
        }
        if y.right != SENTINEL {
            y.right.parent = y;
        }
        y.size_left = z.size_left;
        y.lf_left = z.lf_left;
        recompute_tree_metadata(tree, y);
    }

    z.detach();

    if x.parent.left == x {
        new_size_left = calculate_size(x);
        new_lf_left = calculate_lf(x);
        if new_size_left != x.parent.size_left or new_lf_left != x.parent.lf_left {
            delta = new_size_left - x.parent.size_left;
            lf_delta = new_lf_left - x.parent.lf_left;
            x.parent.size_left = new_size_left;
            x.parent.lf_left = new_lf_left;
            update_tree_metadata(tree, x.parent, delta, lf_delta);
        }
    }

    recompute_tree_metadata(tree, x.parent);

    if y_was_red {
        reset_sentinel();
        return;
    }

    w: TreeNode = SENTINEL;
    while x != tree.tree_root and x.color == NODE_COLOR_BLACK {
        if x == x.parent.left {
            w = x.parent.right;

            if w.color == NODE_COLOR_RED {
                w.color = NODE_COLOR_BLACK;
                x.parent.color = NODE_COLOR_RED;
                left_rotate(tree, x.parent);
                w = x.parent.right;
            }

            if w.left.color == NODE_COLOR_BLACK and w.right.color == NODE_COLOR_BLACK {
                w.color = NODE_COLOR_RED;
                x = x.parent;
            } else {
                if w.right.color == NODE_COLOR_BLACK {
                    w.left.color = NODE_COLOR_BLACK;
                    w.color = NODE_COLOR_RED;
                    right_rotate(tree, w);
                    w = x.parent.right;
                }

                w.color = x.parent.color;
                x.parent.color = NODE_COLOR_BLACK;
                w.right.color = NODE_COLOR_BLACK;
                left_rotate(tree, x.parent);
                x = tree.tree_root;
            }
        } else {
            w = x.parent.left;

            if w.color == NODE_COLOR_RED {
                w.color = NODE_COLOR_BLACK;
                x.parent.color = NODE_COLOR_RED;
                right_rotate(tree, x.parent);
                w = x.parent.left;
            }

            if w.left.color == NODE_COLOR_BLACK and w.right.color == NODE_COLOR_BLACK {
                w.color = NODE_COLOR_RED;
                x = x.parent;
            } else {
                if w.left.color == NODE_COLOR_BLACK {
                    w.right.color = NODE_COLOR_BLACK;
                    w.color = NODE_COLOR_RED;
                    left_rotate(tree, w);
                    w = x.parent.left;
                }

                w.color = x.parent.color;
                x.parent.color = NODE_COLOR_BLACK;
                w.left.color = NODE_COLOR_BLACK;
                right_rotate(tree, x.parent);
                x = tree.tree_root;
            }
        }
    }
    x.color = NODE_COLOR_BLACK;
    reset_sentinel();
}

def fix_insert(tree: PieceTreeBase, x: TreeNode) {
    recompute_tree_metadata(tree, x);

    while x != tree.tree_root and x.parent.color == NODE_COLOR_RED {
        if x.parent == x.parent.parent.left {
            y = x.parent.parent.right;

            if y.color == NODE_COLOR_RED {
                x.parent.color = NODE_COLOR_BLACK;
                y.color = NODE_COLOR_BLACK;
                x.parent.parent.color = NODE_COLOR_RED;
                x = x.parent.parent;
            } else {
                if x == x.parent.right {
                    x = x.parent;
                    left_rotate(tree, x);
                }

                x.parent.color = NODE_COLOR_BLACK;
                x.parent.parent.color = NODE_COLOR_RED;
                right_rotate(tree, x.parent.parent);
            }
        } else {
            y = x.parent.parent.left;

            if y.color == NODE_COLOR_RED {
                x.parent.color = NODE_COLOR_BLACK;
                y.color = NODE_COLOR_BLACK;
                x.parent.parent.color = NODE_COLOR_RED;
                x = x.parent.parent;
            } else {
                if x == x.parent.left {
                    x = x.parent;
                    right_rotate(tree, x);
                }
                x.parent.color = NODE_COLOR_BLACK;
                x.parent.parent.color = NODE_COLOR_RED;
                left_rotate(tree, x.parent.parent);
            }
        }
    }

    tree.tree_root.color = NODE_COLOR_BLACK;
}

def update_tree_metadata(tree: PieceTreeBase, x: TreeNode, delta: int, line_feed_cnt_delta: int) {
    while x != tree.tree_root and x != SENTINEL {
        if x.parent.left == x {
            x.parent.size_left += delta;
            x.parent.lf_left += line_feed_cnt_delta;
        }
        x = x.parent;
    }
}

def recompute_tree_metadata(tree: PieceTreeBase, x: TreeNode) {
    delta = 0;
    lf_delta = 0;
    if x == tree.tree_root {
        return;
    }

    while x != tree.tree_root and x == x.parent.right {
        x = x.parent;
    }

    if x == tree.tree_root {
        return;
    }

    x = x.parent;

    delta = calculate_size(x.left) - x.size_left;
    lf_delta = calculate_lf(x.left) - x.lf_left;
    x.size_left += delta;
    x.lf_left += lf_delta;

    while x != tree.tree_root and (delta != 0 or lf_delta != 0) {
        if x.parent.left == x {
            x.parent.size_left += delta;
            x.parent.lf_left += lf_delta;
        }
        x = x.parent;
    }
}
