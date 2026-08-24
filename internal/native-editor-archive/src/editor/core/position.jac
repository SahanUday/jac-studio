"""Position: a (lineNumber, column) value in the editor's text-buffer coordinate system, ported
from VS Code's core/position.ts (src/vs/editor/common/core/position.ts). `line_number` starts at
1; `column` starts at 1, with column 1 meaning "before the first character on the line" -- both
match upstream's convention exactly, since the piece-tree buffer's own line/column math (and its
ported tests) construct and compare real `Position` values against this convention.

Idiom notes: upstream's separate `IPosition` interface (a serialization-friendly readonly shape
used so callers don't need a full `Position` instance) isn't ported as a distinct type here --
`Position` is the only shape used throughout this project, and every upstream signature that took
`IPosition` takes `Position` below. There is no `position.test.ts` upstream (this file has no
dedicated test suite in VS Code itself), so the `.test.jac` annex is hand-written here, not
ported, exercising every method against expected values.

Jac disallows an instance `def` and a `static def` sharing one name on the same `obj` (confirmed
empirically: `error[E0076]: Duplicate method 'equals' in class body`) -- but upstream's `equals`,
`isBefore`, and `isBeforeOrEqual` are each defined *twice*, once as an instance method
(`pos.equals(other)`) and once as a two-argument static (`Position.equals(a, b)`), with the
instance form simply forwarding to the static one. Those three pairs are split here: the instance
method keeps the exact upstream name, and the two-argument comparison logic moves to a
module-level function (`_position_equals`/`_position_is_before`/`_position_is_before_or_equal`,
mirroring the free-function idiom already used in `interval_tree.jac`) that the instance method
calls. `compare`, `lift`, and `is_i_position` have no instance-side twin upstream, so they stay
as ordinary `static def` methods on `Position` with no renaming needed.

`with` is a reserved word in Jac (see the jac-language skill's reserved-keyword list) -- escaped
as `` `with `` at its one declaration and its one call site (inside `delta`), rather than renamed,
to keep the method name matching upstream exactly. Default-parameter values that need to read
`self` (upstream's `newLineNumber: number = this.lineNumber`) aren't expressible in Jac (defaults
are evaluated at def time, not call time) -- ported as `int | None = None` sentinels, resolved
inside the body instead.
"""

def _position_equals(a: Position | None, b: Position | None) -> bool {
    if a is None and b is None {
        return True;
    }
    return a is not None and b is not None and a.line_number == b.line_number and a.column == b.column;
}

def _position_is_before(a: Position, b: Position) -> bool {
    if a.line_number < b.line_number {
        return True;
    }
    if b.line_number < a.line_number {
        return False;
    }
    return a.column < b.column;
}

def _position_is_before_or_equal(a: Position, b: Position) -> bool {
    if a.line_number < b.line_number {
        return True;
    }
    if b.line_number < a.line_number {
        return False;
    }
    return a.column <= b.column;
}

obj Position {
    has line_number: int, column: int;

    """Create a new position from this position (upstream's `with`)."""
    def `with(new_line_number: int | None = None, new_column: int | None = None) -> Position {
        nl = self.line_number if new_line_number is None else new_line_number;
        nc = self.column if new_column is None else new_column;
        if nl == self.line_number and nc == self.column {
            return self;
        }
        return Position(line_number=nl, column=nc);
    }

    """Derive a new position from this position."""
    def delta(delta_line_number: int = 0, delta_column: int = 0) -> Position {
        return self.`with(
            max(1, self.line_number + delta_line_number), max(1, self.column + delta_column)
        );
    }

    """Test if this position equals other position."""
    def equals(other: Position | None) -> bool {
        return _position_equals(self, other);
    }

    """Test if this position is before other position. Equal positions -> False."""
    def is_before(other: Position) -> bool {
        return _position_is_before(self, other);
    }

    """Test if this position is before other position. Equal positions -> True."""
    def is_before_or_equal(other: Position) -> bool {
        return _position_is_before_or_equal(self, other);
    }

    """A function that compares positions, useful for sorting."""
    static def compare(a: Position, b: Position) -> int {
        a_line_number = a.line_number;
        b_line_number = b.line_number;
        if a_line_number == b_line_number {
            a_column = a.column;
            b_column = b.column;
            return a_column - b_column;
        }
        return a_line_number - b_line_number;
    }

    """Clone this position."""
    def clone -> Position {
        return Position(line_number=self.line_number, column=self.column);
    }

    """Convert to a human-readable representation."""
    def to_string -> str {
        return "(" + str(self.line_number) + "," + str(self.column) + ")";
    }

    """Create a `Position` from an `IPosition`-shaped value."""
    static def lift(pos: Position) -> Position {
        return Position(line_number=pos.line_number, column=pos.column);
    }

    """Test if `value` looks like an `IPosition` (has numeric `line_number`/`column`)."""
    static def is_i_position(value: any) -> bool {
        if value is None {
            return False;
        }
        line_number = value?.line_number;
        column = value?.column;
        return isinstance(line_number, int) and isinstance(column, int);
    }

    """Plain-data representation, matching upstream's camelCase JSON wire shape."""
    def to_json -> dict[str, int] {
        return {"lineNumber": self.line_number, "column": self.column};
    }
}
