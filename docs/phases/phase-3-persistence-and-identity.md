# Phase 3 — Settings, persistence, and workspace state

Status: **complete** — 2026-08-28. All exit criteria in [`../roadmap.md`](../roadmap.md) are met:
closing and reopening the app restores the previous session exactly; settings persist across
restarts; opened files show real syntax highlighting; two versions of a file can be diffed; the
workbench chrome matches VS Code's own current default look, including the activity bar, title
bar, minimap, and Quick Open. Phase 4 (extensions, Part A) is next. Read this before touching
persistence, theming, or any of the workbench-shell chrome added this phase — it's the fastest way
to get oriented without re-reading eleven PRs from scratch.

## Goal (from roadmap.md)

The app remembers things, using Jac's persistence-by-reachability instead of hand-rolled
serialization — settings, keybindings, and workspace state (open tabs, cursor positions, panel
layout) all survive a real restart via the graph, not explicit save/load code.

## What was actually built (PRs #34–#44)

**`Diagnostic` node type** (PR #34) — attached to `File`, data-model-only, no producer yet.
Deliberately built first and alone: Phase 4's task-runner/problem-matcher work and later
language-intelligence work need somewhere to write to from day one, and this bullet was explicitly
scoped as "just the data model."

**Persisted settings and keybinding overrides** (PR #35) — `settings_service.jac` and
`command_registry.jac`'s `KeybindingOverrides`, both graph-attached `obj`s per
`architecture.md`'s data model. This PR is where the phase's single most important finding
surfaced (see "Key decisions" below): a real app-restart test caught that a cached node's `has`
field mutation was never durably committed.

**Workspace-state persistence and restore** (PR #36) — `session_service.jac`; `groups`/
`active_group_id`/`next_group_id`/`terminal_open`/`cursor_positions` all restore from
`load_session()` on `workbench.jac`'s mount. Restore ordering turned out to be load-bearing, not
incidental: `cursor_positions` must be assigned before `groups`, because `groups` becoming
non-empty is what mounts each tab's `MonacoEditorApp` for the first time, and `initialCursor` is
only ever read once, at that mount — assigning in the wrong order silently overwrote just-restored
cursor data with Monaco's own default `(1, 1)` on every restart (caught live via `jac browse`, not
by any test).

**Diff-editor rendering mode** (PR #37) — `monaco_diff_editor.jac`, wrapping
`@monaco-editor/react`'s `DiffEditor`. Confirmed live that it composes with the existing
document-service model; found that `DiffEditor` needs its own differently-named model-retention
props (`keepCurrentOriginalModel`/`keepCurrentModifiedModel`, not the plain editor's
`keepCurrentModel`) for the identical shared-model-disposal reason the plain editor already needed
one. Triggered via the file tree's Alt+Click "select for compare" gesture; a real context-menu
entry for the same action followed later, in PR #43.

**Syntax highlighting confirmed live, not just assumed free** (PR #38) — `jac browse` plus
`monaco.editor.colorize`/`tokenize` confirmed Python/JavaScript/CSS/JSON/Markdown all tokenize for
free from Monaco's bundled languages, closing the "reach a TextMate tokenizer through interop"
question this bullet used to pose for those languages. `.jac` (and `.toml`) are not bundled, so
`jac_language.jac` is a real, scoped Monarch tokenizer written for this project's own dominant file
type. Minimap enabled to match VS Code's default. This same verification pass found the diff
editor's per-side language auto-detection only half-works (see "Key decisions" below).

**Retheme to VS Code's actual default visual identity** (PR #39) — the single biggest surprise of
the phase in scope terms: not originally itemized as its own Phase 3 bullet at the phase's start,
added mid-phase (2026-08-28, PR #32's docs update) once it became clear the Phase 2 chrome used
shadcn's stock `nova`/`neutral` look and `@hugeicons`, not anything resembling VS Code. Checking
the live `microsoft/vscode` source directly found a second surprise on top of the first: the actual
current default is "Dark 2026"/"Light 2026", not the "Dark+"/"Light+" pair originally assumed —
a real correction (the 2026 default drops the classic blue status bar entirely), not a naming
nitpick. Delivered as native `jac retheme` OKLCH tokens (`--baseColor zinc --theme sky --radius
small`) plus hand-edited exact values for tokens the presets can't reach precisely, per
`architecture.md`'s "Visual identity" section. Icon set swapped to the real `@vscode/codicons`
package in place of `@hugeicons` — though this swap turned out to be incomplete until PR #43 (see
below), since only the project's own hand-written components were touched, not the icons baked
into shadcn's own generated primitives.

**Quick Open (Ctrl+P)** (PR #40) — a genuine delivery slip caught while writing Phase 2's own
closing doc: `vscode-complete-triage.md` had already scoped this into Phase 2 as a second
`quickaccess` provider, but it was never built there, and Phase 2 shipped (and was marked complete)
without it. Delivered here as the documented-but-undelivered item it always was. Its file list
comes from `workspace_service.jac`'s new `list_all_files` — a plain `os.walk`, deliberately never
touching the `Workspace`/`Folder`/`File` graph, so it doesn't pay the eager-scan cost
`architecture.md`'s workspace section already ruled out for the file tree.

**Activity bar** (PR #41) — the icon rail switching sidebar views, hand-built since no shadcn
primitive fits (`Sidebar` is a container, not a switcher). Only one real view exists this phase
(Explorer), but the switching mechanism (`active_view_id`, `onSelectView`) is built end-to-end now
so Phase 4's new views (Search, SCM) are a one-entry-plus-one-branch addition. This and the two
items below were all found the same way: a live-source check against `microsoft/vscode` on GitHub
(`gh api`, not just re-reading this project's own docs) found `workbench/browser/parts/*` — a
sibling tree to the two `contrib` trees `vscode-complete-triage.md` had scoped itself to — was
never triaged at all, and `architecture.md`'s mapping table had wrongly folded "activity bar" into
the same row as `Sidebar`.

**Title bar with a Command Center** (PR #42) — the custom title bar plus a Command Center pill
that opens the command palette; no window controls or menu bar (a web app, not a native desktop
host yet, and materially larger scope this bullet never named). Building it surfaced a real gap:
`command_palette.jac`'s `open` state was private, set only by its own self-contained
`Ctrl+Shift+P` listener, so nothing outside it could open the palette. Fixed by lifting that state
to `workbench.jac` and registering `workbench.action.showCommands` — the same move `quick_open.jac`
had already made for the identical reason, so the keyboard shortcut and the title bar's button now
both dispatch through one path instead of two.

**File-tree context menu** (PR #43) — new file/folder, rename, delete, plus a right-click
"Select for Compare"/"Compare with Selected" pair mirroring the existing Alt+Click gesture, via
the shadcn `ContextMenu` primitive. `workspace_service.jac` gained
`create_file`/`create_folder`/`rename_path`/`delete_path`. This PR is where the phase's second
major finding surfaced (see "Key decisions" below): edge deletion inside a `def:pub` doesn't
reliably commit across real HTTP requests, and — found while root-causing that — a plain
application-level dict `del` can corrupt an *unrelated* node's edge reachability. It also finished
PR #39's icon-set swap: `jac install --shadcn context-menu` (and, on inspection, `dialog`, `sheet`,
`command`, `sidebar`) had silently reintroduced `@hugeicons` internally, since only this project's
own hand-written components had been swapped before, not the icons baked into shadcn's own
generated primitive files.

**Tab affordances** (PR #44) — file-type icons (a single `file_icons.jac` helper shared by the
file tree and tabs) and an unsaved-changes dot-vs-close-button indicator, the last Phase 3 bullet.
Dirty tracking threads through `monaco_editor.jac` → `editor_tabs.jac` → `workbench.jac` the same
"leaf reports, parent owns state" shape cursor position already uses, transitioning `False -> True`
once per edit session rather than per keystroke. Found two more real bugs: a `del` statement on a
plain client-side dict has no `jac2js` lowering at all (compiles clean under `jac check`/`jac
test`, fails only in the real dev server build); and a CSS specificity collision between
`@vscode/codicons`' own base rule and Tailwind's `hidden`/`group-hover:` utilities silently
defeated the first hide-on-hover implementation (fixed with opacity/`pointer-events` toggling
instead — not tracker-logged, since it's a collision between two third-party stylesheets, not a
Jac/jaseci gap).

## Key decisions made

- **Cache the `jid`, not the node, for anything an accessor will mutate.** The single most
  important finding of the phase, and a real correction to a rule Phase 0/1/2 had already shipped
  as settled: `docs/architecture.md`'s service-registry pattern says to cache a resolved node in a
  `jid(root)`-keyed `glob` dict. That's correct for *reads* — but a `has`-field mutation made
  through a node cached from an *earlier, separate* request is never durably committed. The bug
  hides in plain sight: the mutation stays visible to every read for the rest of that server
  process's life (including surviving a page reload), so it looked correct in every test that
  didn't kill and restart the actual server — which no Phase 0–2 test ever did. Only caught here
  because Phase 3's own exit criterion ("restores the previous session exactly") demanded a real
  restart test. Fixed by resolving via `jobj(cached_jid)` (documented O(1)) immediately before any
  mutation, instead of writing through the cached object directly — now applied in
  `settings_service.jac`, `session_service.jac`, `workspace_service.jac`, and
  `command_registry.jac`'s `KeybindingOverrides`. See `architecture.md`'s service-registry section
  and tracker entry `2026-08-28-field-mutation-on-cached-node-not-persisted`.
- **Edge deletion has the same "looks committed, isn't" shape as the field-mutation bug above, and
  is not fully closed.** Deleting an edge inside a `def:pub` doesn't reliably take effect for a
  later, separate request's traversal — confirmed live (file deleted from disk correctly, but the
  detached node kept reappearing in later listings) and distinct from the field-mutation finding
  above (this is about edge deletion, not field writes). Worked around, not fixed: the read path
  (`list_children_by_path`) is now authoritative against the real filesystem via `os.path.exists`,
  rather than trusting graph edge state at all. This means `get_or_create_workspace`'s own
  root-switch edge cleanup — shipped in Phase 2, never verified for "does the old parent's listing
  correctly show the child gone" — may carry the same latent gap, simply never triggered in
  practice. Anything built later that needs to durably detach an edge and trust that on a
  subsequent request should not assume it works without its own verification.
- **A plain application-level dict `del` can corrupt an unrelated node's edge reachability** — a
  second, distinct surprise found while root-causing the edge-deletion gap above, not the same bug.
  Reproduced in isolation with a minimal `Parent`/`Child` node pair. The practical rule going
  forward: never delete a stale cache-dict entry keyed by something that also has graph-edge
  significance; leaving it (harmless) is safer than a `del` whose blast radius isn't obviously
  scoped to the dict alone.
- **Native `jac retheme` tokens, not a VS-Code-theme-format compatibility shim, for matching VS
  Code's visual identity.** Decided explicitly, not defaulted into: jac-studio's default look
  should match what a user sees opening VS Code with zero extensions, but achieved by deriving
  `jac retheme`'s own OKLCH tokens from VS Code's palette, not by building an importer for VS
  Code's actual theme JSON format. Whether jac-studio ever supports *installing* third-party
  `.vsix` theme extensions remains a separate, still-open question — see `architecture.md`'s open
  questions.
- **Command execution and dirty-state ownership keep following the "leaf reports, parent owns
  state" shape established in Phase 2** — extended, not reinvented, for every new piece of UI
  state added this phase (`command_palette_open`, `active_view_id`, `dirty_paths`). No new state-
  ownership pattern was needed.
- **No Phase 3 PR used the translator**, and that's consistent with the project's own decision
  procedure, not an oversight — every Phase 3 deliverable is either a redesign (persistence via the
  graph instead of hand-rolled serialization) or build-fresh workbench-shell UI (activity bar,
  title bar, context menu, tab affordances), never a small self-contained algorithm with upstream
  tests to port. Raised as a direct question mid-phase and confirmed by classifying every PR
  against the procedure rather than by assumption.

## Deviations from the original plan (found by actually building, not assumed upfront)

- **Roughly half the phase's scope was added mid-phase, not present in the original Phase 3 bullet
  list.** The visual-identity retheme, Quick Open, activity bar, title bar, and file-tree context
  menu were all added via docs updates (PRs #32/#33) once gaps were found — some by conversation
  ("what does matching VS Code's identity actually mean"), some by rereading Phase 2's own closing
  doc, and the activity bar/title bar specifically by a live-source check against
  `microsoft/vscode` on GitHub that found `vscode-complete-triage.md` had a real blind spot
  (`workbench/browser/parts/*` never triaged at all). None of this was scope creep in the bad
  sense — each addition closed a real, previously-undocumented or previously-slipped gap — but it
  means Phase 3 shipped roughly twice the PR count the phase's original one-paragraph goal
  statement would suggest.
- **The field-mutation persistence bug was only caught because Phase 3's exit criteria forced a
  real restart test.** Every prior phase's persistence-adjacent code had been verified against a
  live but continuously-running server process — sufficient for every property that phase actually
  needed, but never proving durability across a real restart, because nothing had needed to yet.
  This is the same category of lesson Phase 2's closing doc drew from its own late browser-
  verification pass: a verification method that's correct for what it's actually testing can still
  leave a real gap uncovered, if the exit criteria haven't yet forced it to test the right thing.
- **`jac install --shadcn <name>`'s hugeicons re-introduction was a repeat of a gap PR #39 thought
  it had already closed.** PR #39 swapped every hand-written component's icons to `@vscode/codicons`
  and considered the icon-set migration done; PR #43 found that every shadcn-*generated* primitive
  file (`context_menu`, `dialog`, `sheet`, `command`, `sidebar`) still imported `@hugeicons`
  internally, and that running `jac install --shadcn` again for any new primitive would silently
  reintroduce it, since the generator's templates hardcode the dependency with no override
  mechanism. Worth remembering before assuming a "such-and-such is swapped" claim from an earlier
  phase still holds once a new `jac install --shadcn` run happens.

## Blockers logged during this phase

- `2026-08-28-field-mutation-on-cached-node-not-persisted` (blocker, workaround) — this phase's
  most significant finding; see "Key decisions" above.
- `2026-08-28-jac-db-cli-wrong-database-multiple-top-level-jac-files` (minor, open) — found while
  root-causing the entry above: `jac db sql`/`inspect`/`status` (no explicit database name) infer
  the target project by globbing `Path.cwd()` for `*.jac` files, and silently connect to the
  wrong, unrelated, empty database once the project root has more than one top-level `.jac` file.
- `2026-08-28-edge-deletion-not-committed-across-real-http-requests` (blocker, workaround) — see
  "Key decisions" above.
- `2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` (major, workaround) — see
  "Key decisions" above.
- `2026-08-28-shadcn-command-dialog-leaks-dialog-root-props-onto-content` (minor, open) —
  `jac install --shadcn command`'s generated `CommandDialog` spreads its own `props` object onto
  both `Dialog` and `DialogContent`, leaking dialog-root-only props onto the content element too.
- `2026-08-28-client-dict-del-unsupported-by-jac2js` (major, workaround) — see "What was actually
  built" (tab affordances) above.

Not counted above: `2026-08-25-jac-comprehension-over-string-compiles-to-string-map-in-client-js`
is dated inside this phase's working window but its own frontmatter marks it `phase: 2` (found
during Phase 2's ARIA retrofit, PR #30) — listed here only so it isn't mistaken for a Phase 3 gap
by date alone.

## What's left / suggested next steps

Phase 3's exit criteria are fully met; nothing here blocks Phase 4, but none of it should be
silently dropped either:

1. **The edge-deletion durability gap is a workaround, not a fix.** `list_children_by_path` being
   authoritative against the filesystem closes the practical symptom for the file tree, but the
   underlying jaseci gap (`2026-08-28-edge-deletion-not-committed-across-real-http-requests`) is
   still open, and `get_or_create_workspace`'s own root-switch cleanup (Phase 2) has never been
   directly verified against it. Any Phase 4+ feature that needs to durably detach an edge and
   trust the result on a later request should verify it explicitly rather than assume the pattern
   is safe.
2. **`jac install --shadcn <name>` will keep reintroducing `@hugeicons` for every new primitive
   pulled in.** Phase 4's Search/SCM views and Extensions-view work (Phase 5) will likely pull in
   more shadcn primitives — check each new one for the same internal-icon-import issue PR #43 found
   and patch it the same way, rather than assuming PR #39/#43 closed the icon migration for good.
3. **The `jac-db-cli-wrong-database` tooling gap is still open (not just a workaround) and affects
   anyone debugging this project's persistence with `jac db ...` from the repo root**, since the
   repo has more than one top-level `.jac` file. Worth a `cd` into the actual project directory (or
   an explicit database-name argument) as the standing workaround until this is fixed upstream.
4. **The still-open questions from `architecture.md` remain genuinely open, not resolved by this
   phase**: how much VS Code `vscode`-API compatibility to target for the extension system, and
   whether jac-studio ever supports installing VS-Code-compatible third-party theme extensions.
   Phase 4's extension-API compatibility research (checking whether the real
   `jaseci-labs.jaclang-extension` can load largely unmodified) is explicitly scoped to answer the
   first one.
5. **A live-source check against `microsoft/vscode` found real gaps twice this phase** (the
   `workbench/browser/parts/*` blind spot, and Quick Open's Phase 2 delivery slip). Worth treating
   as a standing practice before each new phase, not a one-off — reread
   `vscode-feature-gap-analysis.md`/`vscode-complete-triage.md`, but also periodically re-verify
   the triage doc itself against the live source, the way this phase's `gh api` pass did.
6. **No regression tests exist yet for the two persistence corrections** (cache-the-jid-not-the-
   node, and the edge-deletion-authoritative-filesystem-read workaround) beyond the manual
   `jac browse` restart tests that found them. `workspace_service.test.jac` does cover the new
   file-tree mutation functions themselves, but not a scripted "kill and restart the server, verify
   the mutation survived" regression test — worth adding before this class of bug has a chance to
   silently regress.

Per `roadmap.md`, Phase 4 (extension system, Part A: trusted, in-process) starts next — porting
search-in-files, an SCM shell with a git provider, and a task runner with problem matchers as the
first real "extensions" against the contribution-registry model, plus an Output panel, a
merge-conflict UI, and toast notifications. **Correction (2026-08-31, per project-sponsor
re-prioritization — see `roadmap.md`'s top-of-document note and `architecture.md`'s Extension
System section): the `jaseci-labs.jaclang-extension` compatibility spike named here is no longer
part of Phase 4** — it's deferred, non-blocking research now sequenced into Phase 6. Phase 4
instead gained a bigger, more concrete replacement for the value that spike was chasing: a native
LSP client built directly against `jac lsp` (a real language server already shipped in jaclang
core), plus a DAP client, both promoted into this phase. See the roadmap for the current full
bullet list and exit
criteria.
