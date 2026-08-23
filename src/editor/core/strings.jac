"""A handful of small string utilities, ported from VS Code's strings.ts
(src/vs/base/common/strings.ts). That file is 1421 lines covering a huge surface (word
boundaries, grapheme handling, string builders, etc.) almost none of which the piece-tree needs;
only the pieces below are actually used -- `split_lines` by the piece-tree's own ported test file,
and `contains_rtl`/`contains_unusual_line_terminators`/`starts_with_utf8_bom`/
`UTF8_BOM_CHARACTER` by `PieceTreeTextBufferBuilder` (see piece_tree_text_buffer.jac) to classify
each accepted chunk during construction -- so this file stays a narrow, well-tested set of
utilities rather than a partial port of the rest of strings.ts.

Upstream:
```ts
export function splitLines(str: string): string[] {
    return str.split(/\r\n|\r|\n/);
}
export function containsRTL(str: string): boolean { ... }               // a large generated regex
export function containsUnusualLineTerminators(str: string): boolean { ... }  // LS/PS (U+2028/29)
export const UTF8_BOM_CHARACTER = String.fromCharCode(CharCode.UTF8_BOM);      // CharCode.UTF8_BOM = 65279
export function startsWithUTF8BOM(str: string): boolean { ... }
```

`_CONTAINS_RTL_PATTERN` is NOT upstream's regex source transcribed by hand -- the BMP character
class was pulled directly out of `strings.ts` via a script, confirmed pure-ASCII escape text (no
transcription risk). Upstream's regex also matches four supplementary-plane script ranges (each
written as a UTF-16 surrogate-pair alternative, since the source regex has no `/u` flag): these
are deliberately NOT ported here. A real codepoint-range translation was built and verified
correct in isolation (Python `re` matches codepoints, not UTF-16 code units, so the surrogate-pair
syntax needs converting via the standard decode formula, not copying) -- but assigning a Jac `str`
literal containing a supplementary-plane escape and then compiling/running the file crashes the
compiler outright: `UnicodeEncodeError` on a lone-surrogate codepoint (U+D802), "surrogates not
allowed", thrown from the ECMAScript codegen pass while writing bytecode/output, not from anything
in this file. (Writing that surrogate codepoint as a literal escape sequence directly in this
docstring reproduces the exact same crash recursively -- had to phrase it as "U+D802" above
instead, worth knowing if this note is ever edited.) Logged as `2026-08-23-supplementary-plane-string-crashes-js-codegen`. Until
that's fixed upstream, this pattern only detects the BMP RTL scripts (Hebrew, Arabic, Syriac,
Thaana, and others in that range) -- the overwhelming majority of real-world RTL text. Missing the
four supplementary-plane scripts (Cypro-Minoan, Old Uyghur, Kawi, Nag Mundari, and similar) means
`contains_rtl` under-detects for documents using those scripts specifically; not a concern for
anything this project currently builds, but worth fixing for real once the compiler bug is
resolved rather than silently forgotten.
"""

import re;

glob UTF8_BOM_CHARACTER: str = chr(65279);

glob _CONTAINS_RTL_PATTERN: str = (
    "[־׀׃׆א-״؈؋؍؛-ي٭-ٯٱ-ەۥۦۮۯۺ-ܐܒ-ܯݍ-ޥޱ-ߪߴߵߺ߾-ࠕࠚࠤࠨ࠰-ࡘ࡞-ࢎࢠ-ࣉ‏יִײַ-ﬨשׁ-ﴽﵐ-ﷇﷰ-﷼ﹰ-ﻼ]"
);
glob _UNUSUAL_LINE_TERMINATORS_PATTERN: str = r"[  ]";

def split_lines(s: str) -> list[str] {
    return re.split(r"\r\n|\r|\n", s);
}

def contains_rtl(s: str) -> bool {
    return re.search(_CONTAINS_RTL_PATTERN, s) is not None;
}

def contains_unusual_line_terminators(s: str) -> bool {
    return re.search(_UNUSUAL_LINE_TERMINATORS_PATTERN, s) is not None;
}

def starts_with_utf8_bom(s: str) -> bool {
    return len(s) > 0 and s[0] == UTF8_BOM_CHARACTER;
}
