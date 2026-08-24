# Native editor archive

Status: **parked, not deleted** -- 2026-08-25. This is Phase 1's from-scratch Jac text-editing
engine, moved here (with git history intact via `git mv`) when jac-studio switched to embedding
the real `monaco-editor` npm package as the live editor engine for v1. See
`../../docs/architecture.md`'s "Editor core" section and tracker entry
`2026-08-25-editor-core-decision-reversed-to-monaco` for the full reasoning -- in short, this is a
reuse-over-reinvention call, not a verdict that this code doesn't work. It met every one of Phase
1's exit criteria before being parked; see `../../docs/phases/phase-1-editor-core.md` for the
complete record of how it was built and what it does.

## What's here

The exact `src/editor/` tree as it stood at the point of the switch:

- `src/editor/core/` -- `Position`, `Range`, `WordCharacterClassifier`, `char_code`, `strings`:
  the small pure-math dependency layer the buffer needed.
- `src/editor/model/` -- the ported piece-tree text buffer, interval tree (decoration lookup),
  prefix-sum computer (line/offset math), and the `text_model_search` subset the search methods
  need. Translated from VS Code's own TS modules via the [translator](../translator/), validated
  behavior-for-behavior against VS Code's own ported unit tests.
- `src/editor/client/text_editor.jac` (+ `.impl.jac`) -- the hand-built native rendering
  component: renders lines as JSX elements, tracks (line, column) cursor state itself, and
  round-trips every keystroke through the ported buffer via a document service (below).
- `src/editor/document_service.jac` (+ `.test.jac`) -- the piece-tree-backed document service as
  it stood at the switch: one `DocumentBuffer` (a plain `obj`, not a graph `node` -- see
  `2026-08-23-node-persistence-crashes-on-self-referential-fields`) per open file path, real disk
  reads on first open, per-keystroke edits applied server-side. **This is not the same file as the
  live `src/editor/document_service.jac`** -- the live one was rewritten from scratch, much
  simpler (load/save only, no buffer object at all), once Monaco took over live editing
  client-side.

This directory is its own self-contained Jac project (own `jac.toml` + `main.jac`), the same
pattern `internal/workspace-graph-spike/` and `internal/service-registry-spike/` use, so it can be
checked and tested in isolation without touching the live app:

```
capped -- jac check internal/native-editor-archive
capped -- jac test internal/native-editor-archive
```

## Reviving this

If a future need brings native back (a licensing constraint on Monaco, wanting full control over
the text engine, a desktop/native-JS story that doesn't fit Monaco well):

1. Confirm this subtree still checks/tests clean against whatever `jac` version is current then --
   language/compiler behavior may have shifted since 2026-08-25.
2. `git mv` `src/editor/{core,model,client}` back under the live `src/editor/`, replacing the
   Monaco-based `document_service.jac`/`monaco_editor.jac` with this directory's originals (or a
   merge of both, if the workbench-tabs wiring built on top of Monaco in the meantime needs to
   carry over).
3. Re-point `src/workbench/editor_tabs/editor_tabs.jac`'s import back to `TextEditorApp`.
4. Re-check the two blockers that were still open when this was parked --
   `2026-08-23-circular-import-degrades-native-lowering` and
   `2026-08-23-node-persistence-crashes-on-self-referential-fields` -- against current `jac`
   behavior before relying on the workarounds still being necessary.
5. Rendering virtualization was a known, deliberately deferred gap even when this was live (see
   `docs/phases/phase-1-editor-core.md`'s "What's left" section) -- still true, still unaddressed.
