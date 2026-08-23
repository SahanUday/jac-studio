"""PieceTreeTextBuffer: the ITextBuffer wrapper around PieceTreeBase, ported from VS Code's
pieceTreeTextBuffer.ts (src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeTextBuffer.ts).
Adds position-mapping edit operations (`apply_edits`), BOM/RTL/unusual-line-terminator bookkeeping,
EOL-preference-aware value reads, and a `get_piece_tree()` accessor -- everything a real editor
needs on top of the raw piece-tree data structure in piece_tree_base.jac (not touched by this
file; that module is owned by a parallel session adding search support to it).

`PieceTreeTextBufferBuilder`/`PieceTreeTextBufferFactory` (upstream's separate
pieceTreeTextBufferBuilder.ts) live in the sibling file piece_tree_text_buffer_builder.jac, not
here -- checked empirically (per the `2026-08-23-circular-import-degrades-native-lowering`
precedent from piece_tree_base.jac) whether this needs the same one-file merge: the dependency
here is one-directional (the builder's `PieceTreeTextBufferFactory.create()` constructs a
`PieceTreeTextBuffer`, but nothing in this file references anything from the builder), so there's
no two-way type cycle and `jac check` on both files shows no `Type is Unknown` interpreted-fallback
warnings -- two files is fine.

Deliberate scope cuts (documented, not silently dropped -- same pattern as
`interval_tree.jac`'s `set_options` cut):
- **Event/disposable machinery** (`Emitter`/`Event onDidChangeContent`, the `Disposable` base
  class, `_register`) is entirely upstream's workbench event-and-lifecycle system, not the
  buffer's own data or behavior -- this is a headless buffer at this phase, nothing in this
  project's editor core yet subscribes to content-change events, and wiring that in now would be
  speculative. `apply_edits` still returns the list of content changes it made (`ContentChange`),
  so a future event layer has something to fire from without needing to touch this file again.
- **Undo/redo bookkeeping** (`computeUndoEdits`, `IReverseSingleEditOperation`,
  `_getInverseEditRange(s)`, `ValidAnnotatedEditOperation`'s `identifier`/`_isTracked` fields) is
  cut from `apply_edits` -- this is squarely `textModel.ts`'s undo-stack construction, upstream's
  own comments frame it as producing operations "for undo", and `textModel.ts`'s non-DOM-facing
  subset is a separate, later translator target (see `docs/translator-strategy.md`'s priority
  list). Porting it here would mean guessing at a shape for `textModel.ts` concepts that don't
  exist in Jac yet, the same reasoning `interval_tree.jac` used to defer `setOptions()`.
- **`recordTrimAutoWhitespace`** (the auto-whitespace-trim-candidate tracking in upstream's
  `applyEdits`) is cut for the same reason -- it is an editor *typing-behavior* heuristic
  (candidate line numbers for a *later* edit to maybe strip), not buffer data, and depends on
  nothing this module owns.
- **`_reduceOperations`** (collapsing >=1000 edit operations into one, upstream's own comment
  frames it purely as an OOM-crash workaround for pathological formatter-generated edit counts,
  "not [about] correctness") is cut -- it also depends on `countEOL`/`TextChange`
  (core/textChange.ts, core/misc/eolCounter.ts), neither ported. `apply_edits` here processes
  every operation given to it; nothing in the ported test suite exercises >=1000 operations in one
  call.
- **`getRangeAt`/`getValueInRange`/`getValueLengthInRange`/`getCharacterCountInRange`/
  `getLineMinColumn`/`getLineMaxColumn`/`getLineFirstNonWhitespaceColumn`/
  `getLineLastNonWhitespaceColumn`** ARE ported below (real buffer-data operations, not event
  machinery) even though the ported test suite (see piece_tree_text_buffer_builder.test.jac)
  exercises the wrapper almost entirely through `.get_piece_tree()` and doesn't call most of these
  directly -- kept for API completeness/faithfulness per this module's own task scope, matching
  the project's practice of porting the module's real surface, not just what the ported tests
  happen to touch.

Idiom notes:
- `EndOfLinePreference` (upstream `const enum { TextDefined = 0, LF = 1, CRLF = 2 }`) is added to
  model_types.jac as plain int constants (`END_OF_LINE_PREFERENCE_*`), matching that file's own
  `DefaultEndOfLine` idiom.
- Upstream's `IValidatedEditOperation`/`ValidAnnotatedEditOperation` become `SingleEditOperation`
  (the caller-facing input: `range`, `text`, `force_move_markers`) and `ValidatedEditOperation`
  (the internal delta-encoded form with `sort_index`/`range_offset`/`range_length` computed) here
  -- stripped of the undo/tracking fields per the scope cut above. `IInternalModelContentChange`
  becomes `ContentChange`, the return type of `apply_edits`.
- `strings.isHighSurrogate`/`firstNonWhitespaceIndex`/`lastNonWhitespaceIndex` aren't in
  core/strings.jac (that file is deliberately narrow -- see its own docstring -- and none of its
  three callers before this file needed them); ported here instead as small private module-level
  helpers (`_is_high_surrogate`, `_first_non_whitespace_index`, `_last_non_whitespace_index`)
  since each is a few lines and each has exactly one caller in this file.
- Upstream's `PieceTreeTextBuffer._sortOpsAscending`/`_sortOpsDescending` (each a 2-argument
  comparator passed to `Array.prototype.sort`) become `_sort_ops_ascending`/`_sort_ops_descending`,
  each a self-contained stable insertion sort over the (always small, per real editor usage and
  every ported test) operations list -- avoids depending on whether Jac's `list.sort`/`sorted`
  accept a plain module-level function value as a comparator (untested in this project; the one
  existing precedent, `interval_tree.test.jac`, only uses a `lambda` *key* function, not a
  two-argument comparator), so this sidesteps that open question entirely rather than assuming an
  answer.
"""

