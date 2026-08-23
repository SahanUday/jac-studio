# Phase 0 — Foundations

Status: **complete** — 2026-08-23. All exit criteria in [`../roadmap.md`](../roadmap.md) are met:
service registry validated, translator workflow proven on two modules, tracker live with real
entries. This doc stays as the record of how Phase 0 actually went; Phase 1 (editor core MVP) is
next, starting with the piece-tree buffer per `translator-strategy.md`'s ordering. Read this
before touching anything in the project — it's the fastest way to get oriented without
re-reading every doc and PR from scratch.

## Goal (from roadmap.md)

De-risk the two biggest architectural bets — the root-graph-as-service-registry proposal and the
TS→Jac translator approach — before building anything on top of them, and stand up the
infrastructure (tracker, translator tooling) that every later phase depends on.

## What's actually been built so far

**Planning & research** (`docs/*.md`, `docs/research/*.md`) — thorough investigation of upstream
VS Code (measured layer sizes, DI, extension host, editor core), VSCodium's packaging pipeline,
Jac's documented capabilities, and idioms from Jac's real example apps. Produced
`architecture.md` (the core proposal, including the "rewrite, don't mirror" decision procedure —
redesign / translate / build-fresh), `roadmap.md` (8 phases), `translator-strategy.md`,
`challenge-tracking.md`, plus two full-coverage passes: `vscode-feature-gap-analysis.md` and
`vscode-complete-triage.md` (every one of upstream's 158 `workbench/contrib` + `editor/contrib`
feature areas triaged to a disposition — nothing silently unaccounted for).

**Challenge tracker** — live at https://sahanuday.github.io/jac-studio/, on the `tracking`
branch: a markdown+frontmatter log format, a dependency-free static dashboard, a Python build
script (deliberately not Jac — see `challenge-tracking.md`), deployed via GitHub Actions.
11 entries logged so far (see "Findings logged" below).

