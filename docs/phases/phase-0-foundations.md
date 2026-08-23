# Phase 0 — Foundations

Status: **in progress** — 2026-08-23. Living document: updated as Phase 0 continues, finalized
(status flipped to "complete") once its exit criteria in [`../roadmap.md`](../roadmap.md) are
all met. Read this before touching anything in the project — it's the fastest way to get
oriented without re-reading every doc and PR from scratch.

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

**The translator tool** (`translator/`, merged via PR #4) — the full five-component design from
`translator-strategy.md` implemented and validated against real targets, not synthetic ones:
manifest/ledger, eligibility guard, structural extraction (Node/TypeScript-compiler-API shim,
since a spike confirmed Jac's npm interop can't reach it), verification gate, outcome recorder.
27 passing unit tests. Also `translator/land-blocker.sh` — a one-shot script to land a
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
- **Root-graph-as-service-registry**: proposed in `architecture.md`, **not yet validated** — the
  Phase 0 spike for this (a real 3-service slice) hasn't run yet. Don't treat it as settled.
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

The **service-registry spike** (`service-registry-spike/`) is done: a real `ConfigService` +
`CommandRegistry` + `FileTreeService` slice, interacting through the graph exactly as
`architecture.md` proposed. **Result: validated, with a mandatory implementation rule.** A fresh
`[root-->[?:Type]]` query measured ~600us/call under `jac run` — too slow to call on every access
on a hot path (keystroke handling); caching the resolved node reference per process (already
applied to all three services in the spike) drops that to ~0.06us/call. A second finding: that
cache is a plain Python-level `glob`, which survives across tests sharing one `jac test` worker
even though the persisted graph root is isolated per test — every such service needs a
`_reset_<x>_cache_for_tests()` hook, called at the top of any test exercising it. Both findings are
folded into `architecture.md`'s service-registry section as concrete rules for Phase 1+ service
code, and logged as tracker entry `2026-08-23-service-registry-query-cost`. Full writeup:
`service-registry-spike/README.md`.

## What's NOT done yet (Phase 0's remaining exit criteria)

Per `roadmap.md`: the **minimal project scaffold** for jac-studio's actual app (as opposed to the
translator's own `jac.toml`, or the service-registry spike's own throwaway one) doesn't exist yet.
The translator has queued three real modules (`prefix-sum-computer`, `interval-tree`,
`piece-tree-base` in `translator/manifest.toml`) but **no actual translation has happened** —
extraction works, verification works, but no TS module has been ported into real Jac code yet.

## Suggested next steps

In priority order, with reasoning:

1. **The minimal project scaffold** (`jac create` for the actual jac-studio app, distinct from
   `translator/`'s own project and the spike's throwaway one) — needed before Phase 1 can start
   regardless, and now informed by the service-registry spike's caching + test-isolation rules
   (bake the `get_<x>_service()` + `_reset_<x>_cache_for_tests()` shape into whatever service
   modules the scaffold ships with, rather than rediscovering it later).
2. **Then run the translator for real on `prefix-sum-computer`** — the smallest, lowest-risk
   queued module. This is the first genuine test of the whole extract→translate→verify loop
   end to end, not just the tooling around it. Expect this to surface its own findings; log them
   as they happen, not after.
3. **Close Phase 0 formally** (flip this doc's status) once 1–2 are done, then start Phase 1
   (editor core MVP) per `roadmap.md` — porting the piece-tree buffer is the anchor of that phase,
   and it should only start once the translator has proven itself on the two smaller modules
   first, per `translator-strategy.md`'s own ordering.
