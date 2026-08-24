"""PieceTreeTextBufferBuilder / PieceTreeTextBufferFactory, ported from VS Code's
pieceTreeTextBufferBuilder.ts (src/vs/editor/common/model/pieceTreeTextBuffer/
pieceTreeTextBufferBuilder.ts). The chunk-accumulation front end that every real text buffer gets
built through: streams chunks in (`accept_chunk`), strips a leading UTF-8 BOM, holds back a
trailing `\r` or high surrogate so a chunk boundary never splits a CRLF pair or a surrogate pair,
tracks cr/lf/crlf counts for EOL auto-detection, and flags RTL / unusual-line-terminator content --
then `finish()` freezes that into a `PieceTreeTextBufferFactory` whose `create()` produces the
actual `PieceTreeTextBuffer` (piece_tree_text_buffer.jac, this file's one dependency -- see that
file's own docstring for why the two-file split is safe here, unlike piece_tree_base.jac's merge).

Deliberate scope cut: `create()` upstream returns `{ textBuffer, disposable }` (the buffer doubles
as its own `IDisposable`); since piece_tree_text_buffer.jac already cuts the Disposable/event
machinery entirely (documented there), `create()` here just returns the `PieceTreeTextBuffer`
directly.

Idiom notes:
- Upstream's two-argument, reused-scratch-array `createLineStarts(tmpLineStarts, chunk)` overload
  (a V8 allocation micro-optimization, distinct from the also-named-`createLineStarts`
  no-args-reused single-string form) is not reproduced -- `create_line_starts_with_counts` from
  piece_tree_base.jac (the counting variant this builder actually needs) always returns a fresh
  list, matching that file's own documented decision to drop the reused-typed-array optimization
  project-wide (see its top docstring).
- `String.fromCharCode(previousChar)` (re-materializing a held-back trailing `\r` or lone high
  surrogate) becomes `chr(self.previous_char)` -- Python `str`/`chr()` permits lone surrogate
  codepoints as ordinary string content (this never gets encoded to UTF-8 anywhere in this
  module), matching the same `chr()`-not-literal idiom core/strings.jac already uses for
  `UTF8_BOM_CHARACTER` to sidestep the supplementary-plane-string-literal compiler crash (see that
  file's docstring and `2026-08-23-supplementary-plane-string-crashes-js-codegen`) -- not relevant
  to a lone *surrogate* specifically, but the same "build the string at runtime via `chr()`, never
  write it as a source literal" habit applies.
- `_accept_chunk1`/`_accept_chunk2`/`_finish` are ported as literal 1:1 control-flow translations
  of upstream, including the `_hasPreviousChar` flag's non-reset inside `_acceptChunk1` -- a
  faithful port reproduces upstream's exact (possibly surprising) behavior for a degenerate input
  stream that never pushes a real chunk before `finish()`, rather than guessing at a "fixed"
  version; parity with upstream's own test suite is the goal, not second-guessing it.
"""

import from src.editor.model.piece_tree_base {
    StringBuffer, create_line_starts, create_line_starts_with_counts
}
import from src.editor.model.piece_tree_text_buffer { PieceTreeTextBuffer }
import from src.editor.core.char_code { CARRIAGE_RETURN }
import from src.editor.core.strings {
    starts_with_utf8_bom, UTF8_BOM_CHARACTER,
    contains_rtl as text_contains_rtl, contains_unusual_line_terminators as text_contains_unusual_line_terminators,
    split_lines
}

obj PieceTreeTextBufferFactory {
    has chunks: list[StringBuffer], bom: str, cr: int, lf: int, crlf: int,
        contains_rtl: bool, contains_unusual_line_terminators: bool, is_basic_ascii: bool,
        normalize_eol: bool;

    """`default_eol` is `DefaultEndOfLine.LF` (1) or `DefaultEndOfLine.CRLF` (2), from
    model_types.jac -- kept as a plain int here (not imported) since this function only ever
    compares it against the LF value, matching upstream's own narrow use."""
    def _get_eol(default_eol: int) -> str;

    def create(default_eol: int) -> PieceTreeTextBuffer;
    def get_first_line_text(length_limit: int) -> str;
}

obj PieceTreeTextBufferBuilder {
    has chunks: list[StringBuffer] postinit;
    has bom: str postinit;
    has has_previous_char: bool postinit;
    has previous_char: int postinit;
    has cr: int postinit;
    has lf: int postinit;
    has crlf: int postinit;
    has contains_rtl: bool postinit;
    has contains_unusual_line_terminators: bool postinit;
    has is_basic_ascii: bool postinit;

    def postinit -> None;
    def accept_chunk(chunk: str) -> None;
    def _accept_chunk1(chunk: str, allow_empty_strings: bool) -> None;
    def _accept_chunk2(chunk: str) -> None;
    def finish(normalize_eol: bool = True) -> PieceTreeTextBufferFactory;
    def _finish -> None;
}
