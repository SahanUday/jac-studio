"""A small bundle of shared model-layer types, ported from VS Code's model.ts
(src/vs/editor/common/model.ts). That file is 1622 lines defining the full `ITextModel` surface;
only the handful of small, piece-tree-adjacent exports below are ported here, not a translation of
the file as a whole.

Ported:
- `DefaultEndOfLine` -- upstream `const enum { LF = 1, CRLF = 2 }`, kept as plain int constants
  (same idiom as `NodeColor`/`TrackedRangeStickiness` in interval_tree.jac and `CharCode` in
  core/char_code.jac -- a `const enum` is just inlined numbers, so a real Jac `enum` would add
  comparison-ambiguity risk for no benefit).
- `FindMatch` -- a tiny value type (`range`, `matches`). `range` is typed as `Range`
  (src/editor/core/range.jac), ported in parallel by another agent as part of this same
  piece-tree effort; the forward reference resolves at check-time regardless of write order.
- `SearchData` -- `regex` (a compiled pattern; represented as Python's `re.Pattern[str]` via
  Jac's Python interop, since Jac compiles to Python and stdlib types are directly usable),
  `word_separators` (typed as `WordCharacterClassifier`, src/editor/core/word_character_classifier.jac,
  also being ported in parallel), and `simple_search`.

Documented, not ported:
- `ITextSnapshot` -- upstream is a one-method structural interface (`read(): string | null`).
  Jac doesn't need a literal interface/protocol port for something this trivial: any `obj` with a
  zero-arg `read` method returning `str | None` satisfies the contract by duck typing. No formal
  type is declared for it in this file.
"""

import re;
import from src.editor.core.range { Range }
import from src.editor.core.word_character_classifier { WordCharacterClassifier }

glob DEFAULT_END_OF_LINE_LF: int = 1;
glob DEFAULT_END_OF_LINE_CRLF: int = 2;

obj FindMatch {
    has range: Range, matches: list[str] | None;
}

obj SearchData {
    has regex: re.Pattern[str], word_separators: WordCharacterClassifier | None, simple_search: str | None;
}
