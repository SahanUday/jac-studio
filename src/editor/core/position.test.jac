"""Hand-written tests for position.jac -- there is no dedicated `position.test.ts` upstream (VS
Code has no standalone Position test suite; it's exercised indirectly through Range/editor
tests), so this annex exercises every ported method directly against expected values instead of
porting an existing suite, per this project's practice of writing tests alongside the code."""

test "constructor stores line_number and column" {
    p = Position(line_number=3, column=7);
    assert p.line_number == 3;
    assert p.column == 7;
}

test "with keeps unchanged fields and returns a new position otherwise" {
    p = Position(line_number=3, column=7);
    same = p.`with();
    assert same.line_number == 3;
    assert same.column == 7;

    moved = p.`with(new_column=9);
    assert moved.line_number == 3;
    assert moved.column == 9;

    moved2 = p.`with(new_line_number=5);
    assert moved2.line_number == 5;
    assert moved2.column == 7;

    moved3 = p.`with(new_line_number=5, new_column=9);
    assert moved3.line_number == 5;
    assert moved3.column == 9;
}

test "delta moves by the given amounts and clamps at 1" {
    p = Position(line_number=3, column=7);

    d1 = p.delta();
    assert d1.line_number == 3;
    assert d1.column == 7;

    d2 = p.delta(1, 2);
    assert d2.line_number == 4;
    assert d2.column == 9;

    d3 = p.delta(-10, -10);
    assert d3.line_number == 1;
    assert d3.column == 1;
}

test "equals matches upstream semantics, including both-None" {
    a = Position(line_number=1, column=1);
    b = Position(line_number=1, column=1);
    c = Position(line_number=1, column=2);
    d = Position(line_number=2, column=1);

    assert a.equals(b);
    assert not a.equals(c);
    assert not a.equals(d);
    assert not a.equals(None);

    assert position_equals(None, None);
    assert not position_equals(a, None);
    assert not position_equals(None, a);
}

test "is_before is strict (equal positions are not before)" {
    a = Position(line_number=1, column=1);
    b = Position(line_number=1, column=2);
    c = Position(line_number=2, column=1);
    same = Position(line_number=1, column=1);

    assert a.is_before(b);
    assert a.is_before(c);
    assert not b.is_before(a);
    assert not a.is_before(same);
    assert not a.is_before(a);
}

test "is_before_or_equal includes equal positions" {
    a = Position(line_number=1, column=1);
    b = Position(line_number=1, column=2);
    same = Position(line_number=1, column=1);

    assert a.is_before_or_equal(b);
    assert a.is_before_or_equal(same);
    assert not b.is_before_or_equal(a);
}

test "Position.compare orders by line then column" {
    assert Position.compare(Position(line_number=1, column=1), Position(line_number=1, column=1)) == 0;
    assert Position.compare(Position(line_number=1, column=1), Position(line_number=1, column=2)) < 0;
    assert Position.compare(Position(line_number=1, column=2), Position(line_number=1, column=1)) > 0;
    assert Position.compare(Position(line_number=1, column=99), Position(line_number=2, column=1)) < 0;
    assert Position.compare(Position(line_number=2, column=1), Position(line_number=1, column=99)) > 0;
}

test "clone produces an equal but distinct position" {
    p = Position(line_number=4, column=8);
    c = p.clone();
    assert c.line_number == 4;
    assert c.column == 8;
    assert c.equals(p);
}

test "to_string matches upstream's (line,column) format" {
    p = Position(line_number=3, column=7);
    assert p.to_string() == "(3,7)";
}

test "Position.lift copies fields into a new Position" {
    p = Position(line_number=6, column=2);
    lifted = Position.lift(p);
    assert lifted.line_number == 6;
    assert lifted.column == 2;
    assert lifted.equals(p);
}

obj _MissingColumn {
    has line_number: int;
}

test "Position.is_i_position duck-types line_number/column" {
    assert Position.is_i_position(Position(line_number=1, column=1));
    assert not Position.is_i_position(None);
    assert not Position.is_i_position(_MissingColumn(line_number=1));
}

test "to_json returns the upstream camelCase wire shape" {
    p = Position(line_number=5, column=11);
    j = p.to_json();
    assert j["lineNumber"] == 5;
    assert j["column"] == 11;
}
