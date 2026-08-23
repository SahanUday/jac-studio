---
id: 2026-08-23-node-is-a-reserved-keyword
date: 2026-08-23
category: ergonomics
severity: minor
status: resolved
phase: 0
subsystem: translator
jac_version: "0.36.1 (dev build, jaseci main @ 86b0c25da)"
related_vscode_ref: "src/vs/editor/common/model/intervalTree.ts"
upstream_issue: ""
tags: [reserved-keywords, translator, ergonomics]
---

Hit translating `intervalTree.ts` (the `interval-tree` module in `translator/manifest.toml`):
`node` and `include` are reserved Jac keywords (`jac-core-cheatsheet`'s full list: declaration
words `node`/`edge`/`walker`/`obj`/`def`/`impl`, OSP/control words, module words including
`include`, plus `with`/`can`/`has`) — not just `root`, which is the only one this project's own
`jac-language` skill had previously flagged from direct experience.

**What happened**: a first-pass literal translation preserved upstream's own variable name
(`node`, used ~280 times across `intervalTree.ts`'s red-black tree code, plus 12 uses of
`include` as a filter-inclusion flag). `jac check` correctly rejected all of it — 205 cascading
parse errors from those two collisions alone (a single `node.parent` reference breaks parsing far
past that line). Not a doc gap: `jac-core-cheatsheet` already lists both as reserved; this was a
translation session not cross-checking a natural, expected variable name against that list before
writing several hundred lines.

**Why this is worth recording anyway** (per the `jac-studio-challenge-tracking` skill's own
carve-out for a quick fix that's still surprising): `node` is about the most natural variable name
there is for *any* tree/graph algorithm, and this whole project's translator work is mostly
tree/graph algorithms translated from upstream sources that also use `node` as their own natural
variable name. This isn't a one-off — `piece-tree-base` (the foundational Phase 1 module, also a
tree data structure) will hit the exact same wall, at larger scale, if not anticipated.

**The fix**: whole-file rename to `nd` (and `include` to `should_include`), done via a scripted
whole-word regex substitution (`\bnode\b`, safe against `IntervalNode`/`node_start`/etc. since `_`
is a word character and doesn't create a boundary). Escaping with a leading backtick (`` `node ``)
also works everywhere for these — they aren't Python-reserved — but for a name used this
pervasively, renaming reads far better than backtick-escaping every occurrence.

**Plan**: no upstream ask here — the reserved list is intentional language design, already
documented accurately. Action taken: added to this project's `jac-language` skill's gotcha list
so a future translation session (piece-tree-base especially) checks variable names against the
full reserved list *before* writing the bulk of a module, not after. Closing as resolved.
