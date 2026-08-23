"""Ported from intervalTree.test.ts. Two suites: differential testing against a naive Oracle
(gen01-18 + a forced-delta-overflow regression, each a fixed op sequence upstream generated once
and pinned as a regression test -- the `AutoTest`/random-fuzz generator that produced them is
gated behind `GENERATE_TESTS = false` upstream and never runs as part of the actual test suite,
so it's not ported here) and a large table of `nodeAcceptEdit` cases, mechanically extracted from
the upstream TS file's own `assertNodeAcceptEdit(...)` calls (208 of them) rather than
hand-transcribed, to eliminate transcription risk on data this repetitive.

`Interval` is a real `obj`, not a tuple, on purpose: `Oracle.delete` needs to remove one specific
previously-inserted interval by *identity* (mirroring upstream's `this.intervals[i] === interval`),
which duplicate-valued intervals (see gen08/gen09) make ambiguous under value equality. `==` on a
plain `obj` is identity comparison in this jac-lang build (see
2026-08-23-obj-equality-not-structural) -- exactly the semantics this needs, the same reason
`SENTINEL` comparisons in the base module work correctly. The final list-vs-list comparisons
(`assert.deepStrictEqual` upstream) need the opposite -- structural, not identity -- so those go
through `intervals_equal` instead of `==`."""

obj Interval {
    has start: int, end: int;
}

def intervals_equal(a: list[Interval], b: list[Interval]) -> bool {
    if len(a) != len(b) {
        return False;
    }
    for i in range(len(a)) {
        if a[i].start != b[i].start or a[i].end != b[i].end {
            return False;
        }
    }
    return True;
}

obj Oracle {
    has intervals: list[Interval] postinit;

    def postinit {
        self.intervals = [];
    }

    def insert(interval: Interval) -> Interval {
        self.intervals.append(interval);
        self.intervals.sort(key=lambda (iv: Interval) { return (iv.start, iv.end); });
        return interval;
    }

    def delete(interval: Interval) {
        for i in range(len(self.intervals)) {
            if self.intervals[i] == interval {
                self.intervals.pop(i);
                return;
            }
        }
    }

    def search(interval: Interval) -> list[Interval] {
        result: list[Interval] = [];
        for iv in self.intervals {
            if iv.start <= interval.end and iv.end >= interval.start {
                result.append(iv);
            }
        }
        return result;
    }
}

obj TestState {
    has oracle: Oracle postinit;
    has tree: IntervalTree postinit;
    has last_node_id: int postinit;
    has tree_nodes: list[any] postinit;
    has oracle_nodes: list[any] postinit;

    def postinit {
        self.oracle = Oracle();
        self.tree = IntervalTree();
        self.last_node_id = -1;
        self.tree_nodes = [];
        self.oracle_nodes = [];
    }

    def accept_op(op: dict) {
        op_type = op["type"];

        if op_type == "insert" {
            self.last_node_id += 1;
            nd = IntervalNode(id="", start=op["begin"], end=op["end"]);
            self.tree_nodes.append(nd);
            self.tree.insert(nd);
            oracle_interval = self.oracle.insert(Interval(start=op["begin"], end=op["end"]));
            self.oracle_nodes.append(oracle_interval);
        } elif op_type == "delete" {
            node_id = op["id"];
            self.tree.delete(self.tree_nodes[node_id]);
            self.oracle.delete(self.oracle_nodes[node_id]);
            self.tree_nodes[node_id] = None;
            self.oracle_nodes[node_id] = None;
        } elif op_type == "change" {
            node_id = op["id"];
            self.tree.delete(self.tree_nodes[node_id]);
            self.tree_nodes[node_id].reset(0, op["begin"], op["end"], None);
            self.tree.insert(self.tree_nodes[node_id]);

            self.oracle.delete(self.oracle_nodes[node_id]);
            self.oracle_nodes[node_id].start = op["begin"];
            self.oracle_nodes[node_id].end = op["end"];
            self.oracle.insert(self.oracle_nodes[node_id]);
        } else {
            actual_nodes = self.tree.interval_search(op["begin"], op["end"], 0, False, False, 0, False);
            actual = [Interval(start=n.cached_absolute_start, end=n.cached_absolute_end) for n in actual_nodes];
            expected = self.oracle.search(Interval(start=op["begin"], end=op["end"]));
            assert intervals_equal(actual, expected);
            return;
        }

        assert_tree_invariants(self.tree);

        actual = [
            Interval(start=n.cached_absolute_start, end=n.cached_absolute_end)
            for n in self.tree.get_all_in_order()
        ];
        expected = self.oracle.intervals;
        assert intervals_equal(actual, expected);
    }
}

