# Phase 5 — Native AI coding-tool integrations

Status: **complete** — 2026-09-04, closed by explicit project-sponsor direction. Exit criteria in
[`../roadmap.md`](../roadmap.md) are met: Claude Code is usable end to end inside jac-studio for a
real coding task, with its own auth flow and output surfaced through Phase 4's Output/notification
infra. This doc stays as the record of how Phase 5 actually went; Phase 6 (extension system, Phase
B) is next per the roadmap's own ordering, though nothing in it depends on this phase's closure.
Read this before touching the Claude Code integration again — it's the fastest way to get oriented
without re-reading eight PRs and two research docs from scratch.

## Goal (from roadmap.md)

A small, explicitly-named set of external AI coding tools work natively inside jac-studio, without
building a generic mechanism for arbitrary third-party chat/agent extensions to plug in (that stays
deferred to the extension-system Phase B/C track). Exit criteria: at least one of the three named
tools (GitHub Copilot, OpenCode, Claude Code) usable end to end for a real coding task, not a
mock/demo, with its own auth flow and output surfaced through the Output/notification infra.

## What was actually built (PRs #69–#76)

- **#69 — Native Claude Code chat integration.** The foundation: `claude_code_client.jac`
  (subprocess-only, gated behind `[terminal] enabled`) + `claude_code_launcher.py` (plain Python,
  not `.jac` — see "Key decisions" below) + `ai_chat.jac`'s sidebar panel. Real SSE streaming, real
  multi-turn continuity via the SDK's own `resume` mechanism. Met this phase's exit criteria on its
  own.
- **#70 — Reframe AI-integration plan (docs-only).** Two research passes (a live `microsoft/vscode`
  checkout's actual Copilot Chat source; jaseci's own native agentic capabilities) found Copilot's
  own "Fix"/"Explain" quick-fix menu, inline chat, and inline completions are all built on generic,
  backend-agnostic Monaco/editor APIs, not Copilot-specific mechanisms — reframing the rest of this
  phase from "build three more subprocess integrations" to "build new UI entry points against the
  one provider interface already shipped." See `architecture.md`'s "Reframed 2026-09-03" subsection
  and both linked research docs for the full reasoning.
- **#71 — MCP wiring.** `jac mcp` (a real, working first-party MCP server — confirmed via
  `jac mcp --inspect`: 140 resources/19 tools/9 prompts) pointed at from `claude_code_launcher.py`'s
  `ClaudeAgentOptions.mcp_servers`, giving Claude Code structured Jac-specific tools instead of
  shelling out through Bash for the same work.
- **#72 — Tool approval/confirmation.** The single most-flagged trust/safety gap from the reframe's
  own audit: without it, every Edit/Write/Bash/MCP call ran with the SDK's silent non-interactive
  default (confirmed live: a plain `Write` call was outright denied, invisibly). Wired
  `ClaudeAgentOptions.can_use_tool` to emit an approval-request event and block on a real
  approve/deny card in `ai_chat.jac`.
- **#73 — Multi-file edit review.** A real Monaco diff (`ai_tool_diff_preview.jac`) inside each
  `Edit`/`Write` approval card, computed server-side before the tool call ever runs — closes the
  second trust/safety gap the same audit surfaced (a silent overwrite with no preview).
- **#74 — AI code actions.** The "Fix"/"Explain"/"Modify" lightbulb menu
  (`ai_code_action_provider.jac`, a Monaco `CodeActionProvider` registered for every language),
  routing through the already-shipped sidebar via a new `onAskAI` callback — no new backend call.
- **#75 — Inline chat.** A `Ctrl+I` popover (`inline_chat_widget.jac`), a real Monaco content
  widget with React content mounted via `ReactDOM.createPortal` — the first case in this project of
  React rendering into a Monaco-owned DOM node rather than the other direction. Found and fixed a
  real, previously-undiscovered bug along the way: Monaco's standalone `addCommand` doesn't scope
  keybindings per editor instance, which also silently affected the pre-existing `Ctrl+S`.
- **#76 — Richer agent-session visualization.** Replaced the plain `"[Using X...]"` text marker
  with a structured step card per tool call (name, input, running/done/error status, real result
  text), driven by widening the launcher's single bare `tool_use` event into a three-event
  lifecycle (`tool_use_start`/`tool_use_input`/`tool_result`).

