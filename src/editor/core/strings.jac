"""A single small string utility, ported from VS Code's strings.ts
(src/vs/base/common/strings.ts): `splitLines`. That file is 1421 lines covering a huge surface
(word boundaries, grapheme handling, string builders, etc.) almost none of which the piece-tree
needs; only `splitLines` is actually used, and only by the piece-tree's own ported test file, not
by production code -- so this file stays a narrow, well-tested utility rather than a partial port
of the rest of strings.ts.

Upstream:
```ts
export function splitLines(str: string): string[] {
    return str.split(/\r\n|\r|\n/);
}
```
"""

import re;

def split_lines(s: str) -> list[str] {
    return re.split(r"\r\n|\r|\n", s);
}