def test_interval_tree(ops: list[dict]) {
    state = TestState();
    for op in ops {
        state.accept_op(op);
    }
}

def depth(nd: IntervalNode) -> int {
    if nd == SENTINEL {
        return 1;
    }
    assert depth(nd.left) == depth(nd.right);
    return (1 if get_node_color(nd) == NODE_COLOR_BLACK else 0) + depth(nd.left);
}

def assert_valid_node(nd: IntervalNode, delta: int) {
    if nd == SENTINEL {
        return;
    }

    l = nd.left;
    r = nd.right;

    if get_node_color(nd) == NODE_COLOR_RED {
        assert get_node_color(l) == NODE_COLOR_BLACK;
        assert get_node_color(r) == NODE_COLOR_BLACK;
    }

    expected_max_end = nd.end;
    if l != SENTINEL {
        assert interval_compare(l.start + delta, l.end + delta, nd.start + delta, nd.end + delta) <= 0;
        expected_max_end = max(expected_max_end, l.max_end);
    }
    if r != SENTINEL {
        assert interval_compare(
            nd.start + delta, nd.end + delta, r.start + delta + nd.delta, r.end + delta + nd.delta
        ) <= 0;
        expected_max_end = max(expected_max_end, r.max_end + nd.delta);
    }
    assert nd.max_end == expected_max_end;

    assert_valid_node(l, delta);
    assert_valid_node(r, delta + nd.delta);
}

def assert_valid_tree(t: IntervalTree) {
    if t.tree_root == SENTINEL {
        return;
    }
    assert get_node_color(t.tree_root) == NODE_COLOR_BLACK;
    assert depth(t.tree_root.left) == depth(t.tree_root.right);
    assert_valid_node(t.tree_root, 0);
}

def assert_tree_invariants(t: IntervalTree) {
    assert get_node_color(SENTINEL) == NODE_COLOR_BLACK;
    assert SENTINEL.parent == SENTINEL;
    assert SENTINEL.left == SENTINEL;
    assert SENTINEL.right == SENTINEL;
    assert SENTINEL.start == 0;
    assert SENTINEL.end == 0;
    assert SENTINEL.delta == 0;
    assert t.tree_root.parent == SENTINEL;
    assert_valid_tree(t);
}

test "gen01" {
    test_interval_tree([
        {"type": "insert", "begin": 28, "end": 35},
        {"type": "insert", "begin": 52, "end": 54},
        {"type": "insert", "begin": 63, "end": 69}
    ]);
}

test "gen02" {
    test_interval_tree([
        {"type": "insert", "begin": 80, "end": 89},
        {"type": "insert", "begin": 92, "end": 100},
        {"type": "insert", "begin": 99, "end": 99}
    ]);
}

test "gen03" {
    test_interval_tree([
        {"type": "insert", "begin": 89, "end": 96},
        {"type": "insert", "begin": 71, "end": 74},
        {"type": "delete", "id": 1}
    ]);
}

test "gen04" {
    test_interval_tree([
        {"type": "insert", "begin": 44, "end": 46},
        {"type": "insert", "begin": 85, "end": 88},
        {"type": "delete", "id": 0}
    ]);
}

