"""Augmented interval tree: a red-black tree with lazy delta offsets and maxEnd augmentation,
ported from VS Code's intervalTree.ts (src/vs/editor/common/model/intervalTree.ts). Backs
decoration lookup in the real editor -- the red-black tree is based on "Introduction to
Algorithms" by Cormen, Leiserson and Rivest, same as upstream's own comment says.

Scope note: `options` and `range` are typed as untyped placeholders (`any | None`) here --
`ModelDecorationOptions` (textModel.ts) and `Range` (core/range.ts) are both real, substantial
classes that haven't been translated yet, and the ported upstream test suite
(intervalTree.test.ts) never constructs or reads either field -- every test drives the tree
purely through start/end/id/owner_id and the bit-packed metadata flags. `set_options()` itself
(the only method that actually touches `options`'s shape, and the only piece of upstream's
public API deliberately not ported here) is therefore deferred rather than guessed at -- port it
for real once `ModelDecorationOptions` exists and something can verify it against real behavior.
`ClassName` (decoration CSS class names, only used inside `setOptions`) is skipped for the same
reason.

Idiom notes: `NodeColor`/`TrackedRangeStickiness` are plain int constants, not a Jac `enum` --
upstream's `const enum` is just numbers under the hood (values inlined at compile time), and
keeping them as ints here avoids any enum/int comparison ambiguity in the bit-packing code below,
which is inherently integer arithmetic. TS's `>>>` (unsigned right shift) is translated to plain
`>>`: every value shifted here is a small non-negative packed byte, so the two operators agree.
`SENTINEL` is a genuinely shared, mutable module-level singleton exactly as upstream has it (not
a redesign) -- identity comparison (`nd == SENTINEL`) works correctly in Jac for this precise
reason: `==` on a plain `obj` is identity comparison here (see
2026-08-23-obj-equality-not-structural), which is exactly the semantics a red-black tree's "is
this the sentinel" checks need -- one of the rare cases where that behavior is the right tool,
not a workaround.
"""

glob NODE_COLOR_BLACK: int = 0;
glob NODE_COLOR_RED: int = 1;

glob TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES: int = 0;
glob TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES: int = 1;
glob TRS_GROWS_ONLY_WHEN_TYPING_BEFORE: int = 2;
glob TRS_GROWS_ONLY_WHEN_TYPING_AFTER: int = 3;

glob COLOR_MASK: int = 0b00000001;
glob COLOR_MASK_INVERSE: int = 0b11111110;
glob COLOR_OFFSET: int = 0;

glob IS_VISITED_MASK: int = 0b00000010;
glob IS_VISITED_MASK_INVERSE: int = 0b11111101;
glob IS_VISITED_OFFSET: int = 1;

glob IS_FOR_VALIDATION_MASK: int = 0b00000100;
glob IS_FOR_VALIDATION_MASK_INVERSE: int = 0b11111011;
glob IS_FOR_VALIDATION_OFFSET: int = 2;

glob STICKINESS_MASK: int = 0b00011000;
glob STICKINESS_MASK_INVERSE: int = 0b11100111;
glob STICKINESS_OFFSET: int = 3;

glob COLLAPSE_ON_REPLACE_EDIT_MASK: int = 0b00100000;
glob COLLAPSE_ON_REPLACE_EDIT_MASK_INVERSE: int = 0b11011111;
glob COLLAPSE_ON_REPLACE_EDIT_OFFSET: int = 5;

glob IS_MARGIN_MASK: int = 0b01000000;
glob IS_MARGIN_MASK_INVERSE: int = 0b10111111;
glob IS_MARGIN_OFFSET: int = 6;

glob AFFECTS_FONT_MASK: int = 0b10000000;
glob AFFECTS_FONT_MASK_INVERSE: int = 0b01111111;
glob AFFECTS_FONT_OFFSET: int = 7;

glob MIN_SAFE_DELTA: int = -(1 << 30);
glob MAX_SAFE_DELTA: int = 1 << 30;

def get_node_color(nd: IntervalNode) -> int {
    return (nd.metadata & COLOR_MASK) >> COLOR_OFFSET;
}

def set_node_color(nd: IntervalNode, color: int) {
    nd.metadata = (nd.metadata & COLOR_MASK_INVERSE) | (color << COLOR_OFFSET);
}

