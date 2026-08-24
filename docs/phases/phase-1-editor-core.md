# Phase 1 — Editor core MVP

Status: **complete** -- 2026-08-23. All exit criteria in [`../roadmap.md`](../roadmap.md) are met:
a file's content opens into a buffer, typing/deleting round-trip through a real ported piece-tree
buffer, and the native-vs-Monaco decision point is resolved with real evidence. This doc is the
record of how Phase 1 actually went; Phase 2 (workbench shell MVP) is next -- see the roadmap's
Phase 2 section. Read this before touching editor-core code -- it's the fastest way to get
oriented without re-reading every doc and PR from scratch.

> **Update (2026-08-25, mid-Phase-2): the "continue native" decision below was reversed.** The
> project now embeds the real `monaco-editor` npm package as the actual editor engine for v1 --
> a reuse-over-reinvention call, not a verdict that this phase's work failed. Everything below is
> preserved as an accurate record of what Phase 1 actually did and found; it is no longer the
> live editor path. The code this phase produced is archived at `internal/native-editor-archive/`,
> not deleted. See `docs/architecture.md`'s Editor Core section and tracker entry
> `2026-08-25-editor-core-decision-reversed-to-monaco` for the current state and full reasoning.

## Goal (from roadmap.md)

A single text buffer that can be created, edited, and displayed -- no workbench chrome yet --
plus the deferred native-vs-Monaco decision, made with a working prototype in hand rather than in
the abstract.

## What's actually been built so far

