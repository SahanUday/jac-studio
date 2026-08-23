"""Tests for model_types.jac.

DefaultEndOfLine is fully self-contained and verified standalone. FindMatch/SearchData depend on
`Range` (src/editor/core/range.jac) and `WordCharacterClassifier`
(src/editor/core/word_character_classifier.jac), both being ported in parallel by other agents as
part of this same piece-tree effort; if this annex is run before those land, the FindMatch test
below will fail to resolve `Range`'s constructor (guessed here as
`Range(start_line_number, start_column, end_line_number, end_column)`, snake_cased from
upstream's own constructor param names/order) -- re-run once Range exists and, if its real
constructor differs, adjust the call below to match.
"""

import re;

test "DefaultEndOfLine constants match upstream numeric values" {
    assert DEFAULT_END_OF_LINE_LF == 1;
    assert DEFAULT_END_OF_LINE_CRLF == 2;
}

test "DefaultEndOfLine constants are distinct" {
    assert DEFAULT_END_OF_LINE_LF != DEFAULT_END_OF_LINE_CRLF;
}

test "FindMatch stores range and matches" {
    r = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=5);
    m = FindMatch(range=r, matches=["hello"]);
    assert m.range == r;
    assert m.matches == ["hello"];
}

test "FindMatch matches may be null" {
    r = Range(start_line_number=2, start_column=3, end_line_number=2, end_column=8);
    m = FindMatch(range=r, matches=None);
    assert m.matches is None;
}

test "SearchData stores a compiled regex" {
    pattern = re.compile(r"foo\d+");
    sd = SearchData(regex=pattern, word_separators=None, simple_search="foo");
    assert sd.regex.pattern == r"foo\d+";
    assert sd.simple_search == "foo";
    assert sd.word_separators is None;
    assert sd.regex.search("foo123") is not None;
    assert sd.regex.search("bar") is None;
}

test "SearchData simple_search may be null" {
    pattern = re.compile(r".*");
    sd = SearchData(regex=pattern, word_separators=None, simple_search=None);
    assert sd.simple_search is None;
}
