---
id: 2026-08-25-shadcn-command-generator-missing-root-wrapper
date: 2026-08-25
category: compiler-bug
severity: major
status: workaround-found
phase: 2
subsystem: tooling
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [shadcn, jac-install, cmdk, command-dialog, generator, workbench-shell]
---

`jac install --shadcn command` (jac 0.36.1) scaffolds `components/ui/command.jac`, whose
`CommandDialog` wrapper places `{props["children"]}` directly inside `DialogContent`, never
wrapping them in the `Command` root primitive (`CommandPrimitive`, imported from `cmdk`). Compare
against upstream shadcn/ui's own reference `command.tsx`, which wraps `{children}` in `<Command
className="...">` inside `DialogContent` specifically because `CommandList`/`CommandInput`/
`CommandItem`/etc. are all `CommandPrimitive.*` subcomponents that read from a store/context the
`Command` root sets up.

**Effect: guaranteed crash the first time anyone actually opens a command palette built from this
generated file**, not an edge case. Reproduced live in jac-studio's own command palette
(`src/workbench/command_palette/command_palette.jac`, built directly on the generated
`CommandDialog`): opening it threw `Cannot read properties of undefined (reading 'subscribe')`
every single time, caught via a full React error-boundary stack trace pointing directly at `cmdk`'s
internal store access inside `CommandList` (`node_modules/cmdk`, called from the generated
`components/ui/command.js` at runtime). `jac check`/`jac test` both pass on the generated file with
no warnings — this is a pure runtime/rendering defect, invisible to static checking, only caught by
actually opening the dialog in a real browser.

**Fix applied, workaround only**: hand-patched jac-studio's own generated
`components/ui/command.jac` to wrap `{props["children"]}` in `<Command className="...">` inside
`DialogContent`, matching upstream shadcn's reference markup (including its accompanying utility
classes for `cmdk`-group-heading spacing, item padding, etc., copied from the same upstream
reference rather than invented). Confirmed fixed via a real `jac browse` session: the palette now
renders correctly (rounded dialog, backdrop, search input, item list) with no crash, verified
across a fresh page load and several repeated opens.

**Plan**: this is a defect in the `jac install --shadcn command` template itself, not something
jac-studio's own code did wrong — anyone else running `jac install --shadcn command` on an
unpatched jaseci build will hit the identical crash the first time they open whatever
`CommandDialog` they build on it. The real fix belongs in jaseci's shadcn-in-Jac template for
`command`, mirroring the fix already applied locally. No further jac-studio-side action needed
*unless* the generator is re-run (`jac install --shadcn command` again, e.g. to pick up a template
update) — that would silently regenerate the broken version and overwrite the local patch, so
whoever does that should re-apply this same fix and check this entry first. Worth reporting to
jaseci maintainers as a real generator template bug, ideally with a link back to this entry and the
upstream shadcn `command.tsx` reference for the correct markup.
