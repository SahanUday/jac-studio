---
id: 2026-08-24-client-dict-literal-variable-key-miscompiles
date: 2026-08-24
category: compiler-bug
severity: minor
status: workaround
phase: 2
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, client, dict, codegen]
---

## What we tried

`src/workbench/file_tree/file_tree.impl.jac` (the lazy file-tree sidebar's handler annex) updated
its `children_by_path: dict[str, list[dict]]` state field with a dict literal keyed by a variable,
the same reassign-the-whole-object style already established by `text_editor.impl.jac` (`lines =
new_lines;`) and `notes-app`'s `notes = [note] + notes;`:

```jac
children_by_path = {root_path: top_children};
```

and similarly `expanded = {**expanded, path: True};` for a spread-plus-new-key update.

## What happened

`jac check` and `jac test` both passed cleanly -- this is a client-bundle-only issue, invisible to
either. `jac dev`'s Vite build failed outright:

```
[ERROR] Expected "}" but found "."
compiled/src/workbench/file_tree/file_tree.js:1549:49:
  1549 | ...jacS_children_by_path.set({__jacS_root_path.val: top_children});
```

`jac2js` compiles a bare variable used as a dict-literal *key* into its reactive-wrapper access
form (`__jacS_root_path.val`) even inside a `{ ... : ... }` literal, where JS requires a computed
key to be wrapped in `[...]` (`{[__jacS_root_path.val]: top_children}`) -- it emits the unwrapped
form, which is a straight syntax error, not a silent miscompile. This is a new item for the
`jac2js` miscompilation classes already tracked in `docs/research/jac-capabilities.md`'s gap #3
(`let`-scoping/TDZ bugs, string-literal newline escaping, `sorted(key=lambda)` rejected
client-side, `asChild`/ref-forwarding silent no-ops) -- a computed dict-literal key belongs in that
same list.

**Workaround** (in place in `file_tree.impl.jac` now): build the new dict via a spread copy plus a
plain bracket assignment, never a literal with a variable key:

```jac
updated = {**children_by_path};
updated[root_path] = top_children;
children_by_path = updated;
```

Confirmed this compiles and round-trips correctly via a real `jac dev` session plus direct
`curl -X POST http://localhost:5184/function/<name>` calls against the running server.

## Plan

Not filing upstream yet -- straightforward workaround, no reason to believe it's anything but a
narrow codegen gap in how `jac2js` lowers dict-literal keys specifically (member/bracket-access
lowering elsewhere in the same file works correctly, per the `.val`-suffixed reads seen throughout
the rest of the compiled bundle). Worth a minimal repro upstream if this recurs somewhere the
copy-then-bracket-assign workaround is more awkward (e.g. deeply nested reactive state). General
guidance for future client components: never write `{some_variable: value}` in client-side Jac
code; always build dynamic-keyed dicts via bracket assignment on a fresh copy instead.