**The translator tool** (`internal/translator/`, merged via PR #4) — the full five-component design from
`translator-strategy.md` implemented and validated against real targets, not synthetic ones:
manifest/ledger, eligibility guard, structural extraction (Node/TypeScript-compiler-API shim,
since a spike confirmed Jac's npm interop can't reach it), verification gate, outcome recorder.
27 passing unit tests. Also `internal/translator/land-blocker.sh` — a one-shot script to land a
scaffolded blocker onto `tracking` (deliberately plain bash, not Jac, since it touches the
observability backstop itself — same reasoning as the tracker's own build script).

**Illustrated plan** — a Claude Artifact walking the whole architecture/roadmap/decision-procedure
for the team (URL not repeated here since Artifact links aren't guaranteed durable across time —
ask if you need it re-shared).

## Key decisions made

- **Redesign vs. translate vs. build-fresh**: the concrete two-question decision procedure in
  `architecture.md` — is a component's complexity caused by TS/Electron's limitations (redesign
  in Jac's own shape) or inherent to the problem (translate if small/tested, else build fresh).
- **Jac-first tooling, one confirmed exception**: the translator's own orchestration is plain
  Jac throughout; only structural extraction needs a small Node subprocess, confirmed necessary
  (not just assumed) by a real spike — see the `npm-interop-server-only-blocked` finding below.
- **Root-graph-as-service-registry**: validated by a real spike (`internal/service-registry-spike/`) — see
  the "Update" section below for the two mandatory implementation rules that came with it.
- **Hybrid automation by risk tier**: small/pure modules can run the translate→verify loop with
  lighter supervision; the piece-tree buffer (foundational — everything else depends on it)
  always gets a single-module session with real review, plus differential testing beyond just
  ported-test parity.

## Deviations from the original plan (found by actually building, not assumed upfront)

- The eligibility guard's first DOM-global heuristic false-positived on the word "document" in an
  ordinary doc comment on a real target (`pieceTreeBase.ts`) — tightened from substring matching
  to real DOM-API call-shape patterns.
- `pieceTreeBase.ts` (a real Tier-1 target) has no test file of its own — it's tested only
  through the outer wrapper class's test file. Added an explicit `--test-file` override rather
  than assuming strict basename/path-mirroring always holds.
- Manifest paths are stored relative to `--vscode-root`, not absolute — an early draft baked in
  an absolute, machine-specific path, caught before landing since it isn't portable for a
  git-tracked shared tool.
- Two rounds of Copilot PR review caught real issues before merge: a malformed-filename edge
  case in the blocker scaffolder, missing test coverage for three of the five components (which
  itself surfaced a real latent bug — `main.jac` needed `with entry:__main__`, not plain
  `with entry`, or importing it for testing would trigger the live CLI and call `sys.exit()`),
  incorrect variable-kind labeling in the extraction shim, unquoted YAML in the scaffolded
  entries, and thin failure diagnostics.

## Findings logged (tracking branch, `log/*.md`)

Two categories: real Jac language/tooling friction hit while building the translator, and
strategic/architectural notes surfaced during planning.

- `npm-interop-server-only-blocked` — settles the extraction-language question (blocker→resolved)
- `entry-exit-keyword-doc-mismatch`, `keyword-collisions-common-python-names`,
  `argparse-type-callable-stub-mismatch` — real friction from building the CLI, all resolved
- `no-extension-sandbox`, `desktop-packaging-gap` — known upstream gaps, tracked for later phases
- `chat-subsystem-scale`, `graph-fanout-dedup`, `file-move-schema-migration`,
  `lsp-dap-client-unresearched`, `jac2js-compiler-quirks` — strategic/architectural notes from
  the planning pass, relevant to Phases 1–6

## Update — 2026-08-23: service-registry spike run and closed

The **service-registry spike** (`internal/service-registry-spike/`) is done: a real `ConfigService` +
`CommandRegistry` + `FileTreeService` slice, interacting through the graph exactly as
`architecture.md` proposed. **Result: validated, with two mandatory implementation rules,** the
second of which was only caught after an initial fix shipped incomplete:

1. A fresh `[root-->[?:Type]]` query measured ~600us/call under `jac run` — too slow to call on
   every access on a hot path (keystroke handling). Fix: cache the resolved node reference,
   **keyed by `jid(root)`, not a single bare value** — `root` is bound to whoever is calling, not
   a process-wide constant, and a non-keyed cache verifiably leaked one user's node into another
   user's request once tested with two logged-in users. Keyed correctly, cached reads drop to
   ~0.06us/call with no cross-user leakage.
2. That keyed cache still doesn't fix cross-test leakage on its own: `jid(root)` is the *same*
   identity across different tests sharing one `jac test` worker (unlike real distinct users),
   so every such service also needs a `_reset_<x>_cache_for_tests()` hook, called at the top of
   any test exercising it. Two different problems, two different fixes.

Both rules are folded into `architecture.md`'s service-registry section for Phase 1+ service code,
and logged as tracker entries `2026-08-23-service-registry-query-cost` and
`2026-08-23-service-cache-test-isolation` (plus a still-open, lower-priority question about
whether jaseci could expose a runtime-level snapshot-read primitive instead:
`2026-08-23-service-registry-snapshot-read-primitive`). Full writeup, including the multi-user
regression test that caught rule 1's initial gap: `internal/service-registry-spike/README.md`.

## Update — 2026-08-23: minimal scaffold created, prefix-sum-computer translated and landed

Two more things happened, on a separate branch started before the update above merged:

1. **The minimal project scaffold now exists** — a hand-written `jac.toml` at the repo root
   (`[project] kind = "cli"`, deliberately minimal: no client yet, since Phase 1's editor core is
   headless-only per `roadmap.md`; upgrading to `web-app` is a cheap jac.toml edit deferred to
   Phase 2's workbench shell, not a rebuild). `src/` is where ported/built editor-core modules
   live, matching the path convention `translator-strategy.md`'s manifest example already assumed
   (`src/editor/model/...`).
2. **`prefix-sum-computer` is translated and landed** — the first real translation through the
   whole extract→translate→verify loop, not just the tooling around it. Both `PrefixSumComputer`
   (lazy, O(log n) `get_index_of`) and `ConstantTimePrefixSumComputer` (eager, O(1) amortized) are
   ported to `src/editor/model/prefix_sum_computer.jac`, with all 48 of upstream's ported tests
   passing (`src/editor/model/prefix_sum_computer.test.jac`). `internal/translator/manifest.toml`'s entry
   is `status = "landed"`, verified via the tool's own `verify` command, not just manually.

Two real findings surfaced during the port, both logged:

- **A translation bug caught by the ported tests, not by review**: upstream's own test file wraps
  `PrefixSumComputer` in an adapter (`IPrefixSumComputer`/`createBoth`) that converts its
  index-based `get_prefix_sum` (`0<=j<=index`) to the count-based convention
  (`0<=j<count`) the shared test assertions and `ConstantTimePrefixSumComputer` both use. Missing
  that adapter and calling the raw method directly is a real bug (`get_prefix_sum(0)` returns
  `values[0]`, not `0`) — this is exactly the value of porting the *tests*, not just eyeballing
  the port for correctness (`translator-strategy.md`'s own point). Fixed with a small
  `_PrefixSumComputerAsCount` wrapper in the test annex, mirroring upstream's own structure.
- **`obj` equality does not match its documented behavior** — logged as
  `2026-08-23-obj-equality-not-structural`, still open. `==` on a plain `obj` is identity
  comparison, not the dataclass-style structural equality the language docs claim, and a
  hand-written `__eq__` override has no effect on `==` either. Every value-object comparison in
  the ported test file compares fields directly instead of upstream's
  `assert.deepStrictEqual`-equivalent style. This will recur on `interval-tree` and
  `piece-tree-base`, both of which return comparable result structs from their own tests.

Also worth knowing for next time (not tracker-worthy, just a workflow note): `jac clean --all
--force` wipes a project's `.jac/venv` along with cache/data, so `jac install` needs re-running
after — cost a few minutes rediscovering this on the translator's own project mid-session.

## Update — 2026-08-23: interval-tree translated and landed — Phase 0 exit criteria met

`interval-tree` (`intervalTree.ts` → `src/editor/model/interval_tree.jac`) is the second and
last of the two small modules `roadmap.md`'s Phase 0 exit criteria called for. Much larger and
more tightly coupled than `prefix-sum-computer` (a full red-black tree with lazy delta-offset
propagation and `maxEnd` augmentation, ~1281 upstream lines) — a real test of the translator
workflow at a size that actually stresses it, not just a toy case. 25/25 ported test blocks pass:
18 generated differential-testing regressions against a naive Oracle (asserting tree invariants —
red-black coloring, augmented `maxEnd`, in-order sort order — after every mutation), a
forced-delta-overflow case, 5 Cormen-textbook search cases, and a 208-case `nodeAcceptEdit` table
(mechanically extracted from upstream's own test source via script, not hand-transcribed, to
eliminate transcription risk on data that repetitive). Verified through the translator's own
`verify` command, manifest status `landed`.

**Scope call, made deliberately, not by omission**: `options: ModelDecorationOptions` and
`range: Range | null` are untyped placeholders here. Neither `ModelDecorationOptions`
(`textModel.ts`) nor `Range` (`core/range.ts`) is translated yet, and the ported upstream test
suite never constructs or reads either field — every test drives the tree purely through
start/end/id/owner_id and the bit-packed metadata flags. `set_options()` (the only method that
touches `options`'s shape) is deliberately not ported; building it now would mean guessing at an
unported class's shape with nothing to verify against. Port it for real once
`ModelDecorationOptions` exists.

Two more real findings, both affecting future translations, especially `piece-tree-base`:

- **`node` and `include` are reserved Jac keywords** — not just `root`, which is all this
  project's `jac-language` skill had previously flagged. `node` is the single most natural
  variable name for any tree/graph algorithm, and this file used it ~280 times (matching
  upstream's own naming) before a whole-file rename to `nd` was needed — 205 cascading parse
  errors from that single collision. `piece-tree-base` (also a tree) will hit this at larger
  scale if not anticipated going in. Logged as `2026-08-23-node-is-a-reserved-keyword`, resolved
  (not a doc gap — `jac-core-cheatsheet` already lists the full reserved set; this was a
  translation session not cross-checking it first), added to the `jac-language` skill's gotcha
  list so the next translation checks variable names before writing the bulk of a module.
- **A method calling a bare name matching a module-level function of the same name recurses into
  itself, not the free function** — unlike TS/JS, which resolve a bare (non-`this.`-prefixed)
  call inside a method to module scope. Upstream's `IntervalTree.search(...)` relies on exactly
  this TS-only trick to call a same-named top-level `search(this, ...)`. Fixed by giving the free
  functions an `_impl` suffix, called explicitly from the methods that wrap them. No tracker entry
  (an ordinary translation bug, not a Jac limitation) — added to the `jac-language` skill's
  gotcha list since it's a real scoping-model difference worth knowing before the next module
  with this same upstream pattern (piece-tree-base's `TextBuffer` class likely has it too).

**Phase 0 is now formally complete.** All three exit criteria from `roadmap.md` are met:
service-registry pattern validated (with its two caching rules), translator workflow proven on
two modules (`prefix-sum-computer`, `interval-tree`), tracker live with 18 real entries from this
phase's own friction. See `roadmap.md`'s Phase 1 section for what's next — the piece-tree buffer,
this project's largest and highest-stakes translation so far (`risk_tier = "foundational"` in the
manifest, meaning a supervised single-module session with real review, not the lighter-touch pace
`prefix-sum-computer`/`interval-tree` got), plus the first native Jac client component built on
top of it.