import from src.editor.model.piece_tree_base { PieceTreeBase, PieceTreeSnapshot, StringBuffer }
import from src.editor.model.model_types {
    END_OF_LINE_PREFERENCE_TEXT_DEFINED, END_OF_LINE_PREFERENCE_LF, END_OF_LINE_PREFERENCE_CRLF
}
import from src.editor.core.position { Position }
import from src.editor.core.range { Range }
import from src.editor.core.char_code { TAB }

def _is_high_surrogate(ch_code: int) -> bool {
    return ch_code >= 0xD800 and ch_code <= 0xDBFF;
}

"""Index of the first non-space/non-tab character in `s`, or -1 if `s` is all whitespace (or
empty). Ported from strings.ts's `firstNonWhitespaceIndex`."""
def _first_non_whitespace_index(s: str) -> int {
    i = 0;
    length = len(s);
    while i < length {
        ch_code = ord(s[i]);
        if ch_code != 32 and ch_code != TAB {
            return i;
        }
        i += 1;
    }
    return -1;
}

"""Index of the last non-space/non-tab character in `s`, or -1 if `s` is all whitespace (or
empty). Ported from strings.ts's `lastNonWhitespaceIndex` (default `startIndex` only -- this
file's one caller never passes a custom start)."""
def _last_non_whitespace_index(s: str) -> int {
    i = len(s) - 1;
    while i >= 0 {
        ch_code = ord(s[i]);
        if ch_code != 32 and ch_code != TAB {
            return i;
        }
        i -= 1;
    }
    return -1;
}

"""A single caller-supplied edit: replace `range` with `text`. Ported from upstream's
`ISingleEditOperation`/`ValidAnnotatedEditOperation`, stripped of the undo/tracking-identifier
fields (see this file's top docstring)."""
obj SingleEditOperation {
    has range: Range, text: str, force_move_markers: bool = False;
}

"""An edit operation after position-mapping (offset/length computed against the buffer) and
sort-index assignment, matching upstream's `IValidatedEditOperation` minus the undo/tracking
fields."""
obj ValidatedEditOperation {
    has sort_index: int, range: Range, range_offset: int, range_length: int, text: str,
        force_move_markers: bool;
}

"""One applied edit's effect, matching upstream's `IInternalModelContentChange` minus its
`isRedoing`/`isUndoing`/`isFlush` fields (those are `textModel.ts` undo-stack concerns, not this
buffer's own data -- see this file's scope-cut docstring note)."""
obj ContentChange {
    has range: Range, range_length: int, text: str, range_offset: int, force_move_markers: bool;
}

def _compare_ops_ascending(a: ValidatedEditOperation, b: ValidatedEditOperation) -> int {
    r = Range.compare_ranges_using_ends(a.range, b.range);
    if r != 0 {
        return r;
    }
    return a.sort_index - b.sort_index;
}

def _compare_ops_descending(a: ValidatedEditOperation, b: ValidatedEditOperation) -> int {
    r = Range.compare_ranges_using_ends(a.range, b.range);
    if r != 0 {
        return -r;
    }
    return b.sort_index - a.sort_index;
}

