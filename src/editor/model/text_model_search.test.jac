"""Direct tests for `Searcher`/`create_find_match`/`is_valid_match`, exercising the same shapes
upstream's own textModelSearch.ts test suite drives through `TextModelSearch.findMatches` --
plain-text scans, regex scans, capture groups, and word-boundary filtering via a
`WordCharacterClassifier`. Not a port of upstream's test file (out of scope, see this module's own
docstring); these verify the ported subset directly."""

import re;

def make_range -> Range {
    return Range(start_line_number=1, start_column=1, end_line_number=1, end_column=1);
}

test "Searcher finds every non-overlapping match of a simple pattern" {
    searcher = Searcher(word_separators=None, search_regex=re.compile("abc"));
    text = "abc xyz abc";
    first = searcher.next(text);
    assert first is not None;
    assert first.start() == 0;
    second = searcher.next(text);
    assert second is not None;
    assert second.start() == 8;
    assert searcher.next(text) is None;
}

test "Searcher.reset restarts the scan from a given index" {
    searcher = Searcher(word_separators=None, search_regex=re.compile("a"));
    text = "aaa";
    searcher.next(text);
    searcher.next(text);
    searcher.reset(0);
    m = searcher.next(text);
    assert m is not None;
    assert m.start() == 0;
}

test "Searcher does not get stuck on a zero-length match" {
    searcher = Searcher(word_separators=None, search_regex=re.compile("x*"));
    text = "ab";
    m1 = searcher.next(text);
    assert m1 is not None;
    assert m1.start() == 0;
    m2 = searcher.next(text);
    assert m2 is not None;
    assert m2.start() == 1;
    m3 = searcher.next(text);
    assert m3 is not None;
    assert m3.start() == 2;
    assert searcher.next(text) is None;
}

test "Searcher filters matches that aren't on a word boundary" {
    classifier = WordCharacterClassifier(word_separators=" ", intl_segmenter_locales=[]);
    searcher = Searcher(word_separators=classifier, search_regex=re.compile("cat"));
    # "cat" inside "category" is not word-bounded on the right -- must be skipped.
    text = "category cat";
    m = searcher.next(text);
    assert m is not None;
    assert m.start() == 9;
    assert searcher.next(text) is None;
}

test "create_find_match returns no captures when capture_matches is False" {
    m = re.search("a(b)(c)", "abc");
    assert m is not None;
    result = create_find_match(make_range(), m, False);
    assert result.matches is None;
}

test "create_find_match captures the full match plus every group" {
    m = re.search("a(b)(c)", "abc");
    assert m is not None;
    result = create_find_match(make_range(), m, True);
    assert result.matches == ["abc", "b", "c"];
}

test "create_find_match fills a non-participating optional group with an empty string" {
    m = re.search("a(b)?(c)", "ac");
    assert m is not None;
    result = create_find_match(make_range(), m, True);
    assert result.matches == ["ac", "", "c"];
}

test "is_valid_match is true at the very start and end of the text" {
    classifier = WordCharacterClassifier(word_separators="", intl_segmenter_locales=[]);
    assert is_valid_match(classifier, "cat", 3, 0, 3);
}

test "is_valid_match is false when the match abuts a non-separator character" {
    classifier = WordCharacterClassifier(word_separators=" ", intl_segmenter_locales=[]);
    assert not is_valid_match(classifier, "category", 8, 0, 3);
}

test "is_valid_match is true when the match is flanked by separators" {
    classifier = WordCharacterClassifier(word_separators=" ", intl_segmenter_locales=[]);
    assert is_valid_match(classifier, "a cat b", 7, 2, 3);
}

test "is_valid_match treats a line break as a boundary" {
    classifier = WordCharacterClassifier(word_separators="", intl_segmenter_locales=[]);
    text = "x\ncaty";
    # "cat" starts right after \n (boundary) but ends right before "y" (not a boundary).
    assert not is_valid_match(classifier, text, len(text), 2, 3);
}
