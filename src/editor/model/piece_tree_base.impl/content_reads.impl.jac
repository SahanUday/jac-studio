impl PieceTreeBase.get_offset_at(line_number: int, column: int) -> int {
    left_len = 0;
    x = self.tree_root;

    while x != SENTINEL {
        if x.left != SENTINEL and x.lf_left + 1 >= line_number {
            x = x.left;
        } elif x.lf_left + x.piece.line_feed_cnt + 1 >= line_number {
            left_len += x.size_left;
            accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
            return left_len + accumulated + column - 1;
        } else {
            line_number -= x.lf_left + x.piece.line_feed_cnt;
            left_len += x.size_left + x.piece.length;
            x = x.right;
        }
    }

    return left_len;
}

impl PieceTreeBase.get_position_at(offset: int) -> Position {
    offset = max(0, offset);

    x = self.tree_root;
    lf_cnt = 0;
    original_offset = offset;

    while x != SENTINEL {
        if x.size_left != 0 and x.size_left >= offset {
            x = x.left;
        } elif x.size_left + x.piece.length >= offset {
            (out_index, out_remainder) = self.get_index_of(x, offset - x.size_left);

            lf_cnt += x.lf_left + out_index;

            if out_index == 0 {
                line_start_offset = self.get_offset_at(lf_cnt + 1, 1);
                column = original_offset - line_start_offset;
                return Position(line_number=lf_cnt + 1, column=column + 1);
            }

            return Position(line_number=lf_cnt + 1, column=out_remainder + 1);
        } else {
            offset -= x.size_left + x.piece.length;
            lf_cnt += x.lf_left + x.piece.line_feed_cnt;

            if x.right == SENTINEL {
                line_start_offset = self.get_offset_at(lf_cnt + 1, 1);
                column = original_offset - offset - line_start_offset;
                return Position(line_number=lf_cnt + 1, column=column + 1);
            } else {
                x = x.right;
            }
        }
    }

    return Position(line_number=1, column=1);
}

impl PieceTreeBase.get_value_in_range(rng: Range, eol: str = "") -> str {
    if rng.start_line_number == rng.end_line_number and rng.start_column == rng.end_column {
        return "";
    }

    start_position = self.node_at2(rng.start_line_number, rng.start_column);
    end_position = self.node_at2(rng.end_line_number, rng.end_column);
    assert start_position is not None and end_position is not None, (
        "get_value_in_range: range out of bounds for this document"
    );

    value = self.get_value_in_range2(start_position, end_position);
    if eol != "" and (eol != self.eol or not self.eol_normalized) {
        return re.sub(r"\r\n|\r|\n", eol, value);
    }
    return value;
}

impl PieceTreeBase.get_value_in_range2(start_position: NodePosition, end_position: NodePosition) -> str {
    if start_position.nd == end_position.nd {
        nd = start_position.nd;
        buffer = self.buffers[nd.piece.buffer_index].buffer;
        start_offset = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start);
        return buffer[start_offset + start_position.remainder:start_offset + end_position.remainder];
    }

    x = start_position.nd;
    buffer = self.buffers[x.piece.buffer_index].buffer;
    start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
    ret = buffer[start_offset + start_position.remainder:start_offset + x.piece.length];

    x = x.next();
    while x != SENTINEL {
        buffer = self.buffers[x.piece.buffer_index].buffer;
        start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);

        if x == end_position.nd {
            ret += buffer[start_offset:start_offset + end_position.remainder];
            break;
        } else {
            ret += buffer[start_offset:start_offset + x.piece.length];
        }

        x = x.next();
    }

    return ret;
}

impl PieceTreeBase.get_lines_content -> list[str] {
    lines: list[str] = [];
    current_line = "";
    dangling_cr = False;

