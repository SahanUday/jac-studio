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
base/common/uint.ts) is inlined in the impl file since it's a one-line dependency, not translated
separately. `get_index_of`'s `sum` parameter is typed `int`, not `number` -- upstream's
`Math.floor(sum)` is therefore a no-op and dropped; every real caller (and the whole ported test
suite) only ever passes integers. `PrefixSumComputer.get_prefix_sum` guards the empty-`values` case
explicitly (upstream relies on a JS array returning `undefined` rather than throwing on an
out-of-range index; a Jac `list` raises `IndexError` instead, so the same degenerate input needs an
explicit guard here to avoid a crash a caller outside the ported test wrapper could actually hit).
"""

obj PrefixSumIndexOfResult {
    has index: int, remainder: int;
}

obj PrefixSumComputer {
    has values: list[int];
    has prefix_sum: list[int] postinit;
    has prefix_sum_valid_index: int postinit;

    def postinit -> None;
    def get_count -> int;
    def insert_values(insert_index: int, insert_values: list[int]) -> bool;
    def set_value(index: int, value: int) -> bool;
    def remove_values(start_index: int, count: int) -> bool;
    def get_total_sum -> int;
    def get_prefix_sum(index: int) -> int;
    def _get_prefix_sum(index: int) -> int;
    def get_index_of(target_sum: int) -> PrefixSumIndexOfResult;
}

obj ConstantTimePrefixSumComputer {
    has values: list[int];
    has _is_valid: bool postinit;
    has _valid_end_index: int postinit;
    has _prefix_sum: list[int] postinit;
    has _index_by_sum: list[int] postinit;

    def postinit -> None;
    def get_total_sum -> int;
    def get_prefix_sum(count: int) -> int;
    def get_index_of(target_sum: int) -> PrefixSumIndexOfResult;
    def remove_values(start: int, delete_count: int) -> None;
    def insert_values(insert_index: int, insert_arr: list[int]) -> None;
    def _invalidate(index: int) -> None;
    def _ensure_valid -> None;
    def set_value(index: int, value: int) -> None;
}
