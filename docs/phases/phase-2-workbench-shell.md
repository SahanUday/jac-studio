# Phase 2 — Workbench shell MVP

Status: **complete** — 2026-08-25. All exit criteria in [`../roadmap.md`](../roadmap.md) are met:
a folder can be opened, browsed in a lazy-loading tree, multiple files opened in tabs, the editor
split into resizable side-by-side groups, and a handful of real commands run via the palette or
scoped keybindings — a genuinely usable single-user local editor, matching upstream VS Code's own
earliest-usable-build bar. This doc is the record of how Phase 2 actually went, written later than
it should have been (see "Deviations" below) — Phase 3 (settings, persistence, workspace state) is
next; see the roadmap's Phase 3 section. Read this before touching workbench-shell code — it's the
fastest way to get oriented without re-reading ten PRs from scratch.

## Goal (from roadmap.md)

The app *looks and behaves* like an editor, built almost entirely by composing the shadcn-in-Jac
primitives already available (`Sidebar`, `Resizable`, `Command`, plus a hand-built tree component
shadcn doesn't ship) rather than hand-rolling workbench chrome from scratch.

## What's actually been built so far

**File tree sidebar** (PR #17, validated first by the workspace-graph spike, PR #16) — lazy,
expand-on-demand loading over the `Workspace --Contains--> Folder --Contains--> File` graph model,
per the spike's own measured constraint (eager scan-and-traverse took ~3 seconds combined at real
scale, too slow to feel instant on open).

**Tabs** (PR #18) — open-file tabs wired to the file tree, backed at the time by the archived
native editor engine.

**Editor engine reversed to Monaco** (PR #19) — mid-phase decision reversal, not originally
planned: switched from the from-scratch ported piece-tree engine (Phase 1's own deliverable) to
embedding the real `monaco-editor` npm package. A reuse-over-reinvention call, not a verdict that
Phase 1 failed — see `architecture.md`'s Editor Core section and tracker entry
`2026-08-25-editor-core-decision-reversed-to-monaco` for the full reasoning. The native engine is
archived, not deleted, at `internal/native-editor-archive/`.

**Editor-group splitting** (PR #21) — side-by-side resizable panes via shadcn's `Resizable`
primitive, `groups`/`active_group_id` replacing the earlier flat `open_tabs`/`active_path` shape.

**Command palette** (PR #22) — `Command`/`CommandDialog` wired to a graph-backed `CommandRegistry`
(`Command` nodes reached via a `Contributes` edge, the first real consumer of `architecture.md`'s
contribution-registry pattern outside the Phase 0 spike). Metadata lives server-side; execution
dispatches entirely client-side through `workbench.jac`, since every Phase 2 command is a
client-only UI-state mutation with no server-side effect to invoke.

**Status bar** (PR #23) — cursor position only, no contributions yet, per the roadmap's explicit
scope for this bullet.

**Integrated terminal** (PR #24) — xterm.js UI, `run_in_terminal` streaming a spawned process's
output back over SSE, deny-by-default behind a `[terminal] enabled` gate in `jac.toml` (jac-studio
ships as a `web-app` kind project, so the `@jac/desktop` `shell` capability `architecture.md`
originally scoped this behind isn't reachable — this project reads its own config section instead,
same "must be explicitly granted" posture). One-shot process spawn per Enter press, not a
persistent shell session — a deliberate, stated v1 scope cut (`cd`/exported env vars don't persist
between commands), the same kind of scope boundary the keybinding system below drew for itself.

**Keybinding "when clause" context system** (PR #25) — the roadmap's last Phase 2 bullet. A
capture-phase `document` keydown listener in `workbench.jac` matches a combo string against each
`Command`'s `keybindings` (`{"key", "when"}` pairs) and evaluates a single optionally-`!`-negated
context-key name against a flat `context: dict[str, bool]`, populated by leaf components (the
terminal reports `terminalFocus`). Demonstrated with a real, not contrived, case: `Escape` closes
the terminal only when it has focus, so it doesn't fire from anywhere else in the app.

**A first-ever real-browser verification pass, and seven real bugs it found** (PRs #26, #27) —
every prior Phase 2 PR had been verified via `jac check`/`jac test`/compiled-bundle
inspection/RPC probes, never an actual rendered page, until the user ran `jac start` manually and
screenshotted a completely unstyled app. Using `jac browse` (headless CDP automation) to actually
load and interact with the app found, in order: (1) `main.jac` never imported the global
stylesheet, since the project's inception — zero CSS had ever shipped; (2) the `jac install
--shadcn command`-generated `CommandDialog` never wrapped its children in the `cmdk` `Command`
root, crashing the palette on every open (a real generator defect, not jac-studio's own bug — see
tracker entry `2026-08-25-shadcn-command-generator-missing-root-wrapper`); (3) the terminal sized
itself and wrote its welcome banner while its panel was still `display:none` (0×0), so it never
showed visible content, plus the official `@xterm/xterm/css/xterm.css` was missing (load-bearing
for `.xterm-screen`'s positioning, not just cosmetic as first assumed); (4) `dark` mode was never
activated anywhere, so every shadcn-driven surface rendered in light theme next to the
hand-styled-dark tab bar/terminal/status bar; (5) `workspace_service.jac`'s `get_or_create_workspace`
silently ignored a changed `root_path`, so reopening a different folder kept showing the first one
ever opened; (6) a real concurrency race in the check-then-create pattern used by both the
workspace scanner and the command registry could duplicate graph nodes — see "Key decisions" below
for why the real fix ended up being read-side deduplication, not a lock; (7) `@monaco-editor/react`
disposes its shared-by-`path` text model on unmount by default, so splitting the editor and closing
one copy of a file blanked the *other* group's still-mounted editor for the same file.

## Key decisions made

- **Command execution stays entirely client-side; only metadata lives server-side.** Reasoned
  through explicitly before building the palette: every Phase 2 command is a workbench UI-state
  mutation (split a group, close a tab, toggle the terminal), not something with a server-side
  effect — so `CommandRegistry`/`Command` nodes hold `command_id`/`title`/`keybindings` for
  discovery and display, and `workbench.jac`'s `handle_command` is the one place that maps an id
  onto a client-side ability. Add a server-side `run_command` only once a real command needs one.
- **A closed tab's shared Monaco model is never explicitly disposed — a deliberate accepted leak.**
  `keepCurrentModel={True}` (finding 7 above) means a model can outlive any single editor instance
  showing it, which is correct for split-editor-same-file but means nothing frees it on tab close.
  Accepted for the same reason `workspace_service.jac` already accepts orphaned `Folder`/`File`
  nodes on workspace reopen: this is a local, single-user dev tool, not a long-running service
  where memory needs active reclamation.
- **Read-side deduplication, not write-side locking, is the actual guarantee against duplicate
  graph nodes.** The first fix attempt for finding 6 above was a Python `threading.Lock()` around
  the check-then-create sequence — verified insufficient live, on a freshly-dropped database, not
  just theoretically. Root cause (tracker entry
  `2026-08-25-write-conflict-never-raised-session-commit-blind-retries`): a `def:pub` function's
  actual Postgres commit happens in server middleware *after* the function returns, so any
  in-function lock releases before the write is durable — a second concurrent call can start
  executing after the first one's Python code finished and still read a pre-commit view. jaseci's
  own documented protection for this (a `SERIALIZABLE` transaction plus a `WriteConflict`-catching
  replay-from-start) doesn't currently fire: `WriteConflict` is never raised anywhere in the
  runtime, and `Session.commit`'s own conflict recovery blindly re-flushes already-decided writes
  rather than re-running the caller's check. Fixed by moving the guarantee to the read path
  instead: `list_commands()`/`list_children_by_path()` de-duplicate their return value by natural
  key before it reaches the client, correct regardless of what the graph holds underneath. **This
  is a load-bearing lesson for Phase 3's persistence work**, not just a Phase 2 footnote — any new
  "get node if exists, else create" pattern in the settings/workspace-state code Phase 3 is about
  to write needs the same read-side dedup discipline, not just a lock, or it will hit the identical
  gap.
- **Deny-by-default is jac-studio's own convention, not `@jac/desktop`'s, for the terminal.**
  Because the project ships as `kind = "web-app"`, not `desktop`, `architecture.md`'s original
  `@jac/desktop` `shell`-capability gating isn't reachable — `[terminal] enabled` in `jac.toml`,
  read via `JacConfig.get_section`, reproduces the same "must be explicitly granted" posture using
  a mechanism this project's actual runtime shape can reach.

## Deviations from the original plan (found by actually building, not assumed upfront)

- **No real browser verification happened until after all eight roadmap bullets had already
  shipped.** Every PR from #17 through #25 was verified via `jac check`/`jac test`/compiled-bundle
  inspection/RPC probes — necessary checks, but not sufficient ones, and nothing in that set can
  catch broken CSS wiring, a runtime component crash, or a layout-timing bug that only shows up
  when something actually renders. This is the single largest process deviation of the phase, and
  it's why PRs #26/#27 (seven real, sometimes severe bugs — a completely unstyled app, a palette
  that crashed on every open) exist as separate late-phase work instead of never happening.
  `jac browse` should be treated as a required verification step for UI-affecting work going
  forward, not an occasional spot-check — see the `feedback_jac_studio_browser_verification`
  memory this finding produced.
- **Regression tests were not written alongside PRs #26/#27's fixes**, contrary to
  `jac-studio-implementation`'s explicit "write tests alongside the code, not after being asked"
  rule. Every fix in those two PRs was verified live via `jac browse` (screenshots, DOM inspection,
  concurrent-request stress tests) but none of that became a `.test.jac` regression test — the
  dedup-on-read logic in particular is exactly the kind of pure server-side logic that could and
  should have gotten `jac test` coverage and didn't. Carried forward as a "what's left" item below.
- **Real ARIA semantics were not built into the workbench-shell components**, contrary to
  `vscode-feature-gap-analysis.md`'s explicit Phase 2 note ("build workbench components with real
  ARIA semantics from day one, even before dedicated accessibility features are scoped, since
  retrofitting is much more expensive than building in"). `file_tree.jac`'s tree rows and
  `editor_tabs.jac`'s tab row are both hand-rolled `<div>`/`<span>` elements with `onClick` handlers
  and no `role`/`aria-*`/keyboard-navigation support. Not fixed in this phase; carried forward
  below rather than silently dropped.
- **Tracker entries for the browser-verification pass's real findings were not logged in the same
  sitting they were found**, contrary to `jac-studio-challenge-tracking`'s explicit "not optional...
  in the same sitting" instruction. The `write-conflict-never-raised` and
  `shadcn-command-generator-missing-root-wrapper` entries, and a correction to the pre-existing
  `jac-run-persists-state` entry with the now-fully-root-caused Postgres mechanism, were all landed
  only once this phase doc itself was being written — after the fact, not during. This doc, the
  tracker entries, and the process-fix memory above are the direct product of catching that gap.

## Blockers logged during this phase

- `2026-08-22-graph-fanout-dedup` (resolved) — a Phase 2 planning-adjacent note.
- `2026-08-24-client-dict-literal-variable-key-miscompiles` (workaround) — a bare-identifier dict
  key in client code silently miscompiles to an invalid JS object key; hit twice for real (status
  bar's cursor-position map, then again independently in workbench.jac's context dict) before the
  spread-plus-bracket-assignment workaround became reflexive.
- `2026-08-24-client-import-alias-breaks-rpc-route-name` (workaround) — an aliased client-facing
  `def:pub` import silently calls the wrong RPC route name.
- `2026-08-24-jac-run-persists-state-jac-clean-does-not-reset` (resolved, corrected 2026-08-25) —
  originally an open "not investigated further" question from the workspace-graph spike; fully
  root-caused during this phase's browser-verification pass (embedded Postgres at
  `~/.cache/jac/pg/main`, `jac db list`/`jac db drop` as the real reset mechanism) once the
  identical symptom recurred via `jac start`/`jac dev`.
- `2026-08-24-test-annex-self-import-breaks-unrelated-runs` (workaround).
- `2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale` (resolved) — the spike finding
  that set the file tree's lazy-loading requirement.
- `2026-08-25-editor-core-decision-reversed-to-monaco` (resolved) — the decision-point record for
  the mid-phase engine switch.
- `2026-08-25-root-test-sweep-crosses-internal-subproject-boundary` (workaround) — `jac test .`
  (explicit path) sweeps nested subprojects' `.test.jac` files; bare `jac test`/`jac test src`
  don't.
- `2026-08-25-shadcn-command-generator-missing-root-wrapper` (workaround-found) — see finding 2
  above; a real jaseci tooling defect, not jac-studio's own bug.
- `2026-08-25-write-conflict-never-raised-session-commit-blind-retries` (workaround-found) — see
  finding 6 and "Key decisions" above; the phase's most significant finding.

## What's left / suggested next steps

Phase 2's exit criteria are fully met; nothing here blocks Phase 3, but none of it should be
silently dropped either:

1. **ARIA semantics retrofit** for `file_tree.jac`'s tree rows and `editor_tabs.jac`'s tab row
   (real `role="tree"`/`role="treeitem"`/`aria-expanded` and `role="tab"`/keyboard navigation) —
   deferred out of this phase, not designed yet. Worth doing before Phase 2's component shapes get
   copied as the pattern for Phase 3/4 UI, so the gap doesn't compound.
2. **Regression tests for PRs #26/#27's fixes** — the read-side dedup logic in
   `list_commands`/`list_children_by_path` especially, since it's pure server-side logic with no
   real barrier to `jac test` coverage, unlike the CSS/rendering fixes in the same PRs.
3. **The `ResizeObserver loop completed with undelivered notifications` warning is mitigated
   (deferred into `requestAnimationFrame`), not conclusively root-caused.** Current best
   understanding is Monaco's own `automaticLayout` reacting to the same ancestor layout changes as
   jac-studio's other `ResizeObserver` usage, worth revisiting if it becomes more than console
   noise.
4. **Phase 3's persistence work must design around the `WriteConflict`-never-fires gap from the
   start**, not rediscover it the way this phase did — see "Key decisions" above. Any new
   check-then-create pattern in the settings/workspace-state graph code needs read-side
   idempotency, not an app-level lock, as its actual correctness guarantee.
5. Per `jac-studio-architecture`'s own instruction to revisit `vscode-feature-gap-analysis.md`/
   `vscode-complete-triage.md` before each new phase: both were reread while writing this doc.
   Nothing found changes Phase 3's scope as already written in `roadmap.md` — settings/keybindings
   as graph-attached `obj`s, workspace-state persistence, syntax highlighting and a diff-editor mode
   both now largely free via Monaco's own bundled tokenizer and `createDiffEditor`, and a
   `Diagnostic` node type with no producer yet. Proceed with Phase 3 as already scoped.

Per `roadmap.md`, Phase 3 (settings, persistence, and workspace state) starts next — see the
roadmap for the full bullet list and exit criteria.
