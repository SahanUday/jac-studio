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
upstream name and forwards to an internal module-level function (`_range_is_empty`,
`_range_contains_position`, etc., mirroring `interval_tree.jac`'s free-function idiom) that holds
the real logic. Anything that was static-only upstream (`strictContainsPosition`, `fromPositions`,
`lift`, `isIRange`, `areIntersectingOrTouching`, `areIntersecting`, `areOnlyIntersecting`,
`compareRangesUsingStarts`, `compareRangesUsingEnds`, `spansMultipleLines`) has no instance-side
twin, so it stays a plain `static def` on `Range` with no renaming needed. A caller that upstream
would reach via `Range.plusRange(a, b)` (two arbitrary ranges, no natural receiver) uses the
internal `_range_plus_range(a, b)` function directly here instead.

`Range.lift` upstream is a `null`/`undefined`-swallowing overload (`lift(range) -> Range`,
`lift(null | undefined) -> null`); ported as `range: Range | None -> Range | None` since Jac has
no overload resolution on nullability, with the same behavior (`None` in, `None` out).
`compareRangesUsingStarts`'s `a`/`b` are similarly `Range | None` upstream (used for sorting lists
that may contain missing entries) and stay optional here.
"""

import from .position { Position }

obj Range {
    has start_line_number: int, start_column: int, end_line_number: int, end_column: int;

    def postinit -> None;

    """Test if this range is empty."""
    def is_empty -> bool;

    """Test if position is in this range. Positions at the edges count as contained."""
    def contains_position(position: Position) -> bool;

    """Test if `position` is in `range`, excluding the edges. @internal, static-only upstream."""
    static def strict_contains_position(r: Range, position: Position) -> bool;

    """Test if range is in this range. Equal ranges count as contained."""
    def contains_range(other_range: Range) -> bool;

    """Test if `other_range` is strictly in this range (must start after, end before)."""
    def strict_contains_range(other_range: Range) -> bool;

    """A reunion of this range and `other_range`: smallest start, largest end."""
    def plus_range(other_range: Range) -> Range;

    """An intersection of this range and `other_range`, or None if they don't overlap."""
    def intersect_ranges(other_range: Range) -> Range | None;

    """Test if this range equals `other`."""
    def equals_range(other: Range | None) -> bool;

    """Return the end position (after or equal to the start position)."""
    def get_end_position -> Position;

    """Return the start position (before or equal to the end position)."""
    def get_start_position -> Position;

    """Transform to a user-presentable string representation."""
    def to_string -> str;

    """New range using this range's start, and (end_line_number, end_column) as the end."""
    def set_end_position(end_line_number: int, end_column: int) -> Range;

    """New range using this range's end, and (start_line_number, start_column) as the start."""
    def set_start_position(start_line_number: int, start_column: int) -> Range;

    """New empty range using this range's start position."""
    def collapse_to_start -> Range;

    """New empty range using this range's end position."""
    def collapse_to_end -> Range;

    """Move the range by the given number of lines."""
    def delta(line_count: int) -> Range;

    """Test if this range starts and ends on the same line."""
    def is_single_line -> bool;

    """Build a Range from a start Position and an (optional, defaults to start) end Position."""
    static def from_positions(start: Position, end: Position | None = None) -> Range;

    """Create a `Range` from an `IRange`-shaped value; `None` in, `None` out."""
    static def lift(r: Range | None) -> Range | None;

    """Test if `value` looks like an `IRange` (has all four numeric fields)."""
    static def is_i_range(value: any) -> bool;

    """Test if the two ranges are touching in any way (adjacency counts)."""
    static def are_intersecting_or_touching(a: Range, b: Range) -> bool;

    """Test if the two ranges are intersecting. Touching ranges count as intersecting."""
    static def are_intersecting(a: Range, b: Range) -> bool;

    """Test if the two ranges intersect, but are not merely touching."""
    static def are_only_intersecting(a: Range, b: Range) -> bool;

    """Sort comparator: compares by start position, then end position. None sorts last."""
    static def compare_ranges_using_starts(a: Range | None, b: Range | None) -> int;

    """Sort comparator: compares by end position, then start position."""
    static def compare_ranges_using_ends(a: Range, b: Range) -> int;

    """Test if the range spans multiple lines."""
    static def spans_multiple_lines(r: Range) -> bool;

    """Plain-data representation; upstream returns `this` since Range already has IRange's shape."""
    def to_json -> Range;
}
