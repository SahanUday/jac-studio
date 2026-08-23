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

import re;
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

def _get_eol_for_counts(default_eol: int, cr: int, lf: int, crlf: int) -> str {
    total_eol_count = cr + lf + crlf;
    total_cr_count = cr + crlf;
    if total_eol_count == 0 {
        return "\n" if default_eol == 1 else "\r\n";
    }
    if total_cr_count > total_eol_count / 2 {
        return "\r\n";
    }
    return "\n";
}

obj PieceTreeTextBufferFactory {
    has chunks: list[StringBuffer], bom: str, cr: int, lf: int, crlf: int,
        contains_rtl: bool, contains_unusual_line_terminators: bool, is_basic_ascii: bool,
        normalize_eol: bool;

    """`default_eol` is `DefaultEndOfLine.LF` (1) or `DefaultEndOfLine.CRLF` (2), from
    model_types.jac -- kept as a plain int here (not imported) since this function only ever
    compares it against the LF value, matching upstream's own narrow use."""
    def _get_eol(default_eol: int) -> str {
        return _get_eol_for_counts(default_eol, self.cr, self.lf, self.crlf);
    }

    def create(default_eol: int) -> PieceTreeTextBuffer {
        eol = self._get_eol(default_eol);
        chunks = self.chunks;

        if self.normalize_eol and (
            (eol == "\r\n" and (self.cr > 0 or self.lf > 0))
            or (eol == "\n" and (self.cr > 0 or self.crlf > 0))
        ) {
            i = 0;
            while i < len(chunks) {
                s = re.sub(r"\r\n|\r|\n", eol, chunks[i].buffer);
                new_line_start = create_line_starts(s);
                chunks[i] = StringBuffer(buffer=s, line_starts=new_line_start);
                i += 1;
            }
        }

        return PieceTreeTextBuffer(
            init_chunks=chunks, bom=self.bom, init_eol=eol,
            contains_rtl=self.contains_rtl,
            contains_unusual_line_terminators=self.contains_unusual_line_terminators,
            is_basic_ascii=self.is_basic_ascii, init_eol_normalized=self.normalize_eol
        );
    }

    def get_first_line_text(length_limit: int) -> str {
        lines = split_lines(self.chunks[0].buffer[0:length_limit]);
        return lines[0];
    }
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

    def postinit {
        self.chunks = [];
        self.bom = "";
        self.has_previous_char = False;
        self.previous_char = 0;
        self.cr = 0;
        self.lf = 0;
        self.crlf = 0;
        self.contains_rtl = False;
        self.contains_unusual_line_terminators = False;
        self.is_basic_ascii = True;
    }

    def accept_chunk(chunk: str) {
        if len(chunk) == 0 {
            return;
        }

        if len(self.chunks) == 0 and starts_with_utf8_bom(chunk) {
            self.bom = UTF8_BOM_CHARACTER;
            chunk = chunk[1:];
        }

        if len(chunk) == 0 {
            self._accept_chunk1(chunk, False);
            self.has_previous_char = False;
            self.previous_char = 0;
            return;
        }

        last_char = ord(chunk[-1]);
        if last_char == CARRIAGE_RETURN or (last_char >= 0xD800 and last_char <= 0xDBFF) {
            # last character is \r or a high surrogate => keep it back
            self._accept_chunk1(chunk[0:len(chunk) - 1], False);
            self.has_previous_char = True;
            self.previous_char = last_char;
        } else {
            self._accept_chunk1(chunk, False);
            self.has_previous_char = False;
            self.previous_char = last_char;
        }
    }

    def _accept_chunk1(chunk: str, allow_empty_strings: bool) {
        if not allow_empty_strings and len(chunk) == 0 {
            return;
        }

        if self.has_previous_char {
            self._accept_chunk2(chr(self.previous_char) + chunk);
        } else {
            self._accept_chunk2(chunk);
        }
    }

    def _accept_chunk2(chunk: str) {
        line_starts = create_line_starts_with_counts(chunk);

        self.chunks.append(StringBuffer(buffer=chunk, line_starts=line_starts.line_starts));
        self.cr += line_starts.cr;
        self.lf += line_starts.lf;
        self.crlf += line_starts.crlf;

        if not line_starts.is_basic_ascii {
            # this chunk contains non basic ASCII characters
            self.is_basic_ascii = False;
            if not self.contains_rtl {
                self.contains_rtl = text_contains_rtl(chunk);
            }
            if not self.contains_unusual_line_terminators {
                self.contains_unusual_line_terminators = text_contains_unusual_line_terminators(chunk);
            }
        }
    }

    def finish(normalize_eol: bool = True) -> PieceTreeTextBufferFactory {
        self._finish();
        return PieceTreeTextBufferFactory(
            chunks=self.chunks, bom=self.bom, cr=self.cr, lf=self.lf, crlf=self.crlf,
            contains_rtl=self.contains_rtl,
            contains_unusual_line_terminators=self.contains_unusual_line_terminators,
            is_basic_ascii=self.is_basic_ascii, normalize_eol=normalize_eol
        );
    }

    def _finish {
        if len(self.chunks) == 0 {
            self._accept_chunk1("", True);
        }

        if self.has_previous_char {
            self.has_previous_char = False;
            # recreate last chunk
            last_chunk = self.chunks[-1];
            last_chunk.buffer += chr(self.previous_char);
            new_line_starts = create_line_starts(last_chunk.buffer);
            last_chunk.line_starts = new_line_starts;
            if self.previous_char == CARRIAGE_RETURN {
                self.cr += 1;
            }
        }
    }
}
