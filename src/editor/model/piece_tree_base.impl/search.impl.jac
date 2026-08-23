impl PieceTreeBase.find_matches_in_node(
    nd: TreeNode, searcher: Searcher, start_line_number: int, start_column: int,
    start_cursor: BufferCursor, end_cursor: BufferCursor, capture_matches: bool,
    limit_result_count: int, result: list[FindMatch]
) -> None {
    buffer = self.buffers[nd.piece.buffer_index];
    start_offset_in_buffer = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start);
    start = self.offset_in_buffer(nd.piece.buffer_index, start_cursor);
    end = self.offset_in_buffer(nd.piece.buffer_index, end_cursor);

    if searcher.word_separators is not None {
        search_text = buffer.buffer[start:end];
        offset_delta = start;
        searcher.reset(0);
    } else {
        search_text = buffer.buffer;
        offset_delta = 0;
        searcher.reset(start);
    }

    m = searcher.next(search_text);
    while m is not None {
        m_index = m.start() + offset_delta;
        if m_index >= end {
            return;
        }
        ret = self.position_in_buffer(nd, m_index - start_offset_in_buffer);
        line_feed_cnt = self.get_line_feed_cnt(nd.piece.buffer_index, start_cursor, ret);
        ret_start_column = (
            ret.column - start_cursor.column + start_column if ret.line == start_cursor.line
            else ret.column + 1
        );
        match_text = m.group(0);
        ret_end_column = ret_start_column + len(match_text);
        result.append(create_find_match(
            Range(
                start_line_number=start_line_number + line_feed_cnt, start_column=ret_start_column,
                end_line_number=start_line_number + line_feed_cnt, end_column=ret_end_column
            ),
            m, capture_matches
        ));

        if m_index + len(match_text) >= end {
            return;
        }
        if len(result) >= limit_result_count {
            return;
        }

        m = searcher.next(search_text);
    }
}

impl PieceTreeBase.find_matches_line_by_line(
    search_range: Range, search_data: SearchData, capture_matches: bool, limit_result_count: int
) -> list[FindMatch] {
    result: list[FindMatch] = [];
    searcher = Searcher(word_separators=search_data.word_separators, search_regex=search_data.regex);

    start_position = self.node_at2(search_range.start_line_number, search_range.start_column);
    if start_position is None {
        return [];
    }
    end_position = self.node_at2(search_range.end_line_number, search_range.end_column);
    if end_position is None {
        return [];
    }
    start = self.position_in_buffer(start_position.nd, start_position.remainder);
    end = self.position_in_buffer(end_position.nd, end_position.remainder);

    if start_position.nd == end_position.nd {
        self.find_matches_in_node(
            start_position.nd, searcher, search_range.start_line_number, search_range.start_column,
            start, end, capture_matches, limit_result_count, result
        );
        return result;
    }

    start_line_number = search_range.start_line_number;
    current_nd = start_position.nd;
    while current_nd != end_position.nd {
        line_break_cnt = self.get_line_feed_cnt(current_nd.piece.buffer_index, start, current_nd.piece.end);

        if line_break_cnt >= 1 {
            line_starts = self.buffers[current_nd.piece.buffer_index].line_starts;
            start_offset_in_buffer = self.offset_in_buffer(current_nd.piece.buffer_index, current_nd.piece.start);
            next_line_start_offset = line_starts[start.line + line_break_cnt];
            start_column = (
                search_range.start_column if start_line_number == search_range.start_line_number else 1
            );
            self.find_matches_in_node(
                current_nd, searcher, start_line_number, start_column, start,
                self.position_in_buffer(current_nd, next_line_start_offset - start_offset_in_buffer),
                capture_matches, limit_result_count, result
            );

            if len(result) >= limit_result_count {
                return result;
            }
            start_line_number += line_break_cnt;
        }

        start_column = search_range.start_column - 1 if start_line_number == search_range.start_line_number else 0;
        if start_line_number == search_range.end_line_number {
            text = self.get_line_content(start_line_number)[start_column:search_range.end_column - 1];
            self._find_matches_in_line(
                search_data, searcher, text, search_range.end_line_number, start_column, result,
                capture_matches, limit_result_count
            );
            return result;
        }

        self._find_matches_in_line(
            search_data, searcher, self.get_line_content(start_line_number)[start_column:],
            start_line_number, start_column, result, capture_matches, limit_result_count
        );

        if len(result) >= limit_result_count {
            return result;
        }

        start_line_number += 1;
        start_position = self.node_at2(start_line_number, 1);
        assert start_position is not None, (
            "find_matches_line_by_line: advanced past the last line while still short of end_position"
        );
        current_nd = start_position.nd;
        start = self.position_in_buffer(start_position.nd, start_position.remainder);
    }

    if start_line_number == search_range.end_line_number {
        start_column = search_range.start_column - 1 if start_line_number == search_range.start_line_number else 0;
        text = self.get_line_content(start_line_number)[start_column:search_range.end_column - 1];
        self._find_matches_in_line(
            search_data, searcher, text, search_range.end_line_number, start_column, result,
            capture_matches, limit_result_count
        );
        return result;
    }

    start_column = search_range.start_column if start_line_number == search_range.start_line_number else 1;
    self.find_matches_in_node(
        end_position.nd, searcher, start_line_number, start_column, start, end, capture_matches,
        limit_result_count, result
    );
    return result;
}

impl PieceTreeBase._find_matches_in_line(
    search_data: SearchData, searcher: Searcher, text: str, line_number: int, delta_offset: int,
    result: list[FindMatch], capture_matches: bool, limit_result_count: int
) -> None {
    word_separators = search_data.word_separators;
    if not capture_matches and search_data.simple_search is not None and search_data.simple_search != "" {
        search_string = search_data.simple_search;
        search_string_len = len(search_string);
        text_length = len(text);

        last_match_index = -search_string_len;
        last_match_index = text.find(search_string, last_match_index + search_string_len);
        while last_match_index != -1 {
            if word_separators is None or is_valid_match(
                word_separators, text, text_length, last_match_index, search_string_len
            ) {
                result.append(FindMatch(
                    range=Range(
                        start_line_number=line_number, start_column=last_match_index + 1 + delta_offset,
                        end_line_number=line_number,
                        end_column=last_match_index + 1 + search_string_len + delta_offset
                    ),
                    matches=None
                ));
                if len(result) >= limit_result_count {
                    return;
                }
            }
            last_match_index = text.find(search_string, last_match_index + search_string_len);
        }
        return;
    }

    searcher.reset(0);
    m = searcher.next(text);
    while m is not None {
        match_text = m.group(0);
        result.append(create_find_match(
            Range(
                start_line_number=line_number, start_column=m.start() + 1 + delta_offset,
                end_line_number=line_number, end_column=m.start() + 1 + len(match_text) + delta_offset
            ),
            m, capture_matches
        ));
        if len(result) >= limit_result_count {
            return;
        }
        m = searcher.next(text);
    }
}
