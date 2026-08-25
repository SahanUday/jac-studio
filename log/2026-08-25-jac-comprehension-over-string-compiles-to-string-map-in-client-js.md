---
id: 2026-08-25-jac-comprehension-over-string-compiles-to-string-map-in-client-js
date: 2026-08-25
category: compiler-bug
severity: minor
status: workaround-found
phase: 2
subsystem: client-codegen
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jsx, client-codegen, comprehension, strings, browser-verification]
---

A Jac list comprehension iterating a `str` inside client-side (JSX-emitting) code --
`[c if (c.isalnum()) else "-" for c in path]`, written while adding DOM ids for the editor-tabs
ARIA retrofit -- compiles to `path.map(c => ...)` in the emitted client bundle. That's correct for
Python semantics (strings are iterable, comprehensions lower to a map-like operation server-side)
but wrong for the client target: JS strings have no `.map` method, only `Array.prototype.map`.
`jac check`/`jac test` both passed with zero errors or warnings on this file -- purely a
runtime/rendering defect, invisible to static checking, same shape as the
`2026-08-25-shadcn-command-generator-missing-root-wrapper` finding.

**Effect**: guaranteed crash the first time the function actually ran client-side. Reproduced live
via `jac browse`: opening any file tab in `editor_tabs.jac` (which calls the helper to build the
tab's `id`/`aria-controls` values) threw `TypeError: t.map is not a function`, caught by the app's
error boundary ("🚨 Something went wrong") on every single open, not an edge case. The stack trace
(`jac browse console`) pointed at a minified `Array.map (<anonymous>)` frame with no direct source
mapping to the helper -- diagnosed by re-reading the diff that introduced the change, not from the
trace itself, since the crash message alone doesn't distinguish "the array I meant to map over" from
"a string I didn't realize was getting `.map`-ed."

**Plan**: avoid per-character string comprehensions in client-side Jac code entirely; treat any
`for <char> in <str>` inside a JSX-emitting file as suspect. For the specific case that triggered
this (building a DOM-safe id from an arbitrary string), the actual fix needed no sanitization at
all -- HTML5's `id` attribute grammar only forbids whitespace, which the input (a filesystem path)
never contains, so the fix was to drop the comprehension and use the raw string directly
(`src/workbench/editor_tabs/editor_tabs.jac`'s `_tab_dom_id`). If a future case genuinely needs
character-level string transformation client-side, the safe approach is either a regex-based
`.replace()` (a real JS string method) or explicitly converting to an array first in a way confirmed
to compile correctly for the client target -- not yet verified which comprehension forms are safe
there, so treat every one as needing a `jac browse` check before trusting it, not just `jac
check`/`jac test`.
