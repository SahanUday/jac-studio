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
