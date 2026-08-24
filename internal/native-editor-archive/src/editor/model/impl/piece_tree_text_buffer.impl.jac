def _is_high_surrogate(ch_code: int) -> bool {
    return ch_code >= 0xD800 and ch_code <= 0xDBFF;
}

"""Index of the first non-space/non-tab character in `s`, or -1 if `s` is all whitespace (or
empty). Ported from strings.ts's `firstNonWhitespaceIndex`."""
def _first_non_whitespace_index(s: str) -> int {
    i = 0;
    length = len(s);
    while i < length {
        ch_code = ord(s[i]);
        if ch_code != 32 and ch_code != TAB {
            return i;
        }
        i += 1;
    }
    return -1;
}

"""Index of the last non-space/non-tab character in `s`, or -1 if `s` is all whitespace (or
empty). Ported from strings.ts's `lastNonWhitespaceIndex` (default `startIndex` only -- this
file's one caller never passes a custom start)."""
def _last_non_whitespace_index(s: str) -> int {
    i = len(s) - 1;
    while i >= 0 {
        ch_code = ord(s[i]);
        if ch_code != 32 and ch_code != TAB {
            return i;
        }
        i -= 1;
    }
    return -1;
}

def _compare_ops_ascending(a: ValidatedEditOperation, b: ValidatedEditOperation) -> int {
    r = Range.compare_ranges_using_ends(a.range, b.range);
    if r != 0 {
        return r;
    }
    return a.sort_index - b.sort_index;
}

def _compare_ops_descending(a: ValidatedEditOperation, b: ValidatedEditOperation) -> int {
    r = Range.compare_ranges_using_ends(a.range, b.range);
    if r != 0 {
        return -r;
    }
    return b.sort_index - a.sort_index;
}

def _sort_ops_ascending(operations: list[ValidatedEditOperation]) -> list[ValidatedEditOperation] {
    result: list[ValidatedEditOperation] = operations[:];
    i = 1;
    while i < len(result) {
        key = result[i];
        j = i - 1;
        while j >= 0 and _compare_ops_ascending(result[j], key) > 0 {
            result[j + 1] = result[j];
            j -= 1;
        }
        result[j + 1] = key;
        i += 1;
    }
    return result;
}

def _sort_ops_descending(operations: list[ValidatedEditOperation]) -> list[ValidatedEditOperation] {
    result: list[ValidatedEditOperation] = operations[:];
    i = 1;
    while i < len(result) {
        key = result[i];
        j = i - 1;
        while j >= 0 and _compare_ops_descending(result[j], key) > 0 {
            result[j + 1] = result[j];
            j -= 1;
        }
        result[j + 1] = key;
        i += 1;
    }
    return result;
}

impl PieceTreeTextBuffer.postinit -> None {
    self.piece_tree = PieceTreeBase(
        init_chunks=self.init_chunks, init_eol=self.init_eol,
        init_eol_normalized=self.init_eol_normalized
    );
}

impl PieceTreeTextBuffer.equal(other: PieceTreeTextBuffer) -> bool {
    if self.bom != other.bom {
        return False;
    }
    if self.get_eol() != other.get_eol() {
        return False;
    }
    return self.piece_tree.equal(other.piece_tree);
}

impl PieceTreeTextBuffer.might_contain_rtl -> bool {
    return self.contains_rtl;
}

impl PieceTreeTextBuffer.might_contain_unusual_line_terminators -> bool {
    return self.contains_unusual_line_terminators;
}

impl PieceTreeTextBuffer.reset_might_contain_unusual_line_terminators -> None {
    self.contains_unusual_line_terminators = False;
}

impl PieceTreeTextBuffer.might_contain_non_basic_ascii -> bool {
    return not self.is_basic_ascii;
}

impl PieceTreeTextBuffer.get_bom -> str {
    return self.bom;
}

impl PieceTreeTextBuffer.get_eol -> str {
    return self.piece_tree.get_eol();
}

impl PieceTreeTextBuffer.create_snapshot(preserve_bom: bool) -> PieceTreeSnapshot {
    return self.piece_tree.create_snapshot(self.bom if preserve_bom else "");
}

impl PieceTreeTextBuffer.get_offset_at(line_number: int, column: int) -> int {
    return self.piece_tree.get_offset_at(line_number, column);
}

impl PieceTreeTextBuffer.get_position_at(offset: int) -> Position {
    return self.piece_tree.get_position_at(offset);
}

impl PieceTreeTextBuffer.get_range_at(start: int, length: int) -> Range {
    end = start + length;
    start_position = self.get_position_at(start);
    end_position = self.get_position_at(end);
    return Range(
        start_line_number=start_position.line_number, start_column=start_position.column,
        end_line_number=end_position.line_number, end_column=end_position.column
    );
}

impl PieceTreeTextBuffer.get_value_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> str {
    if rng.is_empty() {
        return "";
    }
    line_ending = self._get_end_of_line(eol);
    return self.piece_tree.get_value_in_range(rng, line_ending);
}

impl PieceTreeTextBuffer.get_value_length_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int {
    if rng.is_empty() {
        return 0;
    }
    if rng.start_line_number == rng.end_line_number {
        return rng.end_column - rng.start_column;
    }

    start_offset = self.get_offset_at(rng.start_line_number, rng.start_column);
    end_offset = self.get_offset_at(rng.end_line_number, rng.end_column);

    eol_offset_compensation = 0;
    desired_eol = self._get_end_of_line(eol);
    actual_eol = self.get_eol();
    if len(desired_eol) != len(actual_eol) {
        delta = len(desired_eol) - len(actual_eol);
        eol_count = rng.end_line_number - rng.start_line_number;
        eol_offset_compensation = delta * eol_count;
    }

