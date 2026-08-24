def _range_is_empty(r: Range) -> bool {
    return r.start_line_number == r.end_line_number and r.start_column == r.end_column;
}

def _range_contains_position(r: Range, position: Position) -> bool {
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

def _range_contains_range(r: Range, other_range: Range) -> bool {
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

def _range_strict_contains_range(r: Range, other_range: Range) -> bool {
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

def _range_plus_range(a: Range, b: Range) -> Range {
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

def _range_intersect_ranges(a: Range, b: Range) -> Range | None {
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

def _range_equals(a: Range | None, b: Range | None) -> bool {
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

def _range_get_end_position(r: Range) -> Position {
    return Position(line_number=r.end_line_number, column=r.end_column);
}

def _range_get_start_position(r: Range) -> Position {
    return Position(line_number=r.start_line_number, column=r.start_column);
}

def _range_collapse_to_start(r: Range) -> Range {
    return Range(
        start_line_number=r.start_line_number, start_column=r.start_column,
        end_line_number=r.start_line_number, end_column=r.start_column
    );
}

def _range_collapse_to_end(r: Range) -> Range {
    return Range(
        start_line_number=r.end_line_number, start_column=r.end_column,
        end_line_number=r.end_line_number, end_column=r.end_column
    );
}

impl Range.postinit -> None {
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

impl Range.is_empty -> bool {
    return _range_is_empty(self);
}

impl Range.contains_position(position: Position) -> bool {
    return _range_contains_position(self, position);
}

impl Range.strict_contains_position(r: Range, position: Position) -> bool {
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

impl Range.contains_range(other_range: Range) -> bool {
    return _range_contains_range(self, other_range);
}

impl Range.strict_contains_range(other_range: Range) -> bool {
    return _range_strict_contains_range(self, other_range);
}

impl Range.plus_range(other_range: Range) -> Range {
    return _range_plus_range(self, other_range);
}

impl Range.intersect_ranges(other_range: Range) -> Range | None {
    return _range_intersect_ranges(self, other_range);
}

impl Range.equals_range(other: Range | None) -> bool {
    return _range_equals(self, other);
}

impl Range.get_end_position -> Position {
    return _range_get_end_position(self);
}

impl Range.get_start_position -> Position {
    return _range_get_start_position(self);
}

impl Range.to_string -> str {
    return (
        "[" + str(self.start_line_number) + "," + str(self.start_column)
        + " -> " + str(self.end_line_number) + "," + str(self.end_column) + "]"
    );
}

impl Range.set_end_position(end_line_number: int, end_column: int) -> Range {
    return Range(
        start_line_number=self.start_line_number, start_column=self.start_column,
        end_line_number=end_line_number, end_column=end_column
    );
}

impl Range.set_start_position(start_line_number: int, start_column: int) -> Range {
    return Range(
        start_line_number=start_line_number, start_column=start_column,
        end_line_number=self.end_line_number, end_column=self.end_column
    );
}

impl Range.collapse_to_start -> Range {
    return _range_collapse_to_start(self);
}

impl Range.collapse_to_end -> Range {
    return _range_collapse_to_end(self);
}

impl Range.delta(line_count: int) -> Range {
    return Range(
        start_line_number=self.start_line_number + line_count, start_column=self.start_column,
        end_line_number=self.end_line_number + line_count, end_column=self.end_column
    );
}

impl Range.is_single_line -> bool {
    return self.start_line_number == self.end_line_number;
}

impl Range.from_positions(start: Position, end: Position | None = None) -> Range {
    real_end = start if end is None else end;
    return Range(
        start_line_number=start.line_number, start_column=start.column,
        end_line_number=real_end.line_number, end_column=real_end.column
    );
}

impl Range.lift(r: Range | None) -> Range | None {
    if r is None {
        return None;
    }
    return Range(
        start_line_number=r.start_line_number, start_column=r.start_column,
        end_line_number=r.end_line_number, end_column=r.end_column
    );
}

impl Range.is_i_range(value: any) -> bool {
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

impl Range.are_intersecting_or_touching(a: Range, b: Range) -> bool {
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

impl Range.are_intersecting(a: Range, b: Range) -> bool {
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

impl Range.are_only_intersecting(a: Range, b: Range) -> bool {
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

impl Range.compare_ranges_using_starts(a: Range | None, b: Range | None) -> int {
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

impl Range.compare_ranges_using_ends(a: Range, b: Range) -> int {
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

impl Range.spans_multiple_lines(r: Range) -> bool {
    return r.end_line_number > r.start_line_number;
}

impl Range.to_json -> Range {
    return self;
}
