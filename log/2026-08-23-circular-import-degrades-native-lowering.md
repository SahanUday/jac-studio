---
id: 2026-08-23-circular-import-degrades-native-lowering
date: 2026-08-23
category: compiler-bug
severity: minor
status: open
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: "src/vs/editor/common/model/pieceTreeTextBuffer/{pieceTreeBase.ts,rbTreeBase.ts}"
upstream_issue: ""
tags: [translator, piece-tree, native-compilation, imports]
---

## What we tried

Upstream splits the piece-tree buffer's red-black tree into two files with a genuine two-way type
dependency: `rbTreeBase.ts`'s `TreeNode` has a `piece: Piece` field (defined in
`pieceTreeBase.ts`), and `rbTreeBase.ts`'s tree-algorithm functions (`leftRotate`, `rbDelete`,
`fixInsert`, ...) take a `tree: PieceTreeBase` parameter (also defined in `pieceTreeBase.ts`),
while `pieceTreeBase.ts` imports `TreeNode`/`SENTINEL`/etc. back from `rbTreeBase.ts`. Fine under
TS's hoisted ES-module type system. Before committing to a Jac module layout for the port, we
tested whether Jac tolerates the same circular-import shape with a minimal isolated repro:

```jac
// a.jac
import from b { Bee }
obj Aye {
    has val: int;
    def use_bee(b: Bee) -> int { return b.val + self.val; }
}

// b.jac
import from a { Aye }
obj Bee {
    has val: int;
    def use_aye(x: Aye) -> int { return x.val + self.val; }
}
```

## What happened

`jac check a.jac` and `jac check b.jac` both report `ok` and both files' single smoke test
passes — so this is easy to miss in normal use. But `a.jac`'s check output includes:

```
warning: native seam -- erasing field Bee.val to an opaque slot (un-lowerable declaration)
warning: native seam -- demoting Bee.use_aye to Python-only (un-lowerable): Native lowering failed for signature type 'Aye'
warning: native seam -- demoting Aye.use_bee to Python-only (un-lowerable): Native lowering failed for signature type 'Bee'
note: a.jac preferred native but did not lower; compiled in the server codespace (error[E1032]: Type is Unknown, cannot access attribute "val")
```

Both sides of the cycle silently lose native lowering and fall back to interpreted "server
codespace" compilation, with a real type-resolution failure underneath the fallback (`Type is
Unknown, cannot access attribute "val"`). Nothing about this is a hard error — `jac check`'s
top-line result is `ok`, and a session not reading the full warning/note output (or one running
`jac check` non-verbosely) would ship this without knowing native compilation degraded on both
modules.

## Plan

Not filing upstream yet — haven't confirmed whether this is a fundamental limitation of resolving
cross-module type references during native lowering (a real architectural question: does the
native lowerer see the *other* module's declarations at the point it lowers the first one, given
the cycle?) or a solvable ordering/caching gap. Worth a minimal-repro upstream issue if a jaseci
maintainer confirms it's not fixable by the porting side.

For this project: avoid the cycle at the module level instead of working around it per-file.
`piece_tree_base.jac` merges `TreeNode` + `Piece` + `PieceTreeBase` + the tree-algorithm functions
into one file rather than mirroring upstream's two-file split — sidesteps the issue entirely and
costs nothing (no consumer needs `TreeNode`/the tree algorithms independently of
`PieceTreeBase`). General guidance for future translations: before splitting a ported module
across files the way upstream does, check whether the split introduces a type cycle, and prefer
one file over reproducing a TS-motivated module boundary that doesn't survive Jac's native-lowering
model. `jac check`'s plain output is not sufficient to catch this — the warnings only showed up
because we were looking for them; worth checking whether `jac check` should surface a
non-buried summary line (e.g. "N declarations fell back to non-native compilation") rather than
requiring a full-output read to notice.
