---
id: 2026-08-22-entry-exit-keyword-doc-mismatch
date: 2026-08-22
category: doc-gap
severity: minor
status: open
phase: 0
subsystem: tooling
jac_version: "0.36.1 (jac dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [keywords, entry, exit, jac-core-cheatsheet, translator]
---

`jac guide jac-core-cheatsheet`'s Pitfalls section states explicitly: "declaration words (`node`,
`edge`, `walker`, `obj`, `def`, `impl`), OSP / control words (`visit`, `disengage`, `report`,
`spawn`, `flow`, `wait`, `skip`, `del`), module words (`include`), and `with`, `can`, `has`.
**(`entry` and `exit` are *not* reserved - fine as identifiers.)**"

In practice, building the translator's CLI (`translator/main.jac`), the compiler rejected both:

- `entry = find_entry(entries, args.id);` (a local variable named `entry`) →
  `error[E0013]: 'entry' is a keyword and cannot be used as a variable name`
- `sys.exit(args.func(args));` (accessing `.exit` as an attribute on the `sys` module) →
  `error[E0013]: 'exit' is a keyword and cannot be used as a attribute name`

**Impact**: minor — both were easy to work around (renamed the local variable to `record`;
escaped as `` sys.`exit(...) ``). But the guide's explicit claim is wrong for this build, at least
for `entry` as a plain variable name, which the guide calls out by name as the safe case. Possibly
`entry`/`exit` are reserved only in some contexts (e.g. near enough to a real `with entry {}`
block that the parser gets confused) rather than unconditionally — not investigated further, since
the workarounds were trivial.

**Plan**: no action needed for jac-studio itself (workarounds already applied). Flagging so the
discrepancy isn't silently trusted next time someone reads that guide section at face value.
