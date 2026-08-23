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

    def postinit {
        self.parent = self;
        self.left = self;
        self.right = self;
        self.size_left = 0;
        self.lf_left = 0;
    }

    def next -> TreeNode {
        if self.right != SENTINEL {
            return leftest(self.right);
        }
        nd = self;
        while nd.parent != SENTINEL {
            if nd.parent.left == nd {
                break;
            }
            nd = nd.parent;
        }
        if nd.parent == SENTINEL {
            return SENTINEL;
        }
        return nd.parent;
    }

    def prev -> TreeNode {
        if self.left != SENTINEL {
            return rightest(self.left);
        }
        nd = self;
        while nd.parent != SENTINEL {
            if nd.parent.right == nd {
                break;
            }
            nd = nd.parent;
        }
        if nd.parent == SENTINEL {
            return SENTINEL;
        }
        return nd.parent;
    }

    def detach {
        self.parent = self;
        self.left = self;
        self.right = self;
    }
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

    def postinit {
        self.cache = [];
    }

    def get(offset: int) -> CacheEntry | None {
        i = len(self.cache) - 1;
        while i >= 0 {
            ent = self.cache[i];
            if (
                ent.node_start_offset <= offset
                and ent.node_start_offset + ent.nd.piece.length >= offset
            ) {
                return ent;
            }
            i -= 1;
        }
        return None;
    }

    def get2(line_number: int) -> CacheEntry | None {
        i = len(self.cache) - 1;
        while i >= 0 {
            ent = self.cache[i];
            if (
                ent.node_start_line_number != -1
                and ent.node_start_line_number < line_number
                and ent.node_start_line_number + ent.nd.piece.line_feed_cnt >= line_number
            ) {
                return ent;
            }
            i -= 1;
        }
        return None;
    }

    def set(ent: CacheEntry) {
        if len(self.cache) >= self.limit {
            self.cache.pop(0);
        }
        self.cache.append(ent);
    }

    def validate(offset: int) {
        has_invalid = False;
        new_cache: list[CacheEntry] = [];
        for ent in self.cache {
            if ent.nd.parent == ent.nd or ent.node_start_offset >= offset {
                has_invalid = True;
                continue;
            }
            new_cache.append(ent);
        }
        if has_invalid {
            self.cache = new_cache;
        }
    }
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

    def postinit {
        self.tree_root = SENTINEL;
        self.buffers = [];
        self.line_cnt = 1;
        self.length = 0;
        self.eol = "\n";
        self.eol_length = 1;
        self.eol_normalized = True;
        self.last_change_buffer_pos = BufferCursor(line=0, column=0);
        self.search_cache = PieceTreeSearchCache(limit=1);
        self.last_visited_line_number = 0;
        self.last_visited_line_value = "";
        self.create(self.init_chunks, self.init_eol, self.init_eol_normalized);
    }

    def create(chunks: list[StringBuffer], eol: str, eol_normalized: bool) {
        self.buffers = [StringBuffer(buffer="", line_starts=[0])];
        self.last_change_buffer_pos = BufferCursor(line=0, column=0);
        self.tree_root = SENTINEL;
        self.line_cnt = 1;
        self.length = 0;
        self.eol = eol;
        self.eol_length = len(eol);
        self.eol_normalized = eol_normalized;

        last_nd: TreeNode = SENTINEL;
        for chunk in chunks {
            if len(chunk.buffer) > 0 {
                if len(chunk.line_starts) == 0 {
                    chunk.line_starts = create_line_starts(chunk.buffer);
                }
                piece = Piece(
                    buffer_index=len(self.buffers),
                    start=BufferCursor(line=0, column=0),
                    end=BufferCursor(
                        line=len(chunk.line_starts) - 1,
                        column=len(chunk.buffer) - chunk.line_starts[-1]
                    ),
                    line_feed_cnt=len(chunk.line_starts) - 1,
                    length=len(chunk.buffer)
                );
                self.buffers.append(chunk);
                last_nd = self.rb_insert_right(last_nd, piece);
            }
        }

        self.search_cache = PieceTreeSearchCache(limit=1);
        self.last_visited_line_number = 0;
        self.last_visited_line_value = "";
        self.compute_buffer_metadata();
    }

    def normalize_eol(eol: str) {
        min_size = AVERAGE_BUFFER_SIZE - (AVERAGE_BUFFER_SIZE // 3);
        max_size = min_size * 2;

        temp_chunk = "";
        temp_chunk_len = 0;
        chunks: list[StringBuffer] = [];

        for nd in collect_nodes_in_order(self.tree_root) {
            text = self.get_node_content(nd);
            text_len = len(text);
            if temp_chunk_len <= min_size or temp_chunk_len + text_len < max_size {
                temp_chunk += text;
                temp_chunk_len += text_len;
                continue;
            }

            normalized = re.sub(r"\r\n|\r|\n", eol, temp_chunk);
            chunks.append(StringBuffer(buffer=normalized, line_starts=create_line_starts(normalized)));
            temp_chunk = text;
            temp_chunk_len = text_len;
        }

        if temp_chunk_len > 0 {
            normalized = re.sub(r"\r\n|\r|\n", eol, temp_chunk);
            chunks.append(StringBuffer(buffer=normalized, line_starts=create_line_starts(normalized)));
        }

        self.create(chunks, eol, True);
    }

    # region Buffer API
    def get_eol -> str {
        return self.eol;
    }

    def set_eol(new_eol: str) {
        self.eol = new_eol;
        self.eol_length = len(new_eol);
        self.normalize_eol(new_eol);
    }

    def create_snapshot(bom: str) -> PieceTreeSnapshot {
        return PieceTreeSnapshot(tree=self, bom=bom);
    }

    def equal(other: PieceTreeBase) -> bool {
        if self.get_length() != other.get_length() {
            return False;
        }
        if self.get_line_count() != other.get_line_count() {
            return False;
        }

        offset = 0;
        for nd in collect_nodes_in_order(self.tree_root) {
            text = self.get_node_content(nd);
            text_len = len(text);
            start_position = other.node_at(offset);
            end_position = other.node_at(offset + text_len);
            val = other.get_value_in_range2(start_position, end_position);

            offset += text_len;
            if text != val {
                return False;
            }
        }
        return True;
    }

    def get_offset_at(line_number: int, column: int) -> int {
        left_len = 0;
        x = self.tree_root;

        while x != SENTINEL {
            if x.left != SENTINEL and x.lf_left + 1 >= line_number {
                x = x.left;
            } elif x.lf_left + x.piece.line_feed_cnt + 1 >= line_number {
                left_len += x.size_left;
                accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                return left_len + accumulated + column - 1;
            } else {
                line_number -= x.lf_left + x.piece.line_feed_cnt;
                left_len += x.size_left + x.piece.length;
                x = x.right;
            }
        }

        return left_len;
    }

    def get_position_at(offset: int) -> Position {
        offset = max(0, offset);

        x = self.tree_root;
        lf_cnt = 0;
        original_offset = offset;

        while x != SENTINEL {
            if x.size_left != 0 and x.size_left >= offset {
                x = x.left;
            } elif x.size_left + x.piece.length >= offset {
                (out_index, out_remainder) = self.get_index_of(x, offset - x.size_left);

                lf_cnt += x.lf_left + out_index;

                if out_index == 0 {
                    line_start_offset = self.get_offset_at(lf_cnt + 1, 1);
                    column = original_offset - line_start_offset;
                    return Position(line_number=lf_cnt + 1, column=column + 1);
                }

                return Position(line_number=lf_cnt + 1, column=out_remainder + 1);
            } else {
                offset -= x.size_left + x.piece.length;
                lf_cnt += x.lf_left + x.piece.line_feed_cnt;

                if x.right == SENTINEL {
                    line_start_offset = self.get_offset_at(lf_cnt + 1, 1);
                    column = original_offset - offset - line_start_offset;
                    return Position(line_number=lf_cnt + 1, column=column + 1);
                } else {
                    x = x.right;
                }
            }
        }

        return Position(line_number=1, column=1);
    }

    def get_value_in_range(rng: Range, eol: str = "") -> str {
        if rng.start_line_number == rng.end_line_number and rng.start_column == rng.end_column {
            return "";
        }

        start_position = self.node_at2(rng.start_line_number, rng.start_column);
        end_position = self.node_at2(rng.end_line_number, rng.end_column);
        assert start_position is not None and end_position is not None, (
            "get_value_in_range: range out of bounds for this document"
        );

        value = self.get_value_in_range2(start_position, end_position);
        if eol != "" and (eol != self.eol or not self.eol_normalized) {
            return re.sub(r"\r\n|\r|\n", eol, value);
        }
        return value;
    }

    def get_value_in_range2(start_position: NodePosition, end_position: NodePosition) -> str {
        if start_position.nd == end_position.nd {
            nd = start_position.nd;
            buffer = self.buffers[nd.piece.buffer_index].buffer;
            start_offset = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start);
            return buffer[start_offset + start_position.remainder:start_offset + end_position.remainder];
        }

        x = start_position.nd;
        buffer = self.buffers[x.piece.buffer_index].buffer;
        start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
        ret = buffer[start_offset + start_position.remainder:start_offset + x.piece.length];

        x = x.next();
        while x != SENTINEL {
            buffer = self.buffers[x.piece.buffer_index].buffer;
            start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);

            if x == end_position.nd {
                ret += buffer[start_offset:start_offset + end_position.remainder];
                break;
            } else {
                ret += buffer[start_offset:start_offset + x.piece.length];
            }

            x = x.next();
        }

        return ret;
    }

    def get_lines_content -> list[str] {
        lines: list[str] = [];
        current_line = "";
        dangling_cr = False;

        for nd in collect_nodes_in_order(self.tree_root) {
            piece = nd.piece;
            piece_length = piece.length;
            if piece_length == 0 {
                continue;
            }

            buffer = self.buffers[piece.buffer_index].buffer;
            line_starts = self.buffers[piece.buffer_index].line_starts;

            piece_start_line = piece.start.line;
            piece_end_line = piece.end.line;
            piece_start_offset = line_starts[piece_start_line] + piece.start.column;

            if dangling_cr {
                if ord(buffer[piece_start_offset]) == LINE_FEED {
                    piece_start_offset += 1;
                    piece_length -= 1;
                }
                lines.append(current_line);
                current_line = "";
                dangling_cr = False;
                if piece_length == 0 {
                    continue;
                }
            }

            if piece_start_line == piece_end_line {
                if (
                    not self.eol_normalized
                    and ord(buffer[piece_start_offset + piece_length - 1]) == CARRIAGE_RETURN
                ) {
                    dangling_cr = True;
                    current_line += buffer[piece_start_offset:piece_start_offset + piece_length - 1];
                } else {
                    current_line += buffer[piece_start_offset:piece_start_offset + piece_length];
                }
                continue;
            }

            if self.eol_normalized {
                current_line += buffer[
                    piece_start_offset:max(piece_start_offset, line_starts[piece_start_line + 1] - self.eol_length)
                ];
            } else {
                current_line += re.sub(
                    r"(\r\n|\r|\n)$", "", buffer[piece_start_offset:line_starts[piece_start_line + 1]]
                );
            }
            lines.append(current_line);

            line = piece_start_line + 1;
            while line < piece_end_line {
                if self.eol_normalized {
                    current_line = buffer[line_starts[line]:line_starts[line + 1] - self.eol_length];
                } else {
                    current_line = re.sub(
                        r"(\r\n|\r|\n)$", "", buffer[line_starts[line]:line_starts[line + 1]]
                    );
                }
                lines.append(current_line);
                line += 1;
            }

            if (
                not self.eol_normalized
                and ord(buffer[line_starts[piece_end_line] + piece.end.column - 1]) == CARRIAGE_RETURN
            ) {
                dangling_cr = True;
                if piece.end.column == 0 {
                    lines.pop();
                } else {
                    current_line = buffer[line_starts[piece_end_line]:line_starts[piece_end_line] + piece.end.column - 1];
                }
            } else {
                current_line = buffer[line_starts[piece_end_line]:line_starts[piece_end_line] + piece.end.column];
            }
        }

        if dangling_cr {
            lines.append(current_line);
            current_line = "";
        }

        lines.append(current_line);
        return lines;
    }

    def get_length -> int {
        return self.length;
    }

    def get_line_count -> int {
        return self.line_cnt;
    }

    def get_line_content(line_number: int) -> str {
        if self.last_visited_line_number == line_number {
            return self.last_visited_line_value;
        }

        self.last_visited_line_number = line_number;

        if line_number == self.line_cnt {
            self.last_visited_line_value = self.get_line_raw_content(line_number, 0);
        } elif self.eol_normalized {
            self.last_visited_line_value = self.get_line_raw_content(line_number, self.eol_length);
        } else {
            self.last_visited_line_value = re.sub(
                r"(\r\n|\r|\n)$", "", self.get_line_raw_content(line_number, 0)
            );
        }

        return self.last_visited_line_value;
    }

    def _get_char_code(node_pos: NodePosition) -> int {
        if node_pos.remainder == node_pos.nd.piece.length {
            matching_nd = node_pos.nd.next();
            if matching_nd == SENTINEL {
                return 0;
            }
            buffer = self.buffers[matching_nd.piece.buffer_index];
            start_offset = self.offset_in_buffer(matching_nd.piece.buffer_index, matching_nd.piece.start);
            return ord(buffer.buffer[start_offset]);
        } else {
            buffer = self.buffers[node_pos.nd.piece.buffer_index];
            start_offset = self.offset_in_buffer(node_pos.nd.piece.buffer_index, node_pos.nd.piece.start);
            target_offset = start_offset + node_pos.remainder;
            return ord(buffer.buffer[target_offset]);
        }
    }

    def get_line_char_code(line_number: int, index: int) -> int {
        node_pos = self.node_at2(line_number, index + 1);
        assert node_pos is not None, "get_line_char_code: position out of bounds for this document";
        return self._get_char_code(node_pos);
    }

    def get_line_length(line_number: int) -> int {
        if line_number == self.get_line_count() {
            start_offset = self.get_offset_at(line_number, 1);
            return self.get_length() - start_offset;
        }
        return self.get_offset_at(line_number + 1, 1) - self.get_offset_at(line_number, 1) - self.eol_length;
    }

    def get_char_code(offset: int) -> int {
        node_pos = self.node_at(offset);
        return self._get_char_code(node_pos);
    }

    def get_nearest_chunk(offset: int) -> str {
        node_pos = self.node_at(offset);
        if node_pos.remainder == node_pos.nd.piece.length {
            matching_nd = node_pos.nd.next();
            if matching_nd == SENTINEL {
                return "";
            }
            buffer = self.buffers[matching_nd.piece.buffer_index];
            start_offset = self.offset_in_buffer(matching_nd.piece.buffer_index, matching_nd.piece.start);
            return buffer.buffer[start_offset:start_offset + matching_nd.piece.length];
        } else {
            buffer = self.buffers[node_pos.nd.piece.buffer_index];
            start_offset = self.offset_in_buffer(node_pos.nd.piece.buffer_index, node_pos.nd.piece.start);
            target_offset = start_offset + node_pos.remainder;
            target_end = start_offset + node_pos.nd.piece.length;
            return buffer.buffer[target_offset:target_end];
        }
    }
    # endregion

    # region Piece Table
    def insert(offset: int, value: str, eol_normalized: bool = False) {
        self.eol_normalized = self.eol_normalized and eol_normalized;
        self.last_visited_line_number = 0;
        self.last_visited_line_value = "";

        if self.tree_root != SENTINEL {
            node_pos = self.node_at(offset);
            nd = node_pos.nd;
            piece = nd.piece;
            buffer_index = piece.buffer_index;
            insert_pos_in_buffer = self.position_in_buffer(nd, node_pos.remainder);
            if (
                nd.piece.buffer_index == 0
                and piece.end.line == self.last_change_buffer_pos.line
                and piece.end.column == self.last_change_buffer_pos.column
                and (node_pos.node_start_offset + piece.length == offset)
                and len(value) < AVERAGE_BUFFER_SIZE
            ) {
                self.append_to_node(nd, value);
                self.compute_buffer_metadata();
                return;
            }

            if node_pos.node_start_offset == offset {
                self.insert_content_to_node_left(value, nd);
                self.search_cache.validate(offset);
            } elif node_pos.node_start_offset + nd.piece.length > offset {
                nodes_to_del: list[TreeNode] = [];
                new_right_piece = Piece(
                    buffer_index=piece.buffer_index,
                    start=insert_pos_in_buffer,
                    end=piece.end,
                    line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, insert_pos_in_buffer, piece.end),
                    length=(
                        self.offset_in_buffer(buffer_index, piece.end)
                        - self.offset_in_buffer(buffer_index, insert_pos_in_buffer)
                    )
                );

                if self.should_check_crlf() and self.end_with_cr_str(value) {
                    head_of_right = self.node_char_code_at(nd, node_pos.remainder);

                    if head_of_right == LINE_FEED {
                        new_start = BufferCursor(line=new_right_piece.start.line + 1, column=0);
                        new_right_piece = Piece(
                            buffer_index=new_right_piece.buffer_index,
                            start=new_start,
                            end=new_right_piece.end,
                            line_feed_cnt=self.get_line_feed_cnt(new_right_piece.buffer_index, new_start, new_right_piece.end),
                            length=new_right_piece.length - 1
                        );
                        value += "\n";
                    }
                }

                if self.should_check_crlf() and self.start_with_lf_str(value) {
                    tail_of_left = self.node_char_code_at(nd, node_pos.remainder - 1);
                    if tail_of_left == CARRIAGE_RETURN {
                        previous_pos = self.position_in_buffer(nd, node_pos.remainder - 1);
                        self.delete_node_tail(nd, previous_pos);
                        value = "\r" + value;

                        if nd.piece.length == 0 {
                            nodes_to_del.append(nd);
                        }
                    } else {
                        self.delete_node_tail(nd, insert_pos_in_buffer);
                    }
                } else {
                    self.delete_node_tail(nd, insert_pos_in_buffer);
                }

                new_pieces = self.create_new_pieces(value);
                if new_right_piece.length > 0 {
                    self.rb_insert_right(nd, new_right_piece);
                }

                tmp_nd = nd;
                for new_piece in new_pieces {
                    tmp_nd = self.rb_insert_right(tmp_nd, new_piece);
                }
                self.delete_nodes(nodes_to_del);
            } else {
                self.insert_content_to_node_right(value, nd);
            }
        } else {
            pieces = self.create_new_pieces(value);
            nd = self.rb_insert_left(SENTINEL, pieces[0]);

            k = 1;
            while k < len(pieces) {
                nd = self.rb_insert_right(nd, pieces[k]);
                k += 1;
            }
        }

        self.compute_buffer_metadata();
    }

    def delete(offset: int, cnt: int) {
        self.last_visited_line_number = 0;
        self.last_visited_line_value = "";

        if cnt <= 0 or self.tree_root == SENTINEL {
            return;
        }

        start_position = self.node_at(offset);
        end_position = self.node_at(offset + cnt);
        start_nd = start_position.nd;
        end_nd = end_position.nd;

        if start_nd == end_nd {
            start_split_pos_in_buffer = self.position_in_buffer(start_nd, start_position.remainder);
            end_split_pos_in_buffer = self.position_in_buffer(start_nd, end_position.remainder);

            if start_position.node_start_offset == offset {
                if cnt == start_nd.piece.length {
                    next_nd = start_nd.next();
                    rb_delete(self, start_nd);
                    self.validate_crlf_with_prev_node(next_nd);
                    self.compute_buffer_metadata();
                    return;
                }
                self.delete_node_head(start_nd, end_split_pos_in_buffer);
                self.search_cache.validate(offset);
                self.validate_crlf_with_prev_node(start_nd);
                self.compute_buffer_metadata();
                return;
            }

            if start_position.node_start_offset + start_nd.piece.length == offset + cnt {
                self.delete_node_tail(start_nd, start_split_pos_in_buffer);
                self.validate_crlf_with_next_node(start_nd);
                self.compute_buffer_metadata();
                return;
            }

            self.shrink_node(start_nd, start_split_pos_in_buffer, end_split_pos_in_buffer);
            self.compute_buffer_metadata();
            return;
        }

        nodes_to_del: list[TreeNode] = [];

        start_split_pos_in_buffer = self.position_in_buffer(start_nd, start_position.remainder);
        self.delete_node_tail(start_nd, start_split_pos_in_buffer);
        self.search_cache.validate(offset);
        if start_nd.piece.length == 0 {
            nodes_to_del.append(start_nd);
        }

        end_split_pos_in_buffer = self.position_in_buffer(end_nd, end_position.remainder);
        self.delete_node_head(end_nd, end_split_pos_in_buffer);
        if end_nd.piece.length == 0 {
            nodes_to_del.append(end_nd);
        }

        second_nd = start_nd.next();
        nd = second_nd;
        while nd != SENTINEL and nd != end_nd {
            nodes_to_del.append(nd);
            nd = nd.next();
        }

        prev = start_nd.prev() if start_nd.piece.length == 0 else start_nd;
        self.delete_nodes(nodes_to_del);
        self.validate_crlf_with_next_node(prev);
        self.compute_buffer_metadata();
    }

    def insert_content_to_node_left(value: str, nd: TreeNode) {
        nodes_to_del: list[TreeNode] = [];
        if self.should_check_crlf() and self.end_with_cr_str(value) and self.start_with_lf_node(nd) {
            piece = nd.piece;
            new_start = BufferCursor(line=piece.start.line + 1, column=0);
            n_piece = Piece(
                buffer_index=piece.buffer_index,
                start=new_start,
                end=piece.end,
                line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end),
                length=piece.length - 1
            );

            nd.piece = n_piece;

            value += "\n";
            update_tree_metadata(self, nd, -1, -1);

            if nd.piece.length == 0 {
                nodes_to_del.append(nd);
            }
        }

        new_pieces = self.create_new_pieces(value);
        new_nd = self.rb_insert_left(nd, new_pieces[-1]);
        k = len(new_pieces) - 2;
        while k >= 0 {
            new_nd = self.rb_insert_left(new_nd, new_pieces[k]);
            k -= 1;
        }
        self.validate_crlf_with_prev_node(new_nd);
        self.delete_nodes(nodes_to_del);
    }

    def insert_content_to_node_right(value: str, nd: TreeNode) {
        if self.adjust_carriage_return_from_next(value, nd) {
            value += "\n";
        }

        new_pieces = self.create_new_pieces(value);
        new_nd = self.rb_insert_right(nd, new_pieces[0]);
        tmp_nd = new_nd;

        k = 1;
        while k < len(new_pieces) {
            tmp_nd = self.rb_insert_right(tmp_nd, new_pieces[k]);
            k += 1;
        }

        self.validate_crlf_with_prev_node(new_nd);
    }

    def position_in_buffer(nd: TreeNode, remainder: int) -> BufferCursor {
        piece = nd.piece;
        buffer_index = nd.piece.buffer_index;
        line_starts = self.buffers[buffer_index].line_starts;

        start_offset = line_starts[piece.start.line] + piece.start.column;
        offset = start_offset + remainder;

        low = piece.start.line;
        high = piece.end.line;

        mid = 0;
        mid_start = 0;

        while low <= high {
            mid = low + (high - low) // 2;
            mid_start = line_starts[mid];

            if mid == high {
                break;
            }

            mid_stop = line_starts[mid + 1];

            if offset < mid_start {
                high = mid - 1;
            } elif offset >= mid_stop {
                low = mid + 1;
            } else {
                break;
            }
        }

        return BufferCursor(line=mid, column=offset - mid_start);
    }

    def get_line_feed_cnt(buffer_index: int, start: BufferCursor, end: BufferCursor) -> int {
        if end.column == 0 {
            return end.line - start.line;
        }

        line_starts = self.buffers[buffer_index].line_starts;
        if end.line == len(line_starts) - 1 {
            return end.line - start.line;
        }

        next_line_start_offset = line_starts[end.line + 1];
        end_offset = line_starts[end.line] + end.column;
        if next_line_start_offset > end_offset + 1 {
            return end.line - start.line;
        }

        previous_char_offset = end_offset - 1;
        buffer = self.buffers[buffer_index].buffer;

        if ord(buffer[previous_char_offset]) == CARRIAGE_RETURN {
            return end.line - start.line + 1;
        } else {
            return end.line - start.line;
        }
    }

    def offset_in_buffer(buffer_index: int, cursor: BufferCursor) -> int {
        line_starts = self.buffers[buffer_index].line_starts;
        return line_starts[cursor.line] + cursor.column;
    }

    def delete_nodes(nodes: list[TreeNode]) {
        for nd in nodes {
            rb_delete(self, nd);
        }
    }

    def create_new_pieces(text: str) -> list[Piece] {
        if len(text) > AVERAGE_BUFFER_SIZE {
            new_pieces: list[Piece] = [];
            while len(text) > AVERAGE_BUFFER_SIZE {
                last_char = ord(text[AVERAGE_BUFFER_SIZE - 1]);
                if last_char == CARRIAGE_RETURN or (last_char >= 0xD800 and last_char <= 0xDBFF) {
                    split_text = text[0:AVERAGE_BUFFER_SIZE - 1];
                    text = text[AVERAGE_BUFFER_SIZE - 1:];
                } else {
                    split_text = text[0:AVERAGE_BUFFER_SIZE];
                    text = text[AVERAGE_BUFFER_SIZE:];
                }

                line_starts = create_line_starts(split_text);
                new_pieces.append(Piece(
                    buffer_index=len(self.buffers),
                    start=BufferCursor(line=0, column=0),
                    end=BufferCursor(line=len(line_starts) - 1, column=len(split_text) - line_starts[-1]),
                    line_feed_cnt=len(line_starts) - 1,
                    length=len(split_text)
                ));
                self.buffers.append(StringBuffer(buffer=split_text, line_starts=line_starts));
            }

            line_starts = create_line_starts(text);
            new_pieces.append(Piece(
                buffer_index=len(self.buffers),
                start=BufferCursor(line=0, column=0),
                end=BufferCursor(line=len(line_starts) - 1, column=len(text) - line_starts[-1]),
                line_feed_cnt=len(line_starts) - 1,
                length=len(text)
            ));
            self.buffers.append(StringBuffer(buffer=text, line_starts=line_starts));

            return new_pieces;
        }

        start_offset = len(self.buffers[0].buffer);
        line_starts = create_line_starts(text);

        start = self.last_change_buffer_pos;
        if (
            self.buffers[0].line_starts[-1] == start_offset
            and start_offset != 0
            and self.start_with_lf_str(text)
            and self.end_with_cr_str(self.buffers[0].buffer)
        ) {
            self.last_change_buffer_pos = BufferCursor(
                line=self.last_change_buffer_pos.line, column=self.last_change_buffer_pos.column + 1
            );
            start = self.last_change_buffer_pos;

            i = 0;
            while i < len(line_starts) {
                line_starts[i] += start_offset + 1;
                i += 1;
            }

            self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
            self.buffers[0].buffer += "_" + text;
            start_offset += 1;
        } else {
            if start_offset != 0 {
                i = 0;
                while i < len(line_starts) {
                    line_starts[i] += start_offset;
                    i += 1;
                }
            }
            self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
            self.buffers[0].buffer += text;
        }

        end_offset = len(self.buffers[0].buffer);
        end_index = len(self.buffers[0].line_starts) - 1;
        end_column = end_offset - self.buffers[0].line_starts[end_index];
        end_pos = BufferCursor(line=end_index, column=end_column);
        new_piece = Piece(
            buffer_index=0,
            start=start,
            end=end_pos,
            line_feed_cnt=self.get_line_feed_cnt(0, start, end_pos),
            length=end_offset - start_offset
        );
        self.last_change_buffer_pos = end_pos;
        return [new_piece];
    }

    def get_lines_raw_content -> str {
        return self.get_content_of_subtree(self.tree_root);
    }

    def get_line_raw_content(line_number: int, end_offset: int) -> str {
        x = self.tree_root;
        ret = "";
        cache = self.search_cache.get2(line_number);
        if cache is not None {
            x = cache.nd;
            prev_accumulated_value = self.get_accumulated_value(x, line_number - cache.node_start_line_number - 1);
            buffer = self.buffers[x.piece.buffer_index].buffer;
            start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
            if cache.node_start_line_number + x.piece.line_feed_cnt == line_number {
                ret = buffer[start_offset + prev_accumulated_value:start_offset + x.piece.length];
            } else {
                accumulated_value = self.get_accumulated_value(x, line_number - cache.node_start_line_number);
                return buffer[start_offset + prev_accumulated_value:start_offset + accumulated_value - end_offset];
            }
        } else {
            node_start_offset = 0;
            original_line_number = line_number;
            while x != SENTINEL {
                if x.left != SENTINEL and x.lf_left >= line_number - 1 {
                    x = x.left;
                } elif x.lf_left + x.piece.line_feed_cnt > line_number - 1 {
                    prev_accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                    accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 1);
                    buffer = self.buffers[x.piece.buffer_index].buffer;
                    start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                    node_start_offset += x.size_left;
                    self.search_cache.set(CacheEntry(
                        nd=x, node_start_offset=node_start_offset,
                        node_start_line_number=original_line_number - (line_number - 1 - x.lf_left)
                    ));
                    return buffer[start_offset + prev_accumulated_value:start_offset + accumulated_value - end_offset];
                } elif x.lf_left + x.piece.line_feed_cnt == line_number - 1 {
                    prev_accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                    buffer = self.buffers[x.piece.buffer_index].buffer;
                    start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                    ret = buffer[start_offset + prev_accumulated_value:start_offset + x.piece.length];
                    break;
                } else {
                    line_number -= x.lf_left + x.piece.line_feed_cnt;
                    node_start_offset += x.size_left + x.piece.length;
                    x = x.right;
                }
            }
        }

        x = x.next();
        while x != SENTINEL {
            buffer = self.buffers[x.piece.buffer_index].buffer;

            if x.piece.line_feed_cnt > 0 {
                accumulated_value = self.get_accumulated_value(x, 0);
                start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                ret += buffer[start_offset:start_offset + accumulated_value - end_offset];
                return ret;
            } else {
                start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                ret += buffer[start_offset:start_offset + x.piece.length];
            }

            x = x.next();
        }

        return ret;
    }

    def compute_buffer_metadata {
        x = self.tree_root;

        lf_cnt = 1;
        length = 0;

        while x != SENTINEL {
            lf_cnt += x.lf_left + x.piece.line_feed_cnt;
            length += x.size_left + x.piece.length;
            x = x.right;
        }

        self.line_cnt = lf_cnt;
        self.length = length;
        self.search_cache.validate(self.length);
    }

    # region node operations
    def get_index_of(nd: TreeNode, accumulated_value: int) -> tuple[int, int] {
        piece = nd.piece;
        pos = self.position_in_buffer(nd, accumulated_value);
        line_cnt = pos.line - piece.start.line;

        if (
            self.offset_in_buffer(piece.buffer_index, piece.end)
            - self.offset_in_buffer(piece.buffer_index, piece.start)
        ) == accumulated_value {
            real_line_cnt = self.get_line_feed_cnt(nd.piece.buffer_index, piece.start, pos);
            if real_line_cnt != line_cnt {
                return (real_line_cnt, 0);
            }
        }

        return (line_cnt, pos.column);
    }

    def get_accumulated_value(nd: TreeNode, index: int) -> int {
        if index < 0 {
            return 0;
        }
        piece = nd.piece;
        line_starts = self.buffers[piece.buffer_index].line_starts;
        expected_line_start_index = piece.start.line + index + 1;
        if expected_line_start_index > piece.end.line {
            return line_starts[piece.end.line] + piece.end.column - line_starts[piece.start.line] - piece.start.column;
        } else {
            return line_starts[expected_line_start_index] - line_starts[piece.start.line] - piece.start.column;
        }
    }

    def delete_node_tail(nd: TreeNode, pos: BufferCursor) {
        piece = nd.piece;
        original_lf_cnt = piece.line_feed_cnt;
        original_end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);

        new_end = pos;
        new_end_offset = self.offset_in_buffer(piece.buffer_index, new_end);
        new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, piece.start, new_end);

        lf_delta = new_line_feed_cnt - original_lf_cnt;
        size_delta = new_end_offset - original_end_offset;
        new_length = piece.length + size_delta;

        nd.piece = Piece(
            buffer_index=piece.buffer_index, start=piece.start, end=new_end,
            line_feed_cnt=new_line_feed_cnt, length=new_length
        );

        update_tree_metadata(self, nd, size_delta, lf_delta);
    }

    def delete_node_head(nd: TreeNode, pos: BufferCursor) {
        piece = nd.piece;
        original_lf_cnt = piece.line_feed_cnt;
        original_start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);

        new_start = pos;
        new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end);
        new_start_offset = self.offset_in_buffer(piece.buffer_index, new_start);
        lf_delta = new_line_feed_cnt - original_lf_cnt;
        size_delta = original_start_offset - new_start_offset;
        new_length = piece.length + size_delta;
        nd.piece = Piece(
            buffer_index=piece.buffer_index, start=new_start, end=piece.end,
            line_feed_cnt=new_line_feed_cnt, length=new_length
        );

        update_tree_metadata(self, nd, size_delta, lf_delta);
    }

    def shrink_node(nd: TreeNode, start: BufferCursor, end: BufferCursor) {
        piece = nd.piece;
        original_start_pos = piece.start;
        original_end_pos = piece.end;

        old_length = piece.length;
        old_lf_cnt = piece.line_feed_cnt;
        new_end = start;
        new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, piece.start, new_end);
        new_length = (
            self.offset_in_buffer(piece.buffer_index, start)
            - self.offset_in_buffer(piece.buffer_index, original_start_pos)
        );

        nd.piece = Piece(
            buffer_index=piece.buffer_index, start=piece.start, end=new_end,
            line_feed_cnt=new_line_feed_cnt, length=new_length
        );

        update_tree_metadata(self, nd, new_length - old_length, new_line_feed_cnt - old_lf_cnt);

        new_piece = Piece(
            buffer_index=piece.buffer_index, start=end, end=original_end_pos,
            line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, end, original_end_pos),
            length=(
                self.offset_in_buffer(piece.buffer_index, original_end_pos)
                - self.offset_in_buffer(piece.buffer_index, end)
            )
        );

        new_nd = self.rb_insert_right(nd, new_piece);
        self.validate_crlf_with_prev_node(new_nd);
    }

    def append_to_node(nd: TreeNode, value: str) {
        if self.adjust_carriage_return_from_next(value, nd) {
            value += "\n";
        }

        hit_crlf = self.should_check_crlf() and self.start_with_lf_str(value) and self.end_with_cr_node(nd);
        start_offset = len(self.buffers[0].buffer);
        self.buffers[0].buffer += value;
        line_starts = create_line_starts(value);
        i = 0;
        while i < len(line_starts) {
            line_starts[i] += start_offset;
            i += 1;
        }
        if hit_crlf {
            prev_start_offset = self.buffers[0].line_starts[-2];
            self.buffers[0].line_starts.pop();
            self.last_change_buffer_pos = BufferCursor(
                line=self.last_change_buffer_pos.line - 1, column=start_offset - prev_start_offset
            );
        }

        self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
        end_index = len(self.buffers[0].line_starts) - 1;
        end_column = len(self.buffers[0].buffer) - self.buffers[0].line_starts[end_index];
        new_end = BufferCursor(line=end_index, column=end_column);
        new_length = nd.piece.length + len(value);
        old_line_feed_cnt = nd.piece.line_feed_cnt;
        new_line_feed_cnt = self.get_line_feed_cnt(0, nd.piece.start, new_end);
        lf_delta = new_line_feed_cnt - old_line_feed_cnt;

        nd.piece = Piece(
            buffer_index=nd.piece.buffer_index, start=nd.piece.start, end=new_end,
            line_feed_cnt=new_line_feed_cnt, length=new_length
        );

        self.last_change_buffer_pos = new_end;
        update_tree_metadata(self, nd, len(value), lf_delta);
    }

    def node_at(offset: int) -> NodePosition {
        x = self.tree_root;
        cache = self.search_cache.get(offset);
        if cache is not None {
            return NodePosition(
                nd=cache.nd, remainder=offset - cache.node_start_offset,
                node_start_offset=cache.node_start_offset
            );
        }

        node_start_offset = 0;

        while x != SENTINEL {
            if x.size_left > offset {
                x = x.left;
            } elif x.size_left + x.piece.length >= offset {
                node_start_offset += x.size_left;
                ret = NodePosition(nd=x, remainder=offset - x.size_left, node_start_offset=node_start_offset);
                self.search_cache.set(CacheEntry(nd=x, node_start_offset=node_start_offset, node_start_line_number=-1));
                return ret;
            } else {
                offset -= x.size_left + x.piece.length;
                node_start_offset += x.size_left + x.piece.length;
                x = x.right;
            }
        }

        raise ValueError("node_at: offset out of bounds -- unreachable for a valid offset");
    }

    def node_at2(line_number: int, column: int) -> NodePosition | None {
        x = self.tree_root;
        node_start_offset = 0;

        while x != SENTINEL {
            if x.left != SENTINEL and x.lf_left >= line_number - 1 {
                x = x.left;
            } elif x.lf_left + x.piece.line_feed_cnt > line_number - 1 {
                prev_accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 1);
                node_start_offset += x.size_left;

                return NodePosition(
                    nd=x, remainder=min(prev_accumulated + column - 1, accumulated),
                    node_start_offset=node_start_offset
                );
            } elif x.lf_left + x.piece.line_feed_cnt == line_number - 1 {
                prev_accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                if prev_accumulated + column - 1 <= x.piece.length {
                    return NodePosition(
                        nd=x, remainder=prev_accumulated + column - 1, node_start_offset=node_start_offset
                    );
                } else {
                    column -= x.piece.length - prev_accumulated;
                    break;
                }
            } else {
                line_number -= x.lf_left + x.piece.line_feed_cnt;
                node_start_offset += x.size_left + x.piece.length;
                x = x.right;
            }
        }

        x = x.next();
        while x != SENTINEL {
            if x.piece.line_feed_cnt > 0 {
                accumulated = self.get_accumulated_value(x, 0);
                node_start_offset = self.offset_of_node(x);
                return NodePosition(
                    nd=x, remainder=min(column - 1, accumulated), node_start_offset=node_start_offset
                );
            } else {
                if x.piece.length >= column - 1 {
                    node_start_offset = self.offset_of_node(x);
                    return NodePosition(nd=x, remainder=column - 1, node_start_offset=node_start_offset);
                } else {
                    column -= x.piece.length;
                }
            }

            x = x.next();
        }

        return None;
    }

    def node_char_code_at(nd: TreeNode, offset: int) -> int {
        if nd.piece.line_feed_cnt < 1 {
            return -1;
        }
        buffer = self.buffers[nd.piece.buffer_index];
        new_offset = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start) + offset;
        return ord(buffer.buffer[new_offset]);
    }

    def offset_of_node(nd: TreeNode) -> int {
        pos = nd.size_left;
        while nd != self.tree_root {
            if nd.parent.right == nd {
                pos += nd.parent.size_left + nd.parent.piece.length;
            }
            nd = nd.parent;
        }
        return pos;
    }
    # endregion

    # region CRLF
    def should_check_crlf -> bool {
        return not (self.eol_normalized and self.eol == "\n");
    }

    def start_with_lf_str(val: str) -> bool {
        return len(val) > 0 and ord(val[0]) == LINE_FEED;
    }

    def start_with_lf_node(nd: TreeNode) -> bool {
        if nd == SENTINEL or nd.piece.line_feed_cnt == 0 {
            return False;
        }

        piece = nd.piece;
        line_starts = self.buffers[piece.buffer_index].line_starts;
        line = piece.start.line;
        start_offset = line_starts[line] + piece.start.column;
        if line == len(line_starts) - 1 {
            return False;
        }
        next_line_offset = line_starts[line + 1];
        if next_line_offset > start_offset + 1 {
            return False;
        }
        return ord(self.buffers[piece.buffer_index].buffer[start_offset]) == LINE_FEED;
    }

    def end_with_cr_str(val: str) -> bool {
        return len(val) > 0 and ord(val[-1]) == CARRIAGE_RETURN;
    }

    def end_with_cr_node(nd: TreeNode) -> bool {
        if nd == SENTINEL or nd.piece.line_feed_cnt == 0 {
            return False;
        }
        return self.node_char_code_at(nd, nd.piece.length - 1) == CARRIAGE_RETURN;
    }

    def validate_crlf_with_prev_node(next_nd: TreeNode) {
        if self.should_check_crlf() and self.start_with_lf_node(next_nd) {
            nd = next_nd.prev();
            if self.end_with_cr_node(nd) {
                self.fix_crlf(nd, next_nd);
            }
        }
    }

    def validate_crlf_with_next_node(nd: TreeNode) {
        if self.should_check_crlf() and self.end_with_cr_node(nd) {
            next_nd = nd.next();
            if self.start_with_lf_node(next_nd) {
                self.fix_crlf(nd, next_nd);
            }
        }
    }

    def fix_crlf(prev: TreeNode, next_nd: TreeNode) {
        nodes_to_del: list[TreeNode] = [];
        line_starts = self.buffers[prev.piece.buffer_index].line_starts;
        if prev.piece.end.column == 0 {
            new_end = BufferCursor(
                line=prev.piece.end.line - 1,
                column=line_starts[prev.piece.end.line] - line_starts[prev.piece.end.line - 1] - 1
            );
        } else {
            new_end = BufferCursor(line=prev.piece.end.line, column=prev.piece.end.column - 1);
        }

        prev_new_length = prev.piece.length - 1;
        prev_new_lf_cnt = prev.piece.line_feed_cnt - 1;
        prev.piece = Piece(
            buffer_index=prev.piece.buffer_index, start=prev.piece.start, end=new_end,
            line_feed_cnt=prev_new_lf_cnt, length=prev_new_length
        );

        update_tree_metadata(self, prev, -1, -1);
        if prev.piece.length == 0 {
            nodes_to_del.append(prev);
        }

        new_start = BufferCursor(line=next_nd.piece.start.line + 1, column=0);
        new_length = next_nd.piece.length - 1;
        new_line_feed_cnt = self.get_line_feed_cnt(next_nd.piece.buffer_index, new_start, next_nd.piece.end);
        next_nd.piece = Piece(
            buffer_index=next_nd.piece.buffer_index, start=new_start, end=next_nd.piece.end,
            line_feed_cnt=new_line_feed_cnt, length=new_length
        );

        update_tree_metadata(self, next_nd, -1, -1);
        if next_nd.piece.length == 0 {
            nodes_to_del.append(next_nd);
        }

        pieces = self.create_new_pieces("\r\n");
        self.rb_insert_right(prev, pieces[0]);

        for del_nd in nodes_to_del {
            rb_delete(self, del_nd);
        }
    }

    def adjust_carriage_return_from_next(value: str, nd: TreeNode) -> bool {
        if self.should_check_crlf() and self.end_with_cr_str(value) {
            next_nd = nd.next();
            if self.start_with_lf_node(next_nd) {
                if next_nd.piece.length == 1 {
                    rb_delete(self, next_nd);
                } else {
                    piece = next_nd.piece;
                    new_start = BufferCursor(line=piece.start.line + 1, column=0);
                    new_length = piece.length - 1;
                    new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end);
                    next_nd.piece = Piece(
                        buffer_index=piece.buffer_index, start=new_start, end=piece.end,
                        line_feed_cnt=new_line_feed_cnt, length=new_length
                    );

                    update_tree_metadata(self, next_nd, -1, -1);
                }
                return True;
            }
        }

        return False;
    }
    # endregion

    # region Tree operations
    def get_node_content(nd: TreeNode) -> str {
        if nd == SENTINEL {
            return "";
        }
        buffer = self.buffers[nd.piece.buffer_index];
        piece = nd.piece;
        start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);
        end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);
        return buffer.buffer[start_offset:end_offset];
    }

    def get_piece_content(piece: Piece) -> str {
        buffer = self.buffers[piece.buffer_index];
        start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);
        end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);
        return buffer.buffer[start_offset:end_offset];
    }

    def rb_insert_right(nd: TreeNode, p: Piece) -> TreeNode {
        z = TreeNode(piece=p, color=NODE_COLOR_RED);
        z.left = SENTINEL;
        z.right = SENTINEL;
        z.parent = SENTINEL;
        z.size_left = 0;
        z.lf_left = 0;

        x = self.tree_root;
        if x == SENTINEL {
            self.tree_root = z;
            z.color = NODE_COLOR_BLACK;
        } elif nd.right == SENTINEL {
            nd.right = z;
            z.parent = nd;
        } else {
            next_nd = leftest(nd.right);
            next_nd.left = z;
            z.parent = next_nd;
        }

        fix_insert(self, z);
        return z;
    }

    def rb_insert_left(nd: TreeNode, p: Piece) -> TreeNode {
        z = TreeNode(piece=p, color=NODE_COLOR_RED);
        z.left = SENTINEL;
        z.right = SENTINEL;
        z.parent = SENTINEL;
        z.size_left = 0;
        z.lf_left = 0;

        if self.tree_root == SENTINEL {
            self.tree_root = z;
            z.color = NODE_COLOR_BLACK;
        } elif nd.left == SENTINEL {
            nd.left = z;
            z.parent = nd;
        } else {
            prev_nd = rightest(nd.left);
            prev_nd.right = z;
            z.parent = prev_nd;
        }

        fix_insert(self, z);
        return z;
    }

    def get_content_of_subtree(nd: TreeNode) -> str {
        text = "";
        for descendant in collect_nodes_in_order(nd) {
            text += self.get_node_content(descendant);
        }
        return text;
    }
    # endregion

    # region Search
    def find_matches_in_node(
        nd: TreeNode, searcher: Searcher, start_line_number: int, start_column: int,
        start_cursor: BufferCursor, end_cursor: BufferCursor, capture_matches: bool,
        limit_result_count: int, result: list[FindMatch]
    ) {
        buffer = self.buffers[nd.piece.buffer_index];
        start_offset_in_buffer = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start);
        start = self.offset_in_buffer(nd.piece.buffer_index, start_cursor);
        end = self.offset_in_buffer(nd.piece.buffer_index, end_cursor);

        if searcher.word_separators is not None {
            search_text = buffer.buffer[start:end];
            offset_delta = start;
            searcher.reset(0);
        } else {
            search_text = buffer.buffer;
            offset_delta = 0;
            searcher.reset(start);
        }

        m = searcher.next(search_text);
        while m is not None {
            m_index = m.start() + offset_delta;
            if m_index >= end {
                return;
            }
            ret = self.position_in_buffer(nd, m_index - start_offset_in_buffer);
            line_feed_cnt = self.get_line_feed_cnt(nd.piece.buffer_index, start_cursor, ret);
            ret_start_column = (
                ret.column - start_cursor.column + start_column if ret.line == start_cursor.line
                else ret.column + 1
            );
            match_text = m.group(0);
            ret_end_column = ret_start_column + len(match_text);
            result.append(create_find_match(
                Range(
                    start_line_number=start_line_number + line_feed_cnt, start_column=ret_start_column,
                    end_line_number=start_line_number + line_feed_cnt, end_column=ret_end_column
                ),
                m, capture_matches
            ));

            if m_index + len(match_text) >= end {
                return;
            }
            if len(result) >= limit_result_count {
                return;
            }

            m = searcher.next(search_text);
        }
    }

    def find_matches_line_by_line(
        search_range: Range, search_data: SearchData, capture_matches: bool, limit_result_count: int
    ) -> list[FindMatch] {
        result: list[FindMatch] = [];
        searcher = Searcher(word_separators=search_data.word_separators, search_regex=search_data.regex);

        start_position = self.node_at2(search_range.start_line_number, search_range.start_column);
        if start_position is None {
            return [];
        }
        end_position = self.node_at2(search_range.end_line_number, search_range.end_column);
        if end_position is None {
            return [];
        }
        start = self.position_in_buffer(start_position.nd, start_position.remainder);
        end = self.position_in_buffer(end_position.nd, end_position.remainder);

        if start_position.nd == end_position.nd {
            self.find_matches_in_node(
                start_position.nd, searcher, search_range.start_line_number, search_range.start_column,
                start, end, capture_matches, limit_result_count, result
            );
            return result;
        }

        start_line_number = search_range.start_line_number;
        current_nd = start_position.nd;
        while current_nd != end_position.nd {
            line_break_cnt = self.get_line_feed_cnt(current_nd.piece.buffer_index, start, current_nd.piece.end);

            if line_break_cnt >= 1 {
                line_starts = self.buffers[current_nd.piece.buffer_index].line_starts;
                start_offset_in_buffer = self.offset_in_buffer(current_nd.piece.buffer_index, current_nd.piece.start);
                next_line_start_offset = line_starts[start.line + line_break_cnt];
                start_column = (
                    search_range.start_column if start_line_number == search_range.start_line_number else 1
                );
                self.find_matches_in_node(
                    current_nd, searcher, start_line_number, start_column, start,
                    self.position_in_buffer(current_nd, next_line_start_offset - start_offset_in_buffer),
                    capture_matches, limit_result_count, result
                );

                if len(result) >= limit_result_count {
                    return result;
                }
                start_line_number += line_break_cnt;
            }

            start_column = search_range.start_column - 1 if start_line_number == search_range.start_line_number else 0;
            if start_line_number == search_range.end_line_number {
                text = self.get_line_content(start_line_number)[start_column:search_range.end_column - 1];
                self._find_matches_in_line(
                    search_data, searcher, text, search_range.end_line_number, start_column, result,
                    capture_matches, limit_result_count
                );
                return result;
            }

            self._find_matches_in_line(
                search_data, searcher, self.get_line_content(start_line_number)[start_column:],
                start_line_number, start_column, result, capture_matches, limit_result_count
            );

            if len(result) >= limit_result_count {
                return result;
            }

            start_line_number += 1;
            start_position = self.node_at2(start_line_number, 1);
            assert start_position is not None, (
                "find_matches_line_by_line: advanced past the last line while still short of end_position"
            );
            current_nd = start_position.nd;
            start = self.position_in_buffer(start_position.nd, start_position.remainder);
        }

        if start_line_number == search_range.end_line_number {
            start_column = search_range.start_column - 1 if start_line_number == search_range.start_line_number else 0;
            text = self.get_line_content(start_line_number)[start_column:search_range.end_column - 1];
            self._find_matches_in_line(
                search_data, searcher, text, search_range.end_line_number, start_column, result,
                capture_matches, limit_result_count
            );
            return result;
        }

        start_column = search_range.start_column if start_line_number == search_range.start_line_number else 1;
        self.find_matches_in_node(
            end_position.nd, searcher, start_line_number, start_column, start, end, capture_matches,
            limit_result_count, result
        );
        return result;
    }

    def _find_matches_in_line(
        search_data: SearchData, searcher: Searcher, text: str, line_number: int, delta_offset: int,
        result: list[FindMatch], capture_matches: bool, limit_result_count: int
    ) {
        word_separators = search_data.word_separators;
        if not capture_matches and search_data.simple_search is not None and search_data.simple_search != "" {
            search_string = search_data.simple_search;
            search_string_len = len(search_string);
            text_length = len(text);

            last_match_index = -search_string_len;
            last_match_index = text.find(search_string, last_match_index + search_string_len);
            while last_match_index != -1 {
                if word_separators is None or is_valid_match(
                    word_separators, text, text_length, last_match_index, search_string_len
                ) {
                    result.append(FindMatch(
                        range=Range(
                            start_line_number=line_number, start_column=last_match_index + 1 + delta_offset,
                            end_line_number=line_number,
                            end_column=last_match_index + 1 + search_string_len + delta_offset
                        ),
                        matches=None
                    ));
                    if len(result) >= limit_result_count {
                        return;
                    }
                }
                last_match_index = text.find(search_string, last_match_index + search_string_len);
            }
            return;
        }

        searcher.reset(0);
        m = searcher.next(text);
        while m is not None {
            match_text = m.group(0);
            result.append(create_find_match(
                Range(
                    start_line_number=line_number, start_column=m.start() + 1 + delta_offset,
                    end_line_number=line_number, end_column=m.start() + 1 + len(match_text) + delta_offset
                ),
                m, capture_matches
            ));
            if len(result) >= limit_result_count {
                return;
            }
            m = searcher.next(text);
        }
    }
    # endregion
}

"""Readonly snapshot for the piece tree, ported from upstream's `PieceTreeSnapshot`. Structurally
satisfies the `read() -> str | None` `ITextSnapshot` contract documented in `model_types.jac` --
no formal interface type is declared for it, per that file's own note."""
obj PieceTreeSnapshot {
    has tree: PieceTreeBase, bom: str;
    has pieces: list[Piece] postinit;
    has index: int postinit;

    def postinit {
        self.pieces = [];
        self.index = 0;
        if self.tree.tree_root != SENTINEL {
            for nd in collect_nodes_in_order(self.tree.tree_root) {
                self.pieces.append(nd.piece);
            }
        }
    }

    def read -> str | None {
        if len(self.pieces) == 0 {
            if self.index == 0 {
                self.index += 1;
                return self.bom;
            } else {
                return None;
            }
        }

        if self.index > len(self.pieces) - 1 {
            return None;
        }

        if self.index == 0 {
            piece = self.pieces[self.index];
            self.index += 1;
            return self.bom + self.tree.get_piece_content(piece);
        }
        piece = self.pieces[self.index];
        self.index += 1;
        return self.tree.get_piece_content(piece);
    }
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
