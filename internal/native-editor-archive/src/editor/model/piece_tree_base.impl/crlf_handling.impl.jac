impl PieceTreeBase.should_check_crlf -> bool {
    return not (self.eol_normalized and self.eol == "\n");
}

impl PieceTreeBase.start_with_lf_str(val: str) -> bool {
    return len(val) > 0 and ord(val[0]) == LINE_FEED;
}

impl PieceTreeBase.start_with_lf_node(nd: TreeNode) -> bool {
    if nd == SENTINEL or nd.piece.line_feed_cnt == 0 {
        return False;
    }

    piece = nd.piece;
    line_starts = self.buffers[piece.buffer_index].line_starts;
    line = piece.start.line;
    start_offset = line_starts[line] + piece.start.column;
    if line == len(line_starts) - 1 {
        return False;
    }
    next_line_offset = line_starts[line + 1];
    if next_line_offset > start_offset + 1 {
        return False;
    }
    return ord(self.buffers[piece.buffer_index].buffer[start_offset]) == LINE_FEED;
}

impl PieceTreeBase.end_with_cr_str(val: str) -> bool {
    return len(val) > 0 and ord(val[-1]) == CARRIAGE_RETURN;
}

impl PieceTreeBase.end_with_cr_node(nd: TreeNode) -> bool {
    if nd == SENTINEL or nd.piece.line_feed_cnt == 0 {
        return False;
    }
    return self.node_char_code_at(nd, nd.piece.length - 1) == CARRIAGE_RETURN;
}

impl PieceTreeBase.validate_crlf_with_prev_node(next_nd: TreeNode) -> None {
    if self.should_check_crlf() and self.start_with_lf_node(next_nd) {
        nd = next_nd.prev();
        if self.end_with_cr_node(nd) {
            self.fix_crlf(nd, next_nd);
        }
    }
}

impl PieceTreeBase.validate_crlf_with_next_node(nd: TreeNode) -> None {
    if self.should_check_crlf() and self.end_with_cr_node(nd) {
        next_nd = nd.next();
        if self.start_with_lf_node(next_nd) {
            self.fix_crlf(nd, next_nd);
        }
    }
}

impl PieceTreeBase.fix_crlf(prev: TreeNode, next_nd: TreeNode) -> None {
    nodes_to_del: list[TreeNode] = [];
    line_starts = self.buffers[prev.piece.buffer_index].line_starts;
    if prev.piece.end.column == 0 {
        new_end = BufferCursor(
            line=prev.piece.end.line - 1,
            column=line_starts[prev.piece.end.line] - line_starts[prev.piece.end.line - 1] - 1
        );
    } else {
        new_end = BufferCursor(line=prev.piece.end.line, column=prev.piece.end.column - 1);
    }

    prev_new_length = prev.piece.length - 1;
    prev_new_lf_cnt = prev.piece.line_feed_cnt - 1;
    prev.piece = Piece(
        buffer_index=prev.piece.buffer_index, start=prev.piece.start, end=new_end,
        line_feed_cnt=prev_new_lf_cnt, length=prev_new_length
    );

    update_tree_metadata(self, prev, -1, -1);
    if prev.piece.length == 0 {
        nodes_to_del.append(prev);
    }

    new_start = BufferCursor(line=next_nd.piece.start.line + 1, column=0);
    new_length = next_nd.piece.length - 1;
    new_line_feed_cnt = self.get_line_feed_cnt(next_nd.piece.buffer_index, new_start, next_nd.piece.end);
    next_nd.piece = Piece(
        buffer_index=next_nd.piece.buffer_index, start=new_start, end=next_nd.piece.end,
        line_feed_cnt=new_line_feed_cnt, length=new_length
    );

    update_tree_metadata(self, next_nd, -1, -1);
    if next_nd.piece.length == 0 {
        nodes_to_del.append(next_nd);
    }

    pieces = self.create_new_pieces("\r\n");
    self.rb_insert_right(prev, pieces[0]);

    for del_nd in nodes_to_del {
        rb_delete(self, del_nd);
    }
}

impl PieceTreeBase.adjust_carriage_return_from_next(value: str, nd: TreeNode) -> bool {
    if self.should_check_crlf() and self.end_with_cr_str(value) {
        next_nd = nd.next();
        if self.start_with_lf_node(next_nd) {
            if next_nd.piece.length == 1 {
                rb_delete(self, next_nd);
            } else {
                piece = next_nd.piece;
                new_start = BufferCursor(line=piece.start.line + 1, column=0);
                new_length = piece.length - 1;
                new_line_feed_cnt = self.get_line_feed_cnt(piece.buffer_index, new_start, piece.end);
                next_nd.piece = Piece(
                    buffer_index=piece.buffer_index, start=new_start, end=piece.end,
                    line_feed_cnt=new_line_feed_cnt, length=new_length
                );

                update_tree_metadata(self, next_nd, -1, -1);
            }
            return True;
        }
    }

    return False;
}
