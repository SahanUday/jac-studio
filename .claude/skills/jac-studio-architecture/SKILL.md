---
name: jac-studio-architecture
description: This skill should be used when working on jac-studio's architecture or roadmap — deciding how to build a new component, scoping a phase, asking "does this exist in VS Code and do we cover it," or navigating which doc has the answer. Also applies when the user asks about the project's overall plan, current phase, or what's been decided vs. still open.
---

# jac-studio architecture — where to look, how to decide

jac-studio is a from-scratch reimplementation of VS Code in Jac. This skill routes to the right
doc rather than restating their content — the docs are the source of truth; read them, don't
trust a paraphrase (including this one) for anything load-bearing.

## Read this first, every time you resume work

`docs/phases/phase-0-foundations.md` (and whichever later phase doc is current, once they exist)
— it's the fastest way to know what's actually been built, what's still open, and what to do
next, without re-deriving it from scratch or re-reading every doc and PR. If no phase doc exists
yet for the current phase, that's itself a signal — check `docs/roadmap.md` for what phase should
be active and consider writing one at that phase's end.

## The doc map

- **`docs/architecture.md`** — the core proposal: layer mapping, service registry, data model,
  workbench shell, editor core, extension system, process execution/terminal/DAP, language
  intelligence/LSP, the **"rewrite, don't mirror" decision procedure** (see below), open
  questions not yet resolved. Read this before designing any new component.
- **`docs/roadmap.md`** — the 8 phases, in dependency order, each phase's scope and exit criteria.
- **`docs/translator-strategy.md`** — the TS→Jac translator's design and workflow (see the
  `jac-studio-workflow` skill for how to actually run it).
- **`docs/challenge-tracking.md`** — the tracker's design (see `jac-studio-workflow` for the
  logging habit itself).
- **`docs/vscode-feature-gap-analysis.md`** and **`docs/vscode-complete-triage.md`** — before
  assuming a VS Code feature isn't planned for, check the triage doc first; every one of
  upstream's 158 `workbench/contrib`+`editor/contrib` feature areas has an assigned disposition
  (Scoped/Tracked/Excluded/New). Don't re-investigate something already triaged; do add to it if
  a genuinely new upstream feature area comes up that isn't covered.
- **`docs/research/*.md`** — grounding research (upstream VS Code architecture, VSCodium
  packaging, Jac's documented capabilities, idioms from Jac's real example apps). Reference
  material, not decisions — the decisions live in `architecture.md`/`roadmap.md`.
- **`docs/phases/*.md`** — one file per completed/in-progress roadmap phase: what got built, key
  decisions, deviations from plan, blockers hit, and suggested next steps. Write one at the end
  of each phase (see `jac-studio-workflow`).

## The decision procedure (the one thing worth restating, since it governs everything)

For any component being built, ask two questions in order (full reasoning in
`architecture.md`'s "Rewrite, don't mirror" section):

1. **Is this complicated in VS Code because of a TypeScript/Electron limitation, or because the
   problem itself is hard?** TS/Electron-forced → **redesign** it using whatever Jac primitive
   already answers the same underlying need (the graph instead of a DI container, `root spawn`
   instead of a hand-written RPC protocol, a capability system instead of always-on OS access).
   Inherent to the problem → question 2.
2. **Is it small, self-contained, and does upstream have tests for it?** Yes → **translate** it
   (see the translator workflow). No → **build fresh**, informed by reading upstream, never
   copied or mechanically translated.

Real examples already decided, for calibration: service registry, IPC, terminal capability
gating, chat/AI assistance → redesign. `prefixSumComputer.ts`, `intervalTree.ts`,
`pieceTreeBase.ts` → translate. The editor's rendering/interaction layer → build fresh.

## Things that are proposed but explicitly NOT yet validated

Don't treat these as settled just because they're written down — `architecture.md` frames them
as hypotheses:

- Root-graph-as-service-registry (Phase 0 spike not yet run as of the last phase-0 doc update)
- Whether a Monaco-embed bridge is needed for the editor core, or the native port is fast enough
- How much VS Code `vscode`-API compatibility to target for the extension system
- Color/icon theming: VS-Code-compatible installable themes vs. Jac's own `jac retheme`

Check the current phase doc and `architecture.md`'s "Open questions" section for the live status
of each before assuming an answer.

## Stuck, surprised, or found a real gap?

Don't work around it silently and don't guess past it. See the `jac-studio-workflow` skill's
"When you hit a blocker" section — it applies to every phase and every subsystem (editor core,
workbench, extensions, persistence, desktop, tooling, translator — not just the translator, even
though most tracker entries so far happen to be translator-related since that's the only thing
built so far).