test "gen05" {
    test_interval_tree([
        {"type": "insert", "begin": 82, "end": 90},
        {"type": "insert", "begin": 69, "end": 73},
        {"type": "delete", "id": 0},
        {"type": "delete", "id": 1}
    ]);
}

test "gen06" {
    test_interval_tree([
        {"type": "insert", "begin": 41, "end": 63},
        {"type": "insert", "begin": 98, "end": 98},
        {"type": "insert", "begin": 47, "end": 51},
        {"type": "delete", "id": 2}
    ]);
}

test "gen07" {
    test_interval_tree([
        {"type": "insert", "begin": 24, "end": 26},
        {"type": "insert", "begin": 11, "end": 28},
        {"type": "insert", "begin": 27, "end": 30},
        {"type": "insert", "begin": 80, "end": 85},
        {"type": "delete", "id": 1}
    ]);
}

test "gen08" {
    test_interval_tree([
        {"type": "insert", "begin": 100, "end": 100},
        {"type": "insert", "begin": 100, "end": 100}
    ]);
}

test "gen09" {
    test_interval_tree([
        {"type": "insert", "begin": 58, "end": 65},
        {"type": "insert", "begin": 82, "end": 96},
        {"type": "insert", "begin": 58, "end": 65}
    ]);
}

test "gen10" {
    test_interval_tree([
        {"type": "insert", "begin": 32, "end": 40},
        {"type": "insert", "begin": 25, "end": 29},
        {"type": "insert", "begin": 24, "end": 32}
    ]);
}

test "gen11" {
    test_interval_tree([
        {"type": "insert", "begin": 25, "end": 70},
        {"type": "insert", "begin": 99, "end": 100},
        {"type": "insert", "begin": 46, "end": 51},
        {"type": "insert", "begin": 57, "end": 57},
        {"type": "delete", "id": 2}
    ]);
}

test "gen12" {
    test_interval_tree([
        {"type": "insert", "begin": 20, "end": 26},
        {"type": "insert", "begin": 10, "end": 18},
        {"type": "insert", "begin": 99, "end": 99},
        {"type": "insert", "begin": 37, "end": 59},
        {"type": "delete", "id": 2}
    ]);
}

test "gen13" {
    test_interval_tree([
        {"type": "insert", "begin": 3, "end": 91},
        {"type": "insert", "begin": 57, "end": 57},
        {"type": "insert", "begin": 35, "end": 44},
        {"type": "insert", "begin": 72, "end": 81},
        {"type": "delete", "id": 2}
    ]);
}

test "gen14" {
    test_interval_tree([
        {"type": "insert", "begin": 58, "end": 61},
        {"type": "insert", "begin": 34, "end": 35},
        {"type": "insert", "begin": 56, "end": 62},
        {"type": "insert", "begin": 69, "end": 78},
        {"type": "delete", "id": 0}
    ]);
}

test "gen15" {
    test_interval_tree([
        {"type": "insert", "begin": 63, "end": 69},
        {"type": "insert", "begin": 17, "end": 24},
        {"type": "insert", "begin": 3, "end": 13},
        {"type": "insert", "begin": 84, "end": 94},
        {"type": "insert", "begin": 18, "end": 23},
        {"type": "insert", "begin": 96, "end": 98},
        {"type": "delete", "id": 1}
    ]);
}

test "gen16" {
    test_interval_tree([
        {"type": "insert", "begin": 27, "end": 27},
        {"type": "insert", "begin": 42, "end": 87},
        {"type": "insert", "begin": 42, "end": 49},
        {"type": "insert", "begin": 69, "end": 71},
        {"type": "insert", "begin": 20, "end": 27},
        {"type": "insert", "begin": 8, "end": 9},
        {"type": "insert", "begin": 42, "end": 49},
        {"type": "delete", "id": 1}
    ]);
}

