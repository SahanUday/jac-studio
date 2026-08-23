"""Ported from range.test.ts (src/vs/editor/test/common/core/range.test.ts), the real upstream
suite for Range -- every `test(...)` block there has a matching `test "..."` here, same
assertions, same expected values. `ensureNoDisposablesAreLeakedInTestSuite()` (a VS Code test
harness hook, unrelated to Range's own behavior) is not ported -- nothing in this suite allocates
a disposable."""

test "empty range" {
    s = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=1);
    assert s.start_line_number == 1;
    assert s.start_column == 1;
    assert s.end_line_number == 1;
    assert s.end_column == 1;
    assert s.is_empty() == True;
}

test "swap start and stop same line" {
    s = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=1);
    assert s.start_line_number == 1;
    assert s.start_column == 1;
    assert s.end_line_number == 1;
    assert s.end_column == 2;
    assert s.is_empty() == False;
}

test "swap start and stop" {
    s = Range(start_line_number=2, start_column=1, end_line_number=1, end_column=2);
    assert s.start_line_number == 1;
    assert s.start_column == 2;
    assert s.end_line_number == 2;
    assert s.end_column == 1;
    assert s.is_empty() == False;
}

test "no swap same line" {
    s = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=2);
    assert s.start_line_number == 1;
    assert s.start_column == 1;
    assert s.end_line_number == 1;
    assert s.end_column == 2;
    assert s.is_empty() == False;
}

test "no swap" {
    s = Range(start_line_number=1, start_column=1, end_line_number=2, end_column=1);
    assert s.start_line_number == 1;
    assert s.start_column == 1;
    assert s.end_line_number == 2;
    assert s.end_column == 1;
    assert s.is_empty() == False;
}

test "compareRangesUsingEnds" {
    a = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=3);
    b = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) < 0;

    a = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=3);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) < 0;

    a = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=3);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) < 0;

    a = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    b = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) < 0;

    a = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) == 0;

    a = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=4);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) > 0;

    a = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=5);
    b = Range(start_line_number=1, start_column=2, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) > 0;

    a = Range(start_line_number=1, start_column=1, end_line_number=2, end_column=4);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) > 0;

    a = Range(start_line_number=1, start_column=2, end_line_number=5, end_column=1);
    b = Range(start_line_number=1, start_column=1, end_line_number=1, end_column=4);
    assert Range.compare_ranges_using_ends(a, b) > 0;
}

test "containsPosition" {
    r = Range(start_line_number=2, start_column=2, end_line_number=5, end_column=10);
    assert r.contains_position(Position(line_number=1, column=3)) == False;
    assert r.contains_position(Position(line_number=2, column=1)) == False;
    assert r.contains_position(Position(line_number=2, column=2)) == True;
    assert r.contains_position(Position(line_number=2, column=3)) == True;
    assert r.contains_position(Position(line_number=3, column=1)) == True;
    assert r.contains_position(Position(line_number=5, column=9)) == True;
    assert r.contains_position(Position(line_number=5, column=10)) == True;
    assert r.contains_position(Position(line_number=5, column=11)) == False;
    assert r.contains_position(Position(line_number=6, column=1)) == False;
}

test "containsRange" {
    r = Range(start_line_number=2, start_column=2, end_line_number=5, end_column=10);
    assert r.contains_range(Range(start_line_number=1, start_column=3, end_line_number=2, end_column=2)) == False;
    assert r.contains_range(Range(start_line_number=2, start_column=1, end_line_number=2, end_column=2)) == False;
    assert r.contains_range(Range(start_line_number=2, start_column=2, end_line_number=5, end_column=11)) == False;
    assert r.contains_range(Range(start_line_number=2, start_column=2, end_line_number=6, end_column=1)) == False;
    assert r.contains_range(Range(start_line_number=5, start_column=9, end_line_number=6, end_column=1)) == False;
    assert r.contains_range(Range(start_line_number=5, start_column=10, end_line_number=6, end_column=1)) == False;
    assert r.contains_range(Range(start_line_number=2, start_column=2, end_line_number=5, end_column=10)) == True;
    assert r.contains_range(Range(start_line_number=2, start_column=3, end_line_number=5, end_column=9)) == True;
    assert r.contains_range(Range(start_line_number=3, start_column=100, end_line_number=4, end_column=100)) == True;
}

test "areIntersecting" {
    assert Range.are_intersecting(
        Range(start_line_number=2, start_column=2, end_line_number=3, end_column=2),
        Range(start_line_number=4, start_column=2, end_line_number=5, end_column=2)
    ) == False;
    assert Range.are_intersecting(
        Range(start_line_number=4, start_column=2, end_line_number=5, end_column=2),
        Range(start_line_number=2, start_column=2, end_line_number=3, end_column=2)
    ) == False;
    assert Range.are_intersecting(
        Range(start_line_number=4, start_column=2, end_line_number=5, end_column=2),
        Range(start_line_number=5, start_column=2, end_line_number=6, end_column=2)
    ) == False;
    assert Range.are_intersecting(
        Range(start_line_number=5, start_column=2, end_line_number=6, end_column=2),
        Range(start_line_number=4, start_column=2, end_line_number=5, end_column=2)
    ) == False;
    assert Range.are_intersecting(
        Range(start_line_number=2, start_column=2, end_line_number=2, end_column=7),
        Range(start_line_number=2, start_column=4, end_line_number=2, end_column=6)
    ) == True;
    assert Range.are_intersecting(
        Range(start_line_number=2, start_column=2, end_line_number=2, end_column=7),
        Range(start_line_number=2, start_column=4, end_line_number=2, end_column=9)
    ) == True;
    assert Range.are_intersecting(
        Range(start_line_number=2, start_column=4, end_line_number=2, end_column=9),
        Range(start_line_number=2, start_column=2, end_line_number=2, end_column=7)
    ) == True;
}
