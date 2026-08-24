---
id: 2026-08-25-editor-core-decision-reversed-to-monaco
date: 2026-08-25
category: workaround-found
severity: note
status: resolved
phase: 2
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: "src/vs/editor"
upstream_issue: ""
tags: [editor-core, decision-point, architecture, monaco, reversal]
---

## What we tried

`2026-08-23-editor-core-native-vs-monaco-decided-native` recorded Phase 1's call to continue the
from-scratch native editor (`text_editor.jac` + the ported piece-tree/interval-tree engine) rather
than bridge to the real `monaco-editor` npm package. That entry's own addendum flagged, eyes-open,
that the decision only validated the algorithmic layer and a bare insert/delete/arrow-key loop --
not the much larger "build fresh" rendering/interaction surface (IME composition, multi-cursor,
selection, bidi/RTL text, virtualized rendering, accessibility, folding, the minimap) that Monaco,
upstream VS Code's own editor component, already ships and maintains.

Mid-Phase-2, direction changed: reuse the real npm package for v1 instead of continuing to build
that remaining surface from scratch. This entry records the reversal and what it actually touched,
since `docs/phases/phase-1-editor-core.md` still needs to stand as an accurate record of what
Phase 1 did, not be silently rewritten.

## What happened

Not a Jac-language limitation -- a deliberate reuse-over-reinvention call. Concretely:

- `src/editor/core/`, `src/editor/model/` (the ported piece-tree/interval-tree/prefix-sum engine),
  `src/editor/client/text_editor.jac` (+`.impl.jac`), and the piece-tree-backed
  `src/editor/document_service.jac` (+`.test.jac`) were `git mv`'d with history intact to
  `internal/native-editor-archive/`, given its own `jac.toml`/`main.jac` so it stays
  check/test-able in isolation (`jac check internal/native-editor-archive`,
  `jac test internal/native-editor-archive` -- 15 checked, 800 passed, confirming the move alone
  broke nothing).
- `src/editor/document_service.jac` was rewritten from scratch: stateless `open_document`/
  `save_document`, no `DocumentBuffer` object, no per-path buffer cache, no per-keystroke edit
  RPC -- Monaco owns the live text model, undo stack, and cursor/selection entirely client-side,
  so there's nothing left for the server to keep in sync with on every keystroke. This also
  retires the obj-vs-node caching-pattern question `DocumentBuffer` used to be the precedent for
  (see `2026-08-23-node-persistence-crashes-on-self-referential-fields`) -- the live document
  service no longer holds any state that question could apply to.
- New `src/editor/client/monaco_editor.jac` (+`.impl.jac`) wraps `@monaco-editor/react`'s
  `<Editor>` component -- confirmed via `jac guide jac-npm-packages` as a documented example
  package, not a novel integration guess. Verified via the compiled client bundle
  (`.jac/client/compiled/src/editor/client/monaco_editor.js`): `Ref[any]` lowers to a plain
  `useRef(null)` import from `"react"` (not `@jac/runtime`), the plain `path` function parameter
  closes correctly over both handler bodies in the paired `.impl.jac` file (no `has`-field copy
  needed, contrary to an initial assumption), and both RPC calls
  (`__jacCallFunction("open_document"/"save_document", ...)`) use the real unaliased server
  function names. Also verified end-to-end against a live `jac dev` session: `open_document`/
  `save_document` round-tripped real files correctly via direct RPC calls, and the app served a
  200 with the client bundle correctly importing `@monaco-editor/react`.
- `src/workbench/editor_tabs/editor_tabs.jac` now mounts `MonacoEditorApp` per open tab (same
  mounted-per-tab, hidden-via-`display`-not-unmounted shape as before) instead of the archived
  `TextEditorApp`.

## Plan

Resolved, not a workaround -- this is the new permanent v1 decision, `docs/architecture.md`'s
Editor Core section and "Open questions" entry, `docs/roadmap.md`'s Phase 1 section (via an added
update note, not a rewrite) and Phase 3's syntax-highlighting/diff-editor bullets (now largely
free via Monaco's own bundled tokenizer and `createDiffEditor`, not new research), and
`docs/phases/phase-1-editor-core.md` (via an added addendum, preserving its original record) were
all updated to reflect it.

The archived native engine at `internal/native-editor-archive/` is not a dead end -- its own
README documents what a future revival would need to touch (re-point `editor_tabs.jac`'s import,
re-check `2026-08-23-circular-import-degrades-native-lowering` and
`2026-08-23-node-persistence-crashes-on-self-referential-fields` against whatever `jac` version is
current then, rendering virtualization is still unaddressed even in the archived version). Nothing
about this reversal invalidates that Phase 1 work; it just isn't v1's active path.
