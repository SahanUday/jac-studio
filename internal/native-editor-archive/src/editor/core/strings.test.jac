"""Tests for strings.jac's `split_lines`, mirroring upstream strings.ts's own behavior for
`\r\n`, bare `\r`, bare `\n`, mixed line endings, and the empty-string / no-separator edge cases."""

test "splits on LF" {
    assert split_lines("a\nb\nc") == ["a", "b", "c"];
}

test "splits on CRLF" {
    assert split_lines("a\r\nb\r\nc") == ["a", "b", "c"];
}

test "splits on bare CR" {
    assert split_lines("a\rb\rc") == ["a", "b", "c"];
}

test "splits on mixed line endings" {
    assert split_lines("a\r\nb\nc\rd") == ["a", "b", "c", "d"];
}

test "no separator returns single-element list" {
    assert split_lines("no newlines here") == ["no newlines here"];
}

test "empty string returns single empty element" {
    assert split_lines("") == [""];
}

test "trailing newline yields trailing empty element" {
    assert split_lines("a\nb\n") == ["a", "b", ""];
}

test "leading newline yields leading empty element" {
    assert split_lines("\na\nb") == ["", "a", "b"];
}

test "consecutive newlines yield empty elements between them" {
    assert split_lines("a\n\nb") == ["a", "", "b"];
}

test "contains_rtl is false for plain ASCII" {
    assert not contains_rtl("hello world");
}

test "contains_rtl is true for a BMP Hebrew character" {
    assert contains_rtl("hello " + chr(0x05D0));
}


# No test for contains_rtl's supplementary-plane scope cut (documented in the module docstring,
# see 2026-08-23-supplementary-plane-string-crashes-js-codegen): both a literal escape AND a
# runtime `chr(0x10900)` call reliably crash the compiler's JS codegen pass with the same
# UnicodeEncodeError, so there's no way to safely exercise a supplementary-plane character in a
# test right now either.

test "contains_unusual_line_terminators detects U+2028 and U+2029" {
    assert contains_unusual_line_terminators(chr(0x2028));
    assert contains_unusual_line_terminators("a" + chr(0x2029) + "b");
    assert not contains_unusual_line_terminators("plain text\n");
}

test "UTF8_BOM_CHARACTER is U+FEFF" {
    assert ord(UTF8_BOM_CHARACTER) == 0xFEFF;
}

test "starts_with_utf8_bom detects a leading BOM" {
    assert starts_with_utf8_bom(UTF8_BOM_CHARACTER + "hello");
    assert not starts_with_utf8_bom("hello");
    assert not starts_with_utf8_bom("");
}
