"""Ported from upstream's pieceTreeTextBuffer.test.ts (src/vs/editor/test/common/model/
pieceTreeTextBuffer/pieceTreeTextBuffer.test.ts, 2125 lines) -- the real "parity against VS
Code's own test suite" deliverable for the PieceTreeTextBuffer/Builder wrapper layer. Lives here
(paired with piece_tree_text_buffer_builder.jac) rather than on piece_tree_text_buffer.jac because
upstream's own construction idiom -- `createTextBuffer(val, normalizeEOL)`, built through
`PieceTreeTextBufferBuilder` -- is this file's helper, and every single ported test uses it (see
`create_text_buffer` below); `piece_tree_text_buffer.test.jac` (the sibling annex) covers
`PieceTreeTextBuffer`'s own direct API instead.

87 tests upstream, grouped into 11 `suite(...)` blocks; ported here as flat `test "suite: name"`
blocks (suite-prefixed since several test names repeat verbatim across different upstream suites,
e.g. two distinct "delete CR in CRLF 1" tests and two distinct "random bug 1..10" sequences under
different suites -- upstream's Mocha nesting disambiguates them structurally, so the prefix
reproduces that here). 84 of the 87 are ported; the 3 tests in upstream's `chunk based search`
suite are deliberately deferred -- see the note at the bottom of this file.

The 69 tests across the `inserts and deletes`, `prefix sum for line feed`, `offset 2 position`,
`get text in range`, `CRLF`, `centralized lineStarts with CRLF`, and `search offset cache` suites
are close to 100% mechanical: `createTextBuffer([...])` + a sequence of `insert`/`delete` calls
each paired with an equivalent `str.substring(...)` update to a plain-string oracle, closed out by
`getLinesRawContent()`/`testLineStarts`/`testLinesContent`/`assertTreeInvariants` calls. Mirroring
this project's established practice for data this repetitive (see interval_tree.test.jac's
208-case `nodeAcceptEdit` table, pulled from its TS source via script rather than hand-transcribed),
these 69 were extracted from the upstream TS source with a small Python script (regex-driven
statement-by-statement translation, not an LLM-authored rewrite) rather than hand-typed, to
eliminate transcription risk on this much repetitive insert/delete/assert data. The remaining 15
(`buffer api`'s 7, `random is unsupervised`'s 3 randomized-fuzz tests plus its one mechanical
"splitting large change buffer" case, and `snapshot`'s 4) were ported by hand -- either too
structurally different from the mechanical shape (fuzz loops, `equal`/`getLineCharCode`/
`getNearestChunk` assertions) or requiring a genuine adaptation (see the `snapshot` note below).

`snapshot` suite adaptation: upstream's 4 tests call `model.applyEdits(...)` where `model` is a
full `TextModel` (`createTextModel(...)` from testTextModel.ts) -- `TextModel` itself is not
ported (`textModel.ts`'s non-DOM-facing subset is a separate, later translator target, see
`docs/translator-strategy.md`). `TextModel.applyEdits` upstream is a thin validation wrapper that
delegates the real work straight to `PieceTreeTextBuffer.applyEdits` -- ported in
piece_tree_text_buffer.jac -- and all four tests only assert on content/snapshot behavior (never
anything TextModel-specific like undo or decorations), so they're ported here calling
`PieceTreeTextBuffer.apply_edits` directly instead, mirroring this project's established practice
of porting a test file's own adapter/helper rather than skipping tests that need one (see
prefix-sum-computer's `IPrefixSumComputer` adapter precedent, `jac-studio-translator` skill).

`getLineRawContent(lineNumber)` upstream has a defaulted second parameter (`endOffset: number = 0`)
that `PieceTreeBase.get_line_raw_content` in piece_tree_base.jac does not (that module wasn't
touched by this port -- owned by a parallel session -- and its two-arg signature has no default);
every ported call below supplies the `0` explicitly.
"""

import re;
import random;
import from src.editor.model.piece_tree_base {
    PieceTreeBase, TreeNode, SENTINEL, NODE_COLOR_BLACK, NODE_COLOR_RED, PieceTreeSnapshot
}
import from src.editor.model.piece_tree_text_buffer { PieceTreeTextBuffer, SingleEditOperation }
import from src.editor.model.model_types { DEFAULT_END_OF_LINE_LF }
import from src.editor.core.position { Position }
import from src.editor.core.range { Range }
import from src.editor.core.char_code { LINE_FEED, CARRIAGE_RETURN }

# ===================================================================================
# Test helpers, ported from the TS file's own top-of-file helper functions.
# ===================================================================================

"""Ported from upstream's `createTextBuffer` test helper -- builds a `PieceTreeTextBuffer` by
streaming each of `val`'s strings through a `PieceTreeTextBufferBuilder`, then finishing and
creating with `DefaultEndOfLine.LF`. Upstream's `factory.create(...)` returns
`{ textBuffer, disposable }`; this file's port of `create()` (piece_tree_text_buffer_builder.jac)
returns the buffer directly since the Disposable machinery is a documented scope cut there."""
def create_text_buffer(val: list[str], normalize_eol: bool = True) -> PieceTreeTextBuffer {
    builder = PieceTreeTextBufferBuilder();
    for chunk in val {
        builder.accept_chunk(chunk);
    }
    factory = builder.finish(normalize_eol);
    return factory.create(DEFAULT_END_OF_LINE_LF);
}

def assert_position(p: Position, line_number: int, column: int) {
    assert p.line_number == line_number;
    assert p.column == column;
}

"""Ported from upstream's `trimLineFeed`."""
def trim_line_feed(text: str) -> str {
    if len(text) == 0 {
        return text;
    }
    if len(text) == 1 {
        last = ord(text[-1]);
        if last == LINE_FEED or last == CARRIAGE_RETURN {
            return "";
        }
        return text;
    }
    if ord(text[-1]) == LINE_FEED {
        if ord(text[-2]) == CARRIAGE_RETURN {
            return text[0:-2];
        }
        return text[0:-1];
    }
    if ord(text[-1]) == CARRIAGE_RETURN {
        return text[0:-1];
    }
    return text;
}

"""Ported from upstream's `testLinesContent`."""
def test_lines_content(s: str, piece_table: PieceTreeBase) {
    lines = split_lines(s);
    assert piece_table.get_line_count() == len(lines);
    assert piece_table.get_lines_raw_content() == s;
    i = 0;
    while i < len(lines) {
        assert piece_table.get_line_content(i + 1) == lines[i];
        end_col = len(lines[i]) + (1 if i == len(lines) - 1 else 2);
        rng = Range(start_line_number=i + 1, start_column=1, end_line_number=i + 1, end_column=end_col);
        assert trim_line_feed(piece_table.get_value_in_range(rng)) == lines[i];
        i += 1;
    }
}

"""Ported from upstream's `testLineStarts` -- collects every `\\r\\n|\\r|\\n` match's end offset
as a line-start, then round-trips `get_position_at`/`get_offset_at` against them. Upstream loops
via `RegExp.exec` with hand-rolled zero-length-match/duplicate-match guards; `re.finditer` already
enumerates non-overlapping matches safely and none of `\\r\\n|\\r|\\n`'s alternatives can match
zero-length, so those guards have no equivalent here -- same set of line-start offsets either
way."""
def test_line_starts(s: str, piece_table: PieceTreeBase) {
    line_starts: list[int] = [0];
    for m in re.finditer(r"\r\n|\r|\n", s) {
        line_starts.append(m.end());
    }

    i = 0;
    while i < len(line_starts) {
        assert_position(piece_table.get_position_at(line_starts[i]), i + 1, 1);
        assert piece_table.get_offset_at(i + 1, 1) == line_starts[i];
        i += 1;
    }

    i = 1;
    while i < len(line_starts) {
        pos = piece_table.get_position_at(line_starts[i] - 1);
        assert piece_table.get_offset_at(pos.line_number, pos.column) == line_starts[i] - 1;
        i += 1;
    }
}

"""Ported from upstream's `depth`/`assertValidNode`/`assertValidTree`/`assertTreeInvariants`. Safe
to recurse (unlike piece_tree_base.jac's own iterative `collect_nodes_in_order`, which avoids
recursion for an arbitrary traversal): a red-black tree's depth is bounded by `2*log2(n)` by
construction, so even the fuzz tests below (up to several thousand nodes) never approach Python's
recursion limit."""
def depth(n: TreeNode) -> int {
    if n == SENTINEL {
        return 1;
    }
    assert depth(n.left) == depth(n.right);
    return (1 if n.color == NODE_COLOR_BLACK else 0) + depth(n.left);
}