Every PR above was live-verified end to end (`jac browse` against a real `jac run --serve --dev`
session, real credentials, screenshots), not just `jac check`/`jac test` — see each PR's own
description and `architecture.md`'s corresponding numbered item for the full verification record.

## Key decisions made

- **`claude_code_launcher.py` is plain Python, never imported into `.jac`-compiled code.**
  `import claude_agent_sdk` pulls in a dependency closure (mcp, pydantic, httpx2, truststore,
  click) that explodes jaclang's own compiler/type-checker with hundreds of errors — confirmed live
  before this design was settled, not assumed. Mirrors `dap_launcher.py`'s identical role for
  debugpy.
- **The tool-approval decision crosses OS processes via a hardcoded `/tmp` file**
  (`_TOOL_APPROVAL_FILE`), reusing `dap_client.jac`'s `_DAP_COMMAND_FILE` pattern verbatim — the
  launcher, and the separate RPC call carrying the user's decision, are different processes with no
  shared `glob` state reaching between them.
- **A tool call's full lifecycle is three events sharing `tool_use_id` as the join key**
  (`tool_use_start`/`tool_use_input`/`tool_result`), the same pairing shape
  `tool_approval_request`/`approve_tool_call` already established — confirmed live (a direct
  `query()` probe against the SDK) that a `can_use_tool` denial reaches the client through the
  identical `tool_result` event as a real execution, which let `handle_approval_decision` drop a
  redundant local note it no longer needed.
- **`ClaudeAgentOptions.model` is pinned to `"haiku"`, permanently, not just for one PR's live
  testing.** Every feature in this phase was exercised for real (real server, real API calls) per
  jac-studio's own "verify empirically" discipline — pinning to the cheapest model keeps that
  affordable across the whole run of AI-integration work, decided explicitly by the project sponsor
  mid-Phase-5 (2026-09-04) to apply going forward, not only to the PR it was first added for.
- **Synthetic Monaco model URIs are keyed by `tool_use_id`, not just file path**
  (`ai_tool_diff_preview.jac`), extending `scm_diff_editor.jac`'s established pattern one step
  further — this card, unlike a single git diff view, can have multiple concurrent pending requests
  against the same file.
- **A module-level keybinding registry (`_focused_editor_handlers`) replaces Monaco's own
  per-instance `addCommand` routing**, found necessary while wiring `Ctrl+I`: with more than one
  editor tab mounted (the normal case), only the last-registered handler for a chord ever fires,
  regardless of which editor has real focus. `Ctrl+S`/`Ctrl+I` are now registered exactly once,
  globally, dispatching dynamically to whichever editor `hasTextFocus()` at invocation time.

## Deviations from the original plan (found by actually building, not assumed upfront)

- **Only one of the three originally-named tools (Claude Code) was actually built.** GitHub Copilot
  and OpenCode were both named in the original Phase 5 scope but never started — see "What's left"
  below for where they live now.
