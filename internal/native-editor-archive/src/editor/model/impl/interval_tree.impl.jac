def _set_node_color(nd: IntervalNode, color: int) {
    nd.metadata = (nd.metadata & COLOR_MASK_INVERSE) | (color << COLOR_OFFSET);
}

def _get_node_is_visited(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_VISITED_MASK) >> IS_VISITED_OFFSET) == 1;
}

def _set_node_is_visited(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_VISITED_MASK_INVERSE) | ((1 if value else 0) << IS_VISITED_OFFSET)
    );
}

def _get_node_is_for_validation(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_FOR_VALIDATION_MASK) >> IS_FOR_VALIDATION_OFFSET) == 1;
}

def _set_node_is_for_validation(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_FOR_VALIDATION_MASK_INVERSE)
        | ((1 if value else 0) << IS_FOR_VALIDATION_OFFSET)
    );
}

def _get_node_is_in_glyph_margin(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_MARGIN_MASK) >> IS_MARGIN_OFFSET) == 1;
}

def _set_node_is_in_glyph_margin(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_MARGIN_MASK_INVERSE) | ((1 if value else 0) << IS_MARGIN_OFFSET)
    );
}

def _get_node_affects_font(nd: IntervalNode) -> bool {
    return ((nd.metadata & AFFECTS_FONT_MASK) >> AFFECTS_FONT_OFFSET) == 1;
}

def _set_node_affects_font(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & AFFECTS_FONT_MASK_INVERSE) | ((1 if value else 0) << AFFECTS_FONT_OFFSET)
    );
}

def _get_node_stickiness(nd: IntervalNode) -> int {
    return (nd.metadata & STICKINESS_MASK) >> STICKINESS_OFFSET;
}

def _set_node_stickiness_raw(nd: IntervalNode, stickiness: int) {
    nd.metadata = (
        (nd.metadata & STICKINESS_MASK_INVERSE) | (stickiness << STICKINESS_OFFSET)
    );
}

def _get_collapse_on_replace_edit(nd: IntervalNode) -> bool {
    return (
        (nd.metadata & COLLAPSE_ON_REPLACE_EDIT_MASK) >> COLLAPSE_ON_REPLACE_EDIT_OFFSET
    ) == 1;
}

def _set_collapse_on_replace_edit(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & COLLAPSE_ON_REPLACE_EDIT_MASK_INVERSE)
        | ((1 if value else 0) << COLLAPSE_ON_REPLACE_EDIT_OFFSET)
    );
}

impl IntervalNode.postinit -> None {
    self.metadata = 0;
    self.parent = self;
    self.left = self;
    self.right = self;
    _set_node_color(self, NODE_COLOR_RED);

    self.delta = 0;
    self.max_end = self.end;

    self.owner_id = 0;
    self.options = None;
    _set_node_is_for_validation(self, False);
    _set_node_is_in_glyph_margin(self, False);
    _set_node_stickiness_raw(self, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES);
    _set_collapse_on_replace_edit(self, False);
    _set_node_affects_font(self, False);

    self.cached_version_id = 0;
    self.cached_absolute_start = self.start;
    self.cached_absolute_end = self.end;
    self.range = None;

    _set_node_is_visited(self, False);
}

impl IntervalNode.reset(version_id: int, start: int, end: int, range: any) -> None {
    self.start = start;
    self.end = end;
    self.max_end = end;
    self.cached_version_id = version_id;
    self.cached_absolute_start = start;
    self.cached_absolute_end = end;
    self.range = range;
}

impl IntervalNode.set_cached_offsets(absolute_start: int, absolute_end: int, cached_version_id: int) -> None {
    if self.cached_version_id != cached_version_id {
        self.range = None;
    }
    self.cached_version_id = cached_version_id;
    self.cached_absolute_start = absolute_start;
    self.cached_absolute_end = absolute_end;
}

impl IntervalNode.detach -> None {
    self.parent = self;
    self.left = self;
    self.right = self;
}

