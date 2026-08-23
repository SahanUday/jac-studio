"""Ported from prefixSumComputer.test.ts -- every `test(...)` block there has a matching
`test "..."` here, run against both implementations via `for_both`, mirroring upstream's own
`forBoth`/`createBoth` harness. Behavioral parity, not just compilation, is the bar
(docs/translator-strategy.md).

`_PrefixSumComputerAsCount` mirrors upstream's `IPrefixSumComputer` wrapper in the TS test file
(not in prefixSumComputer.ts itself): `PrefixSumComputer.get_prefix_sum(index)` returns the sum of
the first `index + 1` items (0<=j<=index), while `ConstantTimePrefixSumComputer.get_prefix_sum`
and every assertion in this file use a count convention (0<=j<count) -- upstream's own test file
adapts the first class to the second's convention (`count === 0 ? 0 : psc.getPrefixSum(count - 1)`
in createBoth); missing that adapter and calling the raw method directly is a real bug this port
hit first, not a hypothetical -- `get_prefix_sum(0)` on a raw `PrefixSumComputer` returns
`values[0]`, not 0.

`index_of_matches` exists because `==` on a plain `obj` does NOT do structural/value equality in
this jac-lang build, despite the language docs claiming dataclass-like auto-generated `__eq__` --
confirmed with two independent checks (two structurally-identical `obj` instances compare unequal;
a hand-written `__eq__` override on the archetype is silently never called by `==`). Comparing
`PrefixSumIndexOfResult` instances directly (as upstream's `assert.deepStrictEqual` does) is not
available; every such assertion here compares `.index`/`.remainder` fields explicitly instead. See
the challenge tracker for the full writeup -- this is a real doc-vs-behavior mismatch, not a
translation shortcut."""

obj _PrefixSumComputerAsCount {
    has psc: PrefixSumComputer;

    def get_total_sum -> int {
        return self.psc.get_total_sum();
    }

    def get_prefix_sum(count: int) -> int {
        return 0 if count == 0 else self.psc.get_prefix_sum(count - 1);
    }

    def get_index_of(target_sum: int) -> PrefixSumIndexOfResult {
        return self.psc.get_index_of(target_sum);
    }

    def set_value(index: int, value: int) {
        self.psc.set_value(index, value);
    }

    def insert_values(insert_index: int, insert_arr: list[int]) {
        self.psc.insert_values(insert_index, insert_arr);
    }

    def remove_values(start: int, delete_count: int) {
        self.psc.remove_values(start, delete_count);
    }
}

def index_of_matches(result: PrefixSumIndexOfResult, index: int, remainder: int) -> bool {
    return result.index == index and result.remainder == remainder;
}

def for_both(values: list[int], check: Callable) {
    check(_PrefixSumComputerAsCount(psc=PrefixSumComputer(values=list(values))));
    check(ConstantTimePrefixSumComputer(values=list(values)));
}

