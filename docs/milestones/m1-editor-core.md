# M1 — Editor core

**Status**: complete, 2026-08-23 (superseded mid-M2: see below)

> The "continue native" decision below was reversed 2026-08-25, mid-M2: the project now embeds the
> real `monaco-editor` package as the editor engine. This record is kept as an accurate account of
> what M1 built and found; it is not the live editor path. The code is archived at
> `internal/native-editor-archive/`, not deleted.

A single text buffer that could be created, edited, and displayed, plus the native-vs-Monaco
decision, made with a working prototype rather than in the abstract.

## Shipped
| PR | What |
|---|---|
| #9 | Piece-tree buffer ported for real: `piece_tree_base.jac` (merged with `rb_tree_base.jac`), `piece_tree_text_buffer(_builder).jac`, `text_model_search.jac`, plus `position.jac`/`range.jac`/`word_character_classifier.jac`/`char_code.jac`/`strings.jac`/`model_types.jac`. 534 tests passing. |
| #10, #11 | Minimal client editor (`text_editor.jac`, `document_service.jac`'s `DocumentBuffer`). Verified live via `jac browse`: typing, backspace, forward-delete, arrow keys. `jac.toml` upgraded to `kind = "web-app"`. |
| — | Native-vs-Monaco decision point resolved: continue native (later reversed in M2). |

## Decisions
- [ADR 0018](../decisions/0018-editor-core-continues-native.md) — editor core continues native (reversed by [0020](../decisions/0020-editor-engine-is-real-monaco.md)).

## Deviations from plan
- The piece-tree buffer's real dependency surface (`Position`, `Range`, `WordCharacterClassifier`, a `textModelSearch.ts` subset) turned out much larger than the translator manifest's original line items assumed.
- `rbTreeBase.ts` was planned as its own manifest entry; landed merged into `piece_tree_base.jac` once the circular-import finding (below) made that the right call.
- `DocumentBuffer` ended up a plain `obj` in a `jid(root)`-keyed cache, not a graph `node` — the service-registry pattern's first real use outside the M0 spike hit a self-referential-field crash the M0 spike never could have surfaced.

## Blockers logged
- `2026-08-23-circular-import-degrades-native-lowering` (open) — circular Jac-file imports pass `jac check` but silently lose native compilation.
- `2026-08-23-instance-and-static-method-same-name-collision` (resolved).
- `2026-08-23-supplementary-plane-string-crashes-js-codegen` (open) — supplementary-plane script detection is a deliberate scope cut in `piece_tree_text_buffer.jac`.
- `2026-08-23-node-persistence-crashes-on-self-referential-fields` (workaround-found) — `DocumentBuffer` uses a cache dict, not a node, as a result.
- `2026-08-23-client-editor-no-per-keystroke-request-queuing` (resolved) — fixed with a strict client-side queue.

## Left open
- Rendering virtualization: `text_editor.jac` re-renders the full document on every edit. Moot once Monaco replaced the engine in M2.
- The two open blockers above are worth raising with a jaseci maintainer before any workbench-graph node holds a ported tree structure — still true for future graph work.