def get_node_is_visited(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_VISITED_MASK) >> IS_VISITED_OFFSET) == 1;
}

def set_node_is_visited(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_VISITED_MASK_INVERSE) | ((1 if value else 0) << IS_VISITED_OFFSET)
    );
}

def get_node_is_for_validation(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_FOR_VALIDATION_MASK) >> IS_FOR_VALIDATION_OFFSET) == 1;
}

def set_node_is_for_validation(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_FOR_VALIDATION_MASK_INVERSE)
        | ((1 if value else 0) << IS_FOR_VALIDATION_OFFSET)
    );
}

def get_node_is_in_glyph_margin(nd: IntervalNode) -> bool {
    return ((nd.metadata & IS_MARGIN_MASK) >> IS_MARGIN_OFFSET) == 1;
}

def set_node_is_in_glyph_margin(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & IS_MARGIN_MASK_INVERSE) | ((1 if value else 0) << IS_MARGIN_OFFSET)
    );
}

def get_node_affects_font(nd: IntervalNode) -> bool {
    return ((nd.metadata & AFFECTS_FONT_MASK) >> AFFECTS_FONT_OFFSET) == 1;
}

def set_node_affects_font(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & AFFECTS_FONT_MASK_INVERSE) | ((1 if value else 0) << AFFECTS_FONT_OFFSET)
    );
}

def get_node_stickiness(nd: IntervalNode) -> int {
    return (nd.metadata & STICKINESS_MASK) >> STICKINESS_OFFSET;
}

def _set_node_stickiness_raw(nd: IntervalNode, stickiness: int) {
    nd.metadata = (
        (nd.metadata & STICKINESS_MASK_INVERSE) | (stickiness << STICKINESS_OFFSET)
    );
}

def get_collapse_on_replace_edit(nd: IntervalNode) -> bool {
    return (
        (nd.metadata & COLLAPSE_ON_REPLACE_EDIT_MASK) >> COLLAPSE_ON_REPLACE_EDIT_OFFSET
    ) == 1;
}

def set_collapse_on_replace_edit(nd: IntervalNode, value: bool) {
    nd.metadata = (
        (nd.metadata & COLLAPSE_ON_REPLACE_EDIT_MASK_INVERSE)
        | ((1 if value else 0) << COLLAPSE_ON_REPLACE_EDIT_OFFSET)
    );
}

def set_node_stickiness(nd: IntervalNode, stickiness: int) {
    _set_node_stickiness_raw(nd, stickiness);
}

obj IntervalNode {
    has id: str, start: int, end: int;
    has metadata: int postinit;
    has parent: IntervalNode postinit;
    has left: IntervalNode postinit;
    has right: IntervalNode postinit;
    has delta: int postinit;
    has max_end: int postinit;
    has owner_id: int postinit;
    has options: any postinit;
    has cached_version_id: int postinit;
    has cached_absolute_start: int postinit;
    has cached_absolute_end: int postinit;
    has range: any postinit;

    def postinit {
        self.metadata = 0;
        self.parent = self;
        self.left = self;
        self.right = self;
        set_node_color(self, NODE_COLOR_RED);

        self.delta = 0;
        self.max_end = self.end;

        self.owner_id = 0;
        self.options = None;
        set_node_is_for_validation(self, False);
        set_node_is_in_glyph_margin(self, False);
        _set_node_stickiness_raw(self, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES);
        set_collapse_on_replace_edit(self, False);
        set_node_affects_font(self, False);

        self.cached_version_id = 0;
        self.cached_absolute_start = self.start;
        self.cached_absolute_end = self.end;
        self.range = None;

        set_node_is_visited(self, False);
    }

    def reset(version_id: int, start: int, end: int, range: any) {
        self.start = start;
        self.end = end;
        self.max_end = end;
        self.cached_version_id = version_id;
        self.cached_absolute_start = start;
        self.cached_absolute_end = end;
        self.range = range;
    }

    def set_cached_offsets(absolute_start: int, absolute_end: int, cached_version_id: int) {
        if self.cached_version_id != cached_version_id {
            self.range = None;
        }
        self.cached_version_id = cached_version_id;
        self.cached_absolute_start = absolute_start;
        self.cached_absolute_end = absolute_end;
    }

    def detach {
        self.parent = self;
        self.left = self;
        self.right = self;
    }
}