test "comprehensive setValue and getIndexOf" {
    def check(psc: any) {
        assert psc.get_total_sum() == 8;
        assert psc.get_prefix_sum(0) == 0;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 2;
        assert psc.get_prefix_sum(3) == 4;
        assert psc.get_prefix_sum(4) == 5;
        assert psc.get_prefix_sum(5) == 8;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 2, 0);
        assert index_of_matches(psc.get_index_of(3), 2, 1);
        assert index_of_matches(psc.get_index_of(4), 3, 0);
        assert index_of_matches(psc.get_index_of(5), 4, 0);
        assert index_of_matches(psc.get_index_of(6), 4, 1);
        assert index_of_matches(psc.get_index_of(7), 4, 2);
        assert index_of_matches(psc.get_index_of(8), 4, 3);

        # [1, 2, 2, 1, 3]
        psc.set_value(1, 2);
        assert psc.get_total_sum() == 9;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 3;
        assert psc.get_prefix_sum(3) == 5;
        assert psc.get_prefix_sum(4) == 6;
        assert psc.get_prefix_sum(5) == 9;

        # [1, 0, 2, 1, 3]
        psc.set_value(1, 0);
        assert psc.get_total_sum() == 7;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 1;
        assert psc.get_prefix_sum(3) == 3;
        assert psc.get_prefix_sum(4) == 4;
        assert psc.get_prefix_sum(5) == 7;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 2, 0);
        assert index_of_matches(psc.get_index_of(2), 2, 1);
        assert index_of_matches(psc.get_index_of(3), 3, 0);
        assert index_of_matches(psc.get_index_of(4), 4, 0);
        assert index_of_matches(psc.get_index_of(5), 4, 1);
        assert index_of_matches(psc.get_index_of(6), 4, 2);

        # [1, 0, 0, 1, 3]
        psc.set_value(2, 0);
        assert psc.get_total_sum() == 5;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 1;
        assert psc.get_prefix_sum(3) == 1;
        assert psc.get_prefix_sum(4) == 2;
        assert psc.get_prefix_sum(5) == 5;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 3, 0);
        assert index_of_matches(psc.get_index_of(2), 4, 0);
        assert index_of_matches(psc.get_index_of(3), 4, 1);
        assert index_of_matches(psc.get_index_of(4), 4, 2);

        # [1, 0, 0, 0, 3]
        psc.set_value(3, 0);
        assert psc.get_total_sum() == 4;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 1;
        assert psc.get_prefix_sum(3) == 1;
        assert psc.get_prefix_sum(4) == 1;
        assert psc.get_prefix_sum(5) == 4;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 4, 0);
        assert index_of_matches(psc.get_index_of(2), 4, 1);
        assert index_of_matches(psc.get_index_of(3), 4, 2);

        # [1, 1, 0, 1, 1]
        psc.set_value(1, 1);
        psc.set_value(3, 1);
        psc.set_value(4, 1);
        assert psc.get_total_sum() == 4;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 2;
        assert psc.get_prefix_sum(3) == 2;
        assert psc.get_prefix_sum(4) == 3;
        assert psc.get_prefix_sum(5) == 4;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 3, 0);
        assert index_of_matches(psc.get_index_of(3), 4, 0);
    }
    for_both([1, 1, 2, 1, 3], check);
}

# --- getTotalSum ---

test "getTotalSum with typical values" {
    for_both([1, 1, 2, 1, 3], lambda (psc: any) { assert psc.get_total_sum() == 8; });
    for_both([10], lambda (psc: any) { assert psc.get_total_sum() == 10; });
    for_both([5, 5, 5], lambda (psc: any) { assert psc.get_total_sum() == 15; });
}

test "getTotalSum with all zeroes" {
    for_both([0, 0, 0], lambda (psc: any) { assert psc.get_total_sum() == 0; });
    for_both([0], lambda (psc: any) { assert psc.get_total_sum() == 0; });
}

test "getTotalSum with empty array" {
    for_both([], lambda (psc: any) { assert psc.get_total_sum() == 0; });
}

test "getTotalSum with single element" {
    for_both([0], lambda (psc: any) { assert psc.get_total_sum() == 0; });
    for_both([1], lambda (psc: any) { assert psc.get_total_sum() == 1; });
    for_both([100], lambda (psc: any) { assert psc.get_total_sum() == 100; });
}

# --- getPrefixSum ---

test "getPrefixSum with typical values" {
    def check(psc: any) {
        assert psc.get_prefix_sum(0) == 0;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 2;
        assert psc.get_prefix_sum(3) == 4;
        assert psc.get_prefix_sum(4) == 5;
        assert psc.get_prefix_sum(5) == 8;
    }
    for_both([1, 1, 2, 1, 3], check);
}

test "getPrefixSum with all zeroes" {
    def check(psc: any) {
        assert psc.get_prefix_sum(0) == 0;
        assert psc.get_prefix_sum(1) == 0;
        assert psc.get_prefix_sum(2) == 0;
        assert psc.get_prefix_sum(3) == 0;
    }
    for_both([0, 0, 0], check);
}

test "getPrefixSum with single element" {
    def check(psc: any) {
        assert psc.get_prefix_sum(0) == 0;
        assert psc.get_prefix_sum(1) == 7;
    }
    for_both([7], check);
}

test "getPrefixSum with empty array" {
    for_both([], lambda (psc: any) { assert psc.get_prefix_sum(0) == 0; });
}

test "getPrefixSum with leading/trailing zeroes" {
    def check(psc: any) {
        assert psc.get_prefix_sum(0) == 0;
        assert psc.get_prefix_sum(1) == 0;
        assert psc.get_prefix_sum(2) == 0;
        assert psc.get_prefix_sum(3) == 3;
        assert psc.get_prefix_sum(4) == 3;
        assert psc.get_prefix_sum(5) == 3;
    }
    for_both([0, 0, 3, 0, 0], check);
}

