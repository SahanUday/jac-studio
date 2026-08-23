"""Range: a (startLineNumber, startColumn, endLineNumber, endColumn) value in the editor, ported
from VS Code's core/range.ts (src/vs/editor/common/core/range.ts). Invariant, enforced in
`postinit` exactly like upstream's constructor: `(start_line_number, start_column)` is always
`<=` `(end_line_number, end_column)` -- if constructed "backwards" the two endpoints are swapped
rather than rejected, matching upstream's swap-not-throw behavior.

Idiom notes: `IRange` (upstream's readonly-interface counterpart to `Range`, used for
serialization/duck-typed callers) is not ported as a separate type, for the same reason as
`position.jac`'s `IPosition` -- `Range` is the only shape used throughout this project, and every
upstream signature taking `IRange` takes `Range` here.

Same Jac restriction as `position.jac`: an instance `def` and a `static def` cannot share one name
on the same `obj` (`error[E0076]: Duplicate method '...' in class body`), but upstream defines
`isEmpty`, `containsPosition`, `containsRange`, `strictContainsRange`, `plusRange`,
`intersectRanges`, `equalsRange`, `getEndPosition`, `getStartPosition`, `collapseToStart`, and
`collapseToEnd` *twice* each -- once as an instance method forwarding to `this`, once as a
two-argument (or one-argument, for the `Range`-only args) static. Each such pair is split here the
same way as Position's `equals`/`isBefore`/`isBeforeOrEqual`: the instance method keeps the exact
upstream name and forwards to a module-level function (`range_is_empty`, `range_contains_position`,
etc., mirroring `interval_tree.jac`'s free-function idiom) that holds the real logic. Anything that
was static-only upstream (`strictContainsPosition`, `fromPositions`, `lift`, `isIRange`,
`areIntersectingOrTouching`, `areIntersecting`, `areOnlyIntersecting`,
`compareRangesUsingStarts`, `compareRangesUsingEnds`, `spansMultipleLines`) has no instance-side
twin, so it stays a plain `static def` on `Range` with no renaming needed. A caller that upstream
would reach via `Range.plusRange(a, b)` (two arbitrary ranges, no natural receiver) uses the
module-level `range_plus_range(a, b)` function directly here instead.

`Range.lift` upstream is a `null`/`undefined`-swallowing overload (`lift(range) -> Range`,
`lift(null | undefined) -> null`); ported as `range: Range | None -> Range | None` since Jac has
no overload resolution on nullability, with the same behavior (`None` in, `None` out).
`compareRangesUsingStarts`'s `a`/`b` are similarly `Range | None` upstream (used for sorting lists
that may contain missing entries) and stay optional here.
"""

import from .position { Position }

def range_is_empty(r: Range) -> bool {
    return r.start_line_number == r.end_line_number and r.start_column == r.end_column;
}

def range_contains_position(r: Range, position: Position) -> bool {
    if position.line_number < r.start_line_number or position.line_number > r.end_line_number {
        return False;
    }
    if position.line_number == r.start_line_number and position.column < r.start_column {
        return False;
    }
    if position.line_number == r.end_line_number and position.column > r.end_column {
        return False;
    }
    return True;
}

def range_contains_range(r: Range, other_range: Range) -> bool {
    if other_range.start_line_number < r.start_line_number or other_range.end_line_number < r.start_line_number {
        return False;
    }
    if other_range.start_line_number > r.end_line_number or other_range.end_line_number > r.end_line_number {
        return False;
    }
    if other_range.start_line_number == r.start_line_number and other_range.start_column < r.start_column {
        return False;
    }
    if other_range.end_line_number == r.end_line_number and other_range.end_column > r.end_column {
        return False;
    }
    return True;
}

def range_strict_contains_range(r: Range, other_range: Range) -> bool {
    if other_range.start_line_number < r.start_line_number or other_range.end_line_number < r.start_line_number {
        return False;
    }
    if other_range.start_line_number > r.end_line_number or other_range.end_line_number > r.end_line_number {
        return False;
    }
    if other_range.start_line_number == r.start_line_number and other_range.start_column <= r.start_column {
        return False;
    }
    if other_range.end_line_number == r.end_line_number and other_range.end_column >= r.end_column {
        return False;
    }
    return True;
}

def range_plus_range(a: Range, b: Range) -> Range {
    start_line_number = 0;
    start_column = 0;
    end_line_number = 0;
    end_column = 0;

    if b.start_line_number < a.start_line_number {
        start_line_number = b.start_line_number;
        start_column = b.start_column;
    } elif b.start_line_number == a.start_line_number {
        start_line_number = b.start_line_number;
        start_column = min(b.start_column, a.start_column);
    } else {
        start_line_number = a.start_line_number;
        start_column = a.start_column;
    }

    if b.end_line_number > a.end_line_number {
        end_line_number = b.end_line_number;
        end_column = b.end_column;
    } elif b.end_line_number == a.end_line_number {
        end_line_number = b.end_line_number;
        end_column = max(b.end_column, a.end_column);
    } else {
        end_line_number = a.end_line_number;
        end_column = a.end_column;
    }

    return Range(
        start_line_number=start_line_number, start_column=start_column,
        end_line_number=end_line_number, end_column=end_column
    );
}