impl IntervalTree.postinit -> None {
    self.tree_root = SENTINEL;
    self.request_normalize_delta = False;
}

impl IntervalTree.interval_search(
    start: int, end: int, filter_owner_id: int, filter_out_validation: bool,
    filter_font_decorations: bool, cached_version_id: int, only_margin_decorations: bool
) -> list[IntervalNode] {
    if self.tree_root == SENTINEL {
        return [];
    }
    return _interval_search_impl(
        self, start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
        cached_version_id, only_margin_decorations
    );
}

impl IntervalTree.search(
    filter_owner_id: int, filter_out_validation: bool, filter_font_decorations: bool,
    cached_version_id: int, only_margin_decorations: bool
) -> list[IntervalNode] {
    if self.tree_root == SENTINEL {
        return [];
    }
    return _search_impl(
        self, filter_owner_id, filter_out_validation, filter_font_decorations,
        cached_version_id, only_margin_decorations
    );
}

impl IntervalTree.collect_nodes_from_owner(owner_id: int) -> list[IntervalNode] {
    return _collect_nodes_from_owner_impl(self, owner_id);
}

impl IntervalTree.collect_nodes_post_order -> list[IntervalNode] {
    return _collect_nodes_post_order_impl(self);
}

impl IntervalTree.insert(nd: IntervalNode) -> None {
    _rb_tree_insert(self, nd);
    self._normalize_delta_if_necessary();
}

impl IntervalTree.delete(nd: IntervalNode) -> None {
    _rb_tree_delete(self, nd);
    self._normalize_delta_if_necessary();
}

impl IntervalTree.resolve_node(nd: IntervalNode, cached_version_id: int) -> None {
    initial_node = nd;
    delta = 0;
    while nd != self.tree_root {
        if nd == nd.parent.right {
            delta += nd.parent.delta;
        }
        nd = nd.parent;
    }

    node_start = initial_node.start + delta;
    node_end = initial_node.end + delta;
    initial_node.set_cached_offsets(node_start, node_end, cached_version_id);
}

impl IntervalTree.accept_replace(offset: int, length: int, text_length: int, force_move_markers: bool) -> None {
    nodes_of_interest = _search_for_editing(self, offset, offset + length);

    for nd in nodes_of_interest {
        _rb_tree_delete(self, nd);
    }
    self._normalize_delta_if_necessary();

    _no_overlap_replace(self, offset, offset + length, text_length);
    self._normalize_delta_if_necessary();

    for nd in nodes_of_interest {
        nd.start = nd.cached_absolute_start;
        nd.end = nd.cached_absolute_end;
        node_accept_edit(nd, offset, offset + length, text_length, force_move_markers);
        nd.max_end = nd.end;
        _rb_tree_insert(self, nd);
    }
    self._normalize_delta_if_necessary();
}

impl IntervalTree.get_all_in_order -> list[IntervalNode] {
    return _search_impl(self, 0, False, False, 0, False);
}

impl IntervalTree._normalize_delta_if_necessary -> None {
    if not self.request_normalize_delta {
        return;
    }
    self.request_normalize_delta = False;
    _normalize_delta(self);
}

def _normalize_delta(t: IntervalTree) {
    nd = t.tree_root;
    delta = 0;
    while nd != SENTINEL {
        if nd.left != SENTINEL and not _get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }

        nd.start = delta + nd.start;
        nd.end = delta + nd.end;
        nd.delta = 0;
        _recompute_max_end(nd);

        _set_node_is_visited(nd, True);

        _set_node_is_visited(nd.left, False);
        _set_node_is_visited(nd.right, False);
        if nd == nd.parent.right {
            delta -= nd.parent.delta;
        }
        nd = nd.parent;
    }

    _set_node_is_visited(t.tree_root, False);
}

