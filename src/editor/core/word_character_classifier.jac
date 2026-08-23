"""Word/word-separator character classification, ported from VS Code's wordCharacterClassifier.ts
(src/vs/editor/common/core/wordCharacterClassifier.ts), folded together with the small generic
`CharacterClassifier<T>` base class it extends (src/vs/editor/common/core/characterClassifier.ts,
a *separate* upstream file). Both are ported into this single module -- there's no other consumer
of the generic base yet, and this project's output-file mapping is one file per upstream *feature*
(mirroring `interval_tree.jac` folding `intervalTree.ts`'s few small supporting types into one
file), not a mechanical 1:1 file split.

Backs `SearchData.wordSeparators` in the piece-tree buffer's own ported test suite
(pieceTreeTextBuffer.test.ts constructs `new WordCharacterClassifier(',./', [])` and passes it
into `findMatchesLineByLine`), which is the only real caller this project has right now -- it
reaches the classifier purely through `get(charCode)` (see `textModelSearch.ts`'s
`isValidMatch`/`leftIsWordBounday`/`rightIsWordBounday`, which look up individual character codes
on either side of a match).

Scope cut: upstream's `intlSegmenterLocales` constructor argument and the `Intl.Segmenter`-backed
methods it enables (`findPrevIntlWordBeforeOrAtOffset`, `findNextIntlWordAtOrAfterOffset`, and the
private segment-caching machinery behind them) are deliberately NOT ported here. Confirmed by
reading the actual call sites: nothing in `pieceTreeBase.ts`'s search path
(`findMatchesLineByLine` -> `textModelSearch.ts`'s `isValidMatch`) calls anything but `get()`; the
Intl.Segmenter methods exist only for locale-aware word-boundary features (word-wise cursor
movement, double-click-to-select-word) that are out of scope for the current piece-tree-buffer
port. `intl_segmenter_locales` is still stored as a field (matching upstream's public readonly
property and the real call shape `WordCharacterClassifier(',./', [])`), just never acted on.

Also deliberately not ported: the module-level `getMapForWordSeparators` LRU-cache-backed factory
function. Every real caller in scope constructs `WordCharacterClassifier` directly (see above);
the cache is a pure performance optimization over repeated construction with the same separator
string, not part of the classification behavior itself, and can be added later if a caller that
actually needs it shows up.

Idiom note: `WordCharacterClass` (`Regular = 0`, `Whitespace = 1`, `WordSeparator = 2`) is ported
as plain int constants, not a Jac `enum`, matching `interval_tree.jac`'s `NodeColor` precedent --
upstream's `const enum` is just numbers under the hood. The generic `Uint8Array`-backed ASCII
table plus sparse `Map` fallback from `CharacterClassifier<T>` is ported as a plain `list[int]` of
length 256 plus a `dict[int, int]`; there's no fixed-width-byte-array concern here since the only
values ever stored are 0/1/2, so `toUint8`'s clamping is a no-op and isn't ported.
"""

glob WORD_CHARACTER_CLASS_REGULAR: int = 0;
glob WORD_CHARACTER_CLASS_WHITESPACE: int = 1;
glob WORD_CHARACTER_CLASS_WORD_SEPARATOR: int = 2;

glob CHAR_CODE_TAB: int = 9;
glob CHAR_CODE_SPACE: int = 32;

obj WordCharacterClassifier {
    has word_separators: str, intl_segmenter_locales: list[str];
    has ascii_map: list[int] postinit;
    has extra_map: dict[int, int] postinit;

    def postinit {
        self.ascii_map = [WORD_CHARACTER_CLASS_REGULAR] * 256;
        self.extra_map = {};

        for i in range(len(self.word_separators)) {
            self.set(ord(self.word_separators[i]), WORD_CHARACTER_CLASS_WORD_SEPARATOR);
        }

        self.set(CHAR_CODE_SPACE, WORD_CHARACTER_CLASS_WHITESPACE);
        self.set(CHAR_CODE_TAB, WORD_CHARACTER_CLASS_WHITESPACE);
    }

    def set(char_code: int, value: int) {
        if char_code >= 0 and char_code < 256 {
            self.ascii_map[char_code] = value;
        } else {
            self.extra_map[char_code] = value;
        }
    }

    def get(char_code: int) -> int {
        if char_code >= 0 and char_code < 256 {
            return self.ascii_map[char_code];
        }
        return self.extra_map.get(char_code, WORD_CHARACTER_CLASS_REGULAR);
    }

    def clear {
        self.ascii_map = [WORD_CHARACTER_CLASS_REGULAR] * 256;
        self.extra_map = {};
    }
}