def range_intersect_ranges(a: Range, b: Range) -> Range | None {
    result_start_line_number = a.start_line_number;
    result_start_column = a.start_column;
    result_end_line_number = a.end_line_number;
    result_end_column = a.end_column;
    other_start_line_number = b.start_line_number;
    other_start_column = b.start_column;
    other_end_line_number = b.end_line_number;
    other_end_column = b.end_column;

    if result_start_line_number < other_start_line_number {
        result_start_line_number = other_start_line_number;
        result_start_column = other_start_column;
    } elif result_start_line_number == other_start_line_number {
        result_start_column = max(result_start_column, other_start_column);
    }

    if result_end_line_number > other_end_line_number {
        result_end_line_number = other_end_line_number;
        result_end_column = other_end_column;
    } elif result_end_line_number == other_end_line_number {
        result_end_column = min(result_end_column, other_end_column);
    }

    if result_start_line_number > result_end_line_number {
        return None;
    }
    if result_start_line_number == result_end_line_number and result_start_column > result_end_column {
        return None;
    }
    return Range(
        start_line_number=result_start_line_number, start_column=result_start_column,
        end_line_number=result_end_line_number, end_column=result_end_column
    );
}

def range_equals(a: Range | None, b: Range | None) -> bool {
    if a is None and b is None {
        return True;
    }
    return (
        a is not None and b is not None
        and a.start_line_number == b.start_line_number
        and a.start_column == b.start_column
        and a.end_line_number == b.end_line_number
        and a.end_column == b.end_column
    );
}

def range_get_end_position(r: Range) -> Position {
    return Position(line_number=r.end_line_number, column=r.end_column);
}

def range_get_start_position(r: Range) -> Position {
    return Position(line_number=r.start_line_number, column=r.start_column);
}

def range_collapse_to_start(r: Range) -> Range {
    return Range(
        start_line_number=r.start_line_number, start_column=r.start_column,
        end_line_number=r.start_line_number, end_column=r.start_column
    );
}

def range_collapse_to_end(r: Range) -> Range {
    return Range(
        start_line_number=r.end_line_number, start_column=r.end_column,
        end_line_number=r.end_line_number, end_column=r.end_column
    );
}

