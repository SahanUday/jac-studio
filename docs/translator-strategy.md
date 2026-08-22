# TS→Jac translator: strategy

## What this is (and isn't)

This is an **internal bootstrapping tool and gap-detection instrument**, not a general-purpose
TypeScript-to-Jac transpiler product. Its two jobs:

1. Fast-forward porting of VS Code source that is algorithmically pure enough to translate
   mechanically, so we're not hand-transcribing well-tested logic from scratch.
2. Generate a steady stream of concrete, reproducible signal about where jac-lang itself has
   gaps — every translation failure is a data point for [`challenge-tracking.md`](challenge-tracking.md),
   which is as much a deliverable of this project as jac-studio itself.

It will never be pointed at `workbench/`. UI code doesn't translate — VS Code's imperative DOM
manipulation and JSX-style Jac rendering are different enough paradigms that mechanical
translation would produce something idiomatic in neither language. Workbench UI is *designed* in
Jac from the start (see [`architecture.md`](architecture.md)), not translated.

## What it's for: the algorithmic core only

Good targets share three properties: pure logic (no DOM, no Electron, no Node-specific I/O),
existing unit tests we can port to `jac test` for behavioral verification, and small enough to
translate + review in one sitting. In priority order:

1. `src/vs/editor/common/model/prefixSumComputer.ts` — line/offset arithmetic, no dependencies.
2. `src/vs/editor/common/model/intervalTree.ts` — decoration lookup structure.
3. `src/vs/editor/common/model/pieceTreeTextBuffer/` — the actual text storage engine. Larger,
   but still pure; this is the one that matters most, since it's the foundation of the whole
   editor core (see `architecture.md`'s Editor Core section).
4. `textModel.ts`'s non-DOM-facing subset (edit stack/undo, search) — once 1–3 are solid.

Everything past this point (tokenization, language services, anything touching the DOM) is
designed fresh in Jac, informed by reading the TS source rather than translating it.

## Workflow

1. **Select target module** from the ordered list above.
2. **Translate with an explicit idiom ruleset**, not a literal line-by-line pass:
   - TS `class` → Jac `obj` (no DI needed — see architecture.md's service-registry section; most
     of these classes have no service dependencies anyway, they're pure data structures)
   - TS `Map`/`Array` operations → idiomatic Jac collection operations, not hand-rolled loops
     mimicking the TS source's exact iteration style
   - `any`/`unknown` in the TS source must resolve to a real Jac type, never carried over as `any`
   - Async TS (`Promise`) → Jac `async`/`await` only where genuine I/O is involved; these target
     modules are mostly synchronous and should stay that way
   - Preserve the original's variable/function names where reasonable, to keep the port
     diffable against upstream for future re-sync
3. **Compile and iterate**: `jac check`, then `jac run`, fixing errors until it builds.
4. **Port the original TS unit tests** (from `src/vs/editor/test/**` — find the matching test
   file) into `jac test` blocks (`jac-testing.md`), and confirm behavioral parity, not just "it
   compiles." A translated piece tree that compiles but inserts text in the wrong place is worse
   than no port at all.
5. **Any blocker gets logged immediately**, not batched up at the end: a Jac compiler error that
   looks wrong, an ergonomics gap that forces an awkward workaround, a stdlib function that
   doesn't exist yet. Log as soon as it's hit — see [`challenge-tracking.md`](challenge-tracking.md)
   for the entry format (category `translator-blocker`, with the TS source reference and the
   Jac attempt reference so the entry is reproducible by someone else later).
6. **Land the ported module with its tests passing** before moving to the next target — no
   partially-translated modules sitting in the tree.

## Who does the translation

The model (Claude, via this same working relationship) does the mechanical translation pass and
the first iteration loop against compiler errors; a human reviews the result for behavioral
correctness (especially edge cases the ported test suite might not catch) before it lands. This
mirrors how the rest of the project is meant to work — the model doing the bulk of the
implementation, blockers surfaced honestly rather than smoothed over, a human making the calls
that are genuinely judgment calls (see `architecture.md`'s open questions).

## Success signal

The translator strategy is working if, by the end of the Phase 0/1 spike (see
[`roadmap.md`](roadmap.md)), we have: the piece tree text buffer running under `jac test` with
parity against VS Code's own test cases, and a non-trivial, well-formed set of tracker entries
describing exactly where and why it was harder than expected. Both outcomes are useful — a clean
port with few blockers means jac-lang is more ready than assumed; a rough port with many blockers
is exactly the signal this whole project exists to produce for the jac-lang team.
