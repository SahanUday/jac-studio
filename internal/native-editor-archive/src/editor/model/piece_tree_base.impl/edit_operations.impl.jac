impl PieceTreeBase.insert(offset: int, value: str, eol_normalized: bool = False) -> None {
    self.eol_normalized = self.eol_normalized and eol_normalized;
    self.last_visited_line_number = 0;
    self.last_visited_line_value = "";

    if self.tree_root != SENTINEL {
        node_pos = self.node_at(offset);
        nd = node_pos.nd;
        piece = nd.piece;
        buffer_index = piece.buffer_index;
        insert_pos_in_buffer = self.position_in_buffer(nd, node_pos.remainder);
        if (
            nd.piece.buffer_index == 0
            and piece.end.line == self.last_change_buffer_pos.line
            and piece.end.column == self.last_change_buffer_pos.column
            and (node_pos.node_start_offset + piece.length == offset)
            and len(value) < AVERAGE_BUFFER_SIZE
        ) {
            self.append_to_node(nd, value);
            self.compute_buffer_metadata();
            return;
        }

        if node_pos.node_start_offset == offset {
            self.insert_content_to_node_left(value, nd);
            self.search_cache.validate(offset);
        } elif node_pos.node_start_offset + nd.piece.length > offset {
            nodes_to_del: list[TreeNode] = [];
            new_right_piece = Piece(
                buffer_index=piece.buffer_index,
                start=insert_pos_in_buffer,
                end=piece.end,
                line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, insert_pos_in_buffer, piece.end),
                length=(
                    self.offset_in_buffer(buffer_index, piece.end)
                    - self.offset_in_buffer(buffer_index, insert_pos_in_buffer)
                )
            );

            if self.should_check_crlf() and self.end_with_cr_str(value) {
                head_of_right = self.node_char_code_at(nd, node_pos.remainder);

                if head_of_right == LINE_FEED {
                    new_start = BufferCursor(line=new_right_piece.start.line + 1, column=0);
                    new_right_piece = Piece(
                        buffer_index=new_right_piece.buffer_index,
                        start=new_start,
                        end=new_right_piece.end,
                        line_feed_cnt=self.get_line_feed_cnt(new_right_piece.buffer_index, new_start, new_right_piece.end),
                        length=new_right_piece.length - 1
                    );
                    value += "\n";
                }
            }

            if self.should_check_crlf() and self.start_with_lf_str(value) {
                tail_of_left = self.node_char_code_at(nd, node_pos.remainder - 1);
                if tail_of_left == CARRIAGE_RETURN {
                    previous_pos = self.position_in_buffer(nd, node_pos.remainder - 1);
                    self.delete_node_tail(nd, previous_pos);
                    value = "\r" + value;

                    if nd.piece.length == 0 {
                        nodes_to_del.append(nd);
                    }
                } else {
                    self.delete_node_tail(nd, insert_pos_in_buffer);
                }
            } else {
                self.delete_node_tail(nd, insert_pos_in_buffer);
            }

            new_pieces = self.create_new_pieces(value);
            if new_right_piece.length > 0 {
                self.rb_insert_right(nd, new_right_piece);
            }

            tmp_nd = nd;
            for new_piece in new_pieces {
                tmp_nd = self.rb_insert_right(tmp_nd, new_piece);
            }
            self.delete_nodes(nodes_to_del);
        } else {
            self.insert_content_to_node_right(value, nd);
        }
    } else {
        pieces = self.create_new_pieces(value);
        nd = self.rb_insert_left(SENTINEL, pieces[0]);

        k = 1;
        while k < len(pieces) {
            nd = self.rb_insert_right(nd, pieces[k]);
            k += 1;
        }
    }

    self.compute_buffer_metadata();
}

impl PieceTreeBase.delete(offset: int, cnt: int) -> None {
    self.last_visited_line_number = 0;
    self.last_visited_line_value = "";

    if cnt <= 0 or self.tree_root == SENTINEL {
        return;
    }

