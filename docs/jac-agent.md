# Jac Agent — a native, dependency-free AI agent for jac-studio

Status: idea, not yet scoped. No architecture spike, no implementation, no milestone assignment.
Kept separate from [`roadmap.md`](roadmap.md) so it isn't implied to be committed, sequenced work.

## The idea

jac-studio's Claude Code integration ([M5](milestones/m5-ai-integrations.md)) spawns an external
CLI as a subprocess. Jac Agent would instead be native: `by llm(tools=[...])`, a working ReAct
tool-calling loop (see [`research/jac-native-agent-capabilities.md`](research/jac-native-agent-capabilities.md)),
pointed at jac-studio's own M4 service functions (`create_file`, `run_in_terminal`,
`search_in_files`, `get_scm_status`, ...) via `sem` descriptions — no external CLI, subprocess, or
separate auth, just a model API key.

## Where it would fit

A fourth entry in the same agent-provider slot Claude Code occupies, same chat UI, sidebar, inline
chat, code-actions menu — the user picks the backend. No install required, a natural default for a
user without an external CLI. Also the real second data point the open `ChatProvider`-split
question ([ADR 0063](decisions/0063-do-not-split-chatprovider-yet.md)) is waiting on.

## The caveat

An external agentic CLI brings permission prompting, context/compaction management, a
battle-tested tool set, and refined safety guardrails. A `by llm(tools=[...])` agent starts from
zero on all of that — a real option, not a drop-in replacement, on day one.

## Next steps

Architecture and a phased plan are intentionally not written yet — follow-up work once picked up
for real, tracked separately from `roadmap.md`.