glob SENTINEL: IntervalNode = IntervalNode(id="", start=0, end=0);

with entry {
    SENTINEL.parent = SENTINEL;
    SENTINEL.left = SENTINEL;
    SENTINEL.right = SENTINEL;
    set_node_color(SENTINEL, NODE_COLOR_BLACK);
}

obj IntervalTree {
    has tree_root: IntervalNode postinit;
    has request_normalize_delta: bool postinit;

    def postinit {
        self.tree_root = SENTINEL;
        self.request_normalize_delta = False;
    }

    def interval_search(
        start: int, end: int, filter_owner_id: int, filter_out_validation: bool,
        filter_font_decorations: bool, cached_version_id: int, only_margin_decorations: bool
    ) -> list[IntervalNode] {
        if self.tree_root == SENTINEL {
            return [];
        }
        return interval_search_impl(
            self, start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
            cached_version_id, only_margin_decorations
        );
    }

    def search(
        filter_owner_id: int, filter_out_validation: bool, filter_font_decorations: bool,
        cached_version_id: int, only_margin_decorations: bool
    ) -> list[IntervalNode] {
        if self.tree_root == SENTINEL {
            return [];
        }
        return search_impl(
            self, filter_owner_id, filter_out_validation, filter_font_decorations,
            cached_version_id, only_margin_decorations
        );
    }

    def collect_nodes_from_owner(owner_id: int) -> list[IntervalNode] {
        return collect_nodes_from_owner_impl(self, owner_id);
    }

    def collect_nodes_post_order -> list[IntervalNode] {
        return collect_nodes_post_order_impl(self);
    }

    def insert(nd: IntervalNode) {
        rb_tree_insert(self, nd);
        self._normalize_delta_if_necessary();
    }

    def delete(nd: IntervalNode) {
        rb_tree_delete(self, nd);
        self._normalize_delta_if_necessary();
    }

    def resolve_node(nd: IntervalNode, cached_version_id: int) {
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

    def accept_replace(offset: int, length: int, text_length: int, force_move_markers: bool) {
        nodes_of_interest = search_for_editing(self, offset, offset + length);

        for nd in nodes_of_interest {
            rb_tree_delete(self, nd);
        }
        self._normalize_delta_if_necessary();

        no_overlap_replace(self, offset, offset + length, text_length);
        self._normalize_delta_if_necessary();

        for nd in nodes_of_interest {
            nd.start = nd.cached_absolute_start;
            nd.end = nd.cached_absolute_end;
            node_accept_edit(nd, offset, offset + length, text_length, force_move_markers);
            nd.max_end = nd.end;
            rb_tree_insert(self, nd);
        }
        self._normalize_delta_if_necessary();
    }

    def get_all_in_order -> list[IntervalNode] {
        return search_impl(self, 0, False, False, 0, False);
    }

    def _normalize_delta_if_necessary {
        if not self.request_normalize_delta {
            return;
        }
        self.request_normalize_delta = False;
        normalize_delta(self);
    }
}

def normalize_delta(t: IntervalTree) {
    nd = t.tree_root;
    delta = 0;
    while nd != SENTINEL {
        if nd.left != SENTINEL and not get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }

        nd.start = delta + nd.start;
        nd.end = delta + nd.end;
        nd.delta = 0;
        recompute_max_end(nd);

        set_node_is_visited(nd, True);

        set_node_is_visited(nd.left, False);
        set_node_is_visited(nd.right, False);
        if nd == nd.parent.right {
            delta -= nd.parent.delta;
        }
        nd = nd.parent;
    }

    set_node_is_visited(t.tree_root, False);
}

glob MARKER_MOVE_DEFINED: int = 0;
glob MARKER_MOVE_FORCE_MOVE: int = 1;
glob MARKER_MOVE_FORCE_STAY: int = 2;

