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
   but still pure.
4. `textModel.ts`'s non-DOM-facing subset (edit stack/undo, search) — once 1–3 are solid.

All four landed (see `manifest.toml`) with parity against VS Code's own test suites for those
modules — a clean signal that jac-lang was ready for this. **None of it is wired into the running
app as of 2026-08-25**, though: the editor engine now embeds the real `monaco-editor` npm package
instead (a reuse-over-reinvention call, not a verdict that the port failed — see
`architecture.md`'s Editor Core section). The ported code is archived, not deleted, at
`internal/native-editor-archive/` for a possible future revival. This list is kept as the record
of what the translator was actually pointed at and proved capable of, not as a statement that the
piece-tree buffer is currently the editor core's foundation — Monaco is.

Everything past this point (tokenization, language services, anything touching the DOM) is
designed fresh in Jac, informed by reading the TS source rather than translating it — doubly so
now that Monaco supplies its own tokenizer and diff engine for the languages it already ships (see
`roadmap.md`'s Phase 3), leaving no currently-queued translator target. The workflow below and the
tool in `internal/translator/` stay ready for whenever a genuinely pure, tested, in-scope module
turns up again — this strategy isn't retired, just currently idle.

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

## Implementation architecture

Not a hand-built TS→Jac compiler — building a real transpiler would be its own large project, and
it would fight the "rewrite, don't mirror" principle (`architecture.md`): we want *idiomatic* Jac
output, which needs judgment, not mechanical syntax substitution. The translator is a **repeatable,
tool-assisted workflow with the model as the translation engine**, wrapped in deterministic
tooling for the parts that shouldn't depend on judgment at all. Five components, realizing the six
workflow steps above:

1. **Manifest / ledger** — the single source of truth for what's in scope and what's landed. A
   plain, git-tracked file (not Jac graph storage, deliberately — see Language below), one entry
   per module:

   ```toml
   [[modules]]
   id = "prefix-sum-computer"
   upstream_path = "src/vs/editor/common/model/prefixSumComputer.ts"
   upstream_commit = "<sha at translation time>"
   jac_path = "src/editor/model/prefix_sum_computer.jac"
   test_upstream_path = "src/vs/editor/test/common/model/prefixSumComputer.test.ts"
   test_jac_path = "src/editor/model/prefix_sum_computer.test.jac"
   status = "queued"       # queued | in-progress | landed | blocked
   risk_tier = "low"       # low | foundational — see Automation below
   verification = "tests"  # tests | tests+differential — see Verification below
   ```

   Recording `upstream_commit` is what makes drift detection possible later: if upstream changes a
   file we've already ported, a manifest check can tell us, rather than the port silently going
   stale.

2. **Eligibility guard** — checks a candidate module against the Tier-1 criteria (`What it's for`
   above) mechanically before anyone attempts it: no DOM/Electron/browser imports, under a size
   threshold, has a co-located upstream test file. Fails fast, refuses out-of-scope modules rather
   than wasting an attempt on something that was always "build fresh" territory.

3. **Structural extraction** — parses the TS module and its test file to pull out exported
   symbols, type signatures, doc comments, and real dependency imports, as *structured* context
   rather than raw text the model has to re-derive that structure from every time. This is where
   most of the token-efficiency and accuracy gain comes from: mechanical extraction removes an
   entire category of context-parsing error before translation even starts, and frees the model's
   reasoning budget for the actual judgment calls.

4. **Translation + iteration loop** — the model, working from the idiom ruleset in `Workflow`
   above and the structured context from step 3: translate, `jac check`, fix, repeat.

5. **Verification gate + outcome recorder** — `jac check` then `jac test` against the ported
   suite; on pass, land the module and flip its manifest status; on failure, auto-scaffold a
   tracker log entry (category `translator-blocker`) pre-filled with the TS reference, the Jac
   attempt, and the actual error, so logging it costs nothing extra in the moment it's hit.

### Automation: hybrid by risk tier

Not uniformly supervised, not uniformly autonomous. Each manifest entry carries a `risk_tier`:

- **`low`** (`prefixSumComputer`, `intervalTree` — small, pure, narrowly scoped): can run through
  the translate→verify loop as an unattended batch, landing passes and logging blockers for
  failures, checked in on periodically rather than watched step by step.
- **`foundational`** (`pieceTreeTextBuffer/` — everything else in the editor core depends on this
  one getting it right): always a supervised, single-module session with deliberate human review
  before landing, regardless of how cleanly it passes verification. The cost of a subtle bug here
  is silent text corruption, not a failed test — worth the slower pace.

### Verification: differential testing for the piece tree specifically

The default bar is "ported unit tests pass" (`Workflow`, step 4) — sufficient for most targets.
The piece-tree buffer gets one thing more, because it's the one module where a bug wouldn't just
fail a test, it would silently corrupt user-visible text: run the original TS module and the Jac
port side by side on the same randomized sequences of edits (insert/delete at random offsets,
including edge cases like empty-buffer and boundary offsets) and diff the resulting buffer state
after each step. This is a `verification = "tests+differential"` entry in the manifest, not a
different workflow — same land/block outcome, one extra gate specific to this module's stakes.

### Where this lives

A permanent, versioned `internal/translator/` directory in the jac-studio repo (on `main`, alongside the
code it's porting into — not the `tracking` branch, which is for the challenge log itself, not the
tooling that feeds it). The manifest's drift-detection value compounds over the life of the whole
project only if it's actually preserved, not thrown away per session.

### Language: Jac-first, one spike to verify how far that goes

The manifest, eligibility guard, and verification-harness invocation (`jac check`/`jac test`,
subprocess calls, file I/O) are plain scripts with no dependency that Jac lacks — written in Jac,
no exceptions, run via the Jac CLI. This is deliberately different from the challenge tracker's
choice to avoid Jac: the tracker has to be an unbreakable observability backstop (if it broke
because of a Jac bug, there'd be no way to even report that bug), while the translator's
orchestration has no such requirement — if it breaks, a tracker entry can still be written by
hand. Dogfooding it directly serves the project's own mission: a blocker hit while building the
orchestrator *is* signal, the same as a blocker hit translating a module.

Extraction (step 3) needs the TypeScript compiler API, which is an npm package. **Settled by a
Phase 0 spike (2026-08-22, `2026-08-22-npm-interop-server-only-blocked.md`): this cannot be done
in Jac.** String-path npm imports are categorically client-only — `jac-codespaces.md`'s evidence
rules seed them client, and in a project kind with no client codespace the whole dependent module
(including the entry point) silently gets pulled client with nothing to execute it. Forcing it
server via `[placement.pins]` doesn't work either: it fails hard with
`error[E5001]: String literal imports are only supported in client (cl) imports, not Python
imports.` This is a deliberate compiler restriction, not a gap to report upstream.

So extraction is a **small Node subprocess shim, invoked from the Jac orchestrator** — confirmed
necessary, not a hedge. Concretely: a short Node script wrapping `typescript`'s
`createSourceFile`/`forEachChild` to emit the structured extraction (exported symbols, signatures,
doc comments, imports) as JSON on stdout; the Jac orchestration code (manifest, eligibility guard,
verification harness) calls it via Python's `subprocess` interop and parses the JSON result. Every
other component stays Jac as planned — this is the one confirmed exception, not evidence the
Jac-first approach was wrong elsewhere.

The manifest itself stays a plain TOML file on disk, not Jac's graph persistence, despite
everything else being Jac — deliberately: its value partly *is* being diffable and reviewable in
git/PR history, which a server-side graph wouldn't give us the same way. The file format is plain;
every piece of code that reads or writes it is Jac.

## Who does the translation

The model (Claude, via this same working relationship) does the mechanical translation pass and
the first iteration loop against compiler errors; a human reviews the result for behavioral
correctness (especially edge cases the ported test suite might not catch) before it lands. This
mirrors how the rest of the project is meant to work — the model doing the bulk of the
implementation, blockers surfaced honestly rather than smoothed over, a human making the calls
that are genuinely judgment calls (see `architecture.md`'s open questions).

## Success signal

**Met, as of the Phase 0/1 spike** (see [`roadmap.md`](roadmap.md)): the piece tree text buffer
ran under `jac test` with parity against VS Code's own test cases, plus a non-trivial, well-formed
set of tracker entries describing exactly where and why it was harder than expected — see `What
it's for` above for the current status of that specific port (archived, superseded by embedding
Monaco). The strategy itself is judged working independent of that particular module's fate: both
outcomes below are useful — a clean
port with few blockers means jac-lang is more ready than assumed; a rough port with many blockers
is exactly the signal this whole project exists to produce for the jac-lang team.
