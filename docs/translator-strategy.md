# TS→Jac translator: strategy

## What this is

An internal bootstrapping tool and gap-detection instrument, not a general-purpose
TypeScript-to-Jac transpiler product. Two jobs: fast-forward porting of VS Code source that is
algorithmically pure enough to translate mechanically, and generating concrete, reproducible signal
about jac-lang gaps for [`challenge-tracking.md`](challenge-tracking.md).

It has never been, and will never be, pointed at `workbench/`: UI code doesn't translate
mechanically between imperative DOM manipulation and JSX-style Jac rendering. Workbench UI is
designed in Jac from the start (see [`architecture.md`](architecture.md)).

## Current status: idle

All four originally-scoped targets (`prefixSumComputer`, `intervalTree`, `pieceTreeTextBuffer/`,
a `textModel.ts` subset) landed with parity against VS Code's own test suites — see
`manifest.toml`. None of it is wired into the running app: the editor engine embeds the real
`monaco-editor` package instead ([ADR 0020](decisions/0020-editor-engine-is-real-monaco.md)). The
ported code is archived, not deleted, at `internal/native-editor-archive/`.

Everything past those four modules (tokenization, language services, anything DOM-facing) is
designed fresh in Jac, informed by reading the TS source rather than translating it — Monaco
already supplies its own tokenizer and diff engine for the languages it ships. No target is
currently queued.

## When this would apply again

The tool and workflow stay ready for a future candidate that is: pure logic (no DOM, no Electron,
no Node-specific I/O), has existing upstream unit tests portable to `jac test`, and is small enough
to translate and review in one sitting. Reuse the workflow below rather than rebuilding it.

## Idiom rules

- TS `class` → Jac `obj` (see [ADR 0015](decisions/0015-default-services-to-obj-not-node.md)); most
  of these classes are pure data structures with no DI needs.
- TS `Map`/`Array` operations → idiomatic Jac collection operations, not hand-rolled loops mimicking
  the TS source's iteration style.
- `any`/`unknown` in the TS source must resolve to a real Jac type, never carried over as `any`.
- Async TS (`Promise`) → Jac `async`/`await` only where genuine I/O is involved.
- Preserve original variable/function names where reasonable, to keep the port diffable against
  upstream for future re-sync.

## Workflow

1. Select the target module and confirm it against the eligibility criteria above.
2. Translate per the idiom rules, `jac check` and iterate until it builds.
3. Port the original TS unit tests into `jac test` blocks and confirm behavioral parity, not just
   that it compiles.
4. Log any blocker immediately (category `translator-blocker`), not batched — see
   [`challenge-tracking.md`](challenge-tracking.md) for the entry format.
5. Land the module with tests passing before moving to the next target.

## Implementation

Five components: a git-tracked TOML manifest (one entry per module, `status`/`risk_tier`/
`verification` fields, `upstream_commit` for drift detection), an eligibility guard, structural
extraction, a translate-and-iterate loop, and a verification gate that auto-scaffolds a tracker
entry on failure.

Automation scales by `risk_tier`: `low` (small, pure, narrowly scoped) runs the translate→verify
loop as an unattended batch; `foundational` (the piece-tree buffer was the one example) always gets
a supervised, single-module session with human review before landing.

The piece-tree buffer alone also got differential testing: running the original TS and the Jac
port side by side on randomized edit sequences, diffing buffer state after each step
(`verification = "tests+differential"` in the manifest) — because a bug there would silently
corrupt user-visible text, not just fail a test.

Extraction needs the TypeScript compiler API, an npm package unreachable from server-side Jac
(`error[E5001]`, string-literal npm imports are client-only) — settled by a Phase 0 spike
(`2026-08-22-npm-interop-server-only-blocked`). Extraction is a small Node subprocess shim invoked
from the Jac orchestrator; every other component (manifest, guard, verification harness) is Jac.
The manifest itself stays plain TOML on disk, not graph storage, so it stays diffable in git.

## Who does the translation

The model does the mechanical translation pass and the first compiler-error iteration loop; a
human reviews for behavioral correctness before landing, especially edge cases the ported test
suite might not catch.
