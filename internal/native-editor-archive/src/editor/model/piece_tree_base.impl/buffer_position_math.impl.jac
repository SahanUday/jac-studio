impl PieceTreeBase.position_in_buffer(nd: TreeNode, remainder: int) -> BufferCursor {
    piece = nd.piece;
    buffer_index = nd.piece.buffer_index;
    line_starts = self.buffers[buffer_index].line_starts;

    start_offset = line_starts[piece.start.line] + piece.start.column;
    offset = start_offset + remainder;

    low = piece.start.line;
    high = piece.end.line;

    mid = 0;
    mid_start = 0;

    while low <= high {
        mid = low + (high - low) // 2;
        mid_start = line_starts[mid];

        if mid == high {
            break;
        }

        mid_stop = line_starts[mid + 1];

        if offset < mid_start {
            high = mid - 1;
        } elif offset >= mid_stop {
            low = mid + 1;
        } else {
            break;
        }
    }

    return BufferCursor(line=mid, column=offset - mid_start);
}

impl PieceTreeBase.get_line_feed_cnt(buffer_index: int, start: BufferCursor, end: BufferCursor) -> int {
    if end.column == 0 {
        return end.line - start.line;
    }

    line_starts = self.buffers[buffer_index].line_starts;
    if end.line == len(line_starts) - 1 {
        return end.line - start.line;
    }

    next_line_start_offset = line_starts[end.line + 1];
    end_offset = line_starts[end.line] + end.column;
    if next_line_start_offset > end_offset + 1 {
        return end.line - start.line;
    }

    previous_char_offset = end_offset - 1;
    buffer = self.buffers[buffer_index].buffer;

    if ord(buffer[previous_char_offset]) == CARRIAGE_RETURN {
        return end.line - start.line + 1;
    } else {
        return end.line - start.line;
    }
}

impl PieceTreeBase.offset_in_buffer(buffer_index: int, cursor: BufferCursor) -> int {
    line_starts = self.buffers[buffer_index].line_starts;
    return line_starts[cursor.line] + cursor.column;
}

impl PieceTreeBase.get_index_of(nd: TreeNode, accumulated_value: int) -> tuple[int, int] {
    piece = nd.piece;
    pos = self.position_in_buffer(nd, accumulated_value);
    line_cnt = pos.line - piece.start.line;

    if (
        self.offset_in_buffer(piece.buffer_index, piece.end)
        - self.offset_in_buffer(piece.buffer_index, piece.start)
    ) == accumulated_value {
        real_line_cnt = self.get_line_feed_cnt(nd.piece.buffer_index, piece.start, pos);
        if real_line_cnt != line_cnt {
            return (real_line_cnt, 0);
        }
    }

    return (line_cnt, pos.column);
}

impl PieceTreeBase.get_accumulated_value(nd: TreeNode, index: int) -> int {
    if index < 0 {
        return 0;
    }
    piece = nd.piece;
    line_starts = self.buffers[piece.buffer_index].line_starts;
    expected_line_start_index = piece.start.line + index + 1;
    if expected_line_start_index > piece.end.line {
        return line_starts[piece.end.line] + piece.end.column - line_starts[piece.start.line] - piece.start.column;
    } else {
        return line_starts[expected_line_start_index] - line_starts[piece.start.line] - piece.start.column;
    }
}