# --- getIndexOf ---

test "getIndexOf with typical values" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 2, 0);
        assert index_of_matches(psc.get_index_of(3), 2, 1);
        assert index_of_matches(psc.get_index_of(4), 3, 0);
        assert index_of_matches(psc.get_index_of(5), 4, 0);
        assert index_of_matches(psc.get_index_of(6), 4, 1);
        assert index_of_matches(psc.get_index_of(7), 4, 2);
        assert index_of_matches(psc.get_index_of(8), 4, 3);
    }
    for_both([1, 1, 2, 1, 3], check);
}

test "getIndexOf with all zeroes" {
    for_both([0, 0, 0], lambda (psc: any) {
        assert index_of_matches(psc.get_index_of(0), 2, 0);
    });
}

test "getIndexOf with single zero" {
    for_both([0], lambda (psc: any) {
        assert index_of_matches(psc.get_index_of(0), 0, 0);
    });
}

test "getIndexOf with single element" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 0, 1);
        assert index_of_matches(psc.get_index_of(4), 0, 4);
    }
    for_both([5], check);
}

test "getIndexOf with leading zeroes" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 2, 0);
        assert index_of_matches(psc.get_index_of(1), 2, 1);
        assert index_of_matches(psc.get_index_of(2), 2, 2);
    }
    for_both([0, 0, 3], check);
}

test "getIndexOf with trailing zeroes" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 0, 1);
        assert index_of_matches(psc.get_index_of(2), 0, 2);
    }
    for_both([3, 0, 0], check);
}

test "getIndexOf with interleaved zeroes" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 1, 0);
        assert index_of_matches(psc.get_index_of(1), 3, 0);
        assert index_of_matches(psc.get_index_of(2), 3, 1);
    }
    for_both([0, 1, 0, 2, 0], check);
}

test "getIndexOf with all ones" {
    def check(psc: any) {
        for i in range(5) {
            assert index_of_matches(psc.get_index_of(i), i, 0);
        }
    }
    for_both([1, 1, 1, 1, 1], check);
}

test "getIndexOf with large value in single element" {
    def check(psc: any) {
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(500), 0, 500);
        assert index_of_matches(psc.get_index_of(999), 0, 999);
    }
    for_both([1000], check);
}

# --- setValue ---

test "setValue no-op when value unchanged" {
    def check(psc: any) {
        assert psc.get_total_sum() == 6;
        psc.set_value(1, 2);
        assert psc.get_total_sum() == 6;
    }
    for_both([1, 2, 3], check);
}

test "setValue increase" {
    def check(psc: any) {
        psc.set_value(1, 5);
        assert psc.get_total_sum() == 9;
        assert psc.get_prefix_sum(2) == 6;
        assert psc.get_prefix_sum(3) == 9;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(5), 1, 4);
        assert index_of_matches(psc.get_index_of(6), 2, 0);
    }
    for_both([1, 2, 3], check);
}

test "setValue decrease" {
    def check(psc: any) {
        psc.set_value(1, 2);
        assert psc.get_total_sum() == 6;
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 1, 1);
        assert index_of_matches(psc.get_index_of(3), 2, 0);
    }
    for_both([1, 5, 3], check);
}

test "setValue to zero" {
    def check(psc: any) {
        psc.set_value(1, 0);
        assert psc.get_total_sum() == 4;
        assert psc.get_prefix_sum(2) == 1;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 2, 0);
    }
    for_both([1, 2, 3], check);
}

test "setValue from zero" {
    def check(psc: any) {
        psc.set_value(1, 3);
        assert psc.get_total_sum() == 3;
        assert index_of_matches(psc.get_index_of(0), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 1, 2);
    }
    for_both([0, 0, 0], check);
}

test "setValue on first element" {
    def check(psc: any) {
        psc.set_value(0, 10);
        assert psc.get_total_sum() == 15;
        assert psc.get_prefix_sum(1) == 10;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(9), 0, 9);
        assert index_of_matches(psc.get_index_of(10), 1, 0);
    }
    for_both([1, 2, 3], check);
}

test "setValue on last element" {
    def check(psc: any) {
        psc.set_value(2, 10);
        assert psc.get_total_sum() == 13;
        assert index_of_matches(psc.get_index_of(3), 2, 0);
        assert index_of_matches(psc.get_index_of(12), 2, 9);
    }
    for_both([1, 2, 3], check);
}

