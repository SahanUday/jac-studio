"""Line/offset prefix-sum arithmetic, ported from VS Code's prefixSumComputer.ts
(src/vs/editor/common/model/prefixSumComputer.ts).

Two implementations, both kept (as upstream does). They are NOT interchangeable as-is, faithfully
preserving a real upstream asymmetry, not a translation gap: `PrefixSumComputer`'s mutators
(`insert_values`/`remove_values`/`set_value`) return `bool` and clamp inputs via `to_uint32`;
`ConstantTimePrefixSumComputer`'s equivalents return nothing and do no clamping -- exactly matching
`prefixSumComputer.ts`'s real signatures (`boolean` + `toUint32` on one class, bare `void` and no
clamping on the other). The ported test file's `_PrefixSumComputerAsCount` wrapper is what
reconciles them into one shared shape for testing, mirroring upstream's own `IPrefixSumComputer`
adapter -- it is not evidence the two classes share an interface on their own.
`PrefixSumComputer` is lazy-invalidation with O(log n) `get_index_of` via binary search;
`ConstantTimePrefixSumComputer` trades memory for O(1) amortized `get_index_of` via an eager
value-to-index lookup table.

Idiom notes (see docs/translator-strategy.md): upstream's `prefixSumValidIndex: Int32Array` is a
1-element array used purely as a mutable box, a TS workaround for lack of pass-by-reference on
primitives -- ported as a plain `int` field here, since Jac always mutates `self.` fields directly.
Upstream's `Uint32Array`/`number[]` become plain `list[int]`; the `toUint32` clamp (from
base/common/uint.ts) is inlined below since it's a one-line dependency, not translated separately.
`get_index_of`'s `sum` parameter is typed `int`, not `number` -- upstream's `Math.floor(sum)` is
therefore a no-op and dropped; every real caller (and the whole ported test suite) only ever
passes integers. `PrefixSumComputer.get_prefix_sum` guards the empty-`values` case explicitly
(upstream relies on a JS array returning `undefined` rather than throwing on an out-of-range
index; a Jac `list` raises `IndexError` instead, so the same degenerate input needs an explicit
guard here to avoid a crash a caller outside the ported test wrapper could actually hit).
"""

def to_uint32(value: int) -> int {
    if value < 0 {
        return 0;
    }
    if value > 4294967295 {
        return 4294967295;
    }
    return value;
}

obj PrefixSumIndexOfResult {
    has index: int, remainder: int;
}

obj PrefixSumComputer {
    has values: list[int];
    has prefix_sum: list[int] postinit;
    has prefix_sum_valid_index: int postinit;

    def postinit {
        self.prefix_sum = [0 for _ in self.values];
        self.prefix_sum_valid_index = -1;
    }

    def get_count -> int {
        return len(self.values);
    }

    def insert_values(insert_index: int, insert_values: list[int]) -> bool {
        insert_index = to_uint32(insert_index);
        old_values = self.values;
        old_prefix_sum = self.prefix_sum;
        insert_len = len(insert_values);

        if insert_len == 0 {
            return False;
        }

        self.values = old_values[:insert_index] + insert_values + old_values[insert_index:];

        if insert_index - 1 < self.prefix_sum_valid_index {
            self.prefix_sum_valid_index = insert_index - 1;
        }

        self.prefix_sum = [0 for _ in self.values];
        if self.prefix_sum_valid_index >= 0 {
            keep = self.prefix_sum_valid_index + 1;
            self.prefix_sum[:keep] = old_prefix_sum[:keep];
        }
        return True;
    }

    def set_value(index: int, value: int) -> bool {
        index = to_uint32(index);
        value = to_uint32(value);

        if self.values[index] == value {
            return False;
        }
        self.values[index] = value;
        if index - 1 < self.prefix_sum_valid_index {
            self.prefix_sum_valid_index = index - 1;
        }
        return True;
    }

    def remove_values(start_index: int, count: int) -> bool {
        start_index = to_uint32(start_index);
        count = to_uint32(count);

        old_values = self.values;
        old_prefix_sum = self.prefix_sum;

        if start_index >= len(old_values) {
            return False;
        }

        max_count = len(old_values) - start_index;
        if count >= max_count {
            count = max_count;
        }

        if count == 0 {
            return False;
        }

        self.values = old_values[:start_index] + old_values[start_index + count:];

        self.prefix_sum = [0 for _ in self.values];
        if start_index - 1 < self.prefix_sum_valid_index {
            self.prefix_sum_valid_index = start_index - 1;
        }
        if self.prefix_sum_valid_index >= 0 {
            keep = self.prefix_sum_valid_index + 1;
            self.prefix_sum[:keep] = old_prefix_sum[:keep];
        }
        return True;
    }

    def get_total_sum -> int {
        if len(self.values) == 0 {
            return 0;
        }
        return self._get_prefix_sum(len(self.values) - 1);
    }

    def get_prefix_sum(index: int) -> int {
        if index < 0 or len(self.values) == 0 {
            return 0;
        }
        index = to_uint32(index);
        return self._get_prefix_sum(index);
    }

    def _get_prefix_sum(index: int) -> int {
        if index <= self.prefix_sum_valid_index {
            return self.prefix_sum[index];
        }

        start_index = self.prefix_sum_valid_index + 1;
        if start_index == 0 {
            self.prefix_sum[0] = self.values[0];
            start_index += 1;
        }

        if index >= len(self.values) {
            index = len(self.values) - 1;
        }

        for i in range(start_index, index + 1) {
            self.prefix_sum[i] = self.prefix_sum[i - 1] + self.values[i];
        }
        self.prefix_sum_valid_index = max(self.prefix_sum_valid_index, index);
        return self.prefix_sum[index];
    }

    def get_index_of(target_sum: int) -> PrefixSumIndexOfResult {
        self.get_total_sum();

        low = 0;
        high = len(self.values) - 1;
        mid = 0;
        mid_stop = 0;
        mid_start = 0;

        while low <= high {
            mid = low + (high - low) // 2;

            mid_stop = self.prefix_sum[mid];
            mid_start = mid_stop - self.values[mid];

            if target_sum < mid_start {
                high = mid - 1;
            } elif target_sum >= mid_stop {
                low = mid + 1;
            } else {
                break;
            }
        }

        return PrefixSumIndexOfResult(index=mid, remainder=target_sum - mid_start);
    }
}