test "gen17" {
    test_interval_tree([
        {"type": "insert", "begin": 21, "end": 23},
        {"type": "insert", "begin": 83, "end": 87},
        {"type": "insert", "begin": 56, "end": 58},
        {"type": "insert", "begin": 1, "end": 55},
        {"type": "insert", "begin": 56, "end": 59},
        {"type": "insert", "begin": 58, "end": 60},
        {"type": "insert", "begin": 56, "end": 65},
        {"type": "delete", "id": 1},
        {"type": "delete", "id": 0},
        {"type": "delete", "id": 6}
    ]);
}

test "gen18" {
    test_interval_tree([
        {"type": "insert", "begin": 25, "end": 25},
        {"type": "insert", "begin": 67, "end": 79},
        {"type": "delete", "id": 0},
        {"type": "search", "begin": 65, "end": 75}
    ]);
}

test "force delta overflow" {
    # Search the IntervalNode ctor for FORCE_OVERFLOWING_TEST in the upstream source to force
    # that this test leads to a delta normalization -- see this port's postinit, which doesn't
    # carry that commented-out debug hook over (upstream leaves it commented out too).
    test_interval_tree([
        {"type": "insert", "begin": 686081138593427, "end": 733009856502260},
        {"type": "insert", "begin": 591031326181669, "end": 591031326181672},
        {"type": "insert", "begin": 940037682731896, "end": 940037682731903},
        {"type": "insert", "begin": 598413641151120, "end": 598413641151128},
        {"type": "insert", "begin": 800564156553344, "end": 800564156553351},
        {"type": "insert", "begin": 894198957565481, "end": 894198957565491}
    ]);
}

def create_cormen_tree -> IntervalTree {
    t = IntervalTree();
    data = [(16, 21), (8, 9), (25, 30), (5, 8), (15, 23), (17, 19), (26, 26), (0, 3), (6, 10), (19, 20)];
    for (s, e) in data {
        nd = IntervalNode(id="", start=s, end=e);
        t.insert(nd);
    }
    return t;
}

def assert_interval_search(t: IntervalTree, start: int, end: int, expected: list[tuple]) {
    actual_nodes = t.interval_search(start, end, 0, False, False, 0, False);
    actual = [(n.cached_absolute_start, n.cached_absolute_end) for n in actual_nodes];
    assert actual == expected;
}

test "cormen 1->2" {
    t = create_cormen_tree();
    assert_interval_search(t, 1, 2, [(0, 3)]);
}

test "cormen 4->8" {
    t = create_cormen_tree();
    assert_interval_search(t, 4, 8, [(5, 8), (6, 10), (8, 9)]);
}

test "cormen 10->15" {
    t = create_cormen_tree();
    assert_interval_search(t, 10, 15, [(6, 10), (15, 23)]);
}

test "cormen 21->25" {
    t = create_cormen_tree();
    assert_interval_search(t, 21, 25, [(15, 23), (16, 21), (25, 30)]);
}

test "cormen 24->24" {
    t = create_cormen_tree();
    assert_interval_search(t, 24, 24, []);
}

def assert_node_accept_edit(
    msg: str, node_start: int, node_end: int, node_stickiness: int, start: int, end: int,
    text_length: int, force_move_markers: bool, expected_node_start: int, expected_node_end: int
) {
    nd = IntervalNode(id="", start=node_start, end=node_end);
    set_node_stickiness(nd, node_stickiness);
    node_accept_edit(nd, start, end, text_length, force_move_markers);
    assert (nd.start, nd.end) == (expected_node_start, expected_node_end), msg;
}

