def _to_uint32(value: int) -> int {
    if value < 0 {
        return 0;
    }
    if value > 4294967295 {
        return 4294967295;
    }
    return value;
}

impl PrefixSumComputer.postinit -> None {
    self.prefix_sum = [0 for _ in self.values];
    self.prefix_sum_valid_index = -1;
}

impl PrefixSumComputer.get_count -> int {
    return len(self.values);
}

impl PrefixSumComputer.insert_values(insert_index: int, insert_values: list[int]) -> bool {
    insert_index = _to_uint32(insert_index);
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

impl PrefixSumComputer.set_value(index: int, value: int) -> bool {
    index = _to_uint32(index);
    value = _to_uint32(value);

    if self.values[index] == value {
        return False;
    }
    self.values[index] = value;
    if index - 1 < self.prefix_sum_valid_index {
        self.prefix_sum_valid_index = index - 1;
    }
    return True;
}

impl PrefixSumComputer.remove_values(start_index: int, count: int) -> bool {
    start_index = _to_uint32(start_index);
    count = _to_uint32(count);

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

impl PrefixSumComputer.get_total_sum -> int {
    if len(self.values) == 0 {
        return 0;
    }
    return self._get_prefix_sum(len(self.values) - 1);
}

impl PrefixSumComputer.get_prefix_sum(index: int) -> int {
    if index < 0 or len(self.values) == 0 {
        return 0;
    }
    index = _to_uint32(index);
    return self._get_prefix_sum(index);
}

impl PrefixSumComputer._get_prefix_sum(index: int) -> int {
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

impl PrefixSumComputer.get_index_of(target_sum: int) -> PrefixSumIndexOfResult {
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

impl ConstantTimePrefixSumComputer.postinit -> None {
    self._is_valid = False;
    self._valid_end_index = -1;
    self._prefix_sum = [];
    self._index_by_sum = [];
}

impl ConstantTimePrefixSumComputer.get_total_sum -> int {
    self._ensure_valid();
    return len(self._index_by_sum);
}

impl ConstantTimePrefixSumComputer.get_prefix_sum(count: int) -> int {
    self._ensure_valid();
    if count == 0 {
        return 0;
    }
    return self._prefix_sum[count - 1];
}

impl ConstantTimePrefixSumComputer.get_index_of(target_sum: int) -> PrefixSumIndexOfResult {
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

impl ConstantTimePrefixSumComputer.remove_values(start: int, delete_count: int) -> None {
    self.values = self.values[:start] + self.values[start + delete_count:];
    self._invalidate(start);
}

impl ConstantTimePrefixSumComputer.insert_values(insert_index: int, insert_arr: list[int]) -> None {
    self.values = self.values[:insert_index] + insert_arr + self.values[insert_index:];
    self._invalidate(insert_index);
}

impl ConstantTimePrefixSumComputer._invalidate(index: int) -> None {
    self._is_valid = False;
    self._valid_end_index = min(self._valid_end_index, index - 1);
}

impl ConstantTimePrefixSumComputer._ensure_valid -> None {
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

impl ConstantTimePrefixSumComputer.set_value(index: int, value: int) -> None {
    if self.values[index] == value {
        return;
    }
    self.values[index] = value;
    self._invalidate(index);
}
