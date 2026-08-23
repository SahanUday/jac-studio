"""Direct tests against `PieceTreeBase`'s own public API. Not a port of upstream's
pieceTreeTextBuffer.test.ts -- that suite drives everything through `PieceTreeTextBuffer` /
`PieceTreeTextBufferBuilder` (the wrapper layer built on top of this module, ported separately,
see `piece_tree_text_buffer.jac`), calling `.getPieceTree()` to reach the underlying
`PieceTreeBase` only for read-side assertions. These tests exercise `PieceTreeBase` itself
directly -- construction from chunks, insert/delete, line/offset math, CRLF splitting, snapshots,
and `equal()` -- as the real verification for this foundational module while the wrapper layer is
built. Full ported-test parity against pieceTreeTextBuffer.test.ts lives with the wrapper port."""

def make_tree(text: str) -> PieceTreeBase {
    return PieceTreeBase(
        init_chunks=[StringBuffer(buffer=text, line_starts=create_line_starts(text))],
        init_eol="\n", init_eol_normalized=True
    );
}

def make_empty_tree -> PieceTreeBase {
    return PieceTreeBase(init_chunks=[], init_eol="\n", init_eol_normalized=True);
}

test "single chunk content round-trips through get_lines_raw_content" {
    tree = make_tree("hello\nworld");
    assert tree.get_lines_raw_content() == "hello\nworld";
    assert tree.get_length() == 11;
    assert tree.get_line_count() == 2;
}

test "get_line_content returns each line without its line break" {
    tree = make_tree("abc\ndef\nghi");
    assert tree.get_line_content(1) == "abc";
    assert tree.get_line_content(2) == "def";
    assert tree.get_line_content(3) == "ghi";
}

test "get_lines_content splits on LF" {
    tree = make_tree("one\ntwo\nthree");
    assert tree.get_lines_content() == ["one", "two", "three"];
}

test "empty tree has one empty line" {
    tree = make_empty_tree();
    assert tree.get_length() == 0;
    assert tree.get_line_count() == 1;
    assert tree.get_line_content(1) == "";
    assert tree.get_lines_content() == [""];
}

test "insert at start prepends content" {
    tree = make_tree("world");
    tree.insert(0, "hello ");
    assert tree.get_lines_raw_content() == "hello world";
}

test "insert at end appends content" {
    tree = make_tree("hello");
    tree.insert(5, " world");
    assert tree.get_lines_raw_content() == "hello world";
}

test "insert in the middle splits the piece" {
    tree = make_tree("heo");
    tree.insert(2, "ll");
    assert tree.get_lines_raw_content() == "hello";
}

test "repeated inserts at the same growing offset (typing simulation)" {
    tree = make_empty_tree();
    text = "hello world";
    i = 0;
    while i < len(text) {
        tree.insert(i, text[i]);
        i += 1;
    }
    assert tree.get_lines_raw_content() == "hello world";
    assert tree.get_length() == len(text);
}

test "delete whole content" {
    tree = make_tree("hello");
    tree.delete(0, 5);
    assert tree.get_lines_raw_content() == "";
    assert tree.get_length() == 0;
}

test "delete a middle range" {
    tree = make_tree("hello world");
    tree.delete(5, 6);
    assert tree.get_lines_raw_content() == "hello";
}

test "delete spanning multiple pieces after an insert" {
    tree = make_tree("heo");
    tree.insert(2, "ll");
    tree.delete(1, 3);
    assert tree.get_lines_raw_content() == "ho";
}

test "insert then delete restores original content" {
    tree = make_tree("The quick fox");
    tree.insert(4, "brown ");
    assert tree.get_lines_raw_content() == "The brown quick fox";
    tree.delete(4, 6);
    assert tree.get_lines_raw_content() == "The quick fox";
}

test "get_offset_at and get_position_at round-trip" {
    tree = make_tree("abc\ndef\nghi");
    text = "abc\ndef\nghi";
    offset = 0;
    while offset <= len(text) {
        pos = tree.get_position_at(offset);
        assert tree.get_offset_at(pos.line_number, pos.column) == offset;
        offset += 1;
    }
}

test "get_position_at at a line start" {
    tree = make_tree("abc\ndef\nghi");
    pos = tree.get_position_at(4);
    assert pos.line_number == 2;
    assert pos.column == 1;
}

test "get_value_in_range extracts a substring across lines" {
    tree = make_tree("abc\ndef\nghi");
    value = tree.get_value_in_range(Range(start_line_number=1, start_column=2, end_line_number=3, end_column=2));
    assert value == "bc\ndef\ng";
}

test "get_line_length excludes the line break" {
    tree = make_tree("abc\ndefgh\ni");
    assert tree.get_line_length(1) == 3;
    assert tree.get_line_length(2) == 5;
    assert tree.get_line_length(3) == 1;
}

test "get_char_code and get_line_char_code read individual characters" {
    tree = make_tree("abc");
    assert tree.get_char_code(0) == ord("a");
    assert tree.get_line_char_code(1, 1) == ord("b");
}

test "CRLF split across an insert boundary is normalized into one piece" {
    tree = make_tree("a\rb");
    tree.insert(2, "\n");
    assert tree.get_lines_raw_content() == "a\r\nb";
    assert tree.get_line_count() == 2;
    assert tree.get_line_content(1) == "a";
    assert tree.get_line_content(2) == "b";
}

test "CRLF split across a delete boundary is normalized into one piece" {
    # Two separate pieces by construction (the initial chunk, then an appended insert) so that
    # deleting the "X" joins a \r-ending piece directly to a \n-starting piece.
    tree = make_tree("a\r");
    tree.insert(2, "X\nb");
    tree.delete(2, 1);
    assert tree.get_lines_raw_content() == "a\r\nb";
    assert tree.get_line_count() == 2;
}

test "set_eol converts line endings and re-normalizes" {
    tree = make_tree("a\nb\nc");
    tree.set_eol("\r\n");
    assert tree.get_eol() == "\r\n";
    assert tree.get_lines_raw_content() == "a\r\nb\r\nc";
    assert tree.get_line_count() == 3;
}

test "equal compares two trees by content, not identity" {
    a = make_tree("hello\nworld");
    b = make_tree("hello\nworld");
    c = make_tree("hello\nthere");
    assert a.equal(b);
    assert not a.equal(c);
}

test "create_snapshot reads back the full content in chunks" {
    tree = make_tree("hello world");
    snapshot = tree.create_snapshot("");
    collected = "";
    chunk = snapshot.read();
    while chunk is not None {
        collected += chunk;
        chunk = snapshot.read();
    }
    assert collected == "hello world";
}

test "create_snapshot prefixes the BOM on the first chunk" {
    tree = make_tree("abc");
    snapshot = tree.create_snapshot("﻿");
    first = snapshot.read();
    assert first is not None;
    assert first.startswith("﻿");
}

test "a piece larger than the average buffer size is split across multiple buffers" {
    text = "x" * (65535 + 100);
    tree = make_tree(text);
    assert tree.get_length() == len(text);
    assert tree.get_lines_raw_content() == text;
    assert len(tree.buffers) > 1;
}

test "TreeNode.next and .prev traverse pieces in document order" {
    tree = make_tree("ab");
    tree.insert(1, "X");
    nodes = collect_nodes_in_order(tree.tree_root);
    assert len(nodes) >= 2;
    first = nodes[0];
    assert first.prev() == SENTINEL;
    last_forward = first;
    count = 1;
    while last_forward.next() != SENTINEL {
        last_forward = last_forward.next();
        count += 1;
    }
    assert count == len(nodes);
    assert last_forward.next() == SENTINEL;
}