    start_position = self.node_at(offset);
    end_position = self.node_at(offset + cnt);
    start_nd = start_position.nd;
    end_nd = end_position.nd;

    if start_nd == end_nd {
        start_split_pos_in_buffer = self.position_in_buffer(start_nd, start_position.remainder);
        end_split_pos_in_buffer = self.position_in_buffer(start_nd, end_position.remainder);

        if start_position.node_start_offset == offset {
            if cnt == start_nd.piece.length {
                next_nd = start_nd.next();
                rb_delete(self, start_nd);
                self.validate_crlf_with_prev_node(next_nd);
                self.compute_buffer_metadata();
                return;
            }
            self.delete_node_head(start_nd, end_split_pos_in_buffer);
            self.search_cache.validate(offset);
            self.validate_crlf_with_prev_node(start_nd);
            self.compute_buffer_metadata();
            return;
        }

        if start_position.node_start_offset + start_nd.piece.length == offset + cnt {
            self.delete_node_tail(start_nd, start_split_pos_in_buffer);
            self.validate_crlf_with_next_node(start_nd);
            self.compute_buffer_metadata();
            return;
        }

        self.shrink_node(start_nd, start_split_pos_in_buffer, end_split_pos_in_buffer);
        self.compute_buffer_metadata();
        return;
    }

    nodes_to_del: list[TreeNode] = [];

    start_split_pos_in_buffer = self.position_in_buffer(start_nd, start_position.remainder);
    self.delete_node_tail(start_nd, start_split_pos_in_buffer);
    self.search_cache.validate(offset);
    if start_nd.piece.length == 0 {
        nodes_to_del.append(start_nd);
    }

    end_split_pos_in_buffer = self.position_in_buffer(end_nd, end_position.remainder);
    self.delete_node_head(end_nd, end_split_pos_in_buffer);
    if end_nd.piece.length == 0 {
        nodes_to_del.append(end_nd);
    }

    second_nd = start_nd.next();
    nd = second_nd;
    while nd != SENTINEL and nd != end_nd {
        nodes_to_del.append(nd);
        nd = nd.next();
    }

    prev = start_nd.prev() if start_nd.piece.length == 0 else start_nd;
    self.delete_nodes(nodes_to_del);
    self.validate_crlf_with_next_node(prev);
    self.compute_buffer_metadata();
}

impl PieceTreeBase.insert_content_to_node_left(value: str, nd: TreeNode) -> None {
    nodes_to_del: list[TreeNode] = [];
    if self.should_check_crlf() and self.end_with_cr_str(value) and self.start_with_lf_node(nd) {
        piece = nd.piece;
        new_start = BufferCursor(line=piece.start.line + 1, column=0);
        n_piece = Piece(
            buffer_index=piece.buffer_index,
            start=new_start,
            end=piece.end,
            line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end),
            length=piece.length - 1
        );

        nd.piece = n_piece;

        value += "\n";
        update_tree_metadata(self, nd, -1, -1);

        if nd.piece.length == 0 {
            nodes_to_del.append(nd);
        }
    }

    new_pieces = self.create_new_pieces(value);
    new_nd = self.rb_insert_left(nd, new_pieces[-1]);
    k = len(new_pieces) - 2;
    while k >= 0 {
        new_nd = self.rb_insert_left(new_nd, new_pieces[k]);
        k -= 1;
    }
    self.validate_crlf_with_prev_node(new_nd);
    self.delete_nodes(nodes_to_del);
}

impl PieceTreeBase.insert_content_to_node_right(value: str, nd: TreeNode) -> None {
    if self.adjust_carriage_return_from_next(value, nd) {
        value += "\n";
    }

    new_pieces = self.create_new_pieces(value);
    new_nd = self.rb_insert_right(nd, new_pieces[0]);
    tmp_nd = new_nd;

    k = 1;
    while k < len(new_pieces) {
        tmp_nd = self.rb_insert_right(tmp_nd, new_pieces[k]);
        k += 1;
    }

    self.validate_crlf_with_prev_node(new_nd);
}

