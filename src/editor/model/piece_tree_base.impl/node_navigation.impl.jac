impl PieceTreeBase.node_at(offset: int) -> NodePosition {
    x = self.tree_root;
    cache = self.search_cache.get(offset);
    if cache is not None {
        return NodePosition(
            nd=cache.nd, remainder=offset - cache.node_start_offset,
            node_start_offset=cache.node_start_offset
        );
    }

    node_start_offset = 0;

    while x != SENTINEL {
        if x.size_left > offset {
            x = x.left;
        } elif x.size_left + x.piece.length >= offset {
            node_start_offset += x.size_left;
            ret = NodePosition(nd=x, remainder=offset - x.size_left, node_start_offset=node_start_offset);
            self.search_cache.set(CacheEntry(nd=x, node_start_offset=node_start_offset, node_start_line_number=-1));
            return ret;
        } else {
            offset -= x.size_left + x.piece.length;
            node_start_offset += x.size_left + x.piece.length;
            x = x.right;
        }
    }

    raise ValueError("node_at: offset out of bounds -- unreachable for a valid offset");
}

impl PieceTreeBase.node_at2(line_number: int, column: int) -> NodePosition | None {
    x = self.tree_root;
    node_start_offset = 0;

    while x != SENTINEL {
        if x.left != SENTINEL and x.lf_left >= line_number - 1 {
            x = x.left;
        } elif x.lf_left + x.piece.line_feed_cnt > line_number - 1 {
            prev_accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
            accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 1);
            node_start_offset += x.size_left;

            return NodePosition(
                nd=x, remainder=min(prev_accumulated + column - 1, accumulated),
                node_start_offset=node_start_offset
            );
        } elif x.lf_left + x.piece.line_feed_cnt == line_number - 1 {
            prev_accumulated = self.get_accumulated_value(x, line_number - x.lf_left - 2);
            if prev_accumulated + column - 1 <= x.piece.length {
                return NodePosition(
                    nd=x, remainder=prev_accumulated + column - 1, node_start_offset=node_start_offset
                );
            } else {
                column -= x.piece.length - prev_accumulated;
                break;
            }
        } else {
            line_number -= x.lf_left + x.piece.line_feed_cnt;
            node_start_offset += x.size_left + x.piece.length;
            x = x.right;
        }
    }

    x = x.next();
    while x != SENTINEL {
        if x.piece.line_feed_cnt > 0 {
            accumulated = self.get_accumulated_value(x, 0);
            node_start_offset = self.offset_of_node(x);
            return NodePosition(
                nd=x, remainder=min(column - 1, accumulated), node_start_offset=node_start_offset
            );
        } else {
            if x.piece.length >= column - 1 {
                node_start_offset = self.offset_of_node(x);
                return NodePosition(nd=x, remainder=column - 1, node_start_offset=node_start_offset);
            } else {
                column -= x.piece.length;
            }
        }

        x = x.next();
    }

    return None;
}

impl PieceTreeBase.node_char_code_at(nd: TreeNode, offset: int) -> int {
    if nd.piece.line_feed_cnt < 1 {
        return -1;
    }
    buffer = self.buffers[nd.piece.buffer_index];
    new_offset = self.offset_in_buffer(nd.piece.buffer_index, nd.piece.start) + offset;
    return ord(buffer.buffer[new_offset]);
}

impl PieceTreeBase.offset_of_node(nd: TreeNode) -> int {
    pos = nd.size_left;
    while nd != self.tree_root {
        if nd.parent.right == nd {
            pos += nd.parent.size_left + nd.parent.piece.length;
        }
        nd = nd.parent;
    }
    return pos;
}

impl PieceTreeBase.rb_insert_right(nd: TreeNode, p: Piece) -> TreeNode {
    z = TreeNode(piece=p, color=NODE_COLOR_RED);
    z.left = SENTINEL;
    z.right = SENTINEL;
    z.parent = SENTINEL;
    z.size_left = 0;
    z.lf_left = 0;

    x = self.tree_root;
    if x == SENTINEL {
        self.tree_root = z;
        z.color = NODE_COLOR_BLACK;
    } elif nd.right == SENTINEL {
        nd.right = z;
        z.parent = nd;
    } else {
        next_nd = leftest(nd.right);
        next_nd.left = z;
        z.parent = next_nd;
    }

    fix_insert(self, z);
    return z;
}

impl PieceTreeBase.rb_insert_left(nd: TreeNode, p: Piece) -> TreeNode {
    z = TreeNode(piece=p, color=NODE_COLOR_RED);
    z.left = SENTINEL;
    z.right = SENTINEL;
    z.parent = SENTINEL;
    z.size_left = 0;
    z.lf_left = 0;

    if self.tree_root == SENTINEL {
        self.tree_root = z;
        z.color = NODE_COLOR_BLACK;
    } elif nd.left == SENTINEL {
        nd.left = z;
        z.parent = nd;
    } else {
        prev_nd = rightest(nd.left);
        prev_nd.right = z;
        z.parent = prev_nd;
    }

    fix_insert(self, z);
    return z;
}
