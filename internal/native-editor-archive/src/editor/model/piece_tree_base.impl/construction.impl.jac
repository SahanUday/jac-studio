impl TreeNode.postinit -> None {
    self.parent = self;
    self.left = self;
    self.right = self;
    self.size_left = 0;
    self.lf_left = 0;
}

impl TreeNode.next -> TreeNode {
    if self.right != SENTINEL {
        return leftest(self.right);
    }
    nd = self;
    while nd.parent != SENTINEL {
        if nd.parent.left == nd {
            break;
        }
        nd = nd.parent;
    }
    if nd.parent == SENTINEL {
        return SENTINEL;
    }
    return nd.parent;
}

impl TreeNode.prev -> TreeNode {
    if self.left != SENTINEL {
        return rightest(self.left);
    }
    nd = self;
    while nd.parent != SENTINEL {
        if nd.parent.right == nd {
            break;
        }
        nd = nd.parent;
    }
    if nd.parent == SENTINEL {
        return SENTINEL;
    }
    return nd.parent;
}

impl TreeNode.detach -> None {
    self.parent = self;
    self.left = self;
    self.right = self;
}

impl PieceTreeSearchCache.postinit -> None {
    self.cache = [];
}

impl PieceTreeSearchCache.get(offset: int) -> CacheEntry | None {
    i = len(self.cache) - 1;
    while i >= 0 {
        ent = self.cache[i];
        if (
            ent.node_start_offset <= offset
            and ent.node_start_offset + ent.nd.piece.length >= offset
        ) {
            return ent;
        }
        i -= 1;
    }
    return None;
}

impl PieceTreeSearchCache.get2(line_number: int) -> CacheEntry | None {
    i = len(self.cache) - 1;
    while i >= 0 {
        ent = self.cache[i];
        if (
            ent.node_start_line_number != -1
            and ent.node_start_line_number < line_number
            and ent.node_start_line_number + ent.nd.piece.line_feed_cnt >= line_number
        ) {
            return ent;
        }
        i -= 1;
    }
    return None;
}

impl PieceTreeSearchCache.set(ent: CacheEntry) -> None {
    if len(self.cache) >= self.limit {
        self.cache.pop(0);
    }
    self.cache.append(ent);
}

impl PieceTreeSearchCache.validate(offset: int) -> None {
    has_invalid = False;
    new_cache: list[CacheEntry] = [];
    for ent in self.cache {
        if ent.nd.parent == ent.nd or ent.node_start_offset >= offset {
            has_invalid = True;
            continue;
        }
        new_cache.append(ent);
    }
    if has_invalid {
        self.cache = new_cache;
    }
}

impl PieceTreeBase.postinit -> None {
    self.tree_root = SENTINEL;
    self.buffers = [];
    self.line_cnt = 1;
    self.length = 0;
    self.eol = "\n";
    self.eol_length = 1;
    self.eol_normalized = True;
    self.last_change_buffer_pos = BufferCursor(line=0, column=0);
    self.search_cache = PieceTreeSearchCache(limit=1);
    self.last_visited_line_number = 0;
    self.last_visited_line_value = "";
    self.create(self.init_chunks, self.init_eol, self.init_eol_normalized);
}

impl PieceTreeBase.create(chunks: list[StringBuffer], eol: str, eol_normalized: bool) -> None {
    self.buffers = [StringBuffer(buffer="", line_starts=[0])];
    self.last_change_buffer_pos = BufferCursor(line=0, column=0);
    self.tree_root = SENTINEL;
    self.line_cnt = 1;
    self.length = 0;
    self.eol = eol;
    self.eol_length = len(eol);
    self.eol_normalized = eol_normalized;

