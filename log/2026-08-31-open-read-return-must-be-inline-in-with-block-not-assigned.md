---
id: 2026-08-31-open-read-return-must-be-inline-in-with-block-not-assigned
date: 2026-08-31
category: compiler-bug
severity: minor
status: resolved
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [type-checker, open, with-block, jac-check]
---

## What happened

Building Phase 4's search-in-files feature (`docs/roadmap.md`), `src/workbench/search/search_service.jac`
needed to read a candidate file's full text before splitting it into lines. The natural shape:

```jac
with open(path, "r", encoding="utf-8", errors="strict") as fh {
    content = fh.read();
}
lines = content.splitlines();
```

`jac check` rejected this with a cascade of real errors, not warnings:

```
error[E1032]: Type is Unknown, cannot access attribute "read"
error[E1032]: Type is Unknown, cannot access attribute "splitlines"
error[E1053]: Cannot assign <Unknown> to parameter 'obj' of type Sized
error[E1032]: Type is Unknown, cannot access attribute "lower"
error[E1032]: Type is Unknown, cannot access attribute "index"
error[E1055]: No matching overload found for method "__add__" with the given arguments
```

Explicit `as str`/`as list[str]` casts on the assignment didn't help (`fh.read` itself, the
attribute access before the cast even applies, was the thing flagged Unknown) -- neither did an
explicit `content: str = ...` annotation on the target (same error, plus a new one: "Cannot assign
<Unknown> to str").

## Root cause

`open()`'s return type is not resolved by the type checker in a way that survives being bound to a
plain local variable and used *after* its `with` block closes. `src/editor/document_service.jac`'s
`_read_file_content` -- already-shipped, already-passing-`jac-check` code -- has the identical
underlying operation (open a file, read its text) but a different shape:

```jac
with open(path, "r", encoding="utf-8", errors="replace") as f {
    return f.read();
}
```

A `return` *directly inside* the `with` block, matched against the enclosing function's own
declared `-> str` return type, is the only form confirmed to type-check cleanly -- the checker
appears to resolve `open()`'s Unknown return type against the function signature at the return
site itself, not through an intermediate variable binding used later.

## Fix (shipped)

Extracted a small helper mirroring `document_service.jac`'s exact working shape:

```jac
def _read_file_text(path: str) -> str {
    with open(path, "r", encoding="utf-8", errors="strict") as fh {
        return fh.read();
    }
}
```

...then called `content = _read_file_text(path);` from the caller, outside any `with` block --
`content`'s type resolves correctly from there since it's now the return value of a function with
a declared `str` return type, not a raw `open()` result.

## Plan

`resolved`, not `workaround-found` -- the "extract a helper matching `document_service.jac`'s
already-proven shape" fix is the correct, permanent pattern for this project, not a stopgap.
Worth a line in `jac-language`'s gotcha list next time it's touched: **`with open(...) as f { ... }`
type-checks cleanly only when the file's content is `return`-ed directly inside the block against a
typed function signature -- assigning to a variable and using it after the block closes surfaces a
cascade of `Type is Unknown` errors on every subsequent operation on that value, even with explicit
casts.**
