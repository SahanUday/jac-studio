---
id: 2026-08-22-chat-subsystem-scale
date: 2026-08-22
category: note
severity: note
status: open
phase: 0
subsystem: workbench-shell
jac_version: ""
related_vscode_ref: "src/vs/workbench/contrib/chat/ (442,661 lines)"
upstream_issue: ""
tags: [chat, ai, strategic, scale]
---

Measured during the second VS Code re-investigation pass: `src/vs/workbench/contrib/chat` is
442,661 lines — larger than the entire `src/vs/editor` layer (279,192 lines). VS Code's chat/agent
infrastructure (inline chat, agent sessions, voice input, tool/prompt services) is now its single
largest subsystem, bigger than Monaco itself. Not a hypothesis — a measured fact from the real
checkout, and a genuine signal of where the product has actually gone since this whole
reimplementation is scoped around a "text editor with extensions" framing.

**Impact on jac-studio**: deliberately NOT filed as a roadmap gap to close by porting 442K lines
of chat UI. Jac already has `by llm()` and `sem` annotations as first-class language features
(`jac-by-llm.md`) — an AI-assist story for jac-studio likely looks architecturally different from
upstream's bolted-on chat panel, which exists because TypeScript has no native LLM-call syntax to
build on top of.

**Plan**: no action for now — this is a strategic note, not a blocker. Revisit explicitly once any
phase considers adding AI-assist features, so the design starts from "what does this look like
when the host language has LLM calls built in" rather than defaulting into a copy of upstream's
approach because that's the only reference point anyone reached for.