def _adjust_marker_before_column(
    marker_offset: int, marker_stick_to_previous_character: bool, check_offset: int,
    move_semantics: int
) -> bool {
    if marker_offset < check_offset {
        return True;
    }
    if marker_offset > check_offset {
        return False;
    }
    if move_semantics == MARKER_MOVE_FORCE_MOVE {
        return False;
    }
    if move_semantics == MARKER_MOVE_FORCE_STAY {
        return True;
    }
    return marker_stick_to_previous_character;
}

def _search_for_editing(t: IntervalTree, start: int, end: int) -> list[IntervalNode] {
    nd = t.tree_root;
    delta = 0;
    node_max_end = 0;
    node_start = 0;
    node_end = 0;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if not _get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < start {
                _set_node_is_visited(nd, True);
                continue;
            }

            if nd.left != SENTINEL {
                nd = nd.left;
                continue;
            }
        }

        node_start = delta + nd.start;
        if node_start > end {
            _set_node_is_visited(nd, True);
            continue;
        }

        node_end = delta + nd.end;
        if node_end >= start {
            nd.set_cached_offsets(node_start, node_end, 0);
            result.append(nd);
        }
        _set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    _set_node_is_visited(t.tree_root, False);

    return result;
}

def _no_overlap_replace(t: IntervalTree, start: int, end: int, text_length: int) {
    nd = t.tree_root;
    delta = 0;
    node_max_end = 0;
    node_start = 0;
    edit_delta = text_length - (end - start);
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            _recompute_max_end(nd);
            nd = nd.parent;
            continue;
        }

        if not _get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < start {
                _set_node_is_visited(nd, True);
                continue;
            }

            if nd.left != SENTINEL {
                nd = nd.left;
                continue;
            }
        }

        node_start = delta + nd.start;
        if node_start > end {
            nd.start += edit_delta;
            nd.end += edit_delta;
            nd.delta += edit_delta;
            if nd.delta < MIN_SAFE_DELTA or nd.delta > MAX_SAFE_DELTA {
                t.request_normalize_delta = True;
            }
            _set_node_is_visited(nd, True);
            continue;
        }

        _set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    _set_node_is_visited(t.tree_root, False);
}

def _collect_nodes_from_owner_impl(t: IntervalTree, owner_id: int) -> list[IntervalNode] {
    nd = t.tree_root;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not _get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.owner_id == owner_id {
            result.append(nd);
        }

        _set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            nd = nd.right;
            continue;
        }
    }

    _set_node_is_visited(t.tree_root, False);

    return result;
}

def _collect_nodes_post_order_impl(t: IntervalTree) -> list[IntervalNode] {
    nd = t.tree_root;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not _get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            nd = nd.right;
            continue;
        }

        result.append(nd);
        _set_node_is_visited(nd, True);
    }

    _set_node_is_visited(t.tree_root, False);

    return result;
}

def _search_impl(
    t: IntervalTree, filter_owner_id: int, filter_out_validation: bool,
    filter_font_decorations: bool, cached_version_id: int, only_margin_decorations: bool
) -> list[IntervalNode] {
    nd = t.tree_root;
    delta = 0;
    node_start = 0;
    node_end = 0;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not _get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        node_start = delta + nd.start;
        node_end = delta + nd.end;

        nd.set_cached_offsets(node_start, node_end, cached_version_id);

        should_include = True;
        if filter_owner_id and nd.owner_id and nd.owner_id != filter_owner_id {
            should_include = False;
        }
        if filter_out_validation and _get_node_is_for_validation(nd) {
            should_include = False;
        }
        if filter_font_decorations and _get_node_affects_font(nd) {
            should_include = False;
        }
        if only_margin_decorations and not _get_node_is_in_glyph_margin(nd) {
            should_include = False;
        }

        if should_include {
            result.append(nd);
        }

        _set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    _set_node_is_visited(t.tree_root, False);

    return result;
}