**The piece-tree buffer, ported for real** (PR #9) -- not just `pieceTreeBase.ts`, but its full
real dependency chain, since (unlike `interval-tree`'s deferred `Range`/`ModelDecorationOptions`
fields) the buffer's entire job is line/offset math and its own ported tests genuinely construct
and check `Position`/`Range` values field-by-field:

- `rb_tree_base.jac` -- merged into `piece_tree_base.jac` rather than kept as a separate file
  (see the circular-import finding below).
- `piece_tree_base.jac` -- the piece tree itself, including search
  (`find_matches_in_node`/`find_matches_line_by_line`).
- `piece_tree_text_buffer.jac` / `piece_tree_text_buffer_builder.jac` -- the `ITextBuffer`
  wrapper and builder (EOL auto-detection, BOM/RTL handling, `apply_edits`).
- `text_model_search.jac` -- the `Searcher`/`createFindMatch`/`isValidMatch` subset the search
  methods above need.
- Six dependency modules: `position.jac`, `range.jac`, `word_character_classifier.jac`,
  `char_code.jac`, `strings.jac`, `model_types.jac`.

**534 tests passing** across the new/touched modules, including all 4 real `chunk based search`
cases and the full `pieceTreeTextBuffer.test.ts` suite (197 + 99 tests across the two wrapper
files). One ported test (`#45892`, searching an empty document) caught a real latent issue:
`nodeAt2`'s upstream TS type claims a non-nullable return, but the fallback branch is genuinely
reachable on an empty tree -- `node_at2` here returns `NodePosition | None` for real.

**The minimal client editor component** (PRs #10/#11) -- `src/editor/client/text_editor.jac`,
backed by `src/editor/document_service.jac`'s `DocumentBuffer`. Deliberately not a `<textarea>`:
renders lines and tracks cursor state itself, so every keystroke genuinely round-trips through the
real ported buffer, the same way a real custom editor surface would. Verified against a real
running server (`jac start --dev` + `jac browse`), not just `jac check`: typed input, backspace,
forward-delete, and all four arrow keys confirmed correct. `jac.toml` upgraded from `kind = "cli"`
to `"web-app"`, per the deferred edit noted in `phase-0-foundations.md`.

**The native-vs-Monaco decision point** -- resolved: **continue native**. See
`2026-08-23-editor-core-native-vs-monaco-decided-native` for the full reasoning; in short, the
prototype meets Phase 1's exit criteria, the two gaps found were both ordinary bounded engineering
(not genuine blocks), and Monaco would have replaced the ported piece-tree buffer's role in live
editing rather than composed with it -- stranding the project's single largest translation effort
for that path. `docs/architecture.md`'s open questions and Editor Core section updated to record
this.

## Key decisions made

- **Real dependency translation, not deferred placeholders, when the module's own job is that
  data.** `interval-tree`'s "leave `Range` untyped, the tests never touch it" move doesn't apply
  when the module *is* line/offset math -- `Position`/`Range`/`WordCharacterClassifier` all
  needed real ports here.
- **Circular Jac-file imports silently degrade native compilation.** Confirmed with a minimal
  repro (`jac check` passes with a warning, but a `Type is Unknown` note shows the compiler
  falling back to interpreted/server-codespace compilation for the affected declarations) --
  `rbTreeBase.ts`'s split from `pieceTreeBase.ts` was a TS-ES-module convenience, not something
  inherent to the algorithm, so the two were merged into one Jac file rather than reproducing the
  cycle. Logged as `2026-08-23-circular-import-degrades-native-lowering`.
- **A node whose fields transitively hold a self-referential structure crashes graph
  persistence.** This directly conflicted with an idiom this project had already established and
  validated twice (`interval_tree.jac`'s and `piece_tree_base.jac`'s `SENTINEL` self-loop, the
  correct translation of upstream's sentinel pattern). `document_service.jac`'s `DocumentBuffer`
  is a plain `obj` held in a `jid(root)`-keyed cache dict, not a graph `node`, as a result --
  logged as `2026-08-23-node-persistence-crashes-on-self-referential-fields`
  (`workaround-found`, not `resolved`: the correct fix is cycle-aware persistence).
- **Per-keystroke edits need explicit ordering, not just `await`.** Found by testing at
  faster-than-human input rates, not by inspection -- fixed with a strict client-side queue once
  the native direction was decided (fixing it before the decision would have been throwaway
  effort if Monaco had been chosen instead).

## Deviations from the original plan (found by actually building, not assumed upfront)

- The piece-tree buffer's real dependency surface (`Position`, `Range`,
  `WordCharacterClassifier`, a subset of `textModelSearch.ts`, small extracts from `model.ts`/
  `charCode.ts`/`strings.ts`) turned out to be a genuinely large translation on its own --
  `translator-strategy.md`'s target list didn't originally break these out as separate line
  items, since they weren't visible as real dependencies until `piece-tree-base` itself was
  actually read in full.
- `rbTreeBase.ts` was planned as its own manifest entry; landed merged into `piece_tree_base.jac`
  instead once the circular-import finding made that the right call.
- The service-registry pattern's first real use outside the Phase 0 spike (`DocumentBuffer`) hit
  a blocker the spike's own `ConfigService` never could have surfaced, since `ConfigService`
  never held a self-referential value. Worth knowing before any future workbench-graph node
  (`Workspace`, `File`, `EditorGroup`) ends up holding a ported tree structure -- see the tracker
  entry's "broader implication" note.

## Blockers logged during this phase

- `2026-08-23-circular-import-degrades-native-lowering` (open) -- circular Jac-file imports pass
  `jac check` but silently lose native compilation.
- `2026-08-23-instance-and-static-method-same-name-collision` (resolved) -- a translation-session
  finding hit while porting `piece_tree_base.jac`.
- `2026-08-23-supplementary-plane-string-crashes-js-codegen` (open) -- hit porting RTL/unusual-
  line-terminator detection; the reason supplementary-plane script detection is a documented,
  deliberate scope cut in `piece_tree_text_buffer.jac`.
- `2026-08-23-node-persistence-crashes-on-self-referential-fields` (workaround-found) -- see above.
- `2026-08-23-client-editor-no-per-keystroke-request-queuing` (resolved) -- see above.
- `2026-08-23-editor-core-native-vs-monaco-decided-native` (resolved) -- the decision-point record
  itself.

## What's left / suggested next steps

Phase 1's exit criteria are fully met; nothing is blocking Phase 2. Two known, deliberately
deferred items carry forward rather than blocking:

1. **Rendering virtualization** -- `text_editor.jac` re-renders the full document on every edit,
   fine for a demo, a real concern once Phase 2 opens actual files. Not urgent: revisit once
   Phase 2's file tree/tabs work means real (larger) files are actually being opened.
2. **`2026-08-23-circular-import-degrades-native-lowering`** and
   **`2026-08-23-node-persistence-crashes-on-self-referential-fields`** are both still open
   upstream questions worth raising with a jaseci maintainer before Phase 2's workbench-graph work
   starts wiring `Workspace`/`File`/`EditorGroup` nodes for real -- the persistence bug in
   particular will recur the moment any of those nodes holds a ported tree structure
   (`IntervalTree` for decorations, the piece-tree buffer itself).

Per `roadmap.md`, Phase 2 (workbench shell MVP) starts with the file tree sidebar, tabs, editor-
group splitting, the command palette, and the integrated terminal -- see the roadmap for the full
list and exit criteria.
