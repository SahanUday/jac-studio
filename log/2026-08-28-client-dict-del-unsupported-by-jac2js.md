---
id: 2026-08-28-client-dict-del-unsupported-by-jac2js
date: 2026-08-28
category: missing-feature
severity: major
status: workaround
phase: 3
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci@ac293949212cedc64c8e6b1f16a6ea66953e3d8e)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, client-codegen, del, dict, workbench-shell]
---

## What happened

Adding a plain `del updated_dict[key];` statement inside a client-lowered component handler
(`workbench.impl.jac`'s `close_tab`, part of the new tab-affordances "unsaved changes" feature)
compiled cleanly under both `jac check` and `jac test` -- zero errors, zero warnings -- but broke
the real dev server's client build entirely:

```
error[E5017]: 'del' statement is not supported by client codegen
  --> workbench.impl.jac:86:9
   86 |         del updated_dirty_paths[path];
      |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
help: This statement has no ECMAScript lowering yet, and without this error it would be silently
dropped from the client bundle. Rewrite it using supported constructs, or move the logic to a
server or native codespace.
```

Only caught by actually running `jac run main.jac --serve --dev` and reading its startup log --
`jac check`/`jac test` both run the server/Python-side path and never exercise `jac2js` at all, the
same class of gap this project has hit before for other client-codegen edge cases (see
`jac-language` skill's "dict literal with a variable key" and "client import alias" entries).

## Why this one is easy to trip

A plain `del dict[key]` (the copy-then-delete idiom this project already uses for map-style state,
e.g. `command_registry.jac`'s `clear_keybinding_override`) reads as completely idiomatic Jac and
is used elsewhere in this same codebase without issue -- but every existing use is inside a
*server-only* `def:pub` function operating on a graph-node-backed service, never inside a
client-component handler. Nothing about the syntax itself signals "this won't lower to JS"; the
failure mode depends entirely on which codespace (client vs. server) the containing function gets
inferred into (see `jac-codespaces`), which isn't visible from the call site itself. The compiler's
own error message is admirably specific once it fires (`E5017`, exact line, explicit "would be
silently dropped from the client bundle" warning about what *used* to happen before this check
existed) -- the gap is that `jac check`/`jac test` give no signal at all beforehand.

## Plan

**Workaround** (used here, and worth defaulting to going forward): for any `dict`/`list` mutation
inside client-component state that would otherwise need `del`, prefer a formulation that doesn't
need key removal at all when the read site can tolerate it -- e.g. overwriting a boolean flag's
entry to `False` instead of deleting the key, when every read of that dict already goes through
`.get(key, False)` and therefore treats "absent" and "False" identically. This sidesteps the gap
entirely rather than working around `del`'s absence with an equivalent construct.

Where key removal is genuinely required (not just "avoidable this time"), the real fix belongs
upstream in `jac2js`: lower `del d[k]` to `delete d[k]` (dict) or `d.splice(i, 1)`
(list-by-index), the direct ECMAScript equivalents, the same way other Python-shaped constructs
already get lowered for client codegen. Filing this as `missing-feature`/`workaround` rather than
`resolved`, since the correct long-term answer is a compiler-side lowering, not an app-level
avoidance pattern -- the workaround above only works because this specific call site's data shape
happened to tolerate it.