impl PieceTreeBase.delete_nodes(nodes: list[TreeNode]) -> None {
    for nd in nodes {
        rb_delete(self, nd);
    }
}

impl PieceTreeBase.create_new_pieces(text: str) -> list[Piece] {
    if len(text) > AVERAGE_BUFFER_SIZE {
        new_pieces: list[Piece] = [];
        while len(text) > AVERAGE_BUFFER_SIZE {
            last_char = ord(text[AVERAGE_BUFFER_SIZE - 1]);
            if last_char == CARRIAGE_RETURN or (last_char >= 0xD800 and last_char <= 0xDBFF) {
                split_text = text[0:AVERAGE_BUFFER_SIZE - 1];
                text = text[AVERAGE_BUFFER_SIZE - 1:];
            } else {
                split_text = text[0:AVERAGE_BUFFER_SIZE];
                text = text[AVERAGE_BUFFER_SIZE:];
            }

            line_starts = create_line_starts(split_text);
            new_pieces.append(Piece(
                buffer_index=len(self.buffers),
                start=BufferCursor(line=0, column=0),
                end=BufferCursor(line=len(line_starts) - 1, column=len(split_text) - line_starts[-1]),
                line_feed_cnt=len(line_starts) - 1,
                length=len(split_text)
            ));
            self.buffers.append(StringBuffer(buffer=split_text, line_starts=line_starts));
        }

        line_starts = create_line_starts(text);
        new_pieces.append(Piece(
            buffer_index=len(self.buffers),
            start=BufferCursor(line=0, column=0),
            end=BufferCursor(line=len(line_starts) - 1, column=len(text) - line_starts[-1]),
            line_feed_cnt=len(line_starts) - 1,
            length=len(text)
        ));
        self.buffers.append(StringBuffer(buffer=text, line_starts=line_starts));

        return new_pieces;
    }

    start_offset = len(self.buffers[0].buffer);
    line_starts = create_line_starts(text);

    start = self.last_change_buffer_pos;
    if (
        self.buffers[0].line_starts[-1] == start_offset
        and start_offset != 0
        and self.start_with_lf_str(text)
        and self.end_with_cr_str(self.buffers[0].buffer)
    ) {
        self.last_change_buffer_pos = BufferCursor(
            line=self.last_change_buffer_pos.line, column=self.last_change_buffer_pos.column + 1
        );
        start = self.last_change_buffer_pos;

        i = 0;
        while i < len(line_starts) {
            line_starts[i] += start_offset + 1;
            i += 1;
        }

        self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
        self.buffers[0].buffer += "_" + text;
        start_offset += 1;
    } else {
        if start_offset != 0 {
            i = 0;
            while i < len(line_starts) {
                line_starts[i] += start_offset;
                i += 1;
            }
        }
        self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
        self.buffers[0].buffer += text;
    }

    end_offset = len(self.buffers[0].buffer);
    end_index = len(self.buffers[0].line_starts) - 1;
    end_column = end_offset - self.buffers[0].line_starts[end_index];
    end_pos = BufferCursor(line=end_index, column=end_column);
    new_piece = Piece(
        buffer_index=0,
        start=start,
        end=end_pos,
        line_feed_cnt=self.get_line_feed_cnt(0, start, end_pos),
        length=end_offset - start_offset
    );
    self.last_change_buffer_pos = end_pos;
    return [new_piece];
}

impl PieceTreeBase.delete_node_tail(nd: TreeNode, pos: BufferCursor) -> None {
    piece = nd.piece;
    original_lf_cnt = piece.line_feed_cnt;
    original_end_offset = self.offset_in_buffer(piece.buffer_index, piece.end);

    new_end = pos;
    new_end_offset = self.offset_in_buffer(piece.buffer_index, new_end);
    new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, piece.start, new_end);

    lf_delta = new_line_feed_cnt - original_lf_cnt;
    size_delta = new_end_offset - original_end_offset;
    new_length = piece.length + size_delta;

    nd.piece = Piece(
        buffer_index=piece.buffer_index, start=piece.start, end=new_end,
        line_feed_cnt=new_line_feed_cnt, length=new_length
    );

    update_tree_metadata(self, nd, size_delta, lf_delta);
}