def _interval_search_impl(
    t: IntervalTree, interval_start: int, interval_end: int, filter_owner_id: int,
    filter_out_validation: bool, filter_font_decorations: bool, cached_version_id: int,
    only_margin_decorations: bool
) -> list[IntervalNode] {
    nd = t.tree_root;
    delta = 0;
    node_max_end = 0;
    node_start = 0;
    node_end = 0;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if _get_node_is_visited(nd) {
            _set_node_is_visited(nd.left, False);
            _set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if not _get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < interval_start {
                _set_node_is_visited(nd, True);
                continue;
            }

            if nd.left != SENTINEL {
                nd = nd.left;
                continue;
            }
        }

        node_start = delta + nd.start;
        if node_start > interval_end {
            _set_node_is_visited(nd, True);
            continue;
        }

        node_end = delta + nd.end;

        if node_end >= interval_start {
            nd.set_cached_offsets(node_start, node_end, cached_version_id);

            should_include = True;
            if filter_owner_id and nd.owner_id and nd.owner_id != filter_owner_id {
                should_include = False;
            }
            if filter_out_validation and _get_node_is_for_validation(nd) {
                should_include = False;
            }
            if filter_font_decorations and _get_node_affects_font(nd) {
                should_include = False;
            }
            if only_margin_decorations and not _get_node_is_in_glyph_margin(nd) {
                should_include = False;
            }

            if should_include {
                result.append(nd);
            }
        }

        _set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not _get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    _set_node_is_visited(t.tree_root, False);

    return result;
}

def _rb_tree_insert(t: IntervalTree, new_node: IntervalNode) -> IntervalNode {
    if t.tree_root == SENTINEL {
        new_node.parent = SENTINEL;
        new_node.left = SENTINEL;
        new_node.right = SENTINEL;
        _set_node_color(new_node, NODE_COLOR_BLACK);
        t.tree_root = new_node;
        return t.tree_root;
    }

    _tree_insert(t, new_node);

    _recompute_max_end_walk_to_root(new_node.parent);

    x = new_node;
    while x != t.tree_root and get_node_color(x.parent) == NODE_COLOR_RED {
        if x.parent == x.parent.parent.left {
            y = x.parent.parent.right;

            if get_node_color(y) == NODE_COLOR_RED {
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(y, NODE_COLOR_BLACK);
                _set_node_color(x.parent.parent, NODE_COLOR_RED);
                x = x.parent.parent;
            } else {
                if x == x.parent.right {
                    x = x.parent;
                    _left_rotate(t, x);
                }
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(x.parent.parent, NODE_COLOR_RED);
                _right_rotate(t, x.parent.parent);
            }
        } else {
            y = x.parent.parent.left;

            if get_node_color(y) == NODE_COLOR_RED {
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(y, NODE_COLOR_BLACK);
                _set_node_color(x.parent.parent, NODE_COLOR_RED);
                x = x.parent.parent;
            } else {
                if x == x.parent.left {
                    x = x.parent;
                    _right_rotate(t, x);
                }
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(x.parent.parent, NODE_COLOR_RED);
                _left_rotate(t, x.parent.parent);
            }
        }
    }

    _set_node_color(t.tree_root, NODE_COLOR_BLACK);

    return new_node;
}

def _tree_insert(t: IntervalTree, z: IntervalNode) {
    delta = 0;
    x = t.tree_root;
    z_absolute_start = z.start;
    z_absolute_end = z.end;
    while True {
        cmp = interval_compare(z_absolute_start, z_absolute_end, x.start + delta, x.end + delta);
        if cmp < 0 {
            if x.left == SENTINEL {
                z.start -= delta;
                z.end -= delta;
                z.max_end -= delta;
                x.left = z;
                break;
            } else {
                x = x.left;
            }
        } else {
            if x.right == SENTINEL {
                z.start -= (delta + x.delta);
                z.end -= (delta + x.delta);
                z.max_end -= (delta + x.delta);
                x.right = z;
                break;
            } else {
                delta += x.delta;
                x = x.right;
            }
        }
    }

    z.parent = x;
    z.left = SENTINEL;
    z.right = SENTINEL;
    _set_node_color(z, NODE_COLOR_RED);
}

