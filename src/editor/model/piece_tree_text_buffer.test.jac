"""Direct tests against `PieceTreeTextBuffer`'s own public API -- construction, `equal`,
BOM/EOL accessors, range-based reads, and `apply_edits`. Not a port of upstream's
pieceTreeTextBuffer.test.ts (that suite drives everything through `PieceTreeTextBufferBuilder`'s
`createTextBuffer` helper -- ported in full in piece_tree_text_buffer_builder.test.jac, the
sibling annex, since that's the module the upstream helper actually lives on). These tests exist
so this file's own surface -- especially `apply_edits`, which the builder's ported suite only
exercises indirectly through four adapted "snapshot" tests -- has direct coverage too."""

import from src.editor.model.piece_tree_base { create_line_starts }

def make_buffer(text: str) -> PieceTreeTextBuffer {
    return PieceTreeTextBuffer(
        init_chunks=[StringBuffer(buffer=text, line_starts=create_line_starts(text))],
        bom="", init_eol="\n", contains_rtl=False, contains_unusual_line_terminators=False,
        is_basic_ascii=True, init_eol_normalized=True
    );
}

test "get_piece_tree exposes the underlying PieceTreeBase" {
    buf = make_buffer("hello");
    assert buf.get_piece_tree().get_lines_raw_content() == "hello";
}

test "get_bom/get_eol/set_eol" {
    buf = make_buffer("a\nb");
    assert buf.get_bom() == "";
    assert buf.get_eol() == "\n";
    buf.set_eol("\r\n");
    assert buf.get_eol() == "\r\n";
    assert buf.get_piece_tree().get_lines_raw_content() == "a\r\nb";
}

test "might_contain_rtl/unusual_line_terminators/non_basic_ascii flags round-trip from ctor" {
    buf = PieceTreeTextBuffer(
        init_chunks=[StringBuffer(buffer="x", line_starts=create_line_starts("x"))],
        bom="", init_eol="\n", contains_rtl=True, contains_unusual_line_terminators=True,
        is_basic_ascii=False, init_eol_normalized=True
    );
    assert buf.might_contain_rtl();
    assert buf.might_contain_unusual_line_terminators();
    assert buf.might_contain_non_basic_ascii();
    buf.reset_might_contain_unusual_line_terminators();
    assert not buf.might_contain_unusual_line_terminators();
}

test "equal compares bom, eol, and underlying piece tree content" {
    a = make_buffer("abc");
    b = make_buffer("abc");
    c = make_buffer("abd");
    assert a.equal(b);
    assert not a.equal(c);
}

test "get_range_at maps an offset/length span to a Range" {
    buf = make_buffer("abc\ndef");
    rng = buf.get_range_at(1, 4);
    assert rng.start_line_number == 1;
    assert rng.start_column == 2;
    assert rng.end_line_number == 2;
    assert rng.end_column == 2;
}

test "get_value_in_range with an explicit EOL preference" {
    buf = make_buffer("a\nb");
    rng = Range(start_line_number=1, start_column=1, end_line_number=2, end_column=2);
    assert buf.get_value_in_range(rng) == "a\nb";
    assert buf.get_value_in_range(rng, END_OF_LINE_PREFERENCE_CRLF) == "a\r\nb";
}

test "get_value_length_in_range single line and multi line" {
    buf = make_buffer("abc\ndef");
    same_line = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=3);
    assert buf.get_value_length_in_range(same_line) == 2;
    cross_line = Range(start_line_number=1, start_column=1, end_line_number=2, end_column=3);
    assert buf.get_value_length_in_range(cross_line) == 6;
}

test "get_line_min_column/get_line_max_column" {
    buf = make_buffer("abcd");
    assert buf.get_line_min_column(1) == 1;
    assert buf.get_line_max_column(1) == 5;
}

test "get_line_first_non_whitespace_column/get_line_last_non_whitespace_column" {
    buf = make_buffer("  abc  \nz");
    assert buf.get_line_first_non_whitespace_column(1) == 3;
    assert buf.get_line_last_non_whitespace_column(1) == 6;
    assert buf.get_line_first_non_whitespace_column(2) == 1;
    assert buf.get_line_last_non_whitespace_column(2) == 2;
}

test "get_line_first_non_whitespace_column on an all-whitespace line returns 0" {
    buf = make_buffer("   \nx");
    assert buf.get_line_first_non_whitespace_column(1) == 0;
    assert buf.get_line_last_non_whitespace_column(1) == 0;
}

test "get_character_count_in_range counts surrogate pairs as one character" {
    buf = PieceTreeTextBuffer(
        init_chunks=[StringBuffer(buffer="ab", line_starts=create_line_starts("ab"))],
        bom="", init_eol="\n", contains_rtl=False, contains_unusual_line_terminators=False,
        is_basic_ascii=False, init_eol_normalized=True
    );
    rng = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=3);
    assert buf.get_character_count_in_range(rng) == 2;
}

test "apply_edits inserts text and reports the content change" {
    buf = make_buffer("hello world");
    changes = buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=6, end_line_number=1, end_column=6), text=",")
    ]);
    assert buf.get_piece_tree().get_lines_raw_content() == "hello, world";
    assert len(changes) == 1;
    assert changes[0].text == ",";
    assert changes[0].range_offset == 5;
    assert changes[0].range_length == 0;
}

test "apply_edits deletes a range when text is empty" {
    buf = make_buffer("hello world");
    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=6, end_line_number=1, end_column=12), text="")
    ]);
    assert buf.get_piece_tree().get_lines_raw_content() == "hello";
}

test "apply_edits replaces a range" {
    buf = make_buffer("hello world");
    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=7, end_line_number=1, end_column=12), text="there")
    ]);
    assert buf.get_piece_tree().get_lines_raw_content() == "hello there";
}

test "apply_edits applies multiple non-overlapping edits in one batch" {
    buf = make_buffer("abcdef");
    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=1, end_line_number=1, end_column=1), text="X"),
        SingleEditOperation(range=Range(start_line_number=1, start_column=7, end_line_number=1, end_column=7), text="Y")
    ]);
    assert buf.get_piece_tree().get_lines_raw_content() == "XabcdefY";
}

test "apply_edits raises on overlapping ranges" {
    buf = make_buffer("abcdef");
    threw = False;
    try {
        buf.apply_edits([
            SingleEditOperation(range=Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4), text="X"),
            SingleEditOperation(range=Range(start_line_number=1, start_column=3, end_line_number=1, end_column=5), text="Y")
        ]);
    } except Exception {
        threw = True;
    }
    assert threw;
}

test "apply_edits no-op when range is empty and text is empty" {
    buf = make_buffer("abcdef");
    changes = buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=1, start_column=3, end_line_number=1, end_column=3), text="")
    ]);
    assert len(changes) == 0;
    assert buf.get_piece_tree().get_lines_raw_content() == "abcdef";
}

test "apply_edits pieces stay immutable across snapshots (bug #45564 adaptation)" {
    buf = make_buffer("\n");
    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=1), text="!")
    ]);
    snapshot1 = buf.create_snapshot(False);
    value_before = get_value_in_snapshot(snapshot1);

    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=2), text="")
    ]);
    buf.apply_edits([
        SingleEditOperation(range=Range(start_line_number=2, start_column=1, end_line_number=2, end_column=1), text="!")
    ]);

    assert value_before == "\n!";
    assert buf.get_piece_tree().get_lines_raw_content() == "\n!";
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