obj ConstantTimePrefixSumComputer {
    has values: list[int];
    has _is_valid: bool postinit;
    has _valid_end_index: int postinit;
    has _prefix_sum: list[int] postinit;
    has _index_by_sum: list[int] postinit;

    def postinit {
        self._is_valid = False;
        self._valid_end_index = -1;
        self._prefix_sum = [];
        self._index_by_sum = [];
    }

    def get_total_sum -> int {
        self._ensure_valid();
        return len(self._index_by_sum);
    }

    def get_prefix_sum(count: int) -> int {
        self._ensure_valid();
        if count == 0 {
            return 0;
        }
        return self._prefix_sum[count - 1];
    }

    def get_index_of(target_sum: int) -> PrefixSumIndexOfResult {
        self._ensure_valid();
        idx = self._index_by_sum[target_sum] if (
            target_sum >= 0 and target_sum < len(self._index_by_sum)
        ) else None;

        if idx is None {
            last_idx = max(0, len(self.values) - 1);
            last_prefix_sum = self._prefix_sum[last_idx - 1] if last_idx > 0 else 0;
            return PrefixSumIndexOfResult(index=last_idx, remainder=target_sum - last_prefix_sum);
        }
        view_lines_above = self._prefix_sum[idx - 1] if idx > 0 else 0;
        return PrefixSumIndexOfResult(index=idx, remainder=target_sum - view_lines_above);
    }

    def remove_values(start: int, delete_count: int) {
        self.values = self.values[:start] + self.values[start + delete_count:];
        self._invalidate(start);
    }

    def insert_values(insert_index: int, insert_arr: list[int]) {
        self.values = self.values[:insert_index] + insert_arr + self.values[insert_index:];
        self._invalidate(insert_index);
    }

    def _invalidate(index: int) {
        self._is_valid = False;
        self._valid_end_index = min(self._valid_end_index, index - 1);
    }

    def _ensure_valid {
        if self._is_valid {
            return;
        }

        length = len(self.values);
        for i in range(self._valid_end_index + 1, length) {
            value = self.values[i];
            sum_above = self._prefix_sum[i - 1] if i > 0 else 0;

            if i < len(self._prefix_sum) {
                self._prefix_sum[i] = sum_above + value;
            } else {
                self._prefix_sum.append(sum_above + value);
            }

            for j in range(value) {
                idx_key = sum_above + j;
                if idx_key < len(self._index_by_sum) {
                    self._index_by_sum[idx_key] = i;
                } else {
                    self._index_by_sum.append(i);
                }
            }
        }

        self._prefix_sum = self._prefix_sum[:length];
        total = self._prefix_sum[length - 1] if length > 0 else 0;
        self._index_by_sum = self._index_by_sum[:total];

        self._is_valid = True;
        self._valid_end_index = length - 1;
    }

    def set_value(index: int, value: int) {
        if self.values[index] == value {
            return;
        }
        self.values[index] = value;
        self._invalidate(index);
    }
}
