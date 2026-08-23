"""Character code constants, ported from VS Code's charCode.ts
(src/vs/base/common/charCode.ts). That file defines a large `const enum CharCode` covering the
full ASCII/Latin-1 range plus a handful of Unicode marks; only three values are actually consumed
by the piece-tree code this bundle exists to support: `CarriageReturn`, `LineFeed`, and `Tab`.
Everything else in upstream's enum is deliberately not ported here.

Idiom note: ported as plain int constants, not a Jac `enum`, matching interval_tree.jac's
`NodeColor`/`TrackedRangeStickiness` precedent -- upstream's `const enum` is just numbers under
the hood (values inlined at compile time), so there's no reason to introduce enum/int comparison
ambiguity for values that are only ever compared against raw character codes (e.g.
`ord(ch) == CARRIAGE_RETURN`).
"""

glob TAB: int = 9;
glob LINE_FEED: int = 10;
glob CARRIAGE_RETURN: int = 13;
