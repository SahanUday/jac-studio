---
id: 2026-08-23-editor-core-native-vs-monaco-decided-native
date: 2026-08-23
category: workaround-found
severity: note
status: resolved
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [editor-core, decision-point, architecture, native, monaco]
---

## What we tried

`docs/architecture.md`'s open questions left the editor-core rendering direction explicitly
undecided: keep building the from-scratch Jac client component (`text_editor.jac`), or bridge to
the real `monaco-editor` npm package via client-only npm interop, per the roadmap's Phase 1
"decision point -- make this call with the working prototype in hand." Built the working
prototype (PRs #10/#11) and used it to gather real evidence rather than deciding from the
architecture doc's fallback description alone.

## What happened

Decided: **continue native.** Evidence from the prototype:

- The full round trip works end to end, verified with a real running server and `jac browse`, not
  just `jac check`: typed input, backspace, forward-delete, and all four arrow keys correctly
  round-trip through the real ported `PieceTreeTextBuffer`.
- Two real gaps found, both bounded and understood, neither a genuine architectural block: no
  per-keystroke request queuing (fixed, PR #11,
  `2026-08-23-client-editor-no-per-keystroke-request-queuing`) and no rendering virtualization
  (still open, not required by Phase 1's exit criteria -- a later-phase performance concern once
  real files are in play).
- The deciding tradeoff: Monaco brings its own complete text model and input pipeline. Adopting
  it would not *compose* with the ported piece-tree buffer -- it would largely *replace* its role
  in live editing. That buffer is the single largest translation this project has done
  (`piece-tree-base`/`piece-tree-text-buffer`/`piece-tree-text-buffer-builder`,
  `translator/manifest.toml`). Going Monaco would strand most of that investment for the
  live-editing path specifically (it would still validate the translator methodology and could
  back other things later -- search, decorations -- just not the editing surface itself).
- Per `architecture.md` principle 2 ("everything in Jac unless genuinely blocked, and every block
  gets logged"): nothing found in this prototype constitutes a genuine block. Both gaps are
  ordinary, boundable engineering work.

## Plan

Resolved, not a workaround -- this is the permanent architectural decision, not a stopgap.
`docs/architecture.md`'s open-questions section and `docs/roadmap.md`'s Phase 1 entry updated to
reflect it. Future phases build on the native client component; the Monaco-embed bridge described
in `architecture.md`'s "Editor core" section remains documented as the path not taken, in case a
future phase's performance data reopens the question -- but it is not the active plan.

**Addendum -- 2026-08-23, reaffirmed after direct scrutiny.** Worth being precise about what this
decision's evidence actually covers, since it was initially framed more confidently than it should
have been. The prototype validates the *algorithmic* layer (the piece tree, and that Jac's
client/server round trip is viable for it) and a bare insert/delete/arrow-key loop -- it does
**not** validate the much larger "build fresh" rendering/interaction layer
`docs/architecture.md`'s own Editor Core section already calls "the hardest, most novel piece":
IME composition, multi-cursor, selection, bidi/RTL text, virtualized rendering for large files,
accessibility, folding, the minimap. None of that has been built or tested yet. Monaco -- which
*is* upstream VS Code's own editor component, not a third-party alternative to it -- ships all of
that already, maintained by Microsoft.

Reaffirmed as native anyway, explicitly eyes-open about that remaining scope: per
`architecture.md` principle 2, that scope is exactly where jac-lang gets genuinely stress-tested,
which is a stated goal of this project, not incidental to it -- and it's the piece that keeps the
ported piece-tree buffer load-bearing rather than stranded. Recorded here so a future session
doesn't read "decided: continue native" as "the hard part is proven out" -- it is not; only the
foundation under it is.