    for nd in collect_nodes_in_order(self.tree_root) {
        piece = nd.piece;
        piece_length = piece.length;
        if piece_length == 0 {
            continue;
        }

        buffer = self.buffers[piece.buffer_index].buffer;
        line_starts = self.buffers[piece.buffer_index].line_starts;

        piece_start_line = piece.start.line;
        piece_end_line = piece.end.line;
        piece_start_offset = line_starts[piece_start_line] + piece.start.column;

        if dangling_cr {
            if ord(buffer[piece_start_offset]) == LINE_FEED {
                piece_start_offset += 1;
                piece_length -= 1;
            }
            lines.append(current_line);
            current_line = "";
            dangling_cr = False;
            if piece_length == 0 {
                continue;
            }
        }

        if piece_start_line == piece_end_line {
            if (
                not self.eol_normalized
                and ord(buffer[piece_start_offset + piece_length - 1]) == CARRIAGE_RETURN
            ) {
                dangling_cr = True;
                current_line += buffer[piece_start_offset:piece_start_offset + piece_length - 1];
            } else {
                current_line += buffer[piece_start_offset:piece_start_offset + piece_length];
            }
            continue;
        }

        if self.eol_normalized {
            current_line += buffer[
                piece_start_offset:max(piece_start_offset, line_starts[piece_start_line + 1] - self.eol_length)
            ];
        } else {
            current_line += re.sub(
                r"(\r\n|\r|\n)$", "", buffer[piece_start_offset:line_starts[piece_start_line + 1]]
            );
        }
        lines.append(current_line);

        line = piece_start_line + 1;
        while line < piece_end_line {
            if self.eol_normalized {
                current_line = buffer[line_starts[line]:line_starts[line + 1] - self.eol_length];
            } else {
                current_line = re.sub(
                    r"(\r\n|\r|\n)$", "", buffer[line_starts[line]:line_starts[line + 1]]
                );
            }
            lines.append(current_line);
            line += 1;
        }

        if (
            not self.eol_normalized
            and ord(buffer[line_starts[piece_end_line] + piece.end.column - 1]) == CARRIAGE_RETURN
        ) {
            dangling_cr = True;
            if piece.end.column == 0 {
                lines.pop();
            } else {
                current_line = buffer[line_starts[piece_end_line]:line_starts[piece_end_line] + piece.end.column - 1];
            }
        } else {
            current_line = buffer[line_starts[piece_end_line]:line_starts[piece_end_line] + piece.end.column];
        }
    }

    if dangling_cr {
        lines.append(current_line);
        current_line = "";
    }

    lines.append(current_line);
    return lines;
}

impl PieceTreeBase.get_length -> int {
    return self.length;
}

impl PieceTreeBase.get_line_count -> int {
    return self.line_cnt;
}

impl PieceTreeBase.get_line_content(line_number: int) -> str {
    if self.last_visited_line_number == line_number {
        return self.last_visited_line_value;
    }

    self.last_visited_line_number = line_number;

    if line_number == self.line_cnt {
        self.last_visited_line_value = self.get_line_raw_content(line_number, 0);
    } elif self.eol_normalized {
        self.last_visited_line_value = self.get_line_raw_content(line_number, self.eol_length);
    } else {
        self.last_visited_line_value = re.sub(
            r"(\r\n|\r|\n)$", "", self.get_line_raw_content(line_number, 0)
        );
    }

    return self.last_visited_line_value;
}

impl PieceTreeBase._get_char_code(node_pos: NodePosition) -> int {
    if node_pos.remainder == node_pos.nd.piece.length {
        matching_nd = node_pos.nd.next();
        if matching_nd == SENTINEL {
            return 0;
        }
        buffer = self.buffers[matching_nd.piece.buffer_index];
        start_offset = self.offset_in_buffer(matching_nd.piece.buffer_index, matching_nd.piece.start);
        return ord(buffer.buffer[start_offset]);
    } else {
        buffer = self.buffers[node_pos.nd.piece.buffer_index];
        start_offset = self.offset_in_buffer(node_pos.nd.piece.buffer_index, node_pos.nd.piece.start);
        target_offset = start_offset + node_pos.remainder;
        return ord(buffer.buffer[target_offset]);
    }
}

impl PieceTreeBase.get_line_char_code(line_number: int, index: int) -> int {
    node_pos = self.node_at2(line_number, index + 1);
    assert node_pos is not None, "get_line_char_code: position out of bounds for this document";
    return self._get_char_code(node_pos);
}

impl PieceTreeBase.get_line_length(line_number: int) -> int {
    if line_number == self.get_line_count() {
        start_offset = self.get_offset_at(line_number, 1);
        return self.get_length() - start_offset;
    }
    return self.get_offset_at(line_number + 1, 1) - self.get_offset_at(line_number, 1) - self.eol_length;
}

impl PieceTreeBase.get_char_code(offset: int) -> int {
    node_pos = self.node_at(offset);
    return self._get_char_code(node_pos);
}