def adjust_marker_before_column(
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

def node_accept_edit(nd: IntervalNode, start: int, end: int, text_length: int, force_move_markers: bool) {
    node_stickiness = get_node_stickiness(nd);
    start_stick_to_previous_character = (
        node_stickiness == TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES
        or node_stickiness == TRS_GROWS_ONLY_WHEN_TYPING_BEFORE
    );
    end_stick_to_previous_character = (
        node_stickiness == TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES
        or node_stickiness == TRS_GROWS_ONLY_WHEN_TYPING_BEFORE
    );

    deleting_cnt = end - start;
    inserting_cnt = text_length;
    common_length = min(deleting_cnt, inserting_cnt);

    node_start = nd.start;
    start_done = False;

    node_end = nd.end;
    end_done = False;

    if start <= node_start and node_end <= end and get_collapse_on_replace_edit(nd) {
        nd.start = start;
        start_done = True;
        nd.end = start;
        end_done = True;
    }

    move_semantics = (
        MARKER_MOVE_FORCE_MOVE if force_move_markers
        else (MARKER_MOVE_FORCE_STAY if deleting_cnt > 0 else MARKER_MOVE_DEFINED)
    );
    if not start_done and adjust_marker_before_column(
        node_start, start_stick_to_previous_character, start, move_semantics
    ) {
        start_done = True;
    }
    if not end_done and adjust_marker_before_column(
        node_end, end_stick_to_previous_character, start, move_semantics
    ) {
        end_done = True;
    }

    if common_length > 0 and not force_move_markers {
        move_semantics = (
            MARKER_MOVE_FORCE_STAY if deleting_cnt > inserting_cnt else MARKER_MOVE_DEFINED
        );
        if not start_done and adjust_marker_before_column(
            node_start, start_stick_to_previous_character, start + common_length, move_semantics
        ) {
            start_done = True;
        }
        if not end_done and adjust_marker_before_column(
            node_end, end_stick_to_previous_character, start + common_length, move_semantics
        ) {
            end_done = True;
        }
    }

    move_semantics = MARKER_MOVE_FORCE_MOVE if force_move_markers else MARKER_MOVE_DEFINED;
    if not start_done and adjust_marker_before_column(
        node_start, start_stick_to_previous_character, end, move_semantics
    ) {
        nd.start = start + inserting_cnt;
        start_done = True;
    }
    if not end_done and adjust_marker_before_column(
        node_end, end_stick_to_previous_character, end, move_semantics
    ) {
        nd.end = start + inserting_cnt;
        end_done = True;
    }

    delta_column = inserting_cnt - deleting_cnt;
    if not start_done {
        nd.start = max(0, node_start + delta_column);
    }
    if not end_done {
        nd.end = max(0, node_end + delta_column);
    }

    if nd.start > nd.end {
        nd.end = nd.start;
    }
}

def search_for_editing(t: IntervalTree, start: int, end: int) -> list[IntervalNode] {
    nd = t.tree_root;
    delta = 0;
    node_max_end = 0;
    node_start = 0;
    node_end = 0;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if not get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < start {
                set_node_is_visited(nd, True);
                continue;
            }

            if nd.left != SENTINEL {
                nd = nd.left;
                continue;
            }
        }

        node_start = delta + nd.start;
        if node_start > end {
            set_node_is_visited(nd, True);
            continue;
        }

        node_end = delta + nd.end;
        if node_end >= start {
            nd.set_cached_offsets(node_start, node_end, 0);
            result.append(nd);
        }
        set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    set_node_is_visited(t.tree_root, False);

    return result;
}

def no_overlap_replace(t: IntervalTree, start: int, end: int, text_length: int) {
    nd = t.tree_root;
    delta = 0;
    node_max_end = 0;
    node_start = 0;
    edit_delta = text_length - (end - start);
    while nd != SENTINEL {
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            recompute_max_end(nd);
            nd = nd.parent;
            continue;
        }

        if not get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < start {
                set_node_is_visited(nd, True);
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
            set_node_is_visited(nd, True);
            continue;
        }

        set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    set_node_is_visited(t.tree_root, False);
}

def collect_nodes_from_owner_impl(t: IntervalTree, owner_id: int) -> list[IntervalNode] {
    nd = t.tree_root;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.owner_id == owner_id {
            result.append(nd);
        }

        set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            nd = nd.right;
            continue;
        }
    }

    set_node_is_visited(t.tree_root, False);

    return result;
}

def collect_nodes_post_order_impl(t: IntervalTree) -> list[IntervalNode] {
    nd = t.tree_root;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not get_node_is_visited(nd.left) {
            nd = nd.left;
            continue;
        }

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            nd = nd.right;
            continue;
        }

        result.append(nd);
        set_node_is_visited(nd, True);
    }

    set_node_is_visited(t.tree_root, False);

    return result;
}

