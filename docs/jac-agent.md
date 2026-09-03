# Jac Agent — a native, dependency-free AI agent for jac-studio

Status: **idea, not yet scoped.** No architecture spike, no implementation, no phase assignment.
This doc exists to capture the idea in one place, deliberately kept separate from
[`roadmap.md`](roadmap.md)'s phase-numbered structure so it can be dug into and detailed later
without implying it's already committed, sequenced work. `roadmap.md` and `architecture.md` each
carry only a light pointer here — this doc is the source of truth for the idea itself.

## The idea

jac-studio's Claude Code integration (Phase 5, closed 2026-09-04 — see
[`phases/phase-5-ai-integrations.md`](phases/phase-5-ai-integrations.md)) works by spawning an
external CLI tool as a subprocess and streaming its output back into the UI. "Jac Agent" is a
different shape entirely: an AI agent built natively in Jac, using the language's own `by llm()`
construct, with **no external CLI, no subprocess, no separate auth flow** — just a model API key.

Concretely: `by llm(tools=[...])` is a real, working ReAct tool-calling loop, confirmed via
`jac guide jac-by-llm` (see [`research/jac-native-agent-capabilities.md`](research/jac-native-agent-capabilities.md)
for the full technical grounding, not repeated here). Point it at jac-studio's own
**already-built** Phase 4 service functions — `create_file`, `run_in_terminal`, `search_in_files`,
`get_scm_status`, and so on — each just needing a `sem` description for the model to see, and the
result is a genuine agent: it can read/write files, run commands, search the workspace, and reason
over multiple tool calls in a loop, entirely in-process.

## Where it would fit

The vision is a **fourth entry in the same agent-provider slot Claude Code occupies today** — same
chat UI, same sidebar, same inline-chat popover, same code-actions menu, but the user picks which
backend actually answers: Claude Code, (eventually) Copilot/OpenCode, or Jac Agent. No install
required for the last one, which makes it a natural default/fallback option for a user who hasn't
set up an external CLI at all.

This directly touches an already-flagged open question in `architecture.md`'s "AI coding tool
integrations" section: whether the `ChatProvider` shape should eventually split into two layers
(agent-behavior identity vs. model backend), the way VS Code's `chat.createChatParticipant` /
`lm.registerLanguageModelChatProvider` do. That question was deliberately left open with only one
provider shipped — Jac Agent, whenever it's built, would be the real second data point it's
waiting on.

## The honest caveat

Worth being upfront about, per the research doc's own "what this does NOT get for free" section: an
external agentic CLI like Claude Code brings a lot beyond raw tool-calling — permission prompting,
context-window/compaction management, a large, battle-tested tool set, safety guardrails refined
over real usage. A `by llm(tools=[...])` agent starts from zero on all of that. Jac Agent is a real,
viable *option*, not a drop-in replacement for the Claude Code integration already shipped, at
least not on day one.

## Next steps

Detailed architecture (the provider-interface shape, exactly which service functions become tools
and with what `sem` descriptions, the streaming/session-continuity model, how tool approval works
without an external CLI's own permission system to lean on, how it surfaces in the existing
provider UI) and its own phased implementation roadmap are intentionally **not** written here yet —
that's follow-up work once this is picked up for real, tracked as its own effort rather than
folded into `roadmap.md`'s phase sequence. Read this doc, `architecture.md`'s pointer, and
`research/jac-native-agent-capabilities.md` first when that time comes.
