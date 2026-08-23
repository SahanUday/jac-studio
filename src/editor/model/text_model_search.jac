"""A narrow, scoped subset of VS Code's textModelSearch.ts
(src/vs/editor/common/model/textModelSearch.ts, 555 lines): `Searcher`, `create_find_match`
(`createFindMatch`), and the word-boundary helpers `isValidMatch`/`leftIsWordBounday`/
`rightIsWordBounday` -- exactly what `PieceTreeBase.find_matches_in_node`/`find_matches_line_by_
line` (see `piece_tree_base.jac`) need to drive a search over the piece tree. Not a port of
`TextModelSearch`/`SearchParams`/`LineFeedCounter` or anything else in that file -- those live
above the piece-tree layer (multiline search, model-wide orchestration) and belong with a future
`TextModel` port, not here.

One-way dependency only: this file imports nothing from `piece_tree_base.jac`, and
`piece_tree_base.jac` imports `Searcher`/`create_find_match`/`is_valid_match` from here -- not
circular, so none of the native-lowering degradation from
`2026-08-23-circular-import-degrades-native-lowering` applies.

Idiom / porting notes:
- JS `RegExp.exec` with a global flag and a mutable `lastIndex` searches from that index onward
  (not anchored there) and auto-advances `lastIndex` to the end of each match it finds. Python's
  `re.Pattern.search(text, pos)` has the identical "search from, not anchored at" semantics, so
  `Searcher` just tracks `last_index` itself and passes it to `search()` each call, advancing it
  to `m.end()` after every match -- a direct, faithful translation of the same iteration protocol,
  not a redesign.
- Upstream's empty-match recovery (`regex.lastIndex` stuck at a zero-length match) advances by two
  code units when the char at that position is a surrogate-pair high surrogate, one otherwise --
  purely a UTF-16-code-unit-vs-Unicode-codepoint concern. Python strings are codepoint sequences
  with no surrogate-pair splitting for supplementary characters, so the two-vs-one distinction
  doesn't apply here; always advancing by one Python string index is the actually-equivalent
  translation, not a simplification of upstream's intent.
- `createFindMatch`'s capture-group loop copies `RegExpExecArray[i]`, which can be `undefined` for
  a non-participating optional group; JS just stores `undefined` in the result array. Ported as an
  empty string for a non-participating group (`re.Match.group(i)` returns `None` there) rather
  than widening `FindMatch.matches`'s element type to `str | None` for an edge case neither this
  module's own scope nor its callers currently exercise -- worth revisiting if a future caller
  needs to distinguish "empty match" from "group didn't participate."
"""

import re;
import from src.editor.core.range { Range }
import from src.editor.core.char_code { LINE_FEED, CARRIAGE_RETURN }
import from src.editor.core.word_character_classifier { WordCharacterClassifier, WORD_CHARACTER_CLASS_REGULAR }
import from src.editor.model.model_types { FindMatch }

def left_is_word_bounday(
    word_separators: WordCharacterClassifier, text: str, text_length: int, match_start_index: int,
    match_length: int
) -> bool {
    if match_start_index == 0 {
        return True;
    }
    char_before = ord(text[match_start_index - 1]);
    if word_separators.get(char_before) != WORD_CHARACTER_CLASS_REGULAR {
        return True;
    }
    if char_before == CARRIAGE_RETURN or char_before == LINE_FEED {
        return True;
    }
    if match_length > 0 {
        first_char_in_match = ord(text[match_start_index]);
        if word_separators.get(first_char_in_match) != WORD_CHARACTER_CLASS_REGULAR {
            return True;
        }
    }
    return False;
}

def right_is_word_bounday(
    word_separators: WordCharacterClassifier, text: str, text_length: int, match_start_index: int,
    match_length: int
) -> bool {
    if match_start_index + match_length == text_length {
        return True;
    }
    char_after = ord(text[match_start_index + match_length]);
    if word_separators.get(char_after) != WORD_CHARACTER_CLASS_REGULAR {
        return True;
    }
    if char_after == CARRIAGE_RETURN or char_after == LINE_FEED {
        return True;
    }
    if match_length > 0 {
        last_char_in_match = ord(text[match_start_index + match_length - 1]);
        if word_separators.get(last_char_in_match) != WORD_CHARACTER_CLASS_REGULAR {
            return True;
        }
    }
    return False;
}

def is_valid_match(
    word_separators: WordCharacterClassifier, text: str, text_length: int, match_start_index: int,
    match_length: int
) -> bool {
    return (
        left_is_word_bounday(word_separators, text, text_length, match_start_index, match_length)
        and right_is_word_bounday(word_separators, text, text_length, match_start_index, match_length)
    );
}

def create_find_match(rng: Range, raw_match: re.Match[str], capture_matches: bool) -> FindMatch {
    if not capture_matches {
        return FindMatch(range=rng, matches=None);
    }
    matches: list[str] = [raw_match.group(0)];
    i = 1;
    while i <= raw_match.re.groups {
        g = raw_match.group(i);
        matches.append(g if g is not None else "");
        i += 1;
    }
    return FindMatch(range=rng, matches=matches);
}

obj Searcher {
    has word_separators: WordCharacterClassifier | None, search_regex: re.Pattern[str];
    has prev_match_start_index: int postinit;
    has prev_match_length: int postinit;
    has last_index: int postinit;

    def postinit {
        self.prev_match_start_index = -1;
        self.prev_match_length = 0;
        self.last_index = 0;
    }

    def reset(last_index: int) {
        self.last_index = last_index;
        self.prev_match_start_index = -1;
        self.prev_match_length = 0;
    }

    def next(text: str) -> re.Match[str] | None {
        text_length = len(text);

        while True {
            if self.prev_match_start_index + self.prev_match_length == text_length {
                return None;
            }

            m = self.search_regex.search(text, self.last_index);
            if m is None {
                return None;
            }

            match_start_index = m.start();
            match_length = m.end() - m.start();

            if match_start_index == self.prev_match_start_index and match_length == self.prev_match_length {
                if match_length == 0 {
                    self.last_index += 1;
                    continue;
                }
                return None;
            }

            self.prev_match_start_index = match_start_index;
            self.prev_match_length = match_length;
            self.last_index = m.end();

            if self.word_separators is None or is_valid_match(
                self.word_separators, text, text_length, match_start_index, match_length
            ) {
                return m;
            }
        }
    }
}
