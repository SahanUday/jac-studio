"""Tests for char_code.jac -- verifies the three ported constants match upstream charCode.ts's
`const enum CharCode` values exactly (`Tab = 9`, `LineFeed = 10`, `CarriageReturn = 13`), and that
they behave correctly against Python's `ord()` for the characters they're meant to identify."""

test "constants match upstream numeric values" {
    assert TAB == 9;
    assert LINE_FEED == 10;
    assert CARRIAGE_RETURN == 13;
}

test "constants match ord() of their real characters" {
    assert TAB == ord("\t");
    assert LINE_FEED == ord("\n");
    assert CARRIAGE_RETURN == ord("\r");
}

test "constants are distinct" {
    values = [TAB, LINE_FEED, CARRIAGE_RETURN];
    assert len(values) == len(set(values));
}