def assert_valid_node(n: TreeNode) -> tuple[int, int] {
    if n == SENTINEL {
        return (0, 0);
    }

    l = n.left;
    r = n.right;

    if n.color == NODE_COLOR_RED {
        assert l.color == NODE_COLOR_BLACK;
        assert r.color == NODE_COLOR_BLACK;
    }

    (actual_left_size, actual_left_lf) = assert_valid_node(l);
    assert actual_left_lf == n.lf_left;
    assert actual_left_size == n.size_left;
    (actual_right_size, actual_right_lf) = assert_valid_node(r);

    return (
        n.size_left + n.piece.length + actual_right_size,
        n.lf_left + n.piece.line_feed_cnt + actual_right_lf
    );
}

def assert_valid_tree(tree: PieceTreeBase) {
    if tree.tree_root == SENTINEL {
        return;
    }
    assert tree.tree_root.color == NODE_COLOR_BLACK;
    assert depth(tree.tree_root.left) == depth(tree.tree_root.right);
    assert_valid_node(tree.tree_root);
}

def assert_tree_invariants(piece_table: PieceTreeBase) {
    assert SENTINEL.color == NODE_COLOR_BLACK;
    assert SENTINEL.parent == SENTINEL;
    assert SENTINEL.left == SENTINEL;
    assert SENTINEL.right == SENTINEL;
    assert SENTINEL.size_left == 0;
    assert SENTINEL.lf_left == 0;
    assert_valid_tree(piece_table);
}

"""Ported from upstream's `alphabet`/`randomChar`/`randomInt`/`randomStr`, used only by the fuzz
tests in `random is unsupervised`. `random_str`'s loop bound is upstream's own (a CoffeeScript-
compiled `for j = 1 to len` artifact that actually produces `length - 1` characters, not
`length`) -- ported as the exact same off-by-one rather than "fixed", since parity with upstream's
real behavior is the goal and nothing asserts an exact generated length."""
glob ALPHABET: str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n";

def random_int(bound: int) -> int {
    return int(random.random() * bound);
}

def random_char -> str {
    return ALPHABET[random_int(len(ALPHABET))];
}

def random_str(length: int) -> str {
    chars: list[str] = [];
    j = 1;
    while j < length {
        chars.append(random_char());
        j += 1;
    }
    return "".join(chars);
}

def get_value_in_snapshot(snapshot: PieceTreeSnapshot) -> str {
    ret = "";
    tmp = snapshot.read();
    while tmp is not None {
        ret += tmp;
        tmp = snapshot.read();
    }
    return ret;
}

# ===================================================================================
# Mechanically-extracted suites: inserts and deletes, prefix sum for line feed,
# offset 2 position, get text in range, CRLF, centralized lineStarts with CRLF,
# search offset cache. See this file's top docstring for the extraction method.
# ===================================================================================

