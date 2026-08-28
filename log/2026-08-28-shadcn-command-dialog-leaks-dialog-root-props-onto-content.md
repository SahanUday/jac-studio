---
id: 2026-08-28-shadcn-command-dialog-leaks-dialog-root-props-onto-content
date: 2026-08-28
category: compiler-bug
severity: minor
status: open
phase: 3
subsystem: workbench-shell
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [shadcn, command, dialog, react-warning, jac-install]
---

## What happened

`jac install --shadcn command`'s generated `components/ui/command.jac` produces a `CommandDialog`
that spreads its own `props` object twice:

```jac
def:pub CommandDialog(props: any) -> JsxElement {
    ...
    <Dialog {**props}>
        ...
        <DialogContent
            {**props}
            className={...}
            showCloseButton={showCloseButton}
        >
```

`props` is the caller's `{open, onOpenChange, ...}` -- meant for `<Dialog>` (Radix's
`DialogPrimitive.Root`, the only place `open`/`onOpenChange` are meaningful). `DialogContent`
(`components/ui/dialog.jac`) spreads its own `{**props}` straight onto
`<DialogPrimitive.Content {**props}>`, which has no use for `open`/`onOpenChange` -- Radix's
`Dialog.Content` doesn't accept them. React ends up forwarding the unrecognized `onOpenChange`
prop down to a raw DOM element, producing this console warning on every open of any
`CommandDialog` instance:

```
Warning: Unknown event handler property `onOpenChange`. It will be ignored.
    at div
    ...
    at DialogContentImpl
    at DialogContent (components/ui/dialog.js)
    at CommandDialog (components/ui/command.js)
```

## Repro

Confirmed live (`jac browse`, real `jac run --serve --dev` process) two independent ways, isolating
it from any of this session's own new code:

1. Freshly reload jac-studio, open the **pre-existing** command palette (`Ctrl+Shift+P`,
   `src/workbench/command_palette/command_palette.jac`, shipped in Phase 2) -- the warning fires
   immediately, with zero involvement from anything built this session.
2. The newly-built Quick Open component (`src/workbench/quick_open/quick_open.jac`, Phase 3) uses
   the identical `<CommandDialog open={open} onOpenChange={...}>` call shape and reproduces the
   same warning.

Both call sites are using `CommandDialog` exactly as its own generated API expects -- this is not a
caller-side mistake, it's `command.jac`'s own prop-spreading.

## Why it's not the already-tracked `command`-generator bug

A prior finding (`2026-08-25-shadcn-command-generator-missing-root-wrapper`) covers a *crash*
(`CommandDialog` missing the `Command` root wrapper around its children, throwing on subscribe).
This is a separate defect in the same generated file: no crash, purely a spurious dev-console
warning (React explicitly says "it will be ignored" -- functionally harmless, confirmed: Quick
Open's open/select/close flow all worked correctly across the repro above). Filed separately per
this project's "one finding per entry" rule.

## Plan

Workaround applied nowhere yet -- this is cosmetic noise, not a functional break, so no urgency to
patch `command.jac` locally the way the other generator bug required (that one crashed on first
open; this one doesn't block anything). If it gets noisy enough to want silencing: `CommandDialog`
should destructure `open`/`onOpenChange` out of `props` before forwarding the rest to
`DialogContent`, passing them only to `<Dialog>` -- the same "peel off what a lower layer doesn't
need before spreading the rest" fix pattern, just one level removed from the already-tracked
missing-wrapper fix. Real fix belongs upstream in jaclang's `jac install --shadcn command`
generator template, alongside the other `command.jac` fix, so a future `jac install --shadcn
command` run doesn't need this patched by hand twice.