def _rb_tree_delete(t: IntervalTree, z: IntervalNode) {
    x: IntervalNode = SENTINEL;
    y: IntervalNode = SENTINEL;

    if z.left == SENTINEL {
        x = z.right;
        y = z;

        x.delta += z.delta;
        if x.delta < MIN_SAFE_DELTA or x.delta > MAX_SAFE_DELTA {
            t.request_normalize_delta = True;
        }
        x.start += z.delta;
        x.end += z.delta;

    } elif z.right == SENTINEL {
        x = z.left;
        y = z;

    } else {
        y = _leftest(z.right);
        x = y.right;

        x.start += y.delta;
        x.end += y.delta;
        x.delta += y.delta;
        if x.delta < MIN_SAFE_DELTA or x.delta > MAX_SAFE_DELTA {
            t.request_normalize_delta = True;
        }

        y.start += z.delta;
        y.end += z.delta;
        y.delta = z.delta;
        if y.delta < MIN_SAFE_DELTA or y.delta > MAX_SAFE_DELTA {
            t.request_normalize_delta = True;
        }
    }

    if y == t.tree_root {
        t.tree_root = x;
        _set_node_color(x, NODE_COLOR_BLACK);

        z.detach();
        _reset_sentinel();
        _recompute_max_end(x);
        t.tree_root.parent = SENTINEL;
        return;
    }

    y_was_red = get_node_color(y) == NODE_COLOR_RED;

    if y == y.parent.left {
        y.parent.left = x;
    } else {
        y.parent.right = x;
    }

    if y == z {
        x.parent = y.parent;
    } else {
        if y.parent == z {
            x.parent = y;
        } else {
            x.parent = y.parent;
        }

        y.left = z.left;
        y.right = z.right;
        y.parent = z.parent;
        _set_node_color(y, get_node_color(z));

        if z == t.tree_root {
            t.tree_root = y;
        } else {
            if z == z.parent.left {
                z.parent.left = y;
            } else {
                z.parent.right = y;
            }
        }

        if y.left != SENTINEL {
            y.left.parent = y;
        }
        if y.right != SENTINEL {
            y.right.parent = y;
        }
    }

    z.detach();

    if y_was_red {
        _recompute_max_end_walk_to_root(x.parent);
        if y != z {
            _recompute_max_end_walk_to_root(y);
            _recompute_max_end_walk_to_root(y.parent);
        }
        _reset_sentinel();
        return;
    }

    _recompute_max_end_walk_to_root(x);
    _recompute_max_end_walk_to_root(x.parent);
    if y != z {
        _recompute_max_end_walk_to_root(y);
        _recompute_max_end_walk_to_root(y.parent);
    }

    w: IntervalNode = SENTINEL;
    while x != t.tree_root and get_node_color(x) == NODE_COLOR_BLACK {
        if x == x.parent.left {
            w = x.parent.right;

            if get_node_color(w) == NODE_COLOR_RED {
                _set_node_color(w, NODE_COLOR_BLACK);
                _set_node_color(x.parent, NODE_COLOR_RED);
                _left_rotate(t, x.parent);
                w = x.parent.right;
            }

            if get_node_color(w.left) == NODE_COLOR_BLACK and get_node_color(w.right) == NODE_COLOR_BLACK {
                _set_node_color(w, NODE_COLOR_RED);
                x = x.parent;
            } else {
                if get_node_color(w.right) == NODE_COLOR_BLACK {
                    _set_node_color(w.left, NODE_COLOR_BLACK);
                    _set_node_color(w, NODE_COLOR_RED);
                    _right_rotate(t, w);
                    w = x.parent.right;
                }

                _set_node_color(w, get_node_color(x.parent));
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(w.right, NODE_COLOR_BLACK);
                _left_rotate(t, x.parent);
                x = t.tree_root;
            }
        } else {
            w = x.parent.left;

            if get_node_color(w) == NODE_COLOR_RED {
                _set_node_color(w, NODE_COLOR_BLACK);
                _set_node_color(x.parent, NODE_COLOR_RED);
                _right_rotate(t, x.parent);
                w = x.parent.left;
            }

            if get_node_color(w.left) == NODE_COLOR_BLACK and get_node_color(w.right) == NODE_COLOR_BLACK {
                _set_node_color(w, NODE_COLOR_RED);
                x = x.parent;
            } else {
                if get_node_color(w.left) == NODE_COLOR_BLACK {
                    _set_node_color(w.right, NODE_COLOR_BLACK);
                    _set_node_color(w, NODE_COLOR_RED);
                    _left_rotate(t, w);
                    w = x.parent.left;
                }

                _set_node_color(w, get_node_color(x.parent));
                _set_node_color(x.parent, NODE_COLOR_BLACK);
                _set_node_color(w.left, NODE_COLOR_BLACK);
                _right_rotate(t, x.parent);
                x = t.tree_root;
            }
        }
    }

    _set_node_color(x, NODE_COLOR_BLACK);
    _reset_sentinel();
}