impl PieceTreeBase.get_nearest_chunk(offset: int) -> str {
    node_pos = self.node_at(offset);
    if node_pos.remainder == node_pos.nd.piece.length {
        matching_nd = node_pos.nd.next();
        if matching_nd == SENTINEL {
            return "";
        }
        buffer = self.buffers[matching_nd.piece.buffer_index];
        start_offset = self.offset_in_buffer(matching_nd.piece.buffer_index, matching_nd.piece.start);
        return buffer.buffer[start_offset:start_offset + matching_nd.piece.length];
    } else {
        buffer = self.buffers[node_pos.nd.piece.buffer_index];
        start_offset = self.offset_in_buffer(node_pos.nd.piece.buffer_index, node_pos.nd.piece.start);
        target_offset = start_offset + node_pos.remainder;
        target_end = start_offset + node_pos.nd.piece.length;
        return buffer.buffer[target_offset:target_end];
    }
}

impl PieceTreeBase.get_lines_raw_content -> str {
    return self.get_content_of_subtree(self.tree_root);
}

impl PieceTreeBase.get_line_raw_content(line_number: int, end_offset: int) -> str {
    x = self.tree_root;
    ret = "";
    cache = self.search_cache.get2(line_number);
    if cache is not None {
        x = cache.nd;
        prev_accumulated_value = self.get_accumulated_value(x, line_number - cache.node_start_line_number - 1);
        buffer = self.buffers[x.piece.buffer_index].buffer;
        start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
        if cache.node_start_line_number + x.piece.line_feed_cnt == line_number {
            ret = buffer[start_offset + prev_accumulated_value:start_offset + x.piece.length];
        } else {
            accumulated_value = self.get_accumulated_value(x, line_number - cache.node_start_line_number);
            return buffer[start_offset + prev_accumulated_value:start_offset + accumulated_value - end_offset];
        }
    } else {
        node_start_offset = 0;
        original_line_number = line_number;
        while x != SENTINEL {
            if x.left != SENTINEL and x.lf_left >= line_number - 1 {
                x = x.left;
            } elif x.lf_left + x.piece.line_feed_cnt > line_number - 1 {
                prev_accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 1);
                buffer = self.buffers[x.piece.buffer_index].buffer;
                start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                node_start_offset += x.size_left;
                self.search_cache.set(CacheEntry(
                    nd=x, node_start_offset=node_start_offset,
                    node_start_line_number=original_line_number - (line_number - 1 - x.lf_left)
                ));
                return buffer[start_offset + prev_accumulated_value:start_offset + accumulated_value - end_offset];
            } elif x.lf_left + x.piece.line_feed_cnt == line_number - 1 {
                prev_accumulated_value = self.get_accumulated_value(x, line_number - x.lf_left - 2);
                buffer = self.buffers[x.piece.buffer_index].buffer;
                start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
                ret = buffer[start_offset + prev_accumulated_value:start_offset + x.piece.length];
                break;
            } else {
                line_number -= x.lf_left + x.piece.line_feed_cnt;
                node_start_offset += x.size_left + x.piece.length;
                x = x.right;
            }
        }
    }

    x = x.next();
    while x != SENTINEL {
        buffer = self.buffers[x.piece.buffer_index].buffer;

        if x.piece.line_feed_cnt > 0 {
            accumulated_value = self.get_accumulated_value(x, 0);
            start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
            ret += buffer[start_offset:start_offset + accumulated_value - end_offset];
            return ret;
        } else {
            start_offset = self.offset_in_buffer(x.piece.buffer_index, x.piece.start);
            ret += buffer[start_offset:start_offset + x.piece.length];
        }

        x = x.next();
    }

    return ret;
}

impl PieceTreeBase.get_node_content(nd: TreeNode) -> str {
    if nd == SENTINEL {
        return "";
    }
    buffer = self.buffers[nd.piece.buffer_index];
    piece = nd.piece;
    start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);
    end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);
    return buffer.buffer[start_offset:end_offset];
}

impl PieceTreeBase.get_piece_content(piece: Piece) -> str {
    buffer = self.buffers[piece.buffer_index];
    start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);
    end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);
    return buffer.buffer[start_offset:end_offset];
}

impl PieceTreeBase.get_content_of_subtree(nd: TreeNode) -> str {
    text = "";
    for descendant in collect_nodes_in_order(nd) {
        text += self.get_node_content(descendant);
    }
    return text;
}