obj Range {
    has start_line_number: int, start_column: int, end_line_number: int, end_column: int;

    def postinit {
        if (self.start_line_number > self.end_line_number) or (
            self.start_line_number == self.end_line_number and self.start_column > self.end_column
        ) {
            orig_start_line_number = self.start_line_number;
            orig_start_column = self.start_column;
            self.start_line_number = self.end_line_number;
            self.start_column = self.end_column;
            self.end_line_number = orig_start_line_number;
            self.end_column = orig_start_column;
        }
    }

    """Test if this range is empty."""
    def is_empty -> bool {
        return range_is_empty(self);
    }

    """Test if position is in this range. Positions at the edges count as contained."""
    def contains_position(position: Position) -> bool {
        return range_contains_position(self, position);
    }

    """Test if `position` is in `range`, excluding the edges. @internal, static-only upstream."""
    static def strict_contains_position(r: Range, position: Position) -> bool {
        if position.line_number < r.start_line_number or position.line_number > r.end_line_number {
            return False;
        }
        if position.line_number == r.start_line_number and position.column <= r.start_column {
            return False;
        }
        if position.line_number == r.end_line_number and position.column >= r.end_column {
            return False;
        }
        return True;
    }

    """Test if range is in this range. Equal ranges count as contained."""
    def contains_range(other_range: Range) -> bool {
        return range_contains_range(self, other_range);
    }

    """Test if `other_range` is strictly in this range (must start after, end before)."""
    def strict_contains_range(other_range: Range) -> bool {
        return range_strict_contains_range(self, other_range);
    }

    """A reunion of this range and `other_range`: smallest start, largest end."""
    def plus_range(other_range: Range) -> Range {
        return range_plus_range(self, other_range);
    }

    """An intersection of this range and `other_range`, or None if they don't overlap."""
    def intersect_ranges(other_range: Range) -> Range | None {
        return range_intersect_ranges(self, other_range);
    }

    """Test if this range equals `other`."""
    def equals_range(other: Range | None) -> bool {
        return range_equals(self, other);
    }

    """Return the end position (after or equal to the start position)."""
    def get_end_position -> Position {
        return range_get_end_position(self);
    }

    """Return the start position (before or equal to the end position)."""
    def get_start_position -> Position {
        return range_get_start_position(self);
    }

    """Transform to a user-presentable string representation."""
    def to_string -> str {
        return (
            "[" + str(self.start_line_number) + "," + str(self.start_column)
            + " -> " + str(self.end_line_number) + "," + str(self.end_column) + "]"
        );
    }

    """New range using this range's start, and (end_line_number, end_column) as the end."""
    def set_end_position(end_line_number: int, end_column: int) -> Range {
        return Range(
            start_line_number=self.start_line_number, start_column=self.start_column,
            end_line_number=end_line_number, end_column=end_column
        );
    }

    """New range using this range's end, and (start_line_number, start_column) as the start."""
    def set_start_position(start_line_number: int, start_column: int) -> Range {
        return Range(
            start_line_number=start_line_number, start_column=start_column,
            end_line_number=self.end_line_number, end_column=self.end_column
        );
    }

    """New empty range using this range's start position."""
    def collapse_to_start -> Range {
        return range_collapse_to_start(self);
    }

    """New empty range using this range's end position."""
    def collapse_to_end -> Range {
        return range_collapse_to_end(self);
    }

    """Move the range by the given number of lines."""
    def delta(line_count: int) -> Range {
        return Range(
            start_line_number=self.start_line_number + line_count, start_column=self.start_column,
            end_line_number=self.end_line_number + line_count, end_column=self.end_column
        );
    }

    """Test if this range starts and ends on the same line."""
    def is_single_line -> bool {
        return self.start_line_number == self.end_line_number;
    }

    """Build a Range from a start Position and an (optional, defaults to start) end Position."""
    static def from_positions(start: Position, end: Position | None = None) -> Range {
        real_end = start if end is None else end;
        return Range(
            start_line_number=start.line_number, start_column=start.column,
            end_line_number=real_end.line_number, end_column=real_end.column
        );
    }

    """Create a `Range` from an `IRange`-shaped value; `None` in, `None` out."""
    static def lift(r: Range | None) -> Range | None {
        if r is None {
            return None;
        }
        return Range(
            start_line_number=r.start_line_number, start_column=r.start_column,
            end_line_number=r.end_line_number, end_column=r.end_column
        );
    }

    """Test if `value` looks like an `IRange` (has all four numeric fields)."""
    static def is_i_range(value: any) -> bool {
        if value is None {
            return False;
        }
        sl = value?.start_line_number;
        sc = value?.start_column;
        el = value?.end_line_number;
        ec = value?.end_column;
        return (
            isinstance(sl, int) and isinstance(sc, int)
            and isinstance(el, int) and isinstance(ec, int)
        );
    }

    """Test if the two ranges are touching in any way (adjacency counts)."""
    static def are_intersecting_or_touching(a: Range, b: Range) -> bool {
        if a.end_line_number < b.start_line_number or (
            a.end_line_number == b.start_line_number and a.end_column < b.start_column
        ) {
            return False;
        }
        if b.end_line_number < a.start_line_number or (
            b.end_line_number == a.start_line_number and b.end_column < a.start_column
        ) {
            return False;
        }
        return True;
    }

    """Test if the two ranges are intersecting. Touching ranges count as intersecting."""
    static def are_intersecting(a: Range, b: Range) -> bool {
        if a.end_line_number < b.start_line_number or (
            a.end_line_number == b.start_line_number and a.end_column <= b.start_column
        ) {
            return False;
        }
        if b.end_line_number < a.start_line_number or (
            b.end_line_number == a.start_line_number and b.end_column <= a.start_column
        ) {
            return False;
        }
        return True;
    }

    """Test if the two ranges intersect, but are not merely touching."""
    static def are_only_intersecting(a: Range, b: Range) -> bool {
        if a.end_line_number < (b.start_line_number - 1) or (
            a.end_line_number == b.start_line_number and a.end_column < (b.start_column - 1)
        ) {
            return False;
        }
        if b.end_line_number < (a.start_line_number - 1) or (
            b.end_line_number == a.start_line_number and b.end_column < (a.start_column - 1)
        ) {
            return False;
        }
        return True;
    }

    """Sort comparator: compares by start position, then end position. None sorts last."""
    static def compare_ranges_using_starts(a: Range | None, b: Range | None) -> int {
        if a is not None and b is not None {
            if a.start_line_number == b.start_line_number {
                if a.start_column == b.start_column {
                    if a.end_line_number == b.end_line_number {
                        return a.end_column - b.end_column;
                    }
                    return a.end_line_number - b.end_line_number;
                }
                return a.start_column - b.start_column;
            }
            return a.start_line_number - b.start_line_number;
        }
        a_exists = 1 if a else 0;
        b_exists = 1 if b else 0;
        return a_exists - b_exists;
    }

    """Sort comparator: compares by end position, then start position."""
    static def compare_ranges_using_ends(a: Range, b: Range) -> int {
        if a.end_line_number == b.end_line_number {
            if a.end_column == b.end_column {
                if a.start_line_number == b.start_line_number {
                    return a.start_column - b.start_column;
                }
                return a.start_line_number - b.start_line_number;
            }
            return a.end_column - b.end_column;
        }
        return a.end_line_number - b.end_line_number;
    }

    """Test if the range spans multiple lines."""
    static def spans_multiple_lines(r: Range) -> bool {
        return r.end_line_number > r.start_line_number;
    }

    """Plain-data representation; upstream returns `this` since Range already has IRange's shape."""
    def to_json -> Range {
        return self;
    }
}