    last_nd: TreeNode = SENTINEL;
    for chunk in chunks {
        if len(chunk.buffer) > 0 {
            if len(chunk.line_starts) == 0 {
                chunk.line_starts = create_line_starts(chunk.buffer);
            }
            piece = Piece(
                buffer_index=len(self.buffers),
                start=BufferCursor(line=0, column=0),
                end=BufferCursor(
                    line=len(chunk.line_starts) - 1,
                    column=len(chunk.buffer) - chunk.line_starts[-1]
                ),
                line_feed_cnt=len(chunk.line_starts) - 1,
                length=len(chunk.buffer)
            );
            self.buffers.append(chunk);
            last_nd = self.rb_insert_right(last_nd, piece);
        }
    }

    self.search_cache = PieceTreeSearchCache(limit=1);
    self.last_visited_line_number = 0;
    self.last_visited_line_value = "";
    self.compute_buffer_metadata();
}

impl PieceTreeBase.normalize_eol(eol: str) -> None {
    min_size = AVERAGE_BUFFER_SIZE - (AVERAGE_BUFFER_SIZE // 3);
    max_size = min_size * 2;

    temp_chunk = "";
    temp_chunk_len = 0;
    chunks: list[StringBuffer] = [];

    for nd in collect_nodes_in_order(self.tree_root) {
        text = self.get_node_content(nd);
        text_len = len(text);
        if temp_chunk_len <= min_size or temp_chunk_len + text_len < max_size {
            temp_chunk += text;
            temp_chunk_len += text_len;
            continue;
        }

        normalized = re.sub(r"\r\n|\r|\n", eol, temp_chunk);
        chunks.append(StringBuffer(buffer=normalized, line_starts=create_line_starts(normalized)));
        temp_chunk = text;
        temp_chunk_len = text_len;
    }

    if temp_chunk_len > 0 {
        normalized = re.sub(r"\r\n|\r|\n", eol, temp_chunk);
        chunks.append(StringBuffer(buffer=normalized, line_starts=create_line_starts(normalized)));
    }

    self.create(chunks, eol, True);
}

impl PieceTreeBase.get_eol -> str {
    return self.eol;
}

impl PieceTreeBase.set_eol(new_eol: str) -> None {
    self.eol = new_eol;
    self.eol_length = len(new_eol);
    self.normalize_eol(new_eol);
}

impl PieceTreeBase.create_snapshot(bom: str) -> PieceTreeSnapshot {
    return PieceTreeSnapshot(tree=self, bom=bom);
}

impl PieceTreeBase.equal(other: PieceTreeBase) -> bool {
    if self.get_length() != other.get_length() {
        return False;
    }
    if self.get_line_count() != other.get_line_count() {
        return False;
    }

    offset = 0;
    for nd in collect_nodes_in_order(self.tree_root) {
        text = self.get_node_content(nd);
        text_len = len(text);
        start_position = other.node_at(offset);
        end_position = other.node_at(offset + text_len);
        val = other.get_value_in_range2(start_position, end_position);

        offset += text_len;
        if text != val {
            return False;
        }
    }
    return True;
}

impl PieceTreeBase.compute_buffer_metadata -> None {
    x = self.tree_root;

    lf_cnt = 1;
    length = 0;

    while x != SENTINEL {
        lf_cnt += x.lf_left + x.piece.line_feed_cnt;
        length += x.size_left + x.piece.length;
        x = x.right;
    }

    self.line_cnt = lf_cnt;
    self.length = length;
    self.search_cache.validate(self.length);
}

impl PieceTreeSnapshot.postinit -> None {
    self.pieces = [];
    self.index = 0;
    if self.tree.tree_root != SENTINEL {
        for nd in collect_nodes_in_order(self.tree.tree_root) {
            self.pieces.append(nd.piece);
        }
    }
}

impl PieceTreeSnapshot.read -> str | None {
    if len(self.pieces) == 0 {
        if self.index == 0 {
            self.index += 1;
            return self.bom;
        } else {
            return None;
        }
    }

    if self.index > len(self.pieces) - 1 {
        return None;
    }

    if self.index == 0 {
        piece = self.pieces[self.index];
        self.index += 1;
        return self.bom + self.tree.get_piece_content(piece);
    }
    piece = self.pieces[self.index];
    self.index += 1;
    return self.tree.get_piece_content(piece);
}