def search_impl(
    t: IntervalTree, filter_owner_id: int, filter_out_validation: bool,
    filter_font_decorations: bool, cached_version_id: int, only_margin_decorations: bool
) -> list[IntervalNode] {
    nd = t.tree_root;
    delta = 0;
    node_start = 0;
    node_end = 0;
    result: list[IntervalNode] = [];
    while nd != SENTINEL {
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if nd.left != SENTINEL and not get_node_is_visited(nd.left) {
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
        if filter_out_validation and get_node_is_for_validation(nd) {
            should_include = False;
        }
        if filter_font_decorations and get_node_affects_font(nd) {
            should_include = False;
        }
        if only_margin_decorations and not get_node_is_in_glyph_margin(nd) {
            should_include = False;
        }

        if should_include {
            result.append(nd);
        }

        set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    set_node_is_visited(t.tree_root, False);

    return result;
}

def interval_search_impl(
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
        if get_node_is_visited(nd) {
            set_node_is_visited(nd.left, False);
            set_node_is_visited(nd.right, False);
            if nd == nd.parent.right {
                delta -= nd.parent.delta;
            }
            nd = nd.parent;
            continue;
        }

        if not get_node_is_visited(nd.left) {
            node_max_end = delta + nd.max_end;
            if node_max_end < interval_start {
                set_node_is_visited(nd, True);
                continue;
            }

            if nd.left != SENTINEL {
                nd = nd.left;
                continue;
            }
        }

        node_start = delta + nd.start;
        if node_start > interval_end {
            set_node_is_visited(nd, True);
            continue;
        }

        node_end = delta + nd.end;

        if node_end >= interval_start {
            nd.set_cached_offsets(node_start, node_end, cached_version_id);

            should_include = True;
            if filter_owner_id and nd.owner_id and nd.owner_id != filter_owner_id {
                should_include = False;
            }
            if filter_out_validation and get_node_is_for_validation(nd) {
                should_include = False;
            }
            if filter_font_decorations and get_node_affects_font(nd) {
                should_include = False;
            }
            if only_margin_decorations and not get_node_is_in_glyph_margin(nd) {
                should_include = False;
            }

            if should_include {
                result.append(nd);
            }
        }

        set_node_is_visited(nd, True);

        if nd.right != SENTINEL and not get_node_is_visited(nd.right) {
            delta += nd.delta;
            nd = nd.right;
            continue;
        }
    }

    set_node_is_visited(t.tree_root, False);

    return result;
}

def rb_tree_insert(t: IntervalTree, new_node: IntervalNode) -> IntervalNode {
    if t.tree_root == SENTINEL {
        new_node.parent = SENTINEL;
        new_node.left = SENTINEL;
        new_node.right = SENTINEL;
        set_node_color(new_node, NODE_COLOR_BLACK);
        t.tree_root = new_node;
        return t.tree_root;
    }

    tree_insert(t, new_node);

    recompute_max_end_walk_to_root(new_node.parent);

    x = new_node;
    while x != t.tree_root and get_node_color(x.parent) == NODE_COLOR_RED {
        if x.parent == x.parent.parent.left {
            y = x.parent.parent.right;

            if get_node_color(y) == NODE_COLOR_RED {
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(y, NODE_COLOR_BLACK);
                set_node_color(x.parent.parent, NODE_COLOR_RED);
                x = x.parent.parent;
            } else {
                if x == x.parent.right {
                    x = x.parent;
                    left_rotate(t, x);
                }
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(x.parent.parent, NODE_COLOR_RED);
                right_rotate(t, x.parent.parent);
            }
        } else {
            y = x.parent.parent.left;

            if get_node_color(y) == NODE_COLOR_RED {
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(y, NODE_COLOR_BLACK);
                set_node_color(x.parent.parent, NODE_COLOR_RED);
                x = x.parent.parent;
            } else {
                if x == x.parent.left {
                    x = x.parent;
                    right_rotate(t, x);
                }
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(x.parent.parent, NODE_COLOR_RED);
                left_rotate(t, x.parent.parent);
            }
        }
    }

    set_node_color(t.tree_root, NODE_COLOR_BLACK);

    return new_node;
}

def tree_insert(t: IntervalTree, z: IntervalNode) {
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
    set_node_color(z, NODE_COLOR_RED);
}

def rb_tree_delete(t: IntervalTree, z: IntervalNode) {
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
        y = leftest(z.right);
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
        set_node_color(x, NODE_COLOR_BLACK);

        z.detach();
        reset_sentinel();
        recompute_max_end(x);
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
        set_node_color(y, get_node_color(z));

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
        recompute_max_end_walk_to_root(x.parent);
        if y != z {
            recompute_max_end_walk_to_root(y);
            recompute_max_end_walk_to_root(y.parent);
        }
        reset_sentinel();
        return;
    }

    recompute_max_end_walk_to_root(x);
    recompute_max_end_walk_to_root(x.parent);
    if y != z {
        recompute_max_end_walk_to_root(y);
        recompute_max_end_walk_to_root(y.parent);
    }

    w: IntervalNode = SENTINEL;
    while x != t.tree_root and get_node_color(x) == NODE_COLOR_BLACK {
        if x == x.parent.left {
            w = x.parent.right;

            if get_node_color(w) == NODE_COLOR_RED {
                set_node_color(w, NODE_COLOR_BLACK);
                set_node_color(x.parent, NODE_COLOR_RED);
                left_rotate(t, x.parent);
                w = x.parent.right;
            }

            if get_node_color(w.left) == NODE_COLOR_BLACK and get_node_color(w.right) == NODE_COLOR_BLACK {
                set_node_color(w, NODE_COLOR_RED);
                x = x.parent;
            } else {
                if get_node_color(w.right) == NODE_COLOR_BLACK {
                    set_node_color(w.left, NODE_COLOR_BLACK);
                    set_node_color(w, NODE_COLOR_RED);
                    right_rotate(t, w);
                    w = x.parent.right;
                }

                set_node_color(w, get_node_color(x.parent));
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(w.right, NODE_COLOR_BLACK);
                left_rotate(t, x.parent);
                x = t.tree_root;
            }
        } else {
            w = x.parent.left;

            if get_node_color(w) == NODE_COLOR_RED {
                set_node_color(w, NODE_COLOR_BLACK);
                set_node_color(x.parent, NODE_COLOR_RED);
                right_rotate(t, x.parent);
                w = x.parent.left;
            }

            if get_node_color(w.left) == NODE_COLOR_BLACK and get_node_color(w.right) == NODE_COLOR_BLACK {
                set_node_color(w, NODE_COLOR_RED);
                x = x.parent;
            } else {
                if get_node_color(w.left) == NODE_COLOR_BLACK {
                    set_node_color(w.right, NODE_COLOR_BLACK);
                    set_node_color(w, NODE_COLOR_RED);
                    left_rotate(t, w);
                    w = x.parent.left;
                }

                set_node_color(w, get_node_color(x.parent));
                set_node_color(x.parent, NODE_COLOR_BLACK);
                set_node_color(w.left, NODE_COLOR_BLACK);
                right_rotate(t, x.parent);
                x = t.tree_root;
            }
        }
    }

    set_node_color(x, NODE_COLOR_BLACK);
    reset_sentinel();
}

def leftest(nd: IntervalNode) -> IntervalNode {
    while nd.left != SENTINEL {
        nd = nd.left;
    }
    return nd;
}

def reset_sentinel {
    SENTINEL.parent = SENTINEL;
    SENTINEL.delta = 0;
    SENTINEL.start = 0;
    SENTINEL.end = 0;
}

def left_rotate(t: IntervalTree, x: IntervalNode) {
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

    recompute_max_end(x);
    recompute_max_end(y);
}

def right_rotate(t: IntervalTree, y: IntervalNode) {
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

    recompute_max_end(y);
    recompute_max_end(x);
}

def compute_max_end(nd: IntervalNode) -> int {
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

def recompute_max_end(nd: IntervalNode) {
    nd.max_end = compute_max_end(nd);
}

def recompute_max_end_walk_to_root(nd: IntervalNode) {
    while nd != SENTINEL {
        max_end = compute_max_end(nd);

        if nd.max_end == max_end {
            return;
        }

        nd.max_end = max_end;
        nd = nd.parent;
    }
}

def interval_compare(a_start: int, a_end: int, b_start: int, b_end: int) -> int {
    if a_start == b_start {
        return a_end - b_end;
    }
    return a_start - b_start;
}
