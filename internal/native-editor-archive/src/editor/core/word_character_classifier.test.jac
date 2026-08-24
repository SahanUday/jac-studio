"""Tests for word_character_classifier.jac. No dedicated upstream test file exists for
WordCharacterClassifier (checked: nothing under `editor/test/common/core/` covers it) -- these are
written directly against upstream's documented semantics and the real call shape the piece-tree
buffer's own ported test suite uses (`new WordCharacterClassifier(',./', [])`, from
pieceTreeTextBuffer.test.ts).

Covers: word characters classify as Regular (the default for anything not explicitly set),
each character in the separator string classifies as WordSeparator, space and tab classify as
Whitespace even when not in the separator string, `set`/`get` round-trip for both the ASCII fast
path and the >=256 sparse fallback, and `clear` resetting a mutated table back to defaults.
"""

test "word characters classify as Regular" {
    classifier = WordCharacterClassifier(word_separators=",./", intl_segmenter_locales=[]);
    assert classifier.get(ord("a")) == WORD_CHARACTER_CLASS_REGULAR;
    assert classifier.get(ord("Z")) == WORD_CHARACTER_CLASS_REGULAR;
    assert classifier.get(ord("5")) == WORD_CHARACTER_CLASS_REGULAR;
    assert classifier.get(ord("_")) == WORD_CHARACTER_CLASS_REGULAR;
}

test "separator characters classify as WordSeparator" {
    classifier = WordCharacterClassifier(word_separators=",./", intl_segmenter_locales=[]);
    assert classifier.get(ord(",")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
    assert classifier.get(ord(".")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
    assert classifier.get(ord("/")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
}

test "space and tab classify as Whitespace" {
    classifier = WordCharacterClassifier(word_separators=",./", intl_segmenter_locales=[]);
    assert classifier.get(ord(" ")) == WORD_CHARACTER_CLASS_WHITESPACE;
    assert classifier.get(ord("\t")) == WORD_CHARACTER_CLASS_WHITESPACE;
}

test "space and tab are Whitespace even when also listed as separators" {
    # Mirrors upstream's constructor order: the separators loop runs first, then Space/Tab are
    # force-set to Whitespace afterward (wordCharacterClassifier.ts lines 34-39) -- Whitespace
    # always wins for these two codes regardless of what's in the separator string.
    classifier = WordCharacterClassifier(word_separators=" \t,", intl_segmenter_locales=[]);
    assert classifier.get(ord(" ")) == WORD_CHARACTER_CLASS_WHITESPACE;
    assert classifier.get(ord("\t")) == WORD_CHARACTER_CLASS_WHITESPACE;
    assert classifier.get(ord(",")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
}

test "empty separator string still classifies space and tab as Whitespace" {
    classifier = WordCharacterClassifier(word_separators="", intl_segmenter_locales=[]);
    assert classifier.get(ord("a")) == WORD_CHARACTER_CLASS_REGULAR;
    assert classifier.get(ord(" ")) == WORD_CHARACTER_CLASS_WHITESPACE;
    assert classifier.get(ord("\t")) == WORD_CHARACTER_CLASS_WHITESPACE;
}

test "set and get round-trip on the ASCII fast path" {
    classifier = WordCharacterClassifier(word_separators="", intl_segmenter_locales=[]);
    classifier.set(ord("x"), WORD_CHARACTER_CLASS_WORD_SEPARATOR);
    assert classifier.get(ord("x")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
}

test "set and get round-trip above the ASCII range (sparse fallback)" {
    classifier = WordCharacterClassifier(word_separators="", intl_segmenter_locales=[]);
    # 0x4E2D = '中', well above the 0-255 ASCII table -- exercises the dict fallback path.
    high_code = 0x4E2D;
    assert classifier.get(high_code) == WORD_CHARACTER_CLASS_REGULAR;
    classifier.set(high_code, WORD_CHARACTER_CLASS_WORD_SEPARATOR);
    assert classifier.get(high_code) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
    # An unrelated high code never explicitly set still falls back to the default.
    assert classifier.get(0x4E2E) == WORD_CHARACTER_CLASS_REGULAR;
}

test "clear resets a mutated table back to defaults" {
    classifier = WordCharacterClassifier(word_separators=",./", intl_segmenter_locales=[]);
    assert classifier.get(ord(",")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
    classifier.clear();
    assert classifier.get(ord(",")) == WORD_CHARACTER_CLASS_REGULAR;
    assert classifier.get(ord(" ")) == WORD_CHARACTER_CLASS_REGULAR;
}

test "intl_segmenter_locales is stored but unused (deliberate scope cut)" {
    classifier = WordCharacterClassifier(word_separators=",./", intl_segmenter_locales=["en-US"]);
    assert classifier.intl_segmenter_locales == ["en-US"];
    # Locale-aware segmentation is out of scope; get() behaves identically regardless of locale.
    assert classifier.get(ord(",")) == WORD_CHARACTER_CLASS_WORD_SEPARATOR;
}