impl PieceTreeBase.delete_node_head(nd: TreeNode, pos: BufferCursor) -> None {
    piece = nd.piece;
    original_lf_cnt = piece.line_feed_cnt;
    original_start_offset = self.offset_in_buffer(piece.buffer_index, piece.start);

    new_start = pos;
    new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end);
    new_start_offset = self.offset_in_buffer(piece.buffer_index, new_start);
    lf_delta = new_line_feed_cnt - original_lf_cnt;
    size_delta = original_start_offset - new_start_offset;
    new_length = piece.length + size_delta;
    nd.piece = Piece(
        buffer_index=piece.buffer_index, start=new_start, end=piece.end,
        line_feed_cnt=new_line_feed_cnt, length=new_length
    );

    update_tree_metadata(self, nd, size_delta, lf_delta);
}

impl PieceTreeBase.shrink_node(nd: TreeNode, start: BufferCursor, end: BufferCursor) -> None {
    piece = nd.piece;
    original_start_pos = piece.start;
    original_end_pos = piece.end;

    old_length = piece.length;
    old_lf_cnt = piece.line_feed_cnt;
    new_end = start;
    new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, piece.start, new_end);
    new_length = (
        self.offset_in_buffer(piece.buffer_index, start)
        - self.offset_in_buffer(piece.buffer_index, original_start_pos)
    );

    nd.piece = Piece(
        buffer_index=piece.buffer_index, start=piece.start, end=new_end,
        line_feed_cnt=new_line_feed_cnt, length=new_length
    );

    update_tree_metadata(self, nd, new_length - old_length, new_line_feed_cnt - old_lf_cnt);

    new_piece = Piece(
        buffer_index=piece.buffer_index, start=end, end=original_end_pos,
        line_feed_cnt=self.get_line_feed_cnt(piece.buffer_index, end, original_end_pos),
        length=(
            self.offset_in_buffer(piece.buffer_index, original_end_pos)
            - self.offset_in_buffer(piece.buffer_index, end)
        )
    );

    new_nd = self.rb_insert_right(nd, new_piece);
    self.validate_crlf_with_prev_node(new_nd);
}

impl PieceTreeBase.append_to_node(nd: TreeNode, value: str) -> None {
    if self.adjust_carriage_return_from_next(value, nd) {
        value += "\n";
    }

    hit_crlf = self.should_check_crlf() and self.start_with_lf_str(value) and self.end_with_cr_node(nd);
    start_offset = len(self.buffers[0].buffer);
    self.buffers[0].buffer += value;
    line_starts = create_line_starts(value);
    i = 0;
    while i < len(line_starts) {
        line_starts[i] += start_offset;
        i += 1;
    }
    if hit_crlf {
        prev_start_offset = self.buffers[0].line_starts[-2];
        self.buffers[0].line_starts.pop();
        self.last_change_buffer_pos = BufferCursor(
            line=self.last_change_buffer_pos.line - 1, column=start_offset - prev_start_offset
        );
    }

    self.buffers[0].line_starts = self.buffers[0].line_starts + line_starts[1:];
    end_index = len(self.buffers[0].line_starts) - 1;
    end_column = len(self.buffers[0].buffer) - self.buffers[0].line_starts[end_index];
    new_end = BufferCursor(line=end_index, column=end_column);
    new_length = nd.piece.length + len(value);
    old_line_feed_cnt = nd.piece.line_feed_cnt;
    new_line_feed_cnt = self.get_line_feed_cnt(0, nd.piece.start, new_end);
    lf_delta = new_line_feed_cnt - old_line_feed_cnt;

    nd.piece = Piece(
        buffer_index=nd.piece.buffer_index, start=nd.piece.start, end=new_end,
        line_feed_cnt=new_line_feed_cnt, length=new_length
    );

    self.last_change_buffer_pos = new_end;
    update_tree_metadata(self, nd, len(value), lf_delta);
}