test "set all values to zero then restore" {
    def check(psc: any) {
        psc.set_value(0, 0);
        psc.set_value(1, 0);
        psc.set_value(2, 0);
        assert psc.get_total_sum() == 0;
        assert index_of_matches(psc.get_index_of(0), 2, 0);

        psc.set_value(0, 4);
        assert psc.get_total_sum() == 4;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(3), 0, 3);
    }
    for_both([1, 2, 3], check);
}

test "setValue multiple times on same index" {
    def check(psc: any) {
        psc.set_value(1, 5);
        psc.set_value(1, 2);
        psc.set_value(1, 10);
        assert psc.get_total_sum() == 12;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(10), 1, 9);
        assert index_of_matches(psc.get_index_of(11), 2, 0);
    }
    for_both([1, 1, 1], check);
}

# --- insertValues ---

test "insertValues at beginning" {
    def check(psc: any) {
        psc.insert_values(0, [1, 2]);
        assert psc.get_total_sum() == 10;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 3;
        assert psc.get_prefix_sum(3) == 6;
        assert psc.get_prefix_sum(4) == 10;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(3), 2, 0);
    }
    for_both([3, 4], check);
}

test "insertValues at end" {
    def check(psc: any) {
        psc.insert_values(2, [3, 4]);
        assert psc.get_total_sum() == 10;
        assert psc.get_prefix_sum(3) == 6;
        assert psc.get_prefix_sum(4) == 10;
    }
    for_both([1, 2], check);
}

test "insertValues in the middle" {
    def check(psc: any) {
        psc.insert_values(1, [2, 3]);
        assert psc.get_total_sum() == 10;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 3;
        assert psc.get_prefix_sum(3) == 6;
        assert psc.get_prefix_sum(4) == 10;
    }
    for_both([1, 4], check);
}

test "insertValues with zeroes" {
    def check(psc: any) {
        psc.insert_values(1, [0, 0]);
        assert psc.get_total_sum() == 3;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 1;
        assert psc.get_prefix_sum(3) == 1;
        assert psc.get_prefix_sum(4) == 3;
    }
    for_both([1, 2], check);
}

test "insertValues into all-zeroes" {
    def check(psc: any) {
        psc.insert_values(1, [2, 3]);
        assert psc.get_total_sum() == 5;
        assert psc.get_prefix_sum(1) == 0;
        assert psc.get_prefix_sum(2) == 2;
        assert psc.get_prefix_sum(3) == 5;
        assert index_of_matches(psc.get_index_of(0), 1, 0);
        assert index_of_matches(psc.get_index_of(2), 2, 0);
        assert index_of_matches(psc.get_index_of(4), 2, 2);
    }
    for_both([0, 0, 0], check);
}

test "insertValues into empty computer" {
    def check(psc: any) {
        psc.insert_values(0, [5, 3]);
        assert psc.get_total_sum() == 8;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(4), 0, 4);
        assert index_of_matches(psc.get_index_of(5), 1, 0);
    }
    for_both([], check);
}

# --- removeValues ---

test "removeValues from beginning" {
    def check(psc: any) {
        psc.remove_values(0, 2);
        assert psc.get_total_sum() == 7;
        assert psc.get_prefix_sum(1) == 3;
        assert psc.get_prefix_sum(2) == 7;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(3), 1, 0);
    }
    for_both([1, 2, 3, 4], check);
}

test "removeValues from end" {
    def check(psc: any) {
        psc.remove_values(2, 2);
        assert psc.get_total_sum() == 3;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 3;
    }
    for_both([1, 2, 3, 4], check);
}

test "removeValues from the middle" {
    def check(psc: any) {
        psc.remove_values(1, 2);
        assert psc.get_total_sum() == 5;
        assert psc.get_prefix_sum(1) == 1;
        assert psc.get_prefix_sum(2) == 5;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(4), 1, 3);
    }
    for_both([1, 2, 3, 4], check);
}

test "removeValues all" {
    for_both([1, 2, 3], lambda (psc: any) {
        psc.remove_values(0, 3);
        assert psc.get_total_sum() == 0;
    });
}

test "removeValues single element" {
    def check(psc: any) {
        psc.remove_values(1, 1);
        assert psc.get_total_sum() == 20;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(5), 1, 0);
        assert index_of_matches(psc.get_index_of(19), 1, 14);
    }
    for_both([5, 10, 15], check);
}