test "nodeAcceptEdit" {
    assert_node_accept_edit("A.000", 0, 0, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, False, 0, 0);
    assert_node_accept_edit("A.001", 0, 0, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, False, 0, 0);
    assert_node_accept_edit("A.002", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 0, False, 0, 0);
    assert_node_accept_edit("A.003", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 0, False, 0, 0);
    assert_node_accept_edit("A.004", 0, 0, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, True, 0, 0);
    assert_node_accept_edit("A.005", 0, 0, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, True, 0, 0);
    assert_node_accept_edit("A.006", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 0, True, 0, 0);
    assert_node_accept_edit("A.007", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 0, True, 0, 0);
    assert_node_accept_edit("A.008", 0, 0, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, False, 0, 1);
    assert_node_accept_edit("A.009", 0, 0, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, False, 1, 1);
    assert_node_accept_edit("A.010", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 1, False, 0, 0);
    assert_node_accept_edit("A.011", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 1, False, 1, 1);
    assert_node_accept_edit("A.012", 0, 0, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, True, 1, 1);
    assert_node_accept_edit("A.013", 0, 0, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, True, 1, 1);
    assert_node_accept_edit("A.014", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 1, True, 1, 1);
    assert_node_accept_edit("A.015", 0, 0, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 1, True, 1, 1);
    assert_node_accept_edit("B.000", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, False, 0, 5);
    assert_node_accept_edit("B.001", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, False, 0, 5);
    assert_node_accept_edit("B.002", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 0, False, 0, 5);
    assert_node_accept_edit("B.003", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 0, False, 0, 5);
    assert_node_accept_edit("B.004", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, True, 0, 5);
    assert_node_accept_edit("B.005", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 0, True, 0, 5);
    assert_node_accept_edit("B.006", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 0, True, 0, 5);
    assert_node_accept_edit("B.007", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 0, True, 0, 5);
    assert_node_accept_edit("B.008", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, False, 0, 6);
    assert_node_accept_edit("B.009", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, False, 1, 6);
    assert_node_accept_edit("B.010", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 1, False, 0, 6);
    assert_node_accept_edit("B.011", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 1, False, 1, 6);
    assert_node_accept_edit("B.012", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, True, 1, 6);
    assert_node_accept_edit("B.013", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 0, 0, 1, True, 1, 6);
    assert_node_accept_edit("B.014", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 0, 0, 1, True, 1, 6);
    assert_node_accept_edit("B.015", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 0, 0, 1, True, 1, 6);
    assert_node_accept_edit("B.016", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 2, 2, 1, False, 0, 6);
    assert_node_accept_edit("B.017", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 2, 2, 1, False, 0, 6);
    assert_node_accept_edit("B.018", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 2, 2, 1, False, 0, 6);
    assert_node_accept_edit("B.019", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 2, 2, 1, False, 0, 6);
    assert_node_accept_edit("B.020", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 2, 2, 1, True, 0, 6);
    assert_node_accept_edit("B.021", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 2, 2, 1, True, 0, 6);
    assert_node_accept_edit("B.022", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 2, 2, 1, True, 0, 6);
    assert_node_accept_edit("B.023", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 2, 2, 1, True, 0, 6);
    assert_node_accept_edit("B.024", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 5, 1, False, 0, 6);
    assert_node_accept_edit("B.025", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 5, 1, False, 0, 5);
    assert_node_accept_edit("B.026", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 5, 1, False, 0, 5);
    assert_node_accept_edit("B.027", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 5, 1, False, 0, 6);
    assert_node_accept_edit("B.028", 0, 5, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 5, 1, True, 0, 6);
    assert_node_accept_edit("B.029", 0, 5, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 5, 1, True, 0, 6);
    assert_node_accept_edit("B.030", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 5, 1, True, 0, 6);
    assert_node_accept_edit("B.031", 0, 5, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 5, 1, True, 0, 6);
    assert_node_accept_edit("B.032", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 2, False, 5, 11);
    assert_node_accept_edit("B.033", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 2, False, 6, 11);
    assert_node_accept_edit("B.034", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 5, 2, False, 5, 11);
    assert_node_accept_edit("B.035", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 5, 2, False, 6, 11);
    assert_node_accept_edit("B.036", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 2, True, 6, 11);
    assert_node_accept_edit("B.037", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 2, True, 6, 11);
    assert_node_accept_edit("B.038", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 5, 2, True, 6, 11);
    assert_node_accept_edit("B.039", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 5, 2, True, 6, 11);
    assert_node_accept_edit("B.040", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 3, 5, 1, False, 4, 9);
    assert_node_accept_edit("B.041", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 3, 5, 1, False, 4, 9);
    assert_node_accept_edit("B.042", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 3, 5, 1, False, 4, 9);
    assert_node_accept_edit("B.043", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 3, 5, 1, False, 4, 9);
    assert_node_accept_edit("B.044", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 3, 5, 1, True, 4, 9);
    assert_node_accept_edit("B.045", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 3, 5, 1, True, 4, 9);
    assert_node_accept_edit("B.046", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 3, 5, 1, True, 4, 9);
    assert_node_accept_edit("B.047", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 3, 5, 1, True, 4, 9);
    assert_node_accept_edit("B.048", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 3, False, 5, 11);
    assert_node_accept_edit("B.049", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 3, False, 5, 11);
    assert_node_accept_edit("B.050", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 3, False, 5, 11);
    assert_node_accept_edit("B.051", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 3, False, 5, 11);
    assert_node_accept_edit("B.052", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 3, True, 7, 11);
    assert_node_accept_edit("B.053", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 3, True, 7, 11);
    assert_node_accept_edit("B.054", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 3, True, 7, 11);
    assert_node_accept_edit("B.055", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 3, True, 7, 11);
    assert_node_accept_edit("B.056", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 1, False, 5, 9);
    assert_node_accept_edit("B.057", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 1, False, 5, 9);
    assert_node_accept_edit("B.058", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 1, False, 5, 9);
    assert_node_accept_edit("B.059", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 1, False, 5, 9);
    assert_node_accept_edit("B.060", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 1, True, 5, 9);
    assert_node_accept_edit("B.061", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 1, True, 5, 9);
    assert_node_accept_edit("B.062", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 1, True, 5, 9);
    assert_node_accept_edit("B.063", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 1, True, 5, 9);
    assert_node_accept_edit("B.064", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 2, False, 5, 11);
    assert_node_accept_edit("B.065", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 2, False, 5, 11);
    assert_node_accept_edit("B.066", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 6, 2, False, 5, 11);
    assert_node_accept_edit("B.067", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 6, 2, False, 5, 11);
    assert_node_accept_edit("B.068", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 2, True, 7, 11);
    assert_node_accept_edit("B.069", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 2, True, 7, 11);
    assert_node_accept_edit("B.070", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 6, 2, True, 7, 11);
    assert_node_accept_edit("B.071", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 6, 2, True, 7, 11);
    assert_node_accept_edit("B.072", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 7, 1, False, 5, 9);
    assert_node_accept_edit("B.073", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 7, 1, False, 5, 9);
    assert_node_accept_edit("B.074", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 7, 1, False, 5, 9);
    assert_node_accept_edit("B.075", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 7, 1, False, 5, 9);
    assert_node_accept_edit("B.076", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 7, 1, True, 6, 9);
    assert_node_accept_edit("B.077", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 7, 1, True, 6, 9);
    assert_node_accept_edit("B.078", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 7, 1, True, 6, 9);
    assert_node_accept_edit("B.079", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 7, 1, True, 6, 9);
    assert_node_accept_edit("B.080", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 2, False, 5, 11);
    assert_node_accept_edit("B.081", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 2, False, 5, 10);
    assert_node_accept_edit("B.082", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 10, 2, False, 5, 10);
    assert_node_accept_edit("B.083", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 10, 2, False, 5, 11);
    assert_node_accept_edit("B.084", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 2, True, 5, 11);
    assert_node_accept_edit("B.085", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 2, True, 5, 11);
    assert_node_accept_edit("B.086", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 10, 2, True, 5, 11);
    assert_node_accept_edit("B.087", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 10, 2, True, 5, 11);
    assert_node_accept_edit("B.088", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 8, 10, 1, False, 5, 9);
    assert_node_accept_edit("B.089", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 8, 10, 1, False, 5, 9);
    assert_node_accept_edit("B.090", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 8, 10, 1, False, 5, 9);
    assert_node_accept_edit("B.091", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 8, 10, 1, False, 5, 9);
    assert_node_accept_edit("B.092", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 8, 10, 1, True, 5, 9);
    assert_node_accept_edit("B.093", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 8, 10, 1, True, 5, 9);
    assert_node_accept_edit("B.094", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 8, 10, 1, True, 5, 9);
    assert_node_accept_edit("B.095", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 8, 10, 1, True, 5, 9);
    assert_node_accept_edit("B.096", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.097", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.098", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.099", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.100", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 3, True, 5, 12);
    assert_node_accept_edit("B.101", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 3, True, 5, 12);
    assert_node_accept_edit("B.102", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 3, True, 5, 12);
    assert_node_accept_edit("B.103", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 3, True, 5, 12);
    assert_node_accept_edit("B.104", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 1, False, 5, 10);
    assert_node_accept_edit("B.105", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 1, False, 5, 10);
    assert_node_accept_edit("B.106", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 1, False, 5, 10);
    assert_node_accept_edit("B.107", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 1, False, 5, 10);
    assert_node_accept_edit("B.108", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 1, True, 5, 10);
    assert_node_accept_edit("B.109", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 1, True, 5, 10);
    assert_node_accept_edit("B.110", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 1, True, 5, 10);
    assert_node_accept_edit("B.111", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 1, True, 5, 10);
    assert_node_accept_edit("B.112", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.113", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.114", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.115", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 11, 3, False, 5, 10);
    assert_node_accept_edit("B.116", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 3, True, 5, 13);
    assert_node_accept_edit("B.117", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 3, True, 5, 13);
    assert_node_accept_edit("B.118", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 11, 3, True, 5, 13);
    assert_node_accept_edit("B.119", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 11, 3, True, 5, 13);
    assert_node_accept_edit("B.120", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 12, 1, False, 5, 10);
    assert_node_accept_edit("B.121", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 12, 1, False, 5, 10);
    assert_node_accept_edit("B.122", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 12, 1, False, 5, 10);
    assert_node_accept_edit("B.123", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 12, 1, False, 5, 10);
    assert_node_accept_edit("B.124", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 12, 1, True, 5, 11);
    assert_node_accept_edit("B.125", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 12, 1, True, 5, 11);
    assert_node_accept_edit("B.126", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 12, 1, True, 5, 11);
    assert_node_accept_edit("B.127", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 12, 1, True, 5, 11);
    assert_node_accept_edit("B.128", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 0, False, 4, 9);
    assert_node_accept_edit("B.129", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 0, False, 4, 9);
    assert_node_accept_edit("B.130", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 5, 0, False, 4, 9);
    assert_node_accept_edit("B.131", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 5, 0, False, 4, 9);
    assert_node_accept_edit("B.132", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 0, True, 4, 9);
    assert_node_accept_edit("B.133", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 5, 0, True, 4, 9);
    assert_node_accept_edit("B.134", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 5, 0, True, 4, 9);
    assert_node_accept_edit("B.135", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 5, 0, True, 4, 9);
    assert_node_accept_edit("B.136", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 0, False, 4, 8);
    assert_node_accept_edit("B.137", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 0, False, 4, 8);
    assert_node_accept_edit("B.138", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 0, False, 4, 8);
    assert_node_accept_edit("B.139", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 0, False, 4, 8);
    assert_node_accept_edit("B.140", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 0, True, 4, 8);
    assert_node_accept_edit("B.141", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 4, 6, 0, True, 4, 8);
    assert_node_accept_edit("B.142", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 4, 6, 0, True, 4, 8);
    assert_node_accept_edit("B.143", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 4, 6, 0, True, 4, 8);
    assert_node_accept_edit("B.144", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 0, False, 5, 9);
    assert_node_accept_edit("B.145", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 0, False, 5, 9);
    assert_node_accept_edit("B.146", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 6, 0, False, 5, 9);
    assert_node_accept_edit("B.147", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 6, 0, False, 5, 9);
    assert_node_accept_edit("B.148", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 0, True, 5, 9);
    assert_node_accept_edit("B.149", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 6, 0, True, 5, 9);
    assert_node_accept_edit("B.150", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 6, 0, True, 5, 9);
    assert_node_accept_edit("B.151", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 6, 0, True, 5, 9);
    assert_node_accept_edit("B.152", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 0, False, 5, 9);
    assert_node_accept_edit("B.153", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 0, False, 5, 9);
    assert_node_accept_edit("B.154", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 10, 0, False, 5, 9);
    assert_node_accept_edit("B.155", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 10, 0, False, 5, 9);
    assert_node_accept_edit("B.156", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 0, True, 5, 9);
    assert_node_accept_edit("B.157", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 10, 0, True, 5, 9);
    assert_node_accept_edit("B.158", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 10, 0, True, 5, 9);
    assert_node_accept_edit("B.159", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 10, 0, True, 5, 9);
    assert_node_accept_edit("B.160", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 0, False, 5, 9);
    assert_node_accept_edit("B.161", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 0, False, 5, 9);
    assert_node_accept_edit("B.162", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 0, False, 5, 9);
    assert_node_accept_edit("B.163", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 0, False, 5, 9);
    assert_node_accept_edit("B.164", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 0, True, 5, 9);
    assert_node_accept_edit("B.165", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 9, 11, 0, True, 5, 9);
    assert_node_accept_edit("B.166", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 9, 11, 0, True, 5, 9);
    assert_node_accept_edit("B.167", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 9, 11, 0, True, 5, 9);
    assert_node_accept_edit("B.168", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 0, False, 5, 10);
    assert_node_accept_edit("B.169", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 0, False, 5, 10);
    assert_node_accept_edit("B.170", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 11, 0, False, 5, 10);
    assert_node_accept_edit("B.171", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 11, 0, False, 5, 10);
    assert_node_accept_edit("B.172", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 0, True, 5, 10);
    assert_node_accept_edit("B.173", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 10, 11, 0, True, 5, 10);
    assert_node_accept_edit("B.174", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 10, 11, 0, True, 5, 10);
    assert_node_accept_edit("B.175", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 10, 11, 0, True, 5, 10);
    assert_node_accept_edit("B.176", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 3, False, 5, 8);
    assert_node_accept_edit("B.177", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 3, False, 5, 8);
    assert_node_accept_edit("B.178", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 10, 3, False, 5, 8);
    assert_node_accept_edit("B.179", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 10, 3, False, 5, 8);
    assert_node_accept_edit("B.180", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 3, True, 8, 8);
    assert_node_accept_edit("B.181", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 3, True, 8, 8);
    assert_node_accept_edit("B.182", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 10, 3, True, 8, 8);
    assert_node_accept_edit("B.183", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 10, 3, True, 8, 8);
    assert_node_accept_edit("B.184", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 7, False, 5, 12);
    assert_node_accept_edit("B.185", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 7, False, 5, 10);
    assert_node_accept_edit("B.186", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 10, 7, False, 5, 10);
    assert_node_accept_edit("B.187", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 10, 7, False, 5, 12);
    assert_node_accept_edit("B.188", 5, 10, TRS_ALWAYS_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 7, True, 12, 12);
    assert_node_accept_edit("B.189", 5, 10, TRS_NEVER_GROWS_WHEN_TYPING_AT_EDGES, 5, 10, 7, True, 12, 12);
    assert_node_accept_edit("B.190", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_BEFORE, 5, 10, 7, True, 12, 12);
    assert_node_accept_edit("B.191", 5, 10, TRS_GROWS_ONLY_WHEN_TYPING_AFTER, 5, 10, 7, True, 12, 12);
}
