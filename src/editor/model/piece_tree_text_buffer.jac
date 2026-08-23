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
  three callers before this file needed them); ported in the impl file instead as small private
  module-level helpers (`_is_high_surrogate`, `_first_non_whitespace_index`,
  `_last_non_whitespace_index`) since each is a few lines and each has exactly one caller in this
  file.
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

obj PieceTreeTextBuffer {
    has init_chunks: list[StringBuffer], bom: str, init_eol: str,
        contains_rtl: bool, contains_unusual_line_terminators: bool, is_basic_ascii: bool,
        init_eol_normalized: bool;

    has piece_tree: PieceTreeBase postinit;

    def postinit -> None;

    # region TextBuffer
    def equal(other: PieceTreeTextBuffer) -> bool;
    def might_contain_rtl -> bool;
    def might_contain_unusual_line_terminators -> bool;
    def reset_might_contain_unusual_line_terminators -> None;
    def might_contain_non_basic_ascii -> bool;
    def get_bom -> str;
    def get_eol -> str;
    def create_snapshot(preserve_bom: bool) -> PieceTreeSnapshot;
    def get_offset_at(line_number: int, column: int) -> int;
    def get_position_at(offset: int) -> Position;
    def get_range_at(start: int, length: int) -> Range;
    def get_value_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> str;
    def get_value_length_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int;
    def get_character_count_in_range(rng: Range, eol: int = END_OF_LINE_PREFERENCE_TEXT_DEFINED) -> int;
    def get_nearest_chunk(offset: int) -> str;
    def get_length -> int;
    def get_line_count -> int;
    def get_lines_content -> list[str];
    def get_line_content(line_number: int) -> str;
    def get_line_char_code(line_number: int, index: int) -> int;
    def get_char_code(offset: int) -> int;
    def get_line_length(line_number: int) -> int;
    def get_line_min_column(line_number: int) -> int;
    def get_line_max_column(line_number: int) -> int;
    def get_line_first_non_whitespace_column(line_number: int) -> int;
    def get_line_last_non_whitespace_column(line_number: int) -> int;
    def _get_end_of_line(eol: int) -> str;
    def set_eol(new_eol: str) -> None;

    """Apply a batch of edits (position-mapped against the current buffer, sorted, then applied
    bottom-to-top so earlier offsets stay valid), returning the list of content changes made.
    Ported from upstream's `applyEdits`, minus the undo/trim-whitespace/OOM-reduction/event-firing
    machinery documented as cut at the top of this file."""
    def apply_edits(raw_operations: list[SingleEditOperation]) -> list[ContentChange];

    def _do_apply_edits(operations: list[ValidatedEditOperation]) -> list[ContentChange];
    # endregion

    # region helper (testing purpose, mirrors upstream)
    def get_piece_tree -> PieceTreeBase;
    # endregion
}