- **The reframe (PR #70, 2026-09-03) changed the shape of "the rest of this phase" mid-flight**,
  from "three more subprocess integrations" to "new UI entry points against the one provider
  already shipped" — a real finding from reading VS Code's actual Copilot Chat source, not a
  planning guess.
- **MCP wiring landed in `claude_code_launcher.py`, not `claude_code_client.jac`** as the original
  roadmap bullet said — that module never touches `ClaudeAgentOptions` at all, for the same
  import-explosion reason the launcher exists as its own plain-Python process.
- **A systematic follow-up audit (all 84 top-level entries in upstream's `chat/browser/`, not just
  the one screenshot that prompted the reframe) surfaced two trust/safety gaps** — tool approval
  and multi-file edit review — that weren't in the original plan at all, and were built ahead of
  the reframed UI items once found, since they're data-loss/trust risks, not polish.
- **Building `Ctrl+I` surfaced a real, previously-unknown bug in the pre-existing `Ctrl+S`** — not
  something this phase set out to fix, but sharing the exact same root cause and fix shape as the
  new feature's own requirement, so it was fixed in the same PR rather than deferred.
- **The phase was closed with two of its three named tools never started**, by explicit
  project-sponsor direction (2026-09-04) once it became clear the exit criteria were already met
  and continuing to hold the phase open around unscoped future work (Copilot, OpenCode) or
  proposal-stage ideas (the native provider, `.claude-plugin/` discovery) was adding status noise
  rather than real progress. Not a scope cut — those items are real, deferred work, not decided
  against.

## Blockers logged during this phase

- `2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure` (blocker,
  workaround-found) — the finding that forced `claude_code_launcher.py`'s plain-Python,
  subprocess-only shape; see "Key decisions" above.
- `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance` (major,
  workaround-found) — found building inline chat (PR #75), also affected the pre-existing `Ctrl+S`.
  Full investigation and the registry-based fix in the entry itself.
- `2026-09-03-jac-run-kill-leaves-vite-child-process-serving-stale-state` — not caused by this
  phase's own code (a general dev-loop issue), but hit repeatedly during this phase's many live
  `jac browse` verification sessions; logged from a different phase's work, cross-referenced here
  since anyone doing more live AI-integration testing will hit it too.

## What's left / suggested next steps

1. **GitHub Copilot, OpenCode, a native `by llm()` provider, and `.claude-plugin/` bundle
   discovery** are all real, legitimate future work, moved to `roadmap.md`'s "Explicitly out of
   scope for now" section on this phase's closure — not decided against, just no longer implicitly
   part of an already-complete phase. Each needs its own scoping pass (auth/licensing model for
   Copilot/OpenCode; nothing beyond implementation for the native provider and plugin discovery,
   which were only ever proposed) before work starts. Pick these up as their own scoped effort
   whenever prioritized, not as a Phase 5 reopening.
2. **The `ChatProvider`-split question in `architecture.md`** (whether agent-behavior identity and
   model backend should eventually decouple, the way VS Code's `chat.createChatParticipant` /
   `lm.registerLanguageModelChatProvider` do) stays genuinely open — worth revisiting once a
   *second* external-tool provider actually exists and there's a real second data point, whenever
   that happens.
3. **Phase 6's own auth-provider broker** (extension system, Phase B) is a natural fit for
   Copilot/OpenCode's eventual auth needs once either is picked up — worth checking whether they
   can reuse that broker rather than each rolling its own credential storage, per Phase 6's own
   roadmap bullet.
4. **No mid-turn cancel** stays a deliberate v1 scope cut across the whole Claude Code integration
   (`claude_code_client.jac`'s own docstring) — still true, not blocking, but worth remembering
   before any of the deferred items above reuse this provider's shape wholesale.
5. Per `roadmap.md`'s own ordering, **Phase 6 (extension system, Phase B: dynamic loading, a
   manifest format, the Extensions view) is next** — nothing in it depends on any of this phase's
   deferred items shipping first.

## Post-closure QA round (2026-09-05)

The project sponsor's own first real, hands-on testing pass of the shipped Claude Code integration
(following the manual test guide handed off after closure) found two real bugs and three genuine
UX gaps — appended here rather than editing "What was actually built" above, so the record of what
shipped at closure time stays honest; see the PR for this round for the full diff.

- **Bug: a chat turn could silently answer based on the server process's own launch directory
  instead of the real open workspace, and a follow-up turn in the same conversation could hit a
  real, uncaught `PgWireError`.** Root cause: `get_current_workspace()` (a real `root`-scoped graph
  query) was called from inside `start_chat_turn`'s own SSE generator — the first confirmation this
  project's known SSE-generator-isolation risk (previously only tested against plain `glob` state)
  extends to a real graph query with its own DB connection/transaction. Fixed by resolving `cwd` in
  the caller (`ai_chat.jac`/`inline_chat_widget.jac`, an ordinary `await`ed call) and passing it
  into `start_chat_turn` as a plain argument — the same "state needed only at spawn time" pattern
  `dap_client.jac`'s own tracker entry already prescribed. See `claude_code_client.jac`'s docstring
  and tracker entry `2026-09-05-sse-generator-root-scoped-graph-query-unreliable`.
- **UX: tool-step cards redesigned to be collapsed by default** (a one-line summary + status icon +
  chevron, click to expand), matching real-product precedent (VS Code's own Copilot Chat) instead
  of always showing full JSON input/result inline.
- **UX: the primary identity is now "AI Chat" (with a small "via Claude Code" caption), not
  "Claude Code" as the headline** — across the sidebar header, the approval card, code-action menu
  items, and inline chat. Deliberately not a full provider-selector UI (only one real provider
  exists today); see `ai_chat.jac`'s own docstring for the reasoning.
- **UX: the sidebar is now resizable**, and **AI Chat has a "maximize" toggle** giving it the whole
  workbench area on demand (a pure CSS overlay on the same mounted instance, not a second mount
  point — see `ai_chat.jac`'s docstring for why that distinction matters: a real tab or portal would
  have unmounted/remounted the component and lost the live conversation).

**A real, unresolved environmental limitation hit while verifying this round, worth recording
honestly rather than glossing over**: this machine's client-bundle build (`.jac/client/compiled`)
repeatedly, deterministically failed to fully compile several files (`command_registry.jac` among
them — its own client output stayed a two-line stub missing `list_commands`, with zero error
reported anywhere) across many full-cache-clear rebuilds, independent of orphaned-process cleanup,
memory headroom (retried with 1.4–2.9 GiB free and a raised `capped --mem 5G` cap), or a settling
period — a genuinely different, more severe symptom than the already-tracked
`2026-09-03-jac-run-kill-leaves-vite-child-process-serving-stale-state` entry (that one is about
*stale* state surviving a bad restart; this is a *fresh*, single, clean process still silently
under-compiling). A `jac lsp` process unrelated to this work was independently observed consuming
2.8–3.3 GiB RSS and climbing throughout, on a shared, multi-session machine — the most likely
contributing factor, though not confirmed to the kernel/OOM-killer level. This blocked a full
`jac browse` live UI verification pass for this round's changes; verification instead relied on
`jac check` (clean on every touched file) + `jac test` (477 passed, 1 known-expected failure from
`jac.toml`'s temporarily-enabled `[terminal]` flag) + a targeted, successful diagnostic session run
earlier in the same investigation (before the environment further degraded) that directly confirmed
the `get_current_workspace()`-inside-the-generator mechanism using real request/response tracing.
Not logged as a new tracker entry in its own right — the evidence doesn't yet distinguish "a real
jaclang build-pipeline robustness gap" from "this specific machine was overloaded by concurrent,
unrelated sessions at this specific time" cleanly enough to write a confident root-cause Plan
section; worth a properly isolated repro (a dedicated machine/container, nothing else running) if
this recurs.

**Update, same day**: the project sponsor manually tested this round's branch directly (not this
investigation's own broken local server) and confirmed it works — all five items above verified
live, in a real session, by a real user. That reframes the build-failure note above: it's specific
to this one investigation's own local sandbox/toolchain state, not a defect this round's actual
code carries, and not something the sponsor's own working session ever hit. The manual test also
surfaced two more real, genuine gaps, fixed in a second commit on the same branch/PR:

- **UX: assistant text now renders as real markdown** (new `markdown_message.jac`, shared by the
  sidebar and inline chat) instead of raw pre-wrap text — a response's own literal ```` ``` ````/`**`
  markdown syntax was showing up unrendered in the panel, confirmed via a real screenshot. User's
  own messages stay plain text.
- **UX: a "Thinking…" status row (spinner + label) now shows for the whole duration a turn is in
  flight** — nothing previously indicated the agent was actively working between hitting Send and
  the first token/tool call, unlike Claude Code's own CLI or VS Code Copilot Chat, both of which
  show a persistent working indicator for the whole turn.

This second commit's own changes were verified via `jac check` (clean) and `jac test` (478 passed)
only — the local build issue above recurred identically even with 5.2 GiB free (this investigation's
own retry log), which weakens "memory pressure" as the primary explanation and strengthens "specific
to this sandbox's own cache/toolchain state" instead. Given the sponsor's own environment has
already verified the base branch works, and given this file's own scope is a UI text-rendering
change with no new backend surface, live-verifying it there (rather than fighting this local
environment further) is the practical path, not a gap being glossed over.

**Update, same day, twice more**: the sponsor's own live testing of the second commit found two
real regressions of its own, each fixed and pushed as its own commit on the same branch/PR:

1. A genuine compile error (`thinking_indicator.jac`'s `Math.floor()` needed an explicit `as int`
   cast) reached the sponsor's browser before this investigation's own `jac check` pass had been
   committed — a real timing gap, not a false negative in `jac check` itself. Also surfaced,
   immediately following that error in the sponsor's own terminal log, a cascading
   `E7001: no export named 'create_file'` for a completely unrelated file
   (`workspace_service.jac`) — much stronger, causally-linked evidence than anything gathered
   earlier that this investigation's whole "silent partial client-bundle compile" saga above was
   never about memory pressure at all: **a genuine compile error in one file appears to leave the
   client bundler's build in a state where unrelated files silently lose their own exports too,
   with no error reported for those other files.** That's a materially better, more actionable
   root cause than the memory-pressure theory this doc originally recorded — worth a real tracker
   entry if it's confirmed to recur cleanly (a deliberately-broken file plus a clean, isolated
   rebuild, checking whether an unrelated file's exports vanish too), not yet written up formally
   here since this round's own evidence, while strong, is still one incident, not a controlled
   repro.
2. A second real error: `react-markdown`'s own `.d.ts` type declarations disagree with its actual
   runtime export shape (`export function Markdown(...)` is real in `lib/index.js`, but the
   package's actual resolved entry point, `index.js`, re-exports it only as `Markdown as default`)
   — `jac check` trusts the `.d.ts` and passes; the browser's real module linker only sees the
   runtime shape and fails. Fixed via `{ default as Markdown }`, the documented pattern for exactly
   this shape (`jac guide jac-types`'s own `mermaid` example) — confirmed correct afterward by
   directly inspecting the compiled output on the sponsor's own still-running server, not assumed.

A third live-testing round (screenshots of the same conversation before/after a follow-up message)
found two more real UI bugs, both fixed in the same commit: **tool-step cards visibly collapsed to
razor-thin bars once the message list grew** (root cause: each card's `overflow: hidden` wrapper
makes its automatic flex min-height `0` per the CSS flexbox spec, the first thing squeezed under
content pressure in a `flexDirection: column` list — fixed with an explicit `flexShrink: "0"` on
every message entry), and **a visible OS-chrome scrollbar** in the narrow message column (fixed
with `styles/global.css`'s own `no-scrollbar` Tailwind utility, defined at some earlier point but
never actually applied anywhere in this project until now).

A fourth round, comparing directly against a real VS Code Claude Code extension screenshot, found
two more gaps: **the message list didn't auto-scroll to the latest content** (fixed with a `Ref`
on the scrollable container plus a `useEffect` keyed on everything that can add visible content —
`messages`, `is_streaming`, `pending_approvals` — setting `scrollTop = scrollHeight`, applied to
both `ai_chat.jac` and `inline_chat_widget.jac`), and **user and assistant messages were hard to
tell apart at a glance** (fixed by giving only the user's own prompt a distinct boxed card,
matching the reference screenshot's own asymmetry — the assistant's response stays unboxed,
flowing markdown text).

## Second QA round (2026-09-04) — PRs #71–73

Testing MCP wiring, tool approval, and multi-file edit review turned up five more real, unrelated
findings — two genuine bugs and three feature requests grounded in real product/SDK capability,
not invented from scratch. Full detail lives in each touched module's own docstring; summarized
here for the phase-level record.

- **Bug: the sidebar's resize handle showed real white space, not this app's dark theme, when
  dragged wider than the active view's content** — two separate gaps in the vendored shadcn
  `Sidebar` primitive's `collapsible="none"` branch, both in the Explorer view specifically but
  latent in every sidebar view: (1) `Sidebar` hardcodes a `16rem` width regardless of its resizable
  container, so dragging wider left the resize handle's own extra space uncovered — fixed with
  `className="w-full min-w-0"` (Tailwind's `cn()`/`tailwind-merge` resolves the class conflict in
  the caller's favor); (2) none of `file_tree.jac`/`scm.jac`/`outline.jac`'s plain-`<div>` roots
  set an explicit background, so any area they didn't cover fell through the app's `.dark`-class
  scoping (applied to a div *inside* `body`, not `body` itself — see `main.jac`'s own docstring) to
  `body`'s genuinely still-light `--background` — fixed with one `#191A1B` fallback on the shared
  `ResizablePanel` all five sidebar views sit inside, matching this file's own chrome color.
- **Bug: asking the agent to create a file named `scratch_test.txt` wrote it to
  `~/.claude-scratch/<session-id>/` instead of the open workspace**, even though `cwd` was
  confirmed correct in the server's own request log. Root cause: `claude_code_launcher.py` runs as
  the same OS user as whoever's own, separate Claude Code CLI session has a personal global
  `~/.claude/CLAUDE.md` — `ClaudeAgentOptions.setting_sources` defaults to loading every filesystem
  settings source, `"user"` included, so this in-app launcher was reading and obeying that
  unrelated, machine-owner-specific config (a real rule about naming a file literally "scratch").
  Fixed with `setting_sources=["project", "local"]`, excluding `"user"` while keeping the two
  sources genuinely scoped to the open workspace itself. See `claude_code_launcher.py`'s own
  docstring for the full finding — this generalizes beyond this one developer's machine to any
  future jac-studio user with their own unrelated global Claude Code config.
- **Feature: model/permission-mode/effort pickers** in `ai_chat.jac`'s composer, all three backed
  by real `ClaudeAgentOptions` fields the installed SDK already exposes (`model`, `permission_mode`,
  `effort` — confirmed by reading the dataclass directly). `permission_mode`'s four options map
  one-to-one onto the real extension's own "Manual/Edit automatically/Plan/Auto" mode switcher, per
  a side-by-side reference screenshot. `model` still defaults to `"haiku"` on mount — a picker to
  move *off* the cheap default when needed, not a reversal of it.
- **Feature: an `@`-triggered file-attachment picker**, investigated against real VS Code's own
  file-reference mechanism first (`chatDynamicVariables.ts`/`chatAttachmentModel.ts` in a real
  `microsoft/vscode` checkout) before building a proportionate equivalent: file content is resolved
  and prepended to the prompt server-side before the request goes out (`claude_code_client.jac`'s
  new `_build_prompt_with_attachments`), the same "resolve to real content before sending" approach
  VS Code's own attachment model uses, rather than hoping raw `@text` gets parsed downstream. Reuses
  `workspace_service.jac`'s existing `list_all_files` (the same RPC `quick_open.jac`'s Ctrl+P
  switcher already calls) through a `CommandDialog` picker. One-shot per turn, not persisted pinned
  context across a conversation — a deliberate v1 scope cut to avoid silently re-sending the same
  file's content (and cost) on every follow-up.

**Update, same day**: live-testing the resizable-sidebar fix above (dragging the Explorer sidebar
wide, then opening two diff editors side by side) surfaced two more real bugs, both root-caused
with `jac browse` + `getComputedStyle`/pixel sampling rather than guessed from screenshots alone:

- **A regression in the sidebar-width fix itself**: `className="w-full min-w-0"` on `Sidebar`
  looked correct and fixed the width, but silently discarded the primitive's own `bg-sidebar
  text-sidebar-foreground` classes too, rendering the entire Explorer tree in near-invisible
  near-black text on a transparent background. Root cause, confirmed via `getComputedStyle` in a
  live session: `sidebar.jac`'s `collapsible="none"` branch spreads `{**attrs}` (every prop,
  `className` included) *after* its own computed `className={cn(...)}` — a prop specified twice in
  JSX keeps the last one, so any `className` passed to `<Sidebar collapsible="none">` from any
  caller clobbers the whole `cn(...)` result. Fixed by routing the width override through `style`
  instead (`style={{"width": "100%", "minWidth": "0"}}`) — `attrs` still carries `style` through
  the same spread, but nothing in that branch sets an explicit `style` of its own to collide with
  it, so it applies cleanly without touching the vendored primitive.
- **A second, unrelated white-gap instance**, this time at the editor group's own split, not the
  sidebar: a genuinely white ~25px band flanking the resize handle between two editor panes,
  confirmed with real sampled pixel values (`(255, 255, 255)`), not assumed from a screenshot.
  Same root cause as the sidebar's white-space bug, one level more general: `.dark`'s
  `--background`/`--foreground` CSS variables cascade to every descendant, but nothing was ever
  painting an actual `background-color`/`color` from them anywhere near the app's actual root —
  every dark surface up to this point was one more hand-styled component's own hardcoded hex color,
  meaning any *other*, not-yet-hand-styled gap anywhere in the tree was one more undiscovered
  instance of the same bug. Fixed at the true root this time, not a third individual container:
  `main.jac`'s own `.dark`-classed wrapper div (the one element that already wraps literally
  everything the app renders) now paints `background: var(--background); color:
  var(--foreground)` directly, making this whole bug class structurally impossible to reintroduce
  by omission elsewhere.

**Update, same day again**: the sponsor re-tested the `~/.claude-scratch/` fix above and hit the
identical bug again -- `setting_sources=["project", "local"]` was real progress but did not
actually close it. Root-caused this time by reading the real `claude` CLI's own TypeScript source
directly (a local checkout at `/home/sahan/dev/coder/src/`), not re-guessing from the Python SDK's
docstring a second time: `"user"` gates one dedicated lookup
(`homedir()/.claude/CLAUDE.md`), but `"project"` gates a *separate* one that walks every ancestor
directory from `cwd` up to the filesystem root looking for `.claude/CLAUDE.md` in each, with no
special case for `$HOME` — and since any real workspace's `cwd` is necessarily nested under the
actual OS user's home directory, that walk always eventually reaches `$HOME` and independently
rediscovers the identical global file through the `"project"`-gated path, completely bypassing the
`"user"` exclusion. Confirmed with standalone `claude_agent_sdk.query()` probe scripts against the
installed SDK directly (not just this launcher): `setting_sources=["project", "local"]` still
leaked the exact `~/.claude-scratch/...` write; `setting_sources=[]` (full isolation) did not, and
correctly landed a normal file request in the open workspace with no confusion. Since `"project"`
scope can never be excluded from this ancestor-walk risk while `cwd` is home-nested — true for
every real jac-studio workspace — full isolation is the *minimum* setting that actually works here,
not a broader fix than necessary. See `claude_code_launcher.py`'s own docstring for the complete,
source-verified write-up.

**Update, same day, third finding**: after confirming the fix above, the sponsor found a follow-on
gap -- a file the agent's `Write` tool created was genuinely on disk (confirmed with their own
terminal) but never appeared in the Explorer sidebar, even with the dev server's HMR running. Not
an HMR gap (Vite's hot reload only concerns this app's own source recompiling, unrelated to
workspace files) -- `file_tree.jac`'s tree is plain client-side state, fetched once per directory
on expand and never re-fetched on its own, and an AI tool call writes to disk from a wholly
separate OS process with no way to signal the tree. A first fix wired a dedicated callback
straight from `ai_chat.jac`'s own `tool_result` handling -- correct, but special-cased to this
app's own AI tool calls as the only possible cause of an external change.

**Update, same day, fourth finding**: asked to check how real VS Code handles the general version
of this problem (a file changing on disk for *any* reason -- an AI tool, a terminal command,
`git checkout`, another program), and it doesn't special-case causes either:
`IFileService.onDidFilesChange` (confirmed by reading `explorerService.ts` in a real
`microsoft/vscode` checkout) is one general, workspace-wide file-change stream every interested
part of the workbench subscribes to. Superseded the AI-specific callback with the same idea, scoped
to what this project needs today: a new `workspace_watcher.jac` module polls a directory-entry-set
snapshot of the open workspace once a second, and `file_tree.jac` refreshes whichever directories
it actually has loaded among whichever changed.

**Update, same day, fifth finding**: the first version of that watcher was itself a real,
live-reproduced regression -- an indefinite SSE stream, opened once and left running for the whole
session, broke `list_children_by_path` server-wide (`'Workspace' object has no attribute 'path'`)
the moment it started, confirmed from the sponsor's own terminal log. This project's own
already-documented SSE-generator-isolation risk (three prior tracker entries), but a worse instance
of it than any before -- every other stream here is short-lived (one chat turn, one debug session);
this was the first that never disconnected on its own. Fixed by not streaming at all: the watcher is
now a plain, ordinary `def:pub` function `file_tree.jac` polls on a `setInterval`, completely
stateless server-side (the client passes back its own last snapshot each call). Verified directly
against the running server with `curl`, not just `jac check` -- confirmed the new function keeps
working correctly even while the old bug's symptom was still reproducing on the same request.

**Update, same day, sixth finding**: that same symptom turned out to be a separate, genuinely
pre-existing bug, unrelated to the watcher -- confirmed by the sponsor themselves, who had seen the
Explorer tree disappear on long-running sessions before the watcher ever existed, and by direct
`curl` testing showing the new watcher function succeeding on the same request that
`list_children_by_path` failed on. Root cause not fully pinned down (the likely candidate,
`get_or_create_workspace`'s cache-vs-commit consistency under concurrent requests, is the same
class of race `_workspace_lock`'s own docstring already flags as real but not reproducible under
`jac test`'s synchronous execution) -- but `list_children_by_path` now defends against the crash
itself: a `Contains`-edge target that isn't actually a `Folder`/`File` is skipped instead of taking
the whole call down. A genuinely surprising secondary finding along the way: `isinstance()` against
the malformed value raised the identical error one line earlier than the `hasattr()` form that
actually works -- confirmed live by temporarily reverting and rerunning the new regression test.
Logged as tracker entry `2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target`.
**This fix needs a real server restart to take effect** -- unlike every other fix in this cycle,
it's server-side Python execution, not the client bundle Vite's `--dev` hot-reloads.

Still scoped to the sidebar only, not `inline_chat_widget.jac` or auto-reloading already-open
editor tabs -- both real, legitimate follow-up work, not dropped, but bigger, separate changes than
this pass's actual finding calls for.

**Update, same day, seventh finding**: a follow-up report that looked at first like another
file-tree bug wasn't one. The sponsor asked the AI Chat to create `scratch_test.txt`; it reported
success, but the file never appeared in the Explorer -- and the terminal log showed why: it had
actually been written to `/tmp/scratch_test.txt`, nowhere near the open workspace, so there was
nothing wrong with the tree or the watcher to find. Root cause was in `claude_code_launcher.py`:
it never set `system_prompt`, and the installed SDK's own source (`subprocess_cli.py`) shows
`system_prompt=None` sends the real CLI `--system-prompt ""` -- an *explicit* empty prompt, not
"use the default." Cross-checked against a real `claude` CLI source checkout
(`utils/queryContext.ts`, `constants/prompts.ts`): an empty custom prompt makes the CLI skip its
entire default system prompt, including the `<env>Working directory: ...</env>` block baked into
it. With no context at all about where it was running, the model fell back to its own pretrained
instinct for a scratch-sounding filename. Fixed with `system_prompt={"type": "preset", "preset":
"claude_code"}`, confirmed (via the same source) not to reopen the earlier `setting_sources`
CLAUDE.md leak -- independent CLI flags.

**Update, same day, eighth finding**: separately, asked to check how VS Code's production
architecture handles file watching efficiently, since `check_workspace_changes` (the polling
function from the fifth finding above) did a full recursive `os.walk` every second, forever,
regardless of whether anything had changed. VS Code's `IFileService` doesn't poll at all -- a real
OS-level notification mechanism (inotify and equivalents) reports changes, and
`files.watcherExclude` prunes exactly the directories (`node_modules`, `.git`) this project's own
`DEFAULT_EXCLUDED_DIRS` already prunes from `os.walk`, for the identical resource reason.
`workspace_watcher.jac` now does the same, using `watchdog` (a new but small dependency, confirmed
safe to import at `.jac` module scope by an actual `jac run` probe before committing to the design
-- unlike `claude-agent-sdk`'s documented compiler-choking dependency closure) -- scheduled
per-directory, non-recursively, matching `files.watcherExclude`'s own reasoning rather than
watching everything and filtering afterward. The client-side poll transport is unchanged
deliberately (a push/stream design would reopen the fifth finding's SSE-isolation risk); what
changed is that answering a poll is now an O(1) in-memory read instead of an O(files) disk walk.
Caught one real bug live-testing this before it shipped: a directory's own `modified` event (fired
because its mtime changes when something inside it changes) was being misattributed to its
*parent* via a naive `dirname()`, marking the wrong directory dirty -- fixed by dropping `modified`
events entirely, since they carry no signal beyond what the `created`/`deleted` event that caused
them already provides.

**Update, same day, ninth finding**: separately, live-tested a genuine re-recurrence of the
`'Workspace' object has no attribute 'path'` crash (sixth finding above) -- confirmed the existing
`hasattr` guard in `list_children_by_path` was still solid (re-verified `isinstance` vs `hasattr`
directly), found and closed one more genuinely unguarded instance of the same gap in
`ensure_path_reachable` (not confirmed as this occurrence's actual cause -- the live browser stack
trace only named `list_children_by_path`), and asked the user to restart their server so a real
next occurrence (if any) could be cleanly attributed to persisted-vs-in-memory corruption. The
restart cleared it.

**Update, same day, tenth finding**: the "Auto" permission-mode picker option (fourth QA pass) was
still prompting for every tool call despite sending `permission_mode: "auto"` correctly end to end
-- confirmed live via the server's own request log. Traced into the real `claude` CLI's own source
(`utils/permissions/PermissionMode.ts`) rather than re-guessing: `"auto"` is a real, accepted
`PermissionMode` value (which is why it never errored), but it's gated
Anthropic-internal-only behind a feature flag and a `USER_TYPE === 'ant'` check, and even when
active its own config maps to the *identical external behavior as `"default"`* (Manual) -- so this
app's "Auto" option had been silently behaving like Manual since the picker was first added. The
correct value for a real full-bypass "Auto" mode is `"bypassPermissions"` -- fixed in `ai_chat.jac`'s
`PERMISSION_MODE_OPTIONS`, and `claude_code_launcher.py`'s docstring corrected in place rather than
left stale.