test "removeValues zero-valued elements" {
    def check(psc: any) {
        psc.remove_values(0, 2);
        assert psc.get_total_sum() == 5;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(4), 0, 4);
    }
    for_both([0, 0, 5, 0, 0], check);
}

# --- combined operations ---

test "insert then remove" {
    def check(psc: any) {
        psc.insert_values(1, [10, 20]);
        assert psc.get_total_sum() == 36;
        psc.remove_values(1, 2);
        assert psc.get_total_sum() == 6;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(3), 2, 0);
    }
    for_both([1, 2, 3], check);
}

test "remove then insert at same position" {
    def check(psc: any) {
        psc.remove_values(1, 1);
        psc.insert_values(1, [5]);
        assert psc.get_total_sum() == 9;
        assert index_of_matches(psc.get_index_of(1), 1, 0);
        assert index_of_matches(psc.get_index_of(5), 1, 4);
        assert index_of_matches(psc.get_index_of(6), 2, 0);
    }
    for_both([1, 2, 3], check);
}

test "setValue then insert then remove" {
    def check(psc: any) {
        psc.set_value(0, 5);
        psc.insert_values(1, [10]);
        psc.remove_values(3, 1);
        # [5, 10, 1]
        assert psc.get_total_sum() == 16;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(4), 0, 4);
        assert index_of_matches(psc.get_index_of(5), 1, 0);
        assert index_of_matches(psc.get_index_of(14), 1, 9);
        assert index_of_matches(psc.get_index_of(15), 2, 0);
    }
    for_both([1, 1, 1], check);
}

test "multiple queries between mutations are consistent" {
    def check(psc: any) {
        assert psc.get_total_sum() == 10;
        assert index_of_matches(psc.get_index_of(0), 0, 0);

        psc.set_value(1, 0);
        assert psc.get_total_sum() == 7;
        assert index_of_matches(psc.get_index_of(2), 2, 0);

        psc.set_value(1, 3);
        assert psc.get_total_sum() == 10;
        assert index_of_matches(psc.get_index_of(2), 1, 0);
    }
    for_both([2, 3, 5], check);
}

# --- edge cases ---

test "large values" {
    def check(psc: any) {
        assert psc.get_total_sum() == 600;
        assert psc.get_prefix_sum(1) == 100;
        assert psc.get_prefix_sum(2) == 300;
        assert psc.get_prefix_sum(3) == 600;
        assert index_of_matches(psc.get_index_of(0), 0, 0);
        assert index_of_matches(psc.get_index_of(99), 0, 99);
        assert index_of_matches(psc.get_index_of(100), 1, 0);
        assert index_of_matches(psc.get_index_of(299), 1, 199);
        assert index_of_matches(psc.get_index_of(300), 2, 0);
        assert index_of_matches(psc.get_index_of(599), 2, 299);
    }
    for_both([100, 200, 300], check);
}

test "many elements" {
    def check(psc: any) {
        assert psc.get_total_sum() == 100;
        assert psc.get_prefix_sum(50) == 50;
        for i in range(100) {
            assert index_of_matches(psc.get_index_of(i), i, 0);
        }
    }
    for_both([1 for _ in range(100)], check);
}

test "many elements all zeroes" {
    def check(psc: any) {
        assert psc.get_total_sum() == 0;
        for i in range(101) {
            assert psc.get_prefix_sum(i) == 0;
        }
        assert index_of_matches(psc.get_index_of(0), 99, 0);
    }
    for_both([0 for _ in range(100)], check);
}

test "setValue between queries re-validates correctly" {
    def check(psc: any) {
        assert psc.get_total_sum() == 5;

        psc.set_value(2, 10);
        assert psc.get_total_sum() == 14;
        assert psc.get_prefix_sum(3) == 12;
        assert index_of_matches(psc.get_index_of(2), 2, 0);
        assert index_of_matches(psc.get_index_of(11), 2, 9);
        assert index_of_matches(psc.get_index_of(12), 3, 0);
        assert index_of_matches(psc.get_index_of(13), 4, 0);

        psc.set_value(0, 0);
        assert psc.get_total_sum() == 13;
        assert index_of_matches(psc.get_index_of(0), 1, 0);
    }
    for_both([1, 1, 1, 1, 1], check);
}