# ===== suite: inserts and deletes (14 tests) =====
test "inserts and deletes: basic insert/delete" {
    piece_tree = create_text_buffer(["This is a document with some text."]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(34, "This is some more text to insert at offset 34.");
    assert piece_table.get_lines_raw_content() == "This is a document with some text.This is some more text to insert at offset 34.";
    piece_table.delete(42, 5);
    assert piece_table.get_lines_raw_content() == "This is a document with some text.This is more text to insert at offset 34.";
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: more inserts" {
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "AAA");
    assert piece_table.get_lines_raw_content() == "AAA";
    piece_table.insert(0, "BBB");
    assert piece_table.get_lines_raw_content() == "BBBAAA";
    piece_table.insert(6, "CCC");
    assert piece_table.get_lines_raw_content() == "BBBAAACCC";
    piece_table.insert(5, "DDD");
    assert piece_table.get_lines_raw_content() == "BBBAADDDACCC";
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: more deletes" {
    piece_tree = create_text_buffer(["012345678"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(8, 1);
    assert piece_table.get_lines_raw_content() == "01234567";
    piece_table.delete(0, 1);
    assert piece_table.get_lines_raw_content() == "1234567";
    piece_table.delete(5, 1);
    assert piece_table.get_lines_raw_content() == "123457";
    piece_table.delete(5, 1);
    assert piece_table.get_lines_raw_content() == "12345";
    piece_table.delete(0, 5);
    assert piece_table.get_lines_raw_content() == "";
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random test 1" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "ceLPHmFzvCtFeHkCBej ");
    str = str[0:0] + "ceLPHmFzvCtFeHkCBej " + str[0:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.insert(8, "gDCEfNYiBUNkSwtvB K ");
    str = str[0:8] + "gDCEfNYiBUNkSwtvB K " + str[8:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.insert(38, "cyNcHxjNPPoehBJldLS ");
    str = str[0:38] + "cyNcHxjNPPoehBJldLS " + str[38:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.insert(59, "ejMx\nOTgWlbpeDExjOk ");
    str = str[0:59] + "ejMx\nOTgWlbpeDExjOk " + str[59:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random test 2" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "VgPG ");
    str = str[0:0] + "VgPG " + str[0:];
    piece_table.insert(2, "DdWF ");
    str = str[0:2] + "DdWF " + str[2:];
    piece_table.insert(0, "hUJc ");
    str = str[0:0] + "hUJc " + str[0:];
    piece_table.insert(8, "lQEq ");
    str = str[0:8] + "lQEq " + str[8:];
    piece_table.insert(10, "Gbtp ");
    str = str[0:10] + "Gbtp " + str[10:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random test 3" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "gYSz");
    str = str[0:0] + "gYSz" + str[0:];
    piece_table.insert(1, "mDQe");
    str = str[0:1] + "mDQe" + str[1:];
    piece_table.insert(1, "DTMQ");
    str = str[0:1] + "DTMQ" + str[1:];
    piece_table.insert(2, "GGZB");
    str = str[0:2] + "GGZB" + str[2:];
    piece_table.insert(12, "wXpq");
    str = str[0:12] + "wXpq" + str[12:];
    assert piece_table.get_lines_raw_content() == str;
}

test "inserts and deletes: random delete 1" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "vfb");
    str = str[0:0] + "vfb" + str[0:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.insert(0, "zRq");
    str = str[0:0] + "zRq" + str[0:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.delete(5, 1);
    str = str[0:5] + str[5 + 1:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.insert(1, "UNw");
    str = str[0:1] + "UNw" + str[1:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.delete(4, 3);
    str = str[0:4] + str[4 + 3:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.delete(1, 4);
    str = str[0:1] + str[1 + 4:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.delete(0, 1);
    str = str[0:0] + str[0 + 1:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random delete 2" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "IDT");
    str = str[0:0] + "IDT" + str[0:];
    piece_table.insert(3, "wwA");
    str = str[0:3] + "wwA" + str[3:];
    piece_table.insert(3, "Gnr");
    str = str[0:3] + "Gnr" + str[3:];
    piece_table.delete(6, 3);
    str = str[0:6] + str[6 + 3:];
    piece_table.insert(4, "eHp");
    str = str[0:4] + "eHp" + str[4:];
    piece_table.insert(1, "UAi");
    str = str[0:1] + "UAi" + str[1:];
    piece_table.insert(2, "FrR");
    str = str[0:2] + "FrR" + str[2:];
    piece_table.delete(6, 7);
    str = str[0:6] + str[6 + 7:];
    piece_table.delete(3, 5);
    str = str[0:3] + str[3 + 5:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random delete 3" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "PqM");
    str = str[0:0] + "PqM" + str[0:];
    piece_table.delete(1, 2);
    str = str[0:1] + str[1 + 2:];
    piece_table.insert(1, "zLc");
    str = str[0:1] + "zLc" + str[1:];
    piece_table.insert(0, "MEX");
    str = str[0:0] + "MEX" + str[0:];
    piece_table.insert(0, "jZh");
    str = str[0:0] + "jZh" + str[0:];
    piece_table.insert(8, "GwQ");
    str = str[0:8] + "GwQ" + str[8:];
    piece_table.delete(5, 6);
    str = str[0:5] + str[5 + 6:];
    piece_table.insert(4, "ktw");
    str = str[0:4] + "ktw" + str[4:];
    piece_table.insert(5, "GVu");
    str = str[0:5] + "GVu" + str[5:];
    piece_table.insert(9, "jdm");
    str = str[0:9] + "jdm" + str[9:];
    piece_table.insert(15, "na\n");
    str = str[0:15] + "na\n" + str[15:];
    piece_table.delete(5, 8);
    str = str[0:5] + str[5 + 8:];
    piece_table.delete(3, 4);
    str = str[0:3] + str[3 + 4:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random insert/delete r bug 1" {
    str = "a";
    piece_tree = create_text_buffer(["a"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(0, 1);
    str = str[0:0] + str[0 + 1:];
    piece_table.insert(0, "\r\r\n\n");
    str = str[0:0] + "\r\r\n\n" + str[0:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.insert(2, "\n\n\ra");
    str = str[0:2] + "\n\n\ra" + str[2:];
    piece_table.delete(4, 3);
    str = str[0:4] + str[4 + 3:];
    piece_table.insert(2, "\na\r\r");
    str = str[0:2] + "\na\r\r" + str[2:];
    piece_table.insert(6, "\ra\n\n");
    str = str[0:6] + "\ra\n\n" + str[6:];
    piece_table.insert(0, "aa\n\n");
    str = str[0:0] + "aa\n\n" + str[0:];
    piece_table.insert(5, "\n\na\r");
    str = str[0:5] + "\n\na\r" + str[5:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random insert/delete r bug 2" {
    str = "a";
    piece_tree = create_text_buffer(["a"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(1, "\naa\r");
    str = str[0:1] + "\naa\r" + str[1:];
    piece_table.delete(0, 4);
    str = str[0:0] + str[0 + 4:];
    piece_table.insert(1, "\r\r\na");
    str = str[0:1] + "\r\r\na" + str[1:];
    piece_table.insert(2, "\n\r\ra");
    str = str[0:2] + "\n\r\ra" + str[2:];
    piece_table.delete(4, 1);
    str = str[0:4] + str[4 + 1:];
    piece_table.insert(8, "\r\n\r\r");
    str = str[0:8] + "\r\n\r\r" + str[8:];
    piece_table.insert(7, "\n\n\na");
    str = str[0:7] + "\n\n\na" + str[7:];
    piece_table.insert(13, "a\n\na");
    str = str[0:13] + "a\n\na" + str[13:];
    piece_table.delete(17, 3);
    str = str[0:17] + str[17 + 3:];
    piece_table.insert(2, "a\ra\n");
    str = str[0:2] + "a\ra\n" + str[2:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random insert/delete r bug 3" {
    str = "a";
    piece_tree = create_text_buffer(["a"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\r\na\r");
    str = str[0:0] + "\r\na\r" + str[0:];
    piece_table.delete(2, 3);
    str = str[0:2] + str[2 + 3:];
    piece_table.insert(2, "a\r\n\r");
    str = str[0:2] + "a\r\n\r" + str[2:];
    piece_table.delete(4, 2);
    str = str[0:4] + str[4 + 2:];
    piece_table.insert(4, "a\n\r\n");
    str = str[0:4] + "a\n\r\n" + str[4:];
    piece_table.insert(1, "aa\n\r");
    str = str[0:1] + "aa\n\r" + str[1:];
    piece_table.insert(7, "\na\r\n");
    str = str[0:7] + "\na\r\n" + str[7:];
    piece_table.insert(5, "\n\na\r");
    str = str[0:5] + "\n\na\r" + str[5:];
    piece_table.insert(10, "\r\r\n\r");
    str = str[0:10] + "\r\r\n\r" + str[10:];
    assert piece_table.get_lines_raw_content() == str;
    piece_table.delete(21, 3);
    str = str[0:21] + str[21 + 3:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random insert/delete r bug 4s" {
    str = "a";
    piece_tree = create_text_buffer(["a"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(0, 1);
    str = str[0:0] + str[0 + 1:];
    piece_table.insert(0, "\naaa");
    str = str[0:0] + "\naaa" + str[0:];
    piece_table.insert(2, "\n\naa");
    str = str[0:2] + "\n\naa" + str[2:];
    piece_table.delete(1, 4);
    str = str[0:1] + str[1 + 4:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.delete(1, 2);
    str = str[0:1] + str[1 + 2:];
    piece_table.delete(0, 1);
    str = str[0:0] + str[0 + 1:];
    piece_table.insert(0, "a\n\n\r");
    str = str[0:0] + "a\n\n\r" + str[0:];
    piece_table.insert(2, "aa\r\n");
    str = str[0:2] + "aa\r\n" + str[2:];
    piece_table.insert(3, "a\naa");
    str = str[0:3] + "a\naa" + str[3:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

test "inserts and deletes: random insert/delete r bug 5" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\n\r");
    str = str[0:0] + "\n\n\n\r" + str[0:];
    piece_table.insert(1, "\n\n\n\r");
    str = str[0:1] + "\n\n\n\r" + str[1:];
    piece_table.insert(2, "\n\r\r\r");
    str = str[0:2] + "\n\r\r\r" + str[2:];
    piece_table.insert(8, "\n\r\n\r");
    str = str[0:8] + "\n\r\n\r" + str[8:];
    piece_table.delete(5, 2);
    str = str[0:5] + str[5 + 2:];
    piece_table.insert(4, "\n\r\r\r");
    str = str[0:4] + "\n\r\r\r" + str[4:];
    piece_table.insert(8, "\n\n\n\r");
    str = str[0:8] + "\n\n\n\r" + str[8:];
    piece_table.delete(0, 7);
    str = str[0:0] + str[0 + 7:];
    piece_table.insert(1, "\r\n\r\r");
    str = str[0:1] + "\r\n\r\r" + str[1:];
    piece_table.insert(15, "\n\r\r\r");
    str = str[0:15] + "\n\r\r\r" + str[15:];
    assert piece_table.get_lines_raw_content() == str;
    assert_tree_invariants(piece_table);
}

# ===== suite: prefix sum for line feed (11 tests) =====
test "prefix sum for line feed: basic" {
    piece_tree = create_text_buffer(["1\n2\n3\n4"]);
    piece_table = piece_tree.get_piece_tree();
    assert piece_table.get_line_count() == 4;
    assert_position(piece_table.get_position_at(0), 1, 1);
    assert_position(piece_table.get_position_at(1), 1, 2);
    assert_position(piece_table.get_position_at(2), 2, 1);
    assert_position(piece_table.get_position_at(3), 2, 2);
    assert_position(piece_table.get_position_at(4), 3, 1);
    assert_position(piece_table.get_position_at(5), 3, 2);
    assert_position(piece_table.get_position_at(6), 4, 1);
    assert piece_table.get_offset_at(1, 1) == 0;
    assert piece_table.get_offset_at(1, 2) == 1;
    assert piece_table.get_offset_at(2, 1) == 2;
    assert piece_table.get_offset_at(2, 2) == 3;
    assert piece_table.get_offset_at(3, 1) == 4;
    assert piece_table.get_offset_at(3, 2) == 5;
    assert piece_table.get_offset_at(4, 1) == 6;
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: append" {
    piece_tree = create_text_buffer(["a\nb\nc\nde"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(8, "fh\ni\njk");
    assert piece_table.get_line_count() == 6;
    assert_position(piece_table.get_position_at(9), 4, 4);
    assert piece_table.get_offset_at(1, 1) == 0;
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: insert" {
    piece_tree = create_text_buffer(["a\nb\nc\nde"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(7, "fh\ni\njk");
    assert piece_table.get_line_count() == 6;
    assert_position(piece_table.get_position_at(6), 4, 1);
    assert_position(piece_table.get_position_at(7), 4, 2);
    assert_position(piece_table.get_position_at(8), 4, 3);
    assert_position(piece_table.get_position_at(9), 4, 4);
    assert_position(piece_table.get_position_at(12), 6, 1);
    assert_position(piece_table.get_position_at(13), 6, 2);
    assert_position(piece_table.get_position_at(14), 6, 3);
    assert piece_table.get_offset_at(4, 1) == 6;
    assert piece_table.get_offset_at(4, 2) == 7;
    assert piece_table.get_offset_at(4, 3) == 8;
    assert piece_table.get_offset_at(4, 4) == 9;
    assert piece_table.get_offset_at(6, 1) == 12;
    assert piece_table.get_offset_at(6, 2) == 13;
    assert piece_table.get_offset_at(6, 3) == 14;
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: delete" {
    piece_tree = create_text_buffer(["a\nb\nc\ndefh\ni\njk"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(7, 2);
    assert piece_table.get_lines_raw_content() == "a\nb\nc\ndh\ni\njk";
    assert piece_table.get_line_count() == 6;
    assert_position(piece_table.get_position_at(6), 4, 1);
    assert_position(piece_table.get_position_at(7), 4, 2);
    assert_position(piece_table.get_position_at(8), 4, 3);
    assert_position(piece_table.get_position_at(9), 5, 1);
    assert_position(piece_table.get_position_at(11), 6, 1);
    assert_position(piece_table.get_position_at(12), 6, 2);
    assert_position(piece_table.get_position_at(13), 6, 3);
    assert piece_table.get_offset_at(4, 1) == 6;
    assert piece_table.get_offset_at(4, 2) == 7;
    assert piece_table.get_offset_at(4, 3) == 8;
    assert piece_table.get_offset_at(5, 1) == 9;
    assert piece_table.get_offset_at(6, 1) == 11;
    assert piece_table.get_offset_at(6, 2) == 12;
    assert piece_table.get_offset_at(6, 3) == 13;
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: add+delete 1" {
    piece_tree = create_text_buffer(["a\nb\nc\nde"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(8, "fh\ni\njk");
    piece_table.delete(7, 2);
    assert piece_table.get_lines_raw_content() == "a\nb\nc\ndh\ni\njk";
    assert piece_table.get_line_count() == 6;
    assert_position(piece_table.get_position_at(6), 4, 1);
    assert_position(piece_table.get_position_at(7), 4, 2);
    assert_position(piece_table.get_position_at(8), 4, 3);
    assert_position(piece_table.get_position_at(9), 5, 1);
    assert_position(piece_table.get_position_at(11), 6, 1);
    assert_position(piece_table.get_position_at(12), 6, 2);
    assert_position(piece_table.get_position_at(13), 6, 3);
    assert piece_table.get_offset_at(4, 1) == 6;
    assert piece_table.get_offset_at(4, 2) == 7;
    assert piece_table.get_offset_at(4, 3) == 8;
    assert piece_table.get_offset_at(5, 1) == 9;
    assert piece_table.get_offset_at(6, 1) == 11;
    assert piece_table.get_offset_at(6, 2) == 12;
    assert piece_table.get_offset_at(6, 3) == 13;
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: insert random bug 1: prefixSumComputer.removeValues(start, cnt) cnt is 1 based." {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, " ZX \n Z\nZ\n YZ\nY\nZXX ");
    str = str[0:0] + " ZX \n Z\nZ\n YZ\nY\nZXX " + str[0:];
    piece_table.insert(14, "X ZZ\nYZZYZXXY Y XY\n ");
    str = str[0:14] + "X ZZ\nYZZYZXXY Y XY\n " + str[14:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: insert random bug 2: prefixSumComputer initialize does not do deep copy of UInt32Array." {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "ZYZ\nYY XY\nX \nZ Y \nZ ");
    str = str[0:0] + "ZYZ\nYY XY\nX \nZ Y \nZ " + str[0:];
    piece_table.insert(3, "XXY \n\nY Y YYY  ZYXY ");
    str = str[0:3] + "XXY \n\nY Y YYY  ZYXY " + str[3:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: delete random bug 1: I forgot to update the lineFeedCnt when deletion is on one single piece." {
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "ba\na\nca\nba\ncbab\ncaa ");
    piece_table.insert(13, "cca\naabb\ncac\nccc\nab ");
    piece_table.delete(5, 8);
    piece_table.delete(30, 2);
    piece_table.insert(24, "cbbacccbac\nbaaab\n\nc ");
    piece_table.delete(29, 3);
    piece_table.delete(23, 9);
    piece_table.delete(21, 5);
    piece_table.delete(30, 3);
    piece_table.insert(3, "cb\nac\nc\n\nacc\nbb\nb\nc ");
    piece_table.delete(19, 5);
    piece_table.insert(18, "\nbb\n\nacbc\ncbb\nc\nbb\n ");
    piece_table.insert(65, "cbccbac\nbc\n\nccabba\n ");
    piece_table.insert(77, "a\ncacb\n\nac\n\n\n\n\nabab ");
    piece_table.delete(30, 9);
    piece_table.insert(45, "b\n\nc\nba\n\nbbbba\n\naa\n ");
    piece_table.insert(82, "ab\nbb\ncabacab\ncbc\na ");
    piece_table.delete(123, 9);
    piece_table.delete(71, 2);
    piece_table.insert(33, "acaa\nacb\n\naa\n\nc\n\n\n\n ");
    str = piece_table.get_lines_raw_content();
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: delete random bug rb tree 1" {
    str = "";
    piece_tree = create_text_buffer([str]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "YXXZ\n\nYY\n");
    str = str[0:0] + "YXXZ\n\nYY\n" + str[0:];
    piece_table.delete(0, 5);
    str = str[0:0] + str[0 + 5:];
    piece_table.insert(0, "ZXYY\nX\nZ\n");
    str = str[0:0] + "ZXYY\nX\nZ\n" + str[0:];
    piece_table.insert(10, "\nXY\nYXYXY");
    str = str[0:10] + "\nXY\nYXYXY" + str[10:];
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: delete random bug rb tree 2" {
    str = "";
    piece_tree = create_text_buffer([str]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "YXXZ\n\nYY\n");
    str = str[0:0] + "YXXZ\n\nYY\n" + str[0:];
    piece_table.insert(0, "ZXYY\nX\nZ\n");
    str = str[0:0] + "ZXYY\nX\nZ\n" + str[0:];
    piece_table.insert(10, "\nXY\nYXYXY");
    str = str[0:10] + "\nXY\nYXYXY" + str[10:];
    piece_table.insert(8, "YZXY\nZ\nYX");
    str = str[0:8] + "YZXY\nZ\nYX" + str[8:];
    piece_table.insert(12, "XX\nXXYXYZ");
    str = str[0:12] + "XX\nXXYXYZ" + str[12:];
    piece_table.delete(0, 4);
    str = str[0:0] + str[0 + 4:];
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "prefix sum for line feed: delete random bug rb tree 3" {
    str = "";
    piece_tree = create_text_buffer([str]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "YXXZ\n\nYY\n");
    str = str[0:0] + "YXXZ\n\nYY\n" + str[0:];
    piece_table.delete(7, 2);
    str = str[0:7] + str[7 + 2:];
    piece_table.delete(6, 1);
    str = str[0:6] + str[6 + 1:];
    piece_table.delete(0, 5);
    str = str[0:0] + str[0 + 5:];
    piece_table.insert(0, "ZXYY\nX\nZ\n");
    str = str[0:0] + "ZXYY\nX\nZ\n" + str[0:];
    piece_table.insert(10, "\nXY\nYXYXY");
    str = str[0:10] + "\nXY\nYXYXY" + str[10:];
    piece_table.insert(8, "YZXY\nZ\nYX");
    str = str[0:8] + "YZXY\nZ\nYX" + str[8:];
    piece_table.insert(12, "XX\nXXYXYZ");
    str = str[0:12] + "XX\nXXYXYZ" + str[12:];
    piece_table.delete(0, 4);
    str = str[0:0] + str[0 + 4:];
    piece_table.delete(30, 3);
    str = str[0:30] + str[30 + 3:];
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: offset 2 position (1 test) =====
test "offset 2 position: random tests bug 1" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "huuyYzUfKOENwGgZLqn ");
    str = str[0:0] + "huuyYzUfKOENwGgZLqn " + str[0:];
    piece_table.delete(18, 2);
    str = str[0:18] + str[18 + 2:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.delete(12, 4);
    str = str[0:12] + str[12 + 4:];
    piece_table.insert(3, "hMbnVEdTSdhLlPevXKF ");
    str = str[0:3] + "hMbnVEdTSdhLlPevXKF " + str[3:];
    piece_table.delete(22, 8);
    str = str[0:22] + str[22 + 8:];
    piece_table.insert(4, "S umSnYrqOmOAV\nEbZJ ");
    str = str[0:4] + "S umSnYrqOmOAV\nEbZJ " + str[4:];
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: get text in range (10 tests) =====
test "get text in range: getContentInRange" {
    piece_tree = create_text_buffer(["a\nb\nc\nde"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(8, "fh\ni\njk");
    piece_table.delete(7, 2);
    assert piece_table.get_value_in_range(Range(start_line_number=1, start_column=1, end_line_number=1, end_column=3)) == "a\n";
    assert piece_table.get_value_in_range(Range(start_line_number=2, start_column=1, end_line_number=2, end_column=3)) == "b\n";
    assert piece_table.get_value_in_range(Range(start_line_number=3, start_column=1, end_line_number=3, end_column=3)) == "c\n";
    assert piece_table.get_value_in_range(Range(start_line_number=4, start_column=1, end_line_number=4, end_column=4)) == "dh\n";
    assert piece_table.get_value_in_range(Range(start_line_number=5, start_column=1, end_line_number=5, end_column=3)) == "i\n";
    assert piece_table.get_value_in_range(Range(start_line_number=6, start_column=1, end_line_number=6, end_column=3)) == "jk";
    assert_tree_invariants(piece_table);
}

test "get text in range: random test value in range" {
    str = "";
    piece_tree = create_text_buffer([str]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "ZXXY");
    str = str[0:0] + "ZXXY" + str[0:];
    piece_table.insert(1, "XZZY");
    str = str[0:1] + "XZZY" + str[1:];
    piece_table.insert(5, "\nX\n\n");
    str = str[0:5] + "\nX\n\n" + str[5:];
    piece_table.insert(3, "\nXX\n");
    str = str[0:3] + "\nXX\n" + str[3:];
    piece_table.insert(12, "YYYX");
    str = str[0:12] + "YYYX" + str[12:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "get text in range: random test value in range exception" {
    str = "";
    piece_tree = create_text_buffer([str]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "XZ\nZ");
    str = str[0:0] + "XZ\nZ" + str[0:];
    piece_table.delete(0, 3);
    str = str[0:0] + str[0 + 3:];
    piece_table.delete(0, 1);
    str = str[0:0] + str[0 + 1:];
    piece_table.insert(0, "ZYX\n");
    str = str[0:0] + "ZYX\n" + str[0:];
    piece_table.delete(0, 4);
    str = str[0:0] + str[0 + 4:];
    piece_table.get_value_in_range(Range(start_line_number=1, start_column=1, end_line_number=1, end_column=1));
    assert_tree_invariants(piece_table);
}

test "get text in range: random tests bug 1" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "huuyYzUfKOENwGgZLqn ");
    str = str[0:0] + "huuyYzUfKOENwGgZLqn " + str[0:];
    piece_table.delete(18, 2);
    str = str[0:18] + str[18 + 2:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.delete(12, 4);
    str = str[0:12] + str[12 + 4:];
    piece_table.insert(3, "hMbnVEdTSdhLlPevXKF ");
    str = str[0:3] + "hMbnVEdTSdhLlPevXKF " + str[3:];
    piece_table.delete(22, 8);
    str = str[0:22] + str[22 + 8:];
    piece_table.insert(4, "S umSnYrqOmOAV\nEbZJ ");
    str = str[0:4] + "S umSnYrqOmOAV\nEbZJ " + str[4:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "get text in range: random tests bug 2" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "xfouRDZwdAHjVXJAMV\n ");
    str = str[0:0] + "xfouRDZwdAHjVXJAMV\n " + str[0:];
    piece_table.insert(16, "dBGndxpFZBEAIKykYYx ");
    str = str[0:16] + "dBGndxpFZBEAIKykYYx " + str[16:];
    piece_table.delete(7, 6);
    str = str[0:7] + str[7 + 6:];
    piece_table.delete(9, 7);
    str = str[0:9] + str[9 + 7:];
    piece_table.delete(17, 6);
    str = str[0:17] + str[17 + 6:];
    piece_table.delete(0, 4);
    str = str[0:0] + str[0 + 4:];
    piece_table.insert(9, "qvEFXCNvVkWgvykahYt ");
    str = str[0:9] + "qvEFXCNvVkWgvykahYt " + str[9:];
    piece_table.delete(4, 6);
    str = str[0:4] + str[4 + 6:];
    piece_table.insert(11, "OcSChUYT\nzPEBOpsGmR ");
    str = str[0:11] + "OcSChUYT\nzPEBOpsGmR " + str[11:];
    piece_table.insert(15, "KJCozaXTvkE\nxnqAeTz ");
    str = str[0:15] + "KJCozaXTvkE\nxnqAeTz " + str[15:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "get text in range: get line content" {
    piece_tree = create_text_buffer(["1"]);
    piece_table = piece_tree.get_piece_tree();
    assert piece_table.get_line_raw_content(1, 0) == "1";
    piece_table.insert(1, "2");
    assert piece_table.get_line_raw_content(1, 0) == "12";
    assert_tree_invariants(piece_table);
}

test "get text in range: get line content basic" {
    piece_tree = create_text_buffer(["1\n2\n3\n4"]);
    piece_table = piece_tree.get_piece_tree();
    assert piece_table.get_line_raw_content(1, 0) == "1\n";
    assert piece_table.get_line_raw_content(2, 0) == "2\n";
    assert piece_table.get_line_raw_content(3, 0) == "3\n";
    assert piece_table.get_line_raw_content(4, 0) == "4";
    assert_tree_invariants(piece_table);
}

test "get text in range: get line content after inserts/deletes" {
    piece_tree = create_text_buffer(["a\nb\nc\nde"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(8, "fh\ni\njk");
    piece_table.delete(7, 2);
    assert piece_table.get_line_raw_content(1, 0) == "a\n";
    assert piece_table.get_line_raw_content(2, 0) == "b\n";
    assert piece_table.get_line_raw_content(3, 0) == "c\n";
    assert piece_table.get_line_raw_content(4, 0) == "dh\n";
    assert piece_table.get_line_raw_content(5, 0) == "i\n";
    assert piece_table.get_line_raw_content(6, 0) == "jk";
    assert_tree_invariants(piece_table);
}

test "get text in range: random 1" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "J eNnDzQpnlWyjmUu\ny ");
    str = str[0:0] + "J eNnDzQpnlWyjmUu\ny " + str[0:];
    piece_table.insert(0, "QPEeRAQmRwlJqtZSWhQ ");
    str = str[0:0] + "QPEeRAQmRwlJqtZSWhQ " + str[0:];
    piece_table.delete(5, 1);
    str = str[0:5] + str[5 + 1:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "get text in range: random 2" {
    str = "";
    piece_tree = create_text_buffer([""]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "DZoQ tglPCRHMltejRI ");
    str = str[0:0] + "DZoQ tglPCRHMltejRI " + str[0:];
    piece_table.insert(10, "JRXiyYqJ qqdcmbfkKX ");
    str = str[0:10] + "JRXiyYqJ qqdcmbfkKX " + str[10:];
    piece_table.delete(16, 3);
    str = str[0:16] + str[16 + 3:];
    piece_table.delete(25, 1);
    str = str[0:25] + str[25 + 1:];
    piece_table.insert(18, "vH\nNlvfqQJPm\nSFkhMc ");
    str = str[0:18] + "vH\nNlvfqQJPm\nSFkhMc " + str[18:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: CRLF (12 tests) =====
test "CRLF: delete CR in CRLF 1" {
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "a\r\nb");
    piece_table.delete(0, 2);
    assert piece_table.get_line_count() == 2;
    assert_tree_invariants(piece_table);
}

test "CRLF: delete CR in CRLF 2" {
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "a\r\nb");
    piece_table.delete(2, 2);
    assert piece_table.get_line_count() == 2;
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 1" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\r\r");
    str = str[0:0] + "\n\n\r\r" + str[0:];
    piece_table.insert(1, "\r\n\r\n");
    str = str[0:1] + "\r\n\r\n" + str[1:];
    piece_table.delete(5, 3);
    str = str[0:5] + str[5 + 3:];
    piece_table.delete(2, 3);
    str = str[0:2] + str[2 + 3:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 2" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\r\n\r");
    str = str[0:0] + "\n\r\n\r" + str[0:];
    piece_table.insert(2, "\n\r\r\r");
    str = str[0:2] + "\n\r\r\r" + str[2:];
    piece_table.delete(4, 1);
    str = str[0:4] + str[4 + 1:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 3" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\n\r");
    str = str[0:0] + "\n\n\n\r" + str[0:];
    piece_table.delete(2, 2);
    str = str[0:2] + str[2 + 2:];
    piece_table.delete(0, 2);
    str = str[0:0] + str[0 + 2:];
    piece_table.insert(0, "\r\r\r\r");
    str = str[0:0] + "\r\r\r\r" + str[0:];
    piece_table.insert(2, "\r\n\r\r");
    str = str[0:2] + "\r\n\r\r" + str[2:];
    piece_table.insert(3, "\r\r\r\n");
    str = str[0:3] + "\r\r\r\n" + str[3:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 4" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\n\n");
    str = str[0:0] + "\n\n\n\n" + str[0:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.insert(1, "\r\r\r\r");
    str = str[0:1] + "\r\r\r\r" + str[1:];
    piece_table.insert(6, "\r\n\n\r");
    str = str[0:6] + "\r\n\n\r" + str[6:];
    piece_table.delete(5, 3);
    str = str[0:5] + str[5 + 3:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 5" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\n\n");
    str = str[0:0] + "\n\n\n\n" + str[0:];
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.insert(0, "\n\r\r\n");
    str = str[0:0] + "\n\r\r\n" + str[0:];
    piece_table.insert(4, "\n\r\r\n");
    str = str[0:4] + "\n\r\r\n" + str[4:];
    piece_table.delete(4, 3);
    str = str[0:4] + str[4 + 3:];
    piece_table.insert(5, "\r\r\n\r");
    str = str[0:5] + "\r\r\n\r" + str[5:];
    piece_table.insert(12, "\n\n\n\r");
    str = str[0:12] + "\n\n\n\r" + str[12:];
    piece_table.insert(5, "\r\r\r\n");
    str = str[0:5] + "\r\r\r\n" + str[5:];
    piece_table.insert(20, "\n\n\r\n");
    str = str[0:20] + "\n\n\r\n" + str[20:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 6" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\r\r\n");
    str = str[0:0] + "\n\r\r\n" + str[0:];
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(3, "\r\n\n\n");
    str = str[0:3] + "\r\n\n\n" + str[3:];
    piece_table.delete(4, 8);
    str = str[0:4] + str[4 + 8:];
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(0, "\r\n\n\r");
    str = str[0:0] + "\r\n\n\r" + str[0:];
    piece_table.delete(4, 0);
    str = str[0:4] + str[4 + 0:];
    piece_table.delete(8, 4);
    str = str[0:8] + str[8 + 4:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 8" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\r\n\n\r");
    str = str[0:0] + "\r\n\n\r" + str[0:];
    piece_table.delete(1, 0);
    str = str[0:1] + str[1 + 0:];
    piece_table.insert(3, "\n\n\n\r");
    str = str[0:3] + "\n\n\n\r" + str[3:];
    piece_table.insert(7, "\n\n\r\n");
    str = str[0:7] + "\n\n\r\n" + str[7:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 7" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\r\r\n\n");
    str = str[0:0] + "\r\r\n\n" + str[0:];
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(7, "\n\r\r\r");
    str = str[0:7] + "\n\r\r\r" + str[7:];
    piece_table.insert(11, "\n\n\r\n");
    str = str[0:11] + "\n\n\r\n" + str[11:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 10" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "qneW");
    str = str[0:0] + "qneW" + str[0:];
    piece_table.insert(0, "YhIl");
    str = str[0:0] + "YhIl" + str[0:];
    piece_table.insert(0, "qdsm");
    str = str[0:0] + "qdsm" + str[0:];
    piece_table.delete(7, 0);
    str = str[0:7] + str[7 + 0:];
    piece_table.insert(12, "iiPv");
    str = str[0:12] + "iiPv" + str[12:];
    piece_table.insert(9, "V\rSA");
    str = str[0:9] + "V\rSA" + str[9:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "CRLF: random bug 9" {
    str = "";
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "\n\n\n\n");
    str = str[0:0] + "\n\n\n\n" + str[0:];
    piece_table.insert(3, "\n\r\n\r");
    str = str[0:3] + "\n\r\n\r" + str[3:];
    piece_table.insert(2, "\n\r\n\n");
    str = str[0:2] + "\n\r\n\n" + str[2:];
    piece_table.insert(0, "\n\n\r\r");
    str = str[0:0] + "\n\n\r\r" + str[0:];
    piece_table.insert(3, "\r\r\r\r");
    str = str[0:3] + "\r\r\r\r" + str[3:];
    piece_table.insert(3, "\n\n\r\r");
    str = str[0:3] + "\n\n\r\r" + str[3:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: centralized lineStarts with CRLF (16 tests) =====
test "centralized lineStarts with CRLF: delete CR in CRLF 1" {
    piece_tree = create_text_buffer(["a\r\nb"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(2, 2);
    assert piece_table.get_line_count() == 2;
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: delete CR in CRLF 2" {
    piece_tree = create_text_buffer(["a\r\nb"]);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(0, 2);
    assert piece_table.get_line_count() == 2;
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 1" {
    str = "\n\n\r\r";
    piece_tree = create_text_buffer(["\n\n\r\r"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(1, "\r\n\r\n");
    str = str[0:1] + "\r\n\r\n" + str[1:];
    piece_table.delete(5, 3);
    str = str[0:5] + str[5 + 3:];
    piece_table.delete(2, 3);
    str = str[0:2] + str[2 + 3:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 2" {
    str = "\n\r\n\r";
    piece_tree = create_text_buffer(["\n\r\n\r"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(2, "\n\r\r\r");
    str = str[0:2] + "\n\r\r\r" + str[2:];
    piece_table.delete(4, 1);
    str = str[0:4] + str[4 + 1:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 3" {
    str = "\n\n\n\r";
    piece_tree = create_text_buffer(["\n\n\n\r"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(2, 2);
    str = str[0:2] + str[2 + 2:];
    piece_table.delete(0, 2);
    str = str[0:0] + str[0 + 2:];
    piece_table.insert(0, "\r\r\r\r");
    str = str[0:0] + "\r\r\r\r" + str[0:];
    piece_table.insert(2, "\r\n\r\r");
    str = str[0:2] + "\r\n\r\r" + str[2:];
    piece_table.insert(3, "\r\r\r\n");
    str = str[0:3] + "\r\r\r\n" + str[3:];
    lines = split_lines(str);
    assert piece_table.get_line_count() == len(lines);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 4" {
    str = "\n\n\n\n";
    piece_tree = create_text_buffer(["\n\n\n\n"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.insert(1, "\r\r\r\r");
    str = str[0:1] + "\r\r\r\r" + str[1:];
    piece_table.insert(6, "\r\n\n\r");
    str = str[0:6] + "\r\n\n\r" + str[6:];
    piece_table.delete(5, 3);
    str = str[0:5] + str[5 + 3:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 5" {
    str = "\n\n\n\n";
    piece_tree = create_text_buffer(["\n\n\n\n"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(3, 1);
    str = str[0:3] + str[3 + 1:];
    piece_table.insert(0, "\n\r\r\n");
    str = str[0:0] + "\n\r\r\n" + str[0:];
    piece_table.insert(4, "\n\r\r\n");
    str = str[0:4] + "\n\r\r\n" + str[4:];
    piece_table.delete(4, 3);
    str = str[0:4] + str[4 + 3:];
    piece_table.insert(5, "\r\r\n\r");
    str = str[0:5] + "\r\r\n\r" + str[5:];
    piece_table.insert(12, "\n\n\n\r");
    str = str[0:12] + "\n\n\n\r" + str[12:];
    piece_table.insert(5, "\r\r\r\n");
    str = str[0:5] + "\r\r\r\n" + str[5:];
    piece_table.insert(20, "\n\n\r\n");
    str = str[0:20] + "\n\n\r\n" + str[20:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 6" {
    str = "\n\r\r\n";
    piece_tree = create_text_buffer(["\n\r\r\n"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(3, "\r\n\n\n");
    str = str[0:3] + "\r\n\n\n" + str[3:];
    piece_table.delete(4, 8);
    str = str[0:4] + str[4 + 8:];
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(0, "\r\n\n\r");
    str = str[0:0] + "\r\n\n\r" + str[0:];
    piece_table.delete(4, 0);
    str = str[0:4] + str[4 + 0:];
    piece_table.delete(8, 4);
    str = str[0:8] + str[8 + 4:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 7" {
    str = "\r\n\n\r";
    piece_tree = create_text_buffer(["\r\n\n\r"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.delete(1, 0);
    str = str[0:1] + str[1 + 0:];
    piece_table.insert(3, "\n\n\n\r");
    str = str[0:3] + "\n\n\n\r" + str[3:];
    piece_table.insert(7, "\n\n\r\n");
    str = str[0:7] + "\n\n\r\n" + str[7:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 8" {
    str = "\r\r\n\n";
    piece_tree = create_text_buffer(["\r\r\n\n"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(4, "\r\n\n\r");
    str = str[0:4] + "\r\n\n\r" + str[4:];
    piece_table.insert(7, "\n\r\r\r");
    str = str[0:7] + "\n\r\r\r" + str[7:];
    piece_table.insert(11, "\n\n\r\n");
    str = str[0:11] + "\n\n\r\n" + str[11:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 9" {
    str = "qneW";
    piece_tree = create_text_buffer(["qneW"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(0, "YhIl");
    str = str[0:0] + "YhIl" + str[0:];
    piece_table.insert(0, "qdsm");
    str = str[0:0] + "qdsm" + str[0:];
    piece_table.delete(7, 0);
    str = str[0:7] + str[7 + 0:];
    piece_table.insert(12, "iiPv");
    str = str[0:12] + "iiPv" + str[12:];
    piece_table.insert(9, "V\rSA");
    str = str[0:9] + "V\rSA" + str[9:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random bug 10" {
    str = "\n\n\n\n";
    piece_tree = create_text_buffer(["\n\n\n\n"], False);
    piece_table = piece_tree.get_piece_tree();
    piece_table.insert(3, "\n\r\n\r");
    str = str[0:3] + "\n\r\n\r" + str[3:];
    piece_table.insert(2, "\n\r\n\n");
    str = str[0:2] + "\n\r\n\n" + str[2:];
    piece_table.insert(0, "\n\n\r\r");
    str = str[0:0] + "\n\n\r\r" + str[0:];
    piece_table.insert(3, "\r\r\r\r");
    str = str[0:3] + "\r\r\r\r" + str[3:];
    piece_table.insert(3, "\n\n\r\r");
    str = str[0:3] + "\n\n\r\r" + str[3:];
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random chunk bug 1" {
    piece_tree = create_text_buffer(["\n\r\r\n\n\n\r\n\r"], False);
    piece_table = piece_tree.get_piece_tree();
    str = "\n\r\r\n\n\n\r\n\r";
    piece_table.delete(0, 2);
    str = str[0:0] + str[0 + 2:];
    piece_table.insert(1, "\r\r\n\n");
    str = str[0:1] + "\r\r\n\n" + str[1:];
    piece_table.insert(7, "\r\r\r\r");
    str = str[0:7] + "\r\r\r\r" + str[7:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random chunk bug 2" {
    piece_tree = create_text_buffer(["\n\r\n\n\n\r\n\r\n\r\r\n\n\n\r\r\n\r\n"], False);
    piece_table = piece_tree.get_piece_tree();
    str = "\n\r\n\n\n\r\n\r\n\r\r\n\n\n\r\r\n\r\n";
    piece_table.insert(16, "\r\n\r\r");
    str = str[0:16] + "\r\n\r\r" + str[16:];
    piece_table.insert(13, "\n\n\r\r");
    str = str[0:13] + "\n\n\r\r" + str[13:];
    piece_table.insert(19, "\n\n\r\n");
    str = str[0:19] + "\n\n\r\n" + str[19:];
    piece_table.delete(5, 0);
    str = str[0:5] + str[5 + 0:];
    piece_table.delete(11, 2);
    str = str[0:11] + str[11 + 2:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random chunk bug 3" {
    piece_tree = create_text_buffer(["\r\n\n\n\n\n\n\r\n"], False);
    piece_table = piece_tree.get_piece_tree();
    str = "\r\n\n\n\n\n\n\r\n";
    piece_table.insert(4, "\n\n\r\n\r\r\n\n\r");
    str = str[0:4] + "\n\n\r\n\r\r\n\n\r" + str[4:];
    piece_table.delete(4, 4);
    str = str[0:4] + str[4 + 4:];
    piece_table.insert(11, "\r\n\r\n\n\r\r\n\n");
    str = str[0:11] + "\r\n\r\n\n\r\r\n\n" + str[11:];
    piece_table.delete(1, 2);
    str = str[0:1] + str[1 + 2:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "centralized lineStarts with CRLF: random chunk bug 4" {
    piece_tree = create_text_buffer(["\n\r\n\r"], False);
    piece_table = piece_tree.get_piece_tree();
    str = "\n\r\n\r";
    piece_table.insert(4, "\n\n\r\n");
    str = str[0:4] + "\n\n\r\n" + str[4:];
    piece_table.insert(3, "\r\n\n\n");
    str = str[0:3] + "\r\n\n\n" + str[3:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: search offset cache (5 tests) =====
test "search offset cache: render white space exception" {
    piece_tree = create_text_buffer(["class Name{\n\t\n\t\t\tget() {\n\n\t\t\t}\n\t\t}"]);
    piece_table = piece_tree.get_piece_tree();
    str = "class Name{\n\t\n\t\t\tget() {\n\n\t\t\t}\n\t\t}";
    piece_table.insert(12, "s");
    str = str[0:12] + "s" + str[12:];
    piece_table.insert(13, "e");
    str = str[0:13] + "e" + str[13:];
    piece_table.insert(14, "t");
    str = str[0:14] + "t" + str[14:];
    piece_table.insert(15, "()");
    str = str[0:15] + "()" + str[15:];
    piece_table.delete(16, 1);
    str = str[0:16] + str[16 + 1:];
    piece_table.insert(17, "()");
    str = str[0:17] + "()" + str[17:];
    piece_table.delete(18, 1);
    str = str[0:18] + str[18 + 1:];
    piece_table.insert(18, "}");
    str = str[0:18] + "}" + str[18:];
    piece_table.insert(12, "\n");
    str = str[0:12] + "\n" + str[12:];
    piece_table.delete(12, 1);
    str = str[0:12] + str[12 + 1:];
    piece_table.delete(18, 1);
    str = str[0:18] + str[18 + 1:];
    piece_table.insert(18, "}");
    str = str[0:18] + "}" + str[18:];
    piece_table.delete(17, 2);
    str = str[0:17] + str[17 + 2:];
    piece_table.delete(16, 1);
    str = str[0:16] + str[16 + 1:];
    piece_table.insert(16, ")");
    str = str[0:16] + ")" + str[16:];
    piece_table.delete(15, 2);
    str = str[0:15] + str[15 + 2:];
    content = piece_table.get_lines_raw_content();
    assert content == str;
}

test "search offset cache: Line breaks replacement is not necessary when EOL is normalized" {
    piece_tree = create_text_buffer(["abc"]);
    piece_table = piece_tree.get_piece_tree();
    str = "abc";
    piece_table.insert(3, "def\nabc");
    str = str + "def\nabc";
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "search offset cache: Line breaks replacement is not necessary when EOL is normalized 2" {
    piece_tree = create_text_buffer(["abc\n"]);
    piece_table = piece_tree.get_piece_tree();
    str = "abc\n";
    piece_table.insert(4, "def\nabc");
    str = str + "def\nabc";
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "search offset cache: Line breaks replacement is not necessary when EOL is normalized 3" {
    piece_tree = create_text_buffer(["abc\n"]);
    piece_table = piece_tree.get_piece_tree();
    str = "abc\n";
    piece_table.insert(2, "def\nabc");
    str = str[0:2] + "def\nabc" + str[2:];
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "search offset cache: Line breaks replacement is not necessary when EOL is normalized 4" {
    piece_tree = create_text_buffer(["abc\n"]);
    piece_table = piece_tree.get_piece_tree();
    str = "abc\n";
    piece_table.insert(3, "def\nabc");
    str = str[0:3] + "def\nabc" + str[3:];
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===================================================================================
# Hand-ported suites (too structurally different from the mechanical shape above, or
# requiring a genuine adaptation -- see this file's top docstring for the `snapshot`
# suite's adaptation rationale).
# ===================================================================================

# ===== suite: buffer api (7 tests) =====
test "buffer api: equal" {
    a = create_text_buffer(["abc"]);
    b = create_text_buffer(["ab", "c"]);
    c = create_text_buffer(["abd"]);
    d = create_text_buffer(["abcd"]);
    assert a.get_piece_tree().equal(b.get_piece_tree());
    assert not a.get_piece_tree().equal(c.get_piece_tree());
    assert not a.get_piece_tree().equal(d.get_piece_tree());
}

test "buffer api: equal with more chunks" {
    a = create_text_buffer(["ab", "cd", "e"]);
    b = create_text_buffer(["ab", "c", "de"]);
    assert a.get_piece_tree().equal(b.get_piece_tree());
}

test "buffer api: equal 2, empty buffer" {
    a = create_text_buffer([""]);
    b = create_text_buffer([""]);
    assert a.get_piece_tree().equal(b.get_piece_tree());
}

test "buffer api: equal 3, empty buffer" {
    a = create_text_buffer(["a"]);
    b = create_text_buffer([""]);
    assert not a.get_piece_tree().equal(b.get_piece_tree());
}

test "buffer api: getLineCharCode - issue #45735" {
    piece_tree = create_text_buffer(["LINE1\nline2"]);
    piece_table = piece_tree.get_piece_tree();
    assert piece_table.get_line_char_code(1, 0) == ord("L");
    assert piece_table.get_line_char_code(1, 1) == ord("I");
    assert piece_table.get_line_char_code(1, 2) == ord("N");
    assert piece_table.get_line_char_code(1, 3) == ord("E");
    assert piece_table.get_line_char_code(1, 4) == ord("1");
    assert piece_table.get_line_char_code(1, 5) == ord("\n");
    assert piece_table.get_line_char_code(2, 0) == ord("l");
    assert piece_table.get_line_char_code(2, 1) == ord("i");
    assert piece_table.get_line_char_code(2, 2) == ord("n");
    assert piece_table.get_line_char_code(2, 3) == ord("e");
    assert piece_table.get_line_char_code(2, 4) == ord("2");
}

test "buffer api: getLineCharCode - issue #47733" {
    piece_tree = create_text_buffer(["", "LINE1\n", "line2"]);
    piece_table = piece_tree.get_piece_tree();
    assert piece_table.get_line_char_code(1, 0) == ord("L");
    assert piece_table.get_line_char_code(1, 1) == ord("I");
    assert piece_table.get_line_char_code(1, 2) == ord("N");
    assert piece_table.get_line_char_code(1, 3) == ord("E");
    assert piece_table.get_line_char_code(1, 4) == ord("1");
    assert piece_table.get_line_char_code(1, 5) == ord("\n");
    assert piece_table.get_line_char_code(2, 0) == ord("l");
    assert piece_table.get_line_char_code(2, 1) == ord("i");
    assert piece_table.get_line_char_code(2, 2) == ord("n");
    assert piece_table.get_line_char_code(2, 3) == ord("e");
    assert piece_table.get_line_char_code(2, 4) == ord("2");
}

test "buffer api: getNearestChunk" {
    piece_tree = create_text_buffer(["012345678"]);
    pt = piece_tree.get_piece_tree();
    pt.insert(3, "ABC");
    assert pt.get_line_content(1) == "012ABC345678";
    assert pt.get_nearest_chunk(3) == "ABC";
    assert pt.get_nearest_chunk(6) == "345678";
    pt.delete(9, 1);
    assert pt.get_line_content(1) == "012ABC34578";
    assert pt.get_nearest_chunk(6) == "345";
    assert pt.get_nearest_chunk(9) == "78";
}

# ===== suite: random is unsupervised (4 tests) =====
test "random is unsupervised: splitting large change buffer" {
    piece_tree = create_text_buffer([""], False);
    piece_table = piece_tree.get_piece_tree();
    str = "";
    piece_table.insert(0, "WUZ\nXVZY\n");
    str = str[0:0] + "WUZ\nXVZY\n" + str[0:];
    piece_table.insert(8, "\r\r\nZXUWVW");
    str = str[0:8] + "\r\r\nZXUWVW" + str[8:];
    piece_table.delete(10, 7);
    str = str[0:10] + str[10 + 7:];
    piece_table.delete(10, 1);
    str = str[0:10] + str[10 + 1:];
    piece_table.insert(4, "VX\r\r\nWZVZ");
    str = str[0:4] + "VX\r\r\nWZVZ" + str[4:];
    piece_table.delete(11, 3);
    str = str[0:11] + str[11 + 3:];
    piece_table.delete(12, 4);
    str = str[0:12] + str[12 + 4:];
    piece_table.delete(8, 0);
    str = str[0:8] + str[8 + 0:];
    piece_table.delete(10, 2);
    str = str[0:10] + str[10 + 2:];
    piece_table.insert(0, "VZXXZYZX\r");
    str = str[0:0] + "VZXXZYZX\r" + str[0:];
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

"""Ported from upstream's `random insert delete`: 1000 iterations, each either inserting a random
~99-char string at a random offset or deleting a random (up to 9-char) run, checked against a
plain-string oracle every iteration via the shared assertions at the end (matching upstream, which
only asserts once after the full loop, not per-iteration)."""
test "random is unsupervised: random insert delete" {
    str = "";
    piece_tree = create_text_buffer([str], False);
    piece_table = piece_tree.get_piece_tree();
    i = 0;
    while i < 1000 {
        if random.random() < 0.6 {
            text = random_str(100);
            pos = random_int(len(str) + 1);
            piece_table.insert(pos, text);
            str = str[0:pos] + text + str[pos:];
        } else {
            pos = random_int(len(str));
            length = min(len(str) - pos, int(random.random() * 10));
            piece_table.delete(pos, length);
            str = str[0:pos] + str[pos + length:];
        }
        i += 1;
    }
    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "random is unsupervised: random chunks" {
    chunks: list[str] = [];
    i = 0;
    while i < 5 {
        chunks.append(random_str(1000));
        i += 1;
    }
    piece_tree = create_text_buffer(chunks, False);
    piece_table = piece_tree.get_piece_tree();
    str = "".join(chunks);

    i = 0;
    while i < 1000 {
        if random.random() < 0.6 {
            text = random_str(100);
            pos = random_int(len(str) + 1);
            piece_table.insert(pos, text);
            str = str[0:pos] + text + str[pos:];
        } else {
            pos = random_int(len(str));
            length = min(len(str) - pos, int(random.random() * 10));
            piece_table.delete(pos, length);
            str = str[0:pos] + str[pos + length:];
        }
        i += 1;
    }

    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

test "random is unsupervised: random chunks 2" {
    chunks: list[str] = [random_str(1000)];
    piece_tree = create_text_buffer(chunks, False);
    piece_table = piece_tree.get_piece_tree();
    str = "".join(chunks);

    i = 0;
    while i < 50 {
        if random.random() < 0.6 {
            text = random_str(30);
            pos = random_int(len(str) + 1);
            piece_table.insert(pos, text);
            str = str[0:pos] + text + str[pos:];
        } else {
            pos = random_int(len(str));
            length = min(len(str) - pos, int(random.random() * 10));
            piece_table.delete(pos, length);
            str = str[0:pos] + str[pos + length:];
        }
        i += 1;
        test_lines_content(str, piece_table);
    }

    assert piece_table.get_lines_raw_content() == str;
    test_line_starts(str, piece_table);
    test_lines_content(str, piece_table);
    assert_tree_invariants(piece_table);
}

# ===== suite: snapshot (4 tests) =====
# See this file's top docstring for the `model.applyEdits(...)` -> `PieceTreeTextBuffer.apply_edits`
# adaptation rationale.

test "snapshot: bug #45564, piece tree pieces should be immutable" {
    model = create_text_buffer(["\n"]);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=1), text="!")
    ]);
    snapshot = model.create_snapshot(False);
    snapshot1 = model.create_snapshot(False);
    assert "\n".join(model.get_lines_content()) == get_value_in_snapshot(snapshot);

    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=2), text="")
    ]);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=1), text="!")
    ]);

    assert "\n".join(model.get_lines_content()) == get_value_in_snapshot(snapshot1);
}

test "snapshot: immutable snapshot 1" {
    model = create_text_buffer(["abc\ndef"]);
    snapshot = model.create_snapshot(False);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=4), text="")
    ]);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=1, end_line_number=2, end_column=1), text="abc\ndef")
    ]);
    assert "\n".join(model.get_lines_content()) == get_value_in_snapshot(snapshot);
}

test "snapshot: immutable snapshot 2" {
    model = create_text_buffer(["abc\ndef"]);
    snapshot = model.create_snapshot(False);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=1), text="!")
    ]);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=2), text="")
    ]);
    assert "\n".join(model.get_lines_content()) == get_value_in_snapshot(snapshot);
}

test "snapshot: immutable snapshot 3" {
    model = create_text_buffer(["abc\ndef"]);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=4, end_line_number=2, end_column=4), text="!")
    ]);
    snapshot = model.create_snapshot(False);
    model.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=5, end_line_number=2, end_column=5), text="!")
    ]);
    assert "\n".join(model.get_lines_content()) != get_value_in_snapshot(snapshot);
}

# Deliberately deferred: upstream's "chunk based search" suite (3 tests -- "#45892. For some
# cases, the buffer is empty but we still try to search", "#45770. FindInNode should not cross
# node boundary.", "search searching from the middle") all call findMatchesLineByLine/construct
# SearchData/WordCharacterClassifier for search purposes. That's ported directly onto
# PieceTreeBase in piece_tree_base.jac (find_matches_in_node/find_matches_line_by_line, plus
# Searcher/create_find_match/is_valid_match in text_model_search.jac) -- all 3 of these exact
# cases are already ported there, against PieceTreeBase's own API rather than through this
# wrapper, so they're not duplicated here.
