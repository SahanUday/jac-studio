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

    def postinit -> None;

    def reset(version_id: int, start: int, end: int, range: any) -> None;

    def set_cached_offsets(absolute_start: int, absolute_end: int, cached_version_id: int) -> None;

    def detach -> None;
}

glob SENTINEL: IntervalNode = IntervalNode(id="", start=0, end=0);

with entry {
    SENTINEL.parent = SENTINEL;
    SENTINEL.left = SENTINEL;
    SENTINEL.right = SENTINEL;
    _set_node_color(SENTINEL, NODE_COLOR_BLACK);
}

def set_node_stickiness(nd: IntervalNode, stickiness: int) {
    _set_node_stickiness_raw(nd, stickiness);
}

obj IntervalTree {
    has tree_root: IntervalNode postinit;
    has request_normalize_delta: bool postinit;

    def postinit -> None;

    def interval_search(
        start: int, end: int, filter_owner_id: int, filter_out_validation: bool,
        filter_font_decorations: bool, cached_version_id: int, only_margin_decorations: bool
    ) -> list[IntervalNode];

    def search(
        filter_owner_id: int, filter_out_validation: bool, filter_font_decorations: bool,
        cached_version_id: int, only_margin_decorations: bool
    ) -> list[IntervalNode];

    def collect_nodes_from_owner(owner_id: int) -> list[IntervalNode];

    def collect_nodes_post_order -> list[IntervalNode];

    def insert(nd: IntervalNode) -> None;

    def delete(nd: IntervalNode) -> None;

    def resolve_node(nd: IntervalNode, cached_version_id: int) -> None;

    def accept_replace(offset: int, length: int, text_length: int, force_move_markers: bool) -> None;

    def get_all_in_order -> list[IntervalNode];

    def _normalize_delta_if_necessary -> None;
}

glob MARKER_MOVE_DEFINED: int = 0;
glob MARKER_MOVE_FORCE_MOVE: int = 1;
glob MARKER_MOVE_FORCE_STAY: int = 2;

def node_accept_edit(nd: IntervalNode, start: int, end: int, text_length: int, force_move_markers: bool) {
    node_stickiness = _get_node_stickiness(nd);
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

    if start <= node_start and node_end <= end and _get_collapse_on_replace_edit(nd) {
        nd.start = start;
        start_done = True;
        nd.end = start;
        end_done = True;
    }

    move_semantics = (
        MARKER_MOVE_FORCE_MOVE if force_move_markers
        else (MARKER_MOVE_FORCE_STAY if deleting_cnt > 0 else MARKER_MOVE_DEFINED)
    );
    if not start_done and _adjust_marker_before_column(
        node_start, start_stick_to_previous_character, start, move_semantics
    ) {
        start_done = True;
    }
    if not end_done and _adjust_marker_before_column(
        node_end, end_stick_to_previous_character, start, move_semantics
    ) {
        end_done = True;
    }

    if common_length > 0 and not force_move_markers {
        move_semantics = (
            MARKER_MOVE_FORCE_STAY if deleting_cnt > inserting_cnt else MARKER_MOVE_DEFINED
        );
        if not start_done and _adjust_marker_before_column(
            node_start, start_stick_to_previous_character, start + common_length, move_semantics
        ) {
            start_done = True;
        }
        if not end_done and _adjust_marker_before_column(
            node_end, end_stick_to_previous_character, start + common_length, move_semantics
        ) {
            end_done = True;
        }
    }

    move_semantics = MARKER_MOVE_FORCE_MOVE if force_move_markers else MARKER_MOVE_DEFINED;
    if not start_done and _adjust_marker_before_column(
        node_start, start_stick_to_previous_character, end, move_semantics
    ) {
        nd.start = start + inserting_cnt;
        start_done = True;
    }
    if not end_done and _adjust_marker_before_column(
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

def interval_compare(a_start: int, a_end: int, b_start: int, b_end: int) -> int {
    if a_start == b_start {
        return a_end - b_end;
    }
    return a_start - b_start;
}