def _leftest(nd: IntervalNode) -> IntervalNode {
    while nd.left != SENTINEL {
        nd = nd.left;
    }
    return nd;
}

def _reset_sentinel {
    SENTINEL.parent = SENTINEL;
    SENTINEL.delta = 0;
    SENTINEL.start = 0;
    SENTINEL.end = 0;
}

def _left_rotate(t: IntervalTree, x: IntervalNode) {
    y = x.right;

    y.delta += x.delta;
    if y.delta < MIN_SAFE_DELTA or y.delta > MAX_SAFE_DELTA {
        t.request_normalize_delta = True;
    }
    y.start += x.delta;
    y.end += x.delta;

    x.right = y.left;
    if y.left != SENTINEL {
        y.left.parent = x;
    }
    y.parent = x.parent;
    if x.parent == SENTINEL {
        t.tree_root = y;
    } elif x == x.parent.left {
        x.parent.left = y;
    } else {
        x.parent.right = y;
    }

    y.left = x;
    x.parent = y;

    _recompute_max_end(x);
    _recompute_max_end(y);
}

def _right_rotate(t: IntervalTree, y: IntervalNode) {
    x = y.left;

    y.delta -= x.delta;
    if y.delta < MIN_SAFE_DELTA or y.delta > MAX_SAFE_DELTA {
        t.request_normalize_delta = True;
    }
    y.start -= x.delta;
    y.end -= x.delta;

    y.left = x.right;
    if x.right != SENTINEL {
        x.right.parent = y;
    }
    x.parent = y.parent;
    if y.parent == SENTINEL {
        t.tree_root = x;
    } elif y == y.parent.right {
        y.parent.right = x;
    } else {
        y.parent.left = x;
    }

    x.right = y;
    y.parent = x;

    _recompute_max_end(y);
    _recompute_max_end(x);
}

def _compute_max_end(nd: IntervalNode) -> int {
    max_end = nd.end;
    if nd.left != SENTINEL {
        left_max_end = nd.left.max_end;
        if left_max_end > max_end {
            max_end = left_max_end;
        }
    }
    if nd.right != SENTINEL {
        right_max_end = nd.right.max_end + nd.delta;
        if right_max_end > max_end {
            max_end = right_max_end;
        }
    }
    return max_end;
}

def _recompute_max_end(nd: IntervalNode) {
    nd.max_end = _compute_max_end(nd);
}

def _recompute_max_end_walk_to_root(nd: IntervalNode) {
    while nd != SENTINEL {
        max_end = _compute_max_end(nd);

        if nd.max_end == max_end {
            return;
        }

        nd.max_end = max_end;
        nd = nd.parent;
    }
}