def _sort_ops_ascending(operations: list[ValidatedEditOperation]) -> list[ValidatedEditOperation] {
    result: list[ValidatedEditOperation] = operations[:];
    i = 1;
    while i < len(result) {
        key = result[i];
        j = i - 1;
        while j >= 0 and _compare_ops_ascending(result[j], key) > 0 {
            result[j + 1] = result[j];
            j -= 1;
        }
        result[j + 1] = key;
        i += 1;
    }
    return result;
}

def _sort_ops_descending(operations: list[ValidatedEditOperation]) -> list[ValidatedEditOperation] {
    result: list[ValidatedEditOperation] = operations[:];
    i = 1;
    while i < len(result) {
        key = result[i];
        j = i - 1;
        while j >= 0 and _compare_ops_descending(result[j], key) > 0 {
            result[j + 1] = result[j];
            j -= 1;
        }
        result[j + 1] = key;
        i += 1;
    }
    return result;
}

obj PieceTreeTextBuffer {
    has init_chunks: list[StringBuffer], bom: str, init_eol: str,
        contains_rtl: bool, contains_unusual_line_terminators: bool, is_basic_ascii: bool,
        init_eol_normalized: bool;

    has piece_tree: PieceTreeBase postinit;

    def postinit {
        self.piece_tree = PieceTreeBase(
            init_chunks=self.init_chunks, init_eol=self.init_eol,
            init_eol_normalized=self.init_eol_normalized
        );
    }

    # region TextBuffer
    def equal(other: PieceTreeTextBuffer) -> bool {
        if self.bom != other.bom {
            return False;
        }
        if self.get_eol() != other.get_eol() {
            return False;
        }
        return self.piece_tree.equal(other.piece_tree);
    }

    def might_contain_rtl -> bool {
        return self.contains_rtl;
    }

    def might_contain_unusual_line_terminators -> bool {
        return self.contains_unusual_line_terminators;
    }

    def reset_might_contain_unusual_line_terminators {
        self.contains_unusual_line_terminators = False;
    }

    def might_contain_non_basic_ascii -> bool {
        return not self.is_basic_ascii;
    }

    def get_bom -> str {
        return self.bom;
    }

    def get_eol -> str {
        return self.piece_tree.get_eol();
    }

    def create_snapshot(preserve_bom: bool) -> PieceTreeSnapshot {
        return self.piece_tree.create_snapshot(self.bom if preserve_bom else "");
    }

    def get_offset_at(line_number: int, column: int) -> int {
        return self.piece_tree.get_offset_at(line_number, column);
    }

    def get_position_at(offset: int) -> Position {
        return self.piece_tree.get_position_at(offset);
    }

    def get_range_at(start: int, length: int) -> Range {
        end = start + length;
        start_position = self.get_position_at(start);
        end_position = self.get_position_at(end);
        return Range(
            start_line_number=start_position.line_number, start_column=start_position.column,
            end_line_number=end_position.line_number, end_column=end_position.column
        );
    }

    def get_value_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> str {
        if rng.is_empty() {
            return "";
        }
        line_ending = self._get_end_of_line(eol);
        return self.piece_tree.get_value_in_range(rng, line_ending);
    }

    def get_value_length_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int {
        if rng.is_empty() {
            return 0;
        }
        if rng.start_line_number == rng.end_line_number {
            return rng.end_column - rng.start_column;
        }

        start_offset = self.get_offset_at(rng.start_line_number, rng.start_column);
        end_offset = self.get_offset_at(rng.end_line_number, rng.end_column);

        eol_offset_compensation = 0;
        desired_eol = self._get_end_of_line(eol);
        actual_eol = self.get_eol();
        if len(desired_eol) != len(actual_eol) {
            delta = len(desired_eol) - len(actual_eol);
            eol_count = rng.end_line_number - rng.start_line_number;
            eol_offset_compensation = delta * eol_count;
        }

        return end_offset - start_offset + eol_offset_compensation;
    }

    def get_character_count_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int {
        if self.might_contain_non_basic_ascii() {
            result = 0;
            from_line_number = rng.start_line_number;
            to_line_number = rng.end_line_number;
            line_number = from_line_number;
            while line_number <= to_line_number {
                line_content = self.get_line_content(line_number);
                from_offset = (rng.start_column - 1) if line_number == from_line_number else 0;
                to_offset = (rng.end_column - 1) if line_number == to_line_number else len(line_content);

                offset = from_offset;
                while offset < to_offset {
                    if _is_high_surrogate(ord(line_content[offset])) {
                        result += 1;
                        offset += 1;
                    } else {
                        result += 1;
                    }
                    offset += 1;
                }
                line_number += 1;
            }

            result += len(self._get_end_of_line(eol)) * (to_line_number - from_line_number);
            return result;
        }

        return self.get_value_length_in_range(rng, eol);
    }

    def get_nearest_chunk(offset: int) -> str {
        return self.piece_tree.get_nearest_chunk(offset);
    }

    def get_length -> int {
        return self.piece_tree.get_length();
    }

    def get_line_count -> int {
        return self.piece_tree.get_line_count();
    }

    def get_lines_content -> list[str] {
        return self.piece_tree.get_lines_content();
    }

    def get_line_content(line_number: int) -> str {
        return self.piece_tree.get_line_content(line_number);
    }

    def get_line_char_code(line_number: int, index: int) -> int {
        return self.piece_tree.get_line_char_code(line_number, index);
    }

    def get_char_code(offset: int) -> int {
        return self.piece_tree.get_char_code(offset);
    }

    def get_line_length(line_number: int) -> int {
        return self.piece_tree.get_line_length(line_number);
    }

    def get_line_min_column(line_number: int) -> int {
        return 1;
    }

    def get_line_max_column(line_number: int) -> int {
        return self.get_line_length(line_number) + 1;
    }

    def get_line_first_non_whitespace_column(line_number: int) -> int {
        result = _first_non_whitespace_index(self.get_line_content(line_number));
        if result == -1 {
            return 0;
        }
        return result + 1;
    }

    def get_line_last_non_whitespace_column(line_number: int) -> int {
        result = _last_non_whitespace_index(self.get_line_content(line_number));
        if result == -1 {
            return 0;
        }
        return result + 2;
    }

    def _get_end_of_line(eol: int) -> str {
        if eol == END_OF_LINE_PREFERENCE_LF {
            return "\n";
        } elif eol == END_OF_LINE_PREFERENCE_CRLF {
            return "\r\n";
        } elif eol == END_OF_LINE_PREFERENCE_TEXT_DEFINED {
            return self.get_eol();
        } else {
            raise ValueError("Unknown EOL preference");
        }
    }

    def set_eol(new_eol: str) {
        self.piece_tree.set_eol(new_eol);
    }

    """Apply a batch of edits (position-mapped against the current buffer, sorted, then applied
    bottom-to-top so earlier offsets stay valid), returning the list of content changes made.
    Ported from upstream's `applyEdits`, minus the undo/trim-whitespace/OOM-reduction/event-firing
    machinery documented as cut at the top of this file."""
    def apply_edits(raw_operations: list[SingleEditOperation]) -> list[ContentChange] {
        operations: list[ValidatedEditOperation] = [];
        i = 0;
        while i < len(raw_operations) {
            op = raw_operations[i];
            range_offset = self.get_offset_at(op.range.start_line_number, op.range.start_column);
            range_length = self.get_value_length_in_range(op.range);
            operations.append(ValidatedEditOperation(
                sort_index=i, range=op.range, range_offset=range_offset, range_length=range_length,
                text=op.text, force_move_markers=op.force_move_markers
            ));
            i += 1;
        }

        operations = _sort_ops_ascending(operations);

        j = 0;
        while j < len(operations) - 1 {
            range_end = operations[j].range.get_end_position();
            next_range_start = operations[j + 1].range.get_start_position();
            if next_range_start.is_before(range_end) {
                raise ValueError("Overlapping ranges are not allowed!");
            }
            j += 1;
        }

        return self._do_apply_edits(operations);
    }

    def _do_apply_edits(operations: list[ValidatedEditOperation]) -> list[ContentChange] {
        descending = _sort_ops_descending(operations);
        content_changes: list[ContentChange] = [];

        i = 0;
        while i < len(descending) {
            op = descending[i];
            start_line_number = op.range.start_line_number;
            start_column = op.range.start_column;
            end_line_number = op.range.end_line_number;
            end_column = op.range.end_column;

            if start_line_number == end_line_number and start_column == end_column and len(op.text) == 0 {
                i += 1;
                continue;
            }

            if len(op.text) > 0 {
                self.piece_tree.delete(op.range_offset, op.range_length);
                self.piece_tree.insert(op.range_offset, op.text, True);
            } else {
                self.piece_tree.delete(op.range_offset, op.range_length);
            }

            content_change_range = Range(
                start_line_number=start_line_number, start_column=start_column,
                end_line_number=end_line_number, end_column=end_column
            );
            content_changes.append(ContentChange(
                range=content_change_range, range_length=op.range_length, text=op.text,
                range_offset=op.range_offset, force_move_markers=op.force_move_markers
            ));
            i += 1;
        }

        return content_changes;
    }
    # endregion

    # region helper (testing purpose, mirrors upstream)
    def get_piece_tree -> PieceTreeBase {
        return self.piece_tree;
    }
    # endregion
}
