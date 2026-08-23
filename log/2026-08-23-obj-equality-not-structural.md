---
id: 2026-08-23-obj-equality-not-structural
date: 2026-08-23
category: doc-gap
severity: major
status: open
phase: 0
subsystem: tooling
jac_version: "0.36.1 (dev build, jaseci main @ 86b0c25da)"
related_vscode_ref: ""
upstream_issue: ""
tags: [obj, equality, dataclass, translator, doc-mismatch]
---

Hit while porting `prefixSumComputer.ts` (the translator's first real translation,
`prefix-sum-computer` in `translator/manifest.toml`): the ported `PrefixSumIndexOfResult` value
object needed `==` comparisons to mirror upstream's `assert.deepStrictEqual(psc.getIndexOf(x), new
PrefixSumIndexOfResult(i, r))`.

**What the docs say**: `jac guide reference/language/syntax-cheatsheet` states plainly --
"`obj` is like a Python dataclass -- fields are per-instance, auto-generates `__init__`, `__eq__`,
`__repr__`, etc."

**What actually happens**: it doesn't. Two independent, minimal checks, both against a
freshly-cleaned cache:

```jac
obj Pet {
    has name: str = "Unnamed", age: int = 0;
}
with entry:__main__ {
    a = Pet(name="rex", age=3);
    b = Pet(name="rex", age=3);
    print(a == b);   # False -- should be True if __eq__ were structural
}
```

Worse: manually authoring `def __eq__(other: any) -> bool { ... }` on the `obj` (which `jac check`
accepts with no error) is silently never called by `==` either -- confirmed by printing both
comparisons directly, not just via `assert`:

```jac
obj Pet {
    has name: str = "Unnamed", age: int = 0;
    def __eq__(other: any) -> bool {
        if not isinstance(other, Pet) { return False; }
        return self.name == other.name and self.age == other.age;
    }
}
with entry:__main__ {
    a = Pet(name="rex", age=3);
    b = Pet(name="rex", age=3);
    print(a == b);   # False -- the override has no effect on `==`
}
```

So `==` on a plain `obj` falls back to identity comparison (default `object.__eq__`) regardless of
whether a matching `__eq__` is hand-written. This is either (a) the doc's "auto-generates `__eq__`"
claim is wrong for this build, or (b) `__eq__` is generated but the compiled `==` operator doesn't
dispatch to it, or (c) an override on an `obj` archetype specifically isn't wired into `==` the way
it would be on a plain Python `class`. Not root-caused further -- didn't dig into codegen for
`==`/dunder dispatch on `obj` archetypes specifically.

**Impact on the translator**: every ported module whose upstream TS tests use
`assert.deepStrictEqual`/structural equality on a value-object return type needs its ported test
file to compare fields explicitly instead of trusting `==` -- worked around here with a small
`index_of_matches(result, index, remainder) -> bool` helper in
`src/editor/model/prefix_sum_computer.test.jac`, not upstream's direct object-equality assertion
style. This will recur on every future translated module with a similar value-object return type
(the piece tree and interval tree both return small result structs), so it's worth knowing about
before hitting it again mid-port.

**Plan**: needs input from someone who can read the `obj`-to-dataclass codegen path (or a jaseci
maintainer) to say definitively whether this is a doc bug (the claim should be removed/qualified)
or a real `__eq__`-wiring gap worth fixing. Until resolved, the translator's own idiom rule should
say explicitly: **do not rely on `==` for value-object comparison in ported test files; compare
fields directly.** Not blocking -- the workaround is small and already applied -- but worth a
clear upstream answer before the piece-tree translation (much larger, much more result-struct
comparison in its own tests) hits the same thing repeatedly instead of once.
