---
id: 2026-08-23-instance-and-static-method-same-name-collision
date: 2026-08-23
category: ergonomics
severity: minor
status: resolved
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: "src/vs/editor/common/core/{position.ts,range.ts}"
upstream_issue: ""
tags: [translator, piece-tree, obj, static-methods]
---

## What we tried

Porting `Position` and `Range` (src/vs/editor/common/core/{position,range}.ts) as dependencies of
the piece-tree buffer. Both upstream classes repeat a common TS pattern: an instance method that
just forwards to a same-named two-argument static, e.g.

```ts
class Position {
    public equals(other: IPosition | null): boolean {
        return Position.equals(this, other);
    }
    public static equals(a: IPosition | null, b: IPosition | null): boolean { ... }
}
```

`Position` alone does this three times (`equals`, `isBefore`, `isBeforeOrEqual`); `Range` does it
eleven times (`isEmpty`, `containsPosition`, `containsRange`, `strictContainsRange`, `plusRange`,
`intersectRanges`, `equalsRange`, `getEndPosition`, `getStartPosition`, `collapseToStart`,
`collapseToEnd`). A direct translation — one `def equals` and one `static def equals` on the same
`obj Position` — fails to compile:

```jac
obj Foo {
    def equals(other: Foo) -> bool { ... }
    static def equals(a: Foo, b: Foo) -> bool { ... }
}
```
```
error[E0076]: Duplicate method 'equals' in class body
```

## What happened

Confirmed with the minimal repro above — an instance `def` and a `static def` cannot share a name
on the same `obj`, even though their signatures differ (arity: one implicit-`self` param vs. two
explicit params, matching how TS distinguishes instance vs. static overloads by receiver rather
than by name mangling). Jac's method-name resolution on an `obj` doesn't appear to split by
static/instance the way TS's does.

## Plan

Resolved, not a blocker — this is a real, recurring shape (any upstream class following this
common "static holds the logic, instance forwards" pattern will hit it identically; expect it
again on `Range`'s remaining twin pairs and potentially on future core/model classes). Workaround,
now the established pattern for this project (see `position.jac`, `range.jac`): keep the instance
method under its exact upstream name, and move the real two-argument logic to a module-level free
function (`position_equals`, `range_contains_position`, etc. — mirroring the free-function idiom
`interval_tree.jac` already established for a different reason). The instance method's one-line
body just calls the free function with `self` as the first argument. Static-only members with no
instance-side twin keep their exact upstream name as an ordinary `static def`, unaffected.

Not filing upstream — this is arguably reasonable behavior (TS's static/instance namespace split
is itself a bit of a wart), and the workaround is cheap and now a documented, repeatable pattern
rather than a per-file surprise.