    return end_offset - start_offset + eol_offset_compensation;
}

impl PieceTreeTextBuffer.get_character_count_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int {
    if self.might_contain_non_basic_ascii() {
        result = 0;
        from_line_number = rng.start_line_number;
        to_line_number = rng.end_line_number;
        line_number = from_line_number;
        while line_number <= to_line_number {
            line_content = self.get_line_content(line_number);
            from_offset = (rng.start_column - 1) if line_number == from_line_number else 0;
            to_offset = (rng.end_column - 1) if line_number == to_line_number else len(line_content);

            offset = from_offset;
            while offset < to_offset {
                if _is_high_surrogate(ord(line_content[offset])) {
                    result += 1;
                    offset += 1;
                } else {
                    result += 1;
                }
                offset += 1;
            }
            line_number += 1;
        }

        result += len(self._get_end_of_line(eol)) * (to_line_number - from_line_number);
        return result;
    }

    return self.get_value_length_in_range(rng, eol);
}

impl PieceTreeTextBuffer.get_nearest_chunk(offset: int) -> str {
    return self.piece_tree.get_nearest_chunk(offset);
}

impl PieceTreeTextBuffer.get_length -> int {
    return self.piece_tree.get_length();
}

impl PieceTreeTextBuffer.get_line_count -> int {
    return self.piece_tree.get_line_count();
}

impl PieceTreeTextBuffer.get_lines_content -> list[str] {
    return self.piece_tree.get_lines_content();
}

impl PieceTreeTextBuffer.get_line_content(line_number: int) -> str {
    return self.piece_tree.get_line_content(line_number);
}

impl PieceTreeTextBuffer.get_line_char_code(line_number: int, index: int) -> int {
    return self.piece_tree.get_line_char_code(line_number, index);
}

impl PieceTreeTextBuffer.get_char_code(offset: int) -> int {
    return self.piece_tree.get_char_code(offset);
}

impl PieceTreeTextBuffer.get_line_length(line_number: int) -> int {
    return self.piece_tree.get_line_length(line_number);
}

impl PieceTreeTextBuffer.get_line_min_column(line_number: int) -> int {
    return 1;
}

impl PieceTreeTextBuffer.get_line_max_column(line_number: int) -> int {
    return self.get_line_length(line_number) + 1;
}

impl PieceTreeTextBuffer.get_line_first_non_whitespace_column(line_number: int) -> int {
    result = _first_non_whitespace_index(self.get_line_content(line_number));
    if result == -1 {
        return 0;
    }
    return result + 1;
}

impl PieceTreeTextBuffer.get_line_last_non_whitespace_column(line_number: int) -> int {
    result = _last_non_whitespace_index(self.get_line_content(line_number));
    if result == -1 {
        return 0;
    }
    return result + 2;
}

impl PieceTreeTextBuffer._get_end_of_line(eol: int) -> str {
    if eol == END_OF_LINE_PREFERENCE_LF {
        return "\n";
    } elif eol == END_OF_LINE_PREFERENCE_CRLF {
        return "\r\n";
    } elif eol == END_OF_LINE_PREFERENCE_TEXT_DEFINED {
        return self.get_eol();
    } else {
        raise ValueError("Unknown EOL preference");
    }
}

impl PieceTreeTextBuffer.set_eol(new_eol: str) -> None {
    self.piece_tree.set_eol(new_eol);
}

impl PieceTreeTextBuffer.apply_edits(raw_operations: list[SingleEditOperation]) -> list[ContentChange] {
    operations: list[ValidatedEditOperation] = [];
    i = 0;
    while i < len(raw_operations) {
        op = raw_operations[i];
        range_offset = self.get_offset_at(op.range.start_line_number, op.range.start_column);
        range_length = self.get_value_length_in_range(op.range);
        operations.append(ValidatedEditOperation(
            sort_index=i, range=op.range, range_offset=range_offset, range_length=range_length,
            text=op.text, force_move_markers=op.force_move_markers
        ));
        i += 1;
    }

    operations = _sort_ops_ascending(operations);

    j = 0;
    while j < len(operations) - 1 {
        range_end = operations[j].range.get_end_position();
        next_range_start = operations[j + 1].range.get_start_position();
        if next_range_start.is_before(range_end) {
            raise ValueError("Overlapping ranges are not allowed!");
        }
        j += 1;
    }

    return self._do_apply_edits(operations);
}

impl PieceTreeTextBuffer._do_apply_edits(operations: list[ValidatedEditOperation]) -> list[ContentChange] {
    descending = _sort_ops_descending(operations);
    content_changes: list[ContentChange] = [];

    i = 0;
    while i < len(descending) {
        op = descending[i];
        start_line_number = op.range.start_line_number;
        start_column = op.range.start_column;
        end_line_number = op.range.end_line_number;
        end_column = op.range.end_column;

        if start_line_number == end_line_number and start_column == end_column and len(op.text) == 0 {
            i += 1;
            continue;
        }

        if len(op.text) > 0 {
            self.piece_tree.delete(op.range_offset, op.range_length);
            self.piece_tree.insert(op.range_offset, op.text, True);
        } else {
            self.piece_tree.delete(op.range_offset, op.range_length);
        }

        content_change_range = Range(
            start_line_number=start_line_number, start_column=start_column,
            end_line_number=end_line_number, end_column=end_column
        );
        content_changes.append(ContentChange(
            range=content_change_range, range_length=op.range_length, text=op.text,
            range_offset=op.range_offset, force_move_markers=op.force_move_markers
        ));
        i += 1;
    }

    return content_changes;
}

impl PieceTreeTextBuffer.get_piece_tree -> PieceTreeBase {
    return self.piece_tree;
}
