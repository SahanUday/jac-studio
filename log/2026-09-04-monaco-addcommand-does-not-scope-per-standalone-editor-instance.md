---
id: 2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance
date: 2026-09-04
category: compiler-bug
severity: major
status: workaround-found
phase: 5
subsystem: editor-core
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [monaco-editor, standalone-editor, keybindings, addCommand, multi-tab, correctness]
---

Found live while wiring `Ctrl+I` for inline chat (`docs/architecture.md`'s "Reframed 2026-09-03"
AI section, item 2) -- and it turns out to affect the pre-existing `Ctrl+S` too, not just the new
command. Not a Jac/jaclang bug; a real limitation of embedding standalone `monaco-editor` (this
project's own Editor Core decision, `2026-08-25-editor-core-decision-reversed-to-monaco`) with
multiple simultaneously-mounted editor instances, worth recording here since it's specific to how
this project uses that package and any future feature adding an editor-scoped keybinding will hit
it again if this isn't known.

## What happened

`monaco_editor.jac`'s `handle_mount` (called once per `MonacoEditorApp` instance -- every open tab
keeps its own editor mounted, per this module's own `keepCurrentModel` docstring) registered
`Ctrl+S`/`Ctrl+I` via `editor.addCommand(keybinding, handler)` on `editor`, the specific instance
passed into that mount callback. With two tabs open, focusing `broken.jac` and pressing the real
key combo (confirmed reaching Monaco's own `onKeyDown` listener with the correct `code`/`ctrlKey`)
invoked `README.md`'s own `handle_save` closure instead -- confirmed live: the server received a
`save_document` call for `README.md`'s content while `broken.jac` was the genuinely focused,
edited file. Reproduced with a completely fresh, minimal test command (not this project's own
code) registered directly on both live editor instances via the browser console: whichever
instance's `addCommand` call happened to run *last* is the only one Monaco ever invokes for that
keybinding, page-wide, regardless of which editor is actually focused (`editor.hasTextFocus()` on
the truly-focused, non-winning instance still correctly returns `true`).

Passing `"editorTextFocus"` as `addCommand`'s third (`context`) argument -- the standard fix for
this exact class of problem in a real VS Code workbench, where each editor's context key service
is properly scoped within the workbench's own hierarchy -- was tried and confirmed **not** to fix
it here: the isolated minimal test still only ever invoked the last-registered handler regardless
of that context string.

## Root cause (as far as this investigation went)

`@monaco-editor/react`'s embedded standalone `monaco-editor` (not the full VS Code workbench this
project intentionally doesn't build, see `docs/architecture.md`'s Editor Core section) appears to
route `addCommand`-registered keybindings through a single, page-global keybinding/command
registration rather than one properly scoped to the issuing editor's own instance -- the `context`
parameter's `"editorTextFocus"` value doesn't resolve against a genuinely per-instance context key
service the way it would inside a real VS Code workbench. Not traced further into
`monaco-editor`'s own source in this session; the workaround below sidesteps the question of
exactly which internal service is responsible rather than waiting on a root-cause fix upstream.

## The fix (shipped, verified live)

Stopped relying on Monaco to route the keypress to the correct closure at all. `monaco_editor.jac`
now keeps a module-level `glob _focused_editor_handlers: dict[str, dict[str, any]]`, keyed by file
`path`, populated by every mounted instance's own `handle_mount` with its own `{"save",
"toggleInlineChat"}` callbacks. `Ctrl+S`/`Ctrl+I` are registered exactly **once**, globally
(guarded by `_global_keybindings_registered`, the same idempotent-guard shape every provider in
`src/editor/client/` already uses) -- whichever instance's `addCommand` call happens to win that
one registration no longer matters, since the handler body itself finds the actually-focused
editor at invocation time (`monaco.editor.getEditors().find(e => e.hasTextFocus())`) and dispatches
through the registry to *that* editor's own stored callbacks. Verified against the exact repro:
two tabs open, focused `broken.jac`, pressed the real key combo, `save_document` now correctly
received `broken.jac`'s path.

## Plan

Not filed upstream (the `@monaco-editor/react`/`monaco-editor` repos, not jaclang) -- out of scope
for this project to pursue further this session, and the workaround is a complete, permanent fix
for this project's own needs, not a stopgap waiting on an upstream change (hence `workaround-found`
rather than `resolved`: the *underlying* Monaco behavior is still there, jac-studio just no longer
depends on it). Any future editor-scoped keybinding added to `monaco_editor.jac` (or a sibling
provider file registering its own `addCommand`) must go through `_focused_editor_handlers` +
`_register_global_editor_keybindings`, not a fresh per-instance `addCommand` call, or it will
silently reproduce this exact bug the moment more than one tab is open.
